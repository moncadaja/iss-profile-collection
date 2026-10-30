# Queue System Quick Reference

## Side-by-Side Code Comparison

### Adding Plans to Queue

**XLive Current:**
```python
# From GUI or code
plan_dict = {
    'plan_name': 'xas_scan',
    'plan_kwargs': {'element': 'Fe', 'edge': 'K', ...}
}
plan_processor.add_plans(plan_dict)
plan_processor.run()
```

**Queue-Server:**
```python
# Using Python API
from bluesky_queueserver_api import BPlan
from bluesky_queueserver_api.zmq import REManagerAPI

RM = REManagerAPI()
RM.environment_open()  # Start worker
RM.wait_for_idle()

item = BPlan('xas_scan', element='Fe', edge='K', ...)
RM.item_add(item)
RM.queue_start()
```

OR via CLI:
```bash
qserver queue add plan '{"name":"xas_scan", "kwargs":{"element":"Fe", "edge":"K"}}'
qserver queue start
```

---

### Queue Status

**XLive Current:**
```python
status = plan_processor.status  # 'idle' | 'running'
queue = plan_processor.plan_list
count = len(queue)
```

**Queue-Server:**
```python
status = RM.status()
# Returns dict with:
# - manager_state: 'idle' | 'running_queue' | ...
# - re_state: 'idle' | 'running' | 'paused'
# - items_in_queue: 5
# - items_in_history: 10

queue = RM.queue_get()
count = queue['items_in_queue']
```

---

### Pause/Resume

**XLive Current:**
```python
plan_processor.pause_plan_list()
plan_processor.unpause_plan_list()
```

**Queue-Server:**
```python
# Pause queue execution
RM.queue_stop()

# Pause running plan
RM.re_pause()
RM.re_resume()
RM.re_stop()  # Graceful stop
RM.re_abort()  # Emergency abort
```

---

### Clear Queue

**XLive Current:**
```python
plan_processor.clear_plan_list()
```

**Queue-Server:**
```python
RM.queue_clear()
```

---

## Feature Mapping

| XLive Feature | Queue-Server Equivalent | Notes |
|---------------|------------------------|-------|
| `plan_processor.add_plans()` | `RM.item_add()` | Similar API |
| `plan_processor.run()` | `RM.queue_start()` | Async in queue-server |
| `plan_processor.pause_plan_list()` | `RM.queue_stop()` | Queue-server also has `re_pause()` |
| `plan_processor.clear_plan_list()` | `RM.queue_clear()` | Similar |
| `plan_processor.status` | `RM.status()['manager_state']` | More detailed in queue-server |
| `plan_processor.plan_list` | `RM.queue_get()['items']` | Redis-backed |
| `plan_processor.beamline_readiness` | *(Custom implementation needed)* | Could be pre-plan hook |
| `plan_processor.auto_foil_set` | *(Custom implementation needed)* | Could be plan decorator |
| `plan_processor.liveplot_maker` | RE subscriptions + 0MQ streaming | Different mechanism |
| *(No equivalent)* | `RM.environment_open/close()` | Worker lifecycle |
| *(No equivalent)* | `RM.permissions_get/set()` | User permissions |
| *(No equivalent)* | `RM.history_get()` | Audit trail |
| *(No equivalent)* | `RM.script_upload()` | Runtime code upload |

---

## GUI Integration Patterns

### Current XLive (Direct Integration)
```python
class UIPlanQueue(QtWidgets.QWidget):
    def __init__(self, plan_processor=None, ...):
        self.plan_processor = plan_processor
        # Direct Python calls
        self.pushButton_run_queue.clicked.connect(self.run_queue)

    def run_queue(self):
        self.plan_processor.run()  # Synchronous call

    def update_plan_list(self):
        # Qt signal from plan_processor
        for plan in self.plan_processor.plan_list:
            # Update GUI directly
            item = QtWidgets.QListWidgetItem(...)
```

### Queue-Server Pattern (Event-Driven)
```python
class UIPlanQueue(QtWidgets.QWidget):
    def __init__(self, rm_api=None, ...):
        self.RM = rm_api  # REManagerAPI instance
        self.status_timer = QtCore.QTimer()
        self.status_timer.timeout.connect(self.update_status)
        self.status_timer.start(1000)  # Poll every second

    def run_queue(self):
        # Async call, doesn't block
        self.RM.queue_start()

    def update_status(self):
        # Poll for changes
        status = self.RM.status()
        if status['plan_queue_uid'] != self.last_queue_uid:
            self.refresh_queue()
        
    def refresh_queue(self):
        queue = self.RM.queue_get()
        # Update GUI with queue['items']
```

OR (Better: Event Subscriptions)
```python
from bluesky_queueserver_api.zmq.aio import REManagerAPI_ZMQ_Async
import asyncio

class UIPlanQueue(QtWidgets.QWidget):
    def __init__(self):
        self.RM = REManagerAPI_ZMQ_Async()
        # Subscribe to status changes
        self.setup_subscriptions()
    
    async def setup_subscriptions(self):
        async for status in self.RM.status_stream():
            # Qt signal to update GUI
            self.status_changed_signal.emit(status)
```

---

## ISS-Specific Feature Implementation

### Beamline Readiness Checks

**Current XLive:**
```python
# In PlanProcessor.perform_pre_scan_routines()
if self.beamline_readiness:
    self.RE(check_hhm_roll_plan())
    self.RE(check_gate_valves_plan())
    self.RE(check_photon_shutter_plan())
    self.RE(check_ic_voltages())
```

**Queue-Server Options:**

Option 1: Pre-plan wrapper (recommended)
```python
# In startup code
from functools import wraps

def with_beamline_checks(plan):
    """Decorator to add beamline readiness checks before a plan"""
    def wrapper(*args, **kwargs):
        # Run checks first
        yield from check_hhm_roll_plan()
        yield from check_gate_valves_plan()
        yield from check_photon_shutter_plan()
        yield from check_ic_voltages()
        # Then run the actual plan
        yield from plan(*args, **kwargs)
    return wrapper

# Apply to XAS plans
@with_beamline_checks
def xas_scan(...):
    ...
```

Option 2: Plan preprocessor
```python
# In startup code
def add_readiness_checks_preprocessor(plan):
    """Add readiness checks to plan"""
    from bluesky.preprocessors import pchain
    return pchain(
        check_hhm_roll_plan(),
        check_gate_valves_plan(),
        check_photon_shutter_plan(),
        check_ic_voltages(),
        plan
    )

# Register with RE
RE.preprocessors.append(add_readiness_checks_preprocessor)
```

Option 3: Configuration in plan metadata
```python
# Plans declare they need checks
def xas_scan(...):
    # Add metadata
    yield Msg('open_run', md={'requires_beamline_checks': True})
    ...

# In startup, check metadata
def conditional_checks_preprocessor(plan):
    md = get_plan_metadata(plan)
    if md.get('requires_beamline_checks'):
        return pchain(check_gates_etc(), plan)
    return plan
```

---

### Auto Foil Setting

**Current XLive:**
```python
# In PlanProcessor.perform_pre_scan_routines()
if self.auto_foil_set:
    if 'element' in plan_kwargs and 'edge' in plan_kwargs:
        self.RE(set_reference_foil(plan_kwargs['element'], plan_kwargs['edge']))
```

**Queue-Server Option 1: Plan decorator**
```python
def with_auto_foil(plan):
    """Decorator to auto-set reference foil based on plan parameters"""
    import inspect
    def wrapper(*args, **kwargs):
        # Extract element and edge from kwargs
        sig = inspect.signature(plan)
        bound = sig.bind(*args, **kwargs)
        params = bound.arguments
        
        if 'element' in params and 'edge' in params:
            yield from set_reference_foil(params['element'], params['edge'])
        
        yield from plan(*args, **kwargs)
    return wrapper
```

**Queue-Server Option 2: Plan parameter defaults**
```python
# Annotate plan to indicate auto-foil behavior
@parameter_annotation_decorator({
    'parameters': {
        'element': {'annotation': 'typing:Str'},
        'edge': {'annotation': 'typing:Str'},
        'auto_set_foil': {
            'annotation': 'typing:Bool',
            'default': True,
            'description': 'Automatically set reference foil'
        }
    }
})
def xas_scan(element, edge, auto_set_foil=True, ...):
    if auto_set_foil:
        yield from set_reference_foil(element, edge)
    ...
```

---

### Liveplot Integration

**Current XLive:**
```python
# In PlanProcessor
liveplots = self.liveplot_maker(plan_name, plan_kwargs)
self.RE(plan, liveplots)  # Callbacks registered
```

**Queue-Server:**
Plans run in isolated worker, but RE subscriptions work:

```python
# In startup code (worker side)
from bluesky.callbacks.best_effort import BestEffortCallback
bec = BestEffortCallback()
RE.subscribe(bec)

# For custom liveplots, use RE subscriptions
from isstools.callbacks import LivePlotCustom
liveplot = LivePlotCustom(...)
RE.subscribe(liveplot)
```

For GUI integration, stream plot data via 0MQ:
```python
# Worker publishes plot data
class PlotDataPublisher:
    def __init__(self, zmq_socket):
        self.socket = zmq_socket
    
    def __call__(self, name, doc):
        if name == 'event':
            # Publish to 0MQ
            self.socket.send_json({
                'type': 'plot_data',
                'data': doc['data']
            })

# GUI subscribes to plot data
class XLiveGui:
    def __init__(self):
        self.plot_subscriber = zmq.Context().socket(zmq.SUB)
        self.plot_subscriber.connect('tcp://localhost:60625')
        # Update plots when data arrives
```

OR use bluesky-widgets (already integrated with queue-server):
```python
from bluesky_widgets.qt import QtRun
from bluesky_widgets.models.plot_specs import Figure, Line

# In GUI
self.run_viewer = QtRun()
# Automatically shows plots from running plans
```

---

## CLI Cheat Sheet

```bash
# Manager control
start-re-manager --startup-dir ~/startup  # Start manager
qserver ping                               # Check if running
qserver status                             # Get full status
qserver environment open                   # Open worker env
qserver environment close                  # Close worker env

# Queue operations
qserver queue add plan '{"name":"count", "args":[["det1"]]}'
qserver queue add plan count "['det1']"    # Alternative syntax
qserver queue get                          # View queue
qserver queue start                        # Start queue
qserver queue stop                         # Stop queue
qserver queue clear                        # Clear queue

# Plan control (during execution)
qserver re pause                           # Pause running plan
qserver re resume                          # Resume paused plan
qserver re stop                            # Stop plan (graceful)
qserver re abort                           # Abort plan (emergency)
qserver re halt                            # Halt immediately

# History
qserver history get                        # Get plan history
qserver history clear                      # Clear history

# Monitoring
qserver-console-monitor                    # Watch console output
qserver monitor                            # Monitor status changes

# Utilities
qserver-list-plans-devices \
    --startup-dir ~/startup \
    --file-dir ~/output                    # Generate plan/device lists
```

---

## Testing Checklist

Before migrating, verify these work with queue-server:

- [ ] ISS startup code loads in worker (no errors)
- [ ] Basic plans execute (count, scan, etc.)
- [ ] XAS-specific plans work (xas_scan, fly_scan, etc.)
- [ ] EPICS connections work in worker
- [ ] Beamline checks can be implemented
- [ ] Auto foil setting can be implemented
- [ ] Liveplots can be displayed
- [ ] Queue persistence survives manager restart
- [ ] Multi-client access works (CLI + GUI)
- [ ] Remote control works (from another machine)
- [ ] Performance is acceptable (no significant overhead)
- [ ] Error handling is acceptable
- [ ] Recovery from failures works

---

## Performance Considerations

**XLive Current:**
- Plan submission: instant (Python function call)
- Queue updates: instant (in-memory list)
- Status: instant (local variable)

**Queue-Server:**
- Plan submission: ~10-50ms (0MQ + Redis)
- Queue updates: ~10-50ms (0MQ + Redis read)
- Status: ~5-20ms (0MQ request)

**Typical overhead:** Negligible for minute-long scans, noticeable for sub-second operations

**Mitigation:**
- Cache status locally, poll at reasonable interval (1 Hz)
- Batch queue operations
- Use async API for GUI (non-blocking)

---

## Summary

**XLive Queue Strengths:** Simple, integrated, ISS-specific features built-in

**Queue-Server Strengths:** Remote control, multi-client, fault tolerance, audit trail, enterprise features

**Migration Complexity:** Medium (2-4 weeks)

**Recommendation:** Evaluate first (1-2 weeks), decide based on priorities

**Key Question:** Do you need remote control / multi-user / automation?
- **Yes** → Migrate to queue-server
- **No** → Keep current, but document well
- **Maybe** → Do the evaluation


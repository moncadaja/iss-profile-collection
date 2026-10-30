# XLive Queue vs. Bluesky Queue-Server Comparison

## Executive Summary

**Recommendation**: **Consider migrating to bluesky-queueserver** for long-term maintainability and feature richness, but be prepared for significant integration effort.

The NSLS-II DSSI bluesky-queueserver is a production-grade, actively maintained solution with enterprise features that the homemade XLive queue lacks. However, migration requires architectural changes to how XLive interacts with the Run Engine.

---

## Architecture Comparison

### XLive Homemade Queue (`PlanProcessor`)

**Design**: Single-process, tightly coupled to XLive GUI
- Lives in the same process as the Run Engine and XLive GUI
- Direct Python API calls (synchronous)
- Queue stored as JSON file on disk
- Status signals via Qt signals/slots
- Direct RE control: `self.RE(*plan_args)`

**Location**: `iss-profile-collection/startup/96-plan_processor.py`

**Key Components**:
- `PlanProcessor(PersistentListInteractingWithGUI)` - ~370 lines
- `UIPlanQueue` widget - ~170 lines
- Direct RE access in same process

---

### Bluesky Queue-Server

**Design**: Multi-process, decoupled architecture
- **RE Manager**: Separate process managing queue and worker
- **RE Worker**: Isolated process running Run Engine
- **Redis**: External queue/history persistence
- **0MQ/HTTP API**: Network-based communication
- **Client Libraries**: `bluesky-queueserver-api` for Python clients

**Key Components**:
- Manager process (maintains queue, handles API)
- Worker process (runs plans in isolated environment)
- Redis backend (persistent storage)
- 0MQ/HTTP communication layer
- Qt widgets in separate `bluesky-widgets` package

---

## Feature Comparison

| Feature | XLive Queue | Queue-Server | Impact |
|---------|------------|--------------|--------|
| **Queue Persistence** | JSON file | Redis | ✓ Queue-Server more robust |
| **Remote Control** | None | 0MQ + HTTP REST API | ✓✓ Queue-Server enables remote ops |
| **Multi-client** | Single GUI only | Multiple concurrent clients | ✓✓ Queue-Server allows CLI + GUI + web |
| **Process Isolation** | Same process as GUI | Separate worker process | ✓ Queue-Server: crash doesn't kill GUI |
| **Plan History** | No | Full history with metadata | ✓ Queue-Server better for audit trail |
| **User Permissions** | None | Group-based ACLs | ✓ Queue-Server for multi-user facilities |
| **Loop Mode** | No | Yes (re-queue completed plans) | ✓ Queue-Server for automated runs |
| **Plan Validation** | Basic (runtime errors) | Schema validation before queue | ✓ Queue-Server catches errors early |
| **Console Monitoring** | Local only | Remote 0MQ streaming | ✓ Queue-Server for remote ops |
| **Plan Pause/Resume** | Basic | Full RE pause/resume/stop/abort/halt API | ✓ Queue-Server more control |
| **Environment Management** | N/A | Open/close/destroy worker env | ✓ Queue-Server can reload startup code |
| **Script Upload** | No | Upload & execute scripts at runtime | ✓ Queue-Server for dynamic workflows |
| **Function Execution** | No | Execute functions in worker namespace | ✓ Queue-Server for custom operations |
| **GUI Widgets** | Custom (in isstools) | `bluesky-widgets` (separate package) | ≈ Both have Qt widgets |
| **Beamline Readiness Checks** | Built-in (shutters, valves, etc.) | Not built-in | ✓ XLive has ISS-specific logic |
| **Auto Foil Setting** | Built-in | Not built-in | ✓ XLive has ISS-specific logic |
| **GUI Service Injection** | Yes (liveplot_maker, etc.) | Not directly | ✓ XLive tightly integrated |

---

## Technical Details

### XLive Queue Implementation

**Pros**:
- ✓ Simple, easy to understand (~500 total lines)
- ✓ Tight GUI integration (liveplots, services)
- ✓ ISS-specific features (beamline readiness, auto foil)
- ✓ No external dependencies (just JSON + Qt signals)
- ✓ Already working and tested at ISS

**Cons**:
- ✗ No remote control capability
- ✗ Single client only (GUI)
- ✗ GUI crash = queue crash
- ✗ No plan history
- ✗ No validation before execution
- ✗ Limited error handling
- ✗ Maintenance burden on ISS team
- ✗ No multi-user support

**Current Features**:
```python
# Queue operations
plan_processor.add_plans(plans, add_at='tail|head|index', pause_after=False)
plan_processor.run()
plan_processor.pause_plan_list()
plan_processor.unpause_plan_list()
plan_processor.clear_plan_list()
plan_processor.reset()

# Status
plan_processor.status  # 'idle' | 'running'
plan_processor.RE_state  # RE.state passthrough
plan_processor.plan_list  # [{plan_info, plan_status}, ...]

# ISS-specific
plan_processor.beamline_readiness = True  # Checks shutters/valves
plan_processor.auto_foil_set = True  # Auto-set reference foil
plan_processor.liveplot_maker = func  # GUI service injection
```

---

### Queue-Server Implementation

**Pros**:
- ✓ Production-ready, battle-tested at multiple beamlines
- ✓ Actively maintained by DSSI team
- ✓ Full remote control (0MQ + HTTP)
- ✓ Multi-client support
- ✓ Process isolation (fault tolerance)
- ✓ Comprehensive API (~50+ methods)
- ✓ User permissions & ACLs
- ✓ Plan validation & annotations
- ✓ Full audit trail (history)
- ✓ Console output streaming
- ✓ Environment lifecycle management
- ✓ Loop mode & ignore_failures
- ✓ CLI tools included
- ✓ Documentation & tutorials

**Cons**:
- ✗ Complex architecture (3+ processes)
- ✗ External dependencies (Redis)
- ✗ Requires startup code adaptation
- ✗ ISS-specific features need custom implementation
- ✗ GUI integration less tight (0MQ API layer)
- ✗ Steeper learning curve

**Already in ISS Environment**:
```bash
# Your pixi environment already has it!
$ ls iss-profile-collection/.pixi/envs/terminal/lib/python3.12/site-packages/bluesky_queueserver*
bluesky_queueserver-0.0.24.dist-info
bluesky_queueserver
bluesky_queueserver_api-0.0.12.dist-info
bluesky_queueserver_api
```

---

## Migration Considerations

### Effort Estimate

**Medium-High Effort** (2-4 weeks)

1. **Infrastructure** (3-5 days)
   - Set up Redis (already available at NSLS-II)
   - Configure RE Manager startup
   - Adapt startup code for queue-server compatibility
   - Set up systemd service

2. **GUI Integration** (5-7 days)
   - Replace `UIPlanQueue` widget with queue-server client
   - Implement 0MQ API calls (or use bluesky-queueserver-api)
   - Adapt status monitoring to queue-server events
   - Handle worker process lifecycle

3. **Feature Parity** (3-5 days)
   - Implement beamline readiness checks (as plan or pre-plan hook)
   - Implement auto foil setting (as plan parameter defaults or wrapper)
   - Adapt liveplot integration (worker-side callbacks)
   - Migrate plan bundles to queue-server format

4. **Testing & Validation** (3-5 days)
   - Test queue operations
   - Test remote control
   - Test multi-user scenarios
   - Test failure scenarios
   - Verify ISS-specific workflows

### Migration Risks

1. **ISS-Specific Features**
   - Beamline readiness checks currently run *before* each plan
   - Auto foil setting is deeply integrated
   - **Mitigation**: Implement as plan decorators or startup hooks in worker

2. **GUI Service Injection**
   - Current: `liveplot_maker`, `gui_services_dict` injected into plans
   - Queue-Server: Plans run in worker process, no direct GUI access
   - **Mitigation**: Use RE subscriptions + 0MQ streaming for live plots

3. **Tight Coupling**
   - XLive expects synchronous plan execution
   - Queue-Server is async/event-driven
   - **Mitigation**: Refactor GUI to poll status or subscribe to events

4. **Startup Code Compatibility**
   - Queue-Server loads startup in isolated worker
   - Some IPython-specific code may need adaptation
   - **Mitigation**: Test with `qserver-list-plans-devices` tool

### What Stays the Same

✓ Plan definitions (no changes needed)
✓ Device definitions (no changes needed)
✓ Scan parameters & metadata
✓ Data acquisition workflow
✓ Bluesky documents & databroker

### What Changes

✗ Queue API calls (Python function calls → 0MQ API)
✗ GUI integration (Qt signals → 0MQ polling/subscriptions)
✗ Process architecture (single → multi-process)
✗ Liveplot mechanism (direct callback → RE subscription + streaming)
✗ ISS-specific hooks (need re-implementation in worker)

---

## Operational Impact

### Current XLive Workflow
```
User → XLive GUI → PlanProcessor → RE (same process)
                                 ↓
                             EPICS IOCs
```

### Queue-Server Workflow
```
User → XLive GUI → 0MQ API → RE Manager → Worker Process (RE)
                                                       ↓
  OR                                               EPICS IOCs
                                                       ↑
Remote Client → HTTP REST API ──┘              Startup Code
```

### Operational Benefits of Queue-Server

1. **Fault Tolerance**: GUI crash doesn't stop running scans
2. **Remote Operations**: Control from anywhere (ssh, web, scripts)
3. **Multi-User**: Multiple operators can monitor/queue scans
4. **Audit Trail**: Full history for troubleshooting
5. **Environment Reloads**: Update startup code without restarting entire system
6. **Automation**: Script-based queue population (e.g., batch jobs)

---

## Decision Matrix

### Keep XLive Queue If:
- ✓ ISS is a single-user beamline with one control station
- ✓ No remote operations needed
- ✓ Current functionality is sufficient
- ✓ Limited development resources
- ✓ "If it ain't broke, don't fix it" philosophy

### Migrate to Queue-Server If:
- ✓ Need remote control capabilities
- ✓ Multiple users/clients need queue access
- ✓ Want robust audit trail & history
- ✓ Plan to support web-based or automated workflows
- ✓ Want fault isolation (GUI crash ≠ scan stop)
- ✓ Have development time for migration
- ✓ Want to align with NSLS-II standard tools

---

## Hybrid Approach (Recommended Exploration)

### Phase 1: Evaluate (Low Risk)
1. **Set up Queue-Server in parallel** (1 week)
   - Install on test machine
   - Load ISS startup code
   - Test basic queue operations with `qserver` CLI
   - Test with simple plans

2. **Test Feature Parity** (1 week)
   - Can ISS startup code run in worker?
   - How to implement beamline readiness checks?
   - How to handle liveplots?
   - Document gaps

3. **Decision Point**: Full migration vs. keep current

### Phase 2: Gradual Migration (If proceeding)
1. **Run both systems** (transition period)
   - Keep XLive queue operational
   - Add queue-server backend option
   - Add GUI toggle to switch between backends

2. **Feature-by-feature migration**
   - Start with simple scans
   - Add ISS-specific features progressively
   - Monitor for issues

3. **Deprecate old queue** when confident

---

## Recommendation

### **Short Term** (Next 1-2 months)
**Keep XLive homemade queue** - it works and is proven.

**But**: Spend 1-2 weeks doing Phase 1 evaluation:
- Set up queue-server on a test system
- Load ISS startup code in worker environment
- Test basic operations with CLI
- Document integration challenges

This low-risk evaluation will give you real data on migration effort.

### **Long Term** (6-12 months)
**Migrate to queue-server** if any of these become priorities:
- Remote operations capability
- Web-based interfaces
- Multi-user support
- Automated batch workflows
- Alignment with facility standards

### **Why Wait to Decide?**
1. Your current queue works fine for day-to-day ops
2. Migration is non-trivial (~2-4 weeks developer time)
3. Queue-server evaluation needs hands-on testing
4. ISS-specific features need design work
5. Better to evaluate on test system first

---

## Technical Questions to Answer During Evaluation

1. **Startup Code Compatibility**
   - Does ISS startup load cleanly in queue-server worker?
   - Are there IPython-specific constructs that break?
   - Do EPICS connections work in isolated worker?

2. **ISS-Specific Features**
   - How to implement pre-scan beamline checks?
   - How to handle auto-foil setting?
   - How to inject GUI services into plans?

3. **Liveplot Integration**
   - Can we stream liveplot data via 0MQ?
   - Does it add significant latency?
   - Can multiple GUIs show same liveplot?

4. **Performance**
   - Overhead of 0MQ communication?
   - Redis persistence impact?
   - Worker startup time?

5. **Operational**
   - Redis backup/recovery procedures?
   - What happens if RE Manager crashes?
   - How to handle network issues?

---

## Resources

### Queue-Server Documentation
- Main docs: https://blueskyproject.io/bluesky-queueserver/
- Tutorials: `bluesky-queueserver/docs/source/tutorials.rst`
- API Reference: `bluesky-queueserver/docs/source/re_manager_api.rst`
- Widgets: https://blueskyproject.io/bluesky-widgets/

### ISS Current Implementation
- PlanProcessor: `iss-profile-collection/startup/96-plan_processor.py`
- Queue Widget: `isstools/isstools/widgets/widget_plan_queue.py`
- Run Widget: `isstools/isstools/widgets/widget_run.py`

### NSLS-II Resources
- DSSI team: queue-server developers at BNL
- Other beamlines using it: SRX, TES, ISS(?), SMI(?)
- Ask on #bluesky Slack or DSSI mailing list

---

## Next Steps

1. **Schedule 30-min discussion** with Jorge to clarify priorities:
   - Is remote control needed?
   - Multi-user scenarios?
   - Automation plans?
   - Available developer time?

2. **If evaluating**: Set up test system
   ```bash
   # On test workstation
   pixi install bluesky-queueserver redis
   start-re-manager --startup-dir ~/repos-dev-jorge-fork/iss-profile-collection/startup
   ```

3. **If keeping current**: Document XLive queue for future maintainers
   - Add docstrings to `PlanProcessor`
   - Document ISS-specific features
   - Add unit tests

4. **Long-term planning**: Include in beamline software roadmap

---

*Generated 2026-10-30 by Claude Code based on analysis of both implementations*

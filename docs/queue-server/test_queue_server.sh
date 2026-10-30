#!/bin/bash
# Quick evaluation script for bluesky-queueserver with ISS startup code
# Usage: bash test_queue_server.sh

set -e

echo "================================================"
echo "Bluesky Queue-Server Evaluation for ISS"
echo "================================================"
echo ""

# Check if Redis is available
echo "1. Checking Redis availability..."
if command -v redis-cli &> /dev/null; then
    if redis-cli ping &> /dev/null; then
        echo "   ✓ Redis is running"
    else
        echo "   ✗ Redis server not responding"
        echo "   Start Redis with: redis-server &"
        exit 1
    fi
else
    echo "   ✗ redis-cli not found"
    echo ""
    echo "   Install options:"
    echo "   A. System install (as root/sudo):"
    echo "      sudo dnf install redis"
    echo "      sudo systemctl start redis"
    echo ""
    echo "   B. Or run Redis in pixi environment:"
    echo "      pixi global install redis"
    echo "      redis-server --daemonize yes"
    echo ""
    echo "   C. Or use existing NSLS-II Redis (if available):"
    echo "      Ask controls group for Redis server address"
    echo ""
    exit 1
fi
echo ""

# Check if queue-server is installed
echo "2. Checking bluesky-queueserver installation..."
if command -v start-re-manager &> /dev/null; then
    VERSION=$(start-re-manager --version 2>&1 | head -1 || echo "unknown")
    echo "   ✓ Queue-server installed: $VERSION"
else
    echo "   ✗ start-re-manager not found"
    echo ""
    echo "   The iss-profile-collection pixi environment already has it!"
    echo "   Run from that environment:"
    echo "      cd iss-profile-collection"
    echo "      pixi shell -e terminal"
    echo "      start-re-manager --version"
    echo ""
    exit 1
fi
echo ""

# Check startup code
STARTUP_DIR="$PWD/iss-profile-collection/startup"
echo "3. Checking ISS startup code..."
if [ -d "$STARTUP_DIR" ]; then
    FILE_COUNT=$(ls -1 "$STARTUP_DIR"/*.py 2>/dev/null | wc -l)
    echo "   ✓ Startup directory exists: $STARTUP_DIR"
    echo "   ✓ Found $FILE_COUNT Python files"
else
    echo "   ✗ Startup directory not found: $STARTUP_DIR"
    exit 1
fi
echo ""

# Test: Can startup code load in queue-server?
echo "4. Testing startup code compatibility..."
echo "   Generating allowed plans/devices list..."
OUTPUT_DIR="/tmp/iss-qserver-test-$$"
mkdir -p "$OUTPUT_DIR"

# Try to generate lists (this loads startup code)
if qserver-list-plans-devices \
    --startup-dir "$STARTUP_DIR" \
    --file-dir "$OUTPUT_DIR" \
    --overwrite 2>&1 | tee "$OUTPUT_DIR/gen-lists.log"; then
    echo "   ✓ Startup code loaded successfully!"

    # Show what was found
    if [ -f "$OUTPUT_DIR/existing_plans_and_devices.yaml" ]; then
        PLAN_COUNT=$(grep -c "^  [a-z]" "$OUTPUT_DIR/existing_plans_and_devices.yaml" 2>/dev/null || echo 0)
        echo "   ✓ Found $PLAN_COUNT plans/devices"
        echo ""
        echo "   Sample plans found:"
        grep "^  [a-z]" "$OUTPUT_DIR/existing_plans_and_devices.yaml" | head -10
        echo "   ..."
    fi
else
    echo "   ✗ Startup code failed to load"
    echo "   Check log: $OUTPUT_DIR/gen-lists.log"
    echo ""
    echo "   Common issues:"
    echo "   - IPython-specific imports"
    echo "   - Missing dependencies"
    echo "   - Syntax errors"
    exit 1
fi
echo ""

echo "5. Next steps for evaluation:"
echo ""
echo "   A. Start RE Manager (in a separate terminal):"
echo "      $ start-re-manager \\"
echo "          --startup-dir $STARTUP_DIR \\"
echo "          --zmq-publish-console ON"
echo ""
echo "   B. In another terminal, test basic operations:"
echo "      $ qserver environment open"
echo "      $ qserver status"
echo "      $ qserver queue add plan '{\"name\":\"count\", \"args\":[[\"det1\", \"det2\"]]}'"
echo "      $ qserver queue start"
echo "      $ qserver queue get"
echo ""
echo "   C. Check generated files:"
echo "      Plans/devices: $OUTPUT_DIR/existing_plans_and_devices.yaml"
echo "      Permissions:   $OUTPUT_DIR/user_group_permissions.yaml"
echo ""
echo "   D. Advanced: Monitor console output (in another terminal):"
echo "      $ qserver-console-monitor"
echo ""

echo "================================================"
echo "Evaluation Results"
echo "================================================"
if [ -f "$OUTPUT_DIR/existing_plans_and_devices.yaml" ]; then
    echo "✓ PASS: ISS startup code is compatible with queue-server"
    echo ""
    echo "Your startup code can run in queue-server worker environment."
    echo "Next: Test actual plan execution and ISS-specific features."
else
    echo "✗ FAIL: Compatibility issues found"
    echo ""
    echo "Review the log file for errors:"
    echo "  $OUTPUT_DIR/gen-lists.log"
fi
echo ""

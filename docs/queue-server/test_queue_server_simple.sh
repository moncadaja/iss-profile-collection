#!/bin/bash
# Simple queue-server compatibility test (no Redis required)
# Tests if ISS startup code can load in queue-server worker environment

set -e

echo "================================================"
echo "Queue-Server Startup Code Compatibility Test"
echo "================================================"
echo ""
echo "This test checks if ISS startup code works with"
echo "queue-server WITHOUT needing Redis running."
echo ""

STARTUP_DIR="$PWD/iss-profile-collection/startup"

# Check startup code exists
echo "1. Checking ISS startup code..."
if [ -d "$STARTUP_DIR" ]; then
    FILE_COUNT=$(ls -1 "$STARTUP_DIR"/*.py 2>/dev/null | wc -l)
    echo "   ✓ Found startup directory: $STARTUP_DIR"
    echo "   ✓ Contains $FILE_COUNT Python files"
else
    echo "   ✗ Startup directory not found"
    echo "   Run this from: repos-dev-jorge-fork/"
    exit 1
fi
echo ""

# Run from pixi environment
echo "2. Running test in pixi environment..."
echo "   (This uses the queue-server already in your pixi env)"
echo ""

cd iss-profile-collection

OUTPUT_DIR="${TMPDIR:-/tmp}/iss-qserver-test-$$"
mkdir -p "$OUTPUT_DIR"

echo "3. Testing if startup code loads in queue-server worker..."
echo "   Command: qserver-list-plans-devices --startup-dir startup"
echo ""

if pixi run -e terminal qserver-list-plans-devices \
    --startup-dir startup \
    --file-dir "$OUTPUT_DIR"; then

    echo ""
    echo "================================================"
    echo "✓ SUCCESS: Startup code is compatible!"
    echo "================================================"
    echo ""

    if [ -f "$OUTPUT_DIR/existing_plans_and_devices.yaml" ]; then
        echo "Generated files:"
        ls -lh "$OUTPUT_DIR"/*.yaml
        echo ""

        PLAN_COUNT=$(grep -c "^  [a-z_]" "$OUTPUT_DIR/existing_plans_and_devices.yaml" 2>/dev/null || echo 0)
        echo "Found $PLAN_COUNT callable plans/devices"
        echo ""
        echo "Sample plans found (first 15):"
        grep "^  [a-z_]" "$OUTPUT_DIR/existing_plans_and_devices.yaml" | head -15 | sed 's/^/  - /'
        echo ""

        # Check for XAS-specific plans
        echo "ISS-specific plans detected:"
        grep -E "xas_scan|fly_scan|johann|multipos" "$OUTPUT_DIR/existing_plans_and_devices.yaml" | head -10 | sed 's/^/  - /' || echo "  (none with typical XAS names)"
        echo ""
    fi

    echo "Next steps:"
    echo ""
    echo "  1. Review generated files:"
    echo "     cat $OUTPUT_DIR/existing_plans_and_devices.yaml"
    echo ""
    echo "  2. To actually RUN queue-server, you need Redis:"
    echo "     # Option A: System Redis (ask controls group)"
    echo "     sudo systemctl start redis"
    echo ""
    echo "     # Option B: Redis in container (if Docker available)"
    echo "     docker run -d -p 6379:6379 redis:alpine"
    echo ""
    echo "     # Option C: Install Redis locally"
    echo "     pixi global install redis"
    echo "     redis-server --daemonize yes"
    echo ""
    echo "  3. Then start RE Manager:"
    echo "     cd iss-profile-collection"
    echo "     pixi run -e terminal start-re-manager \\"
    echo "       --startup-dir startup \\"
    echo "       --zmq-publish-console ON"
    echo ""
    echo "  4. Test in another terminal:"
    echo "     pixi run -e terminal qserver status"
    echo "     pixi run -e terminal qserver environment open"
    echo ""

else
    echo ""
    echo "================================================"
    echo "✗ FAIL: Startup code has compatibility issues"
    echo "================================================"
    echo ""
    echo "Check the error messages above. Common issues:"
    echo ""
    echo "  - IPython-specific constructs (get_ipython(), %magic)"
    echo "  - Missing imports when run outside IPython"
    echo "  - Qt GUI initialization in startup (should be conditional)"
    echo "  - Syntax errors"
    echo ""
    echo "Log saved to: $OUTPUT_DIR/qserver-test.log"
    echo ""
    exit 1
fi

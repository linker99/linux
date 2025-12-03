#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Example script to trace workqueue usage and identify which user-space
# processes trigger __queue_work()
#
# This script demonstrates how to use the workqueue_queue_work_caller
# tracepoint to debug and understand workqueue activity.

TRACE_DIR="/sys/kernel/tracing"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Check if tracing is available
if [ ! -d "$TRACE_DIR" ]; then
    echo "Tracing not available. Please enable CONFIG_TRACING in kernel." >&2
    exit 1
fi

echo "Setting up workqueue tracing..."

# Disable tracing first
echo 0 > "$TRACE_DIR/tracing_on"

# Clear the trace buffer
echo > "$TRACE_DIR/trace"

# Enable the workqueue_queue_work_caller tracepoint
echo 1 > "$TRACE_DIR/events/workqueue/workqueue_queue_work_caller/enable"

# Optional: Enable stack traces for complete call paths
# Uncomment the following line for more detailed tracing
# echo 1 > "$TRACE_DIR/options/stacktrace"

# Enable tracing
echo 1 > "$TRACE_DIR/tracing_on"

echo "Tracing enabled. Waiting for workqueue activity..."
echo "Press Ctrl+C to stop tracing and view results."
echo ""

# Wait for user interrupt
sleep infinity &
SLEEP_PID=$!
trap "kill $SLEEP_PID 2>/dev/null; echo ''; echo 'Stopping trace...'" INT

wait $SLEEP_PID

# Disable tracing
echo 0 > "$TRACE_DIR/tracing_on"

# Display results
echo ""
echo "=== Workqueue Trace Results ==="
echo ""
cat "$TRACE_DIR/trace"

# Clean up
echo 0 > "$TRACE_DIR/events/workqueue/workqueue_queue_work_caller/enable"

echo ""
echo "=== Summary ==="
echo "Processes that triggered workqueue operations:"
cat "$TRACE_DIR/trace" | grep -oP 'pid=\K\d+|comm=\K[^ ]+' | paste - - | sort -u

echo ""
echo "Tracing complete."

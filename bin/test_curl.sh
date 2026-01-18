#!/bin/bash
# Check if port 8080 is open
if ! lsof -i :8080 -sTCP:LISTEN >/dev/null; then
    echo "ERROR: Port 8080 is NOT open. Cannot run curl."
    exit 1
fi

TS=$(date +%Y%m%d_%H%M%S_%3N)
LOGDIR=".tmp/logs/$TS"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/curl.log"

echo "Running curl with timeout 3s..." | tee -a "$LOGFILE"
# Use array for args to preserve quoting
ARGS=("$@")
curl -v --max-time 3 "${ARGS[@]}" >> "$LOGFILE" 2>&1
EXIT_CODE=$?

echo "Curl exit code: $EXIT_CODE" | tee -a "$LOGFILE"
exit $EXIT_CODE

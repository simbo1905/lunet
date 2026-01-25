#!/bin/bash
set -e

# 1. Generate Certs
bin/generate_dev_certs.sh

# 2. Start Lunet on Unix Socket
SOCKET_PATH=".tmp/lunet.sock"
rm -f "$SOCKET_PATH"

export LUNET_LISTEN="unix://$SOCKET_PATH"

echo "Starting Lunet on $SOCKET_PATH..."
./build/lunet app/main.lua > .tmp/lunet.log 2>&1 &
LUNET_PID=$!
echo $LUNET_PID > .tmp/lunet.pid

# Wait for socket
echo "Waiting for socket..."
for i in {1..20}; do
    if [ -S "$SOCKET_PATH" ]; then
        echo "Lunet socket ready."
        break
    fi
    sleep 0.1
done

if [ ! -S "$SOCKET_PATH" ]; then
    echo "Lunet failed to start."
    cat .tmp/lunet.log
    kill $LUNET_PID || true
    exit 1
fi

# 3. Start Nginx
echo "Starting Nginx on https://localhost:8443..."
# Ensure log dir exists
mkdir -p .tmp
# Stop any existing nginx
nginx -p $PWD -c bench/lunet/nginx-https.conf -s stop 2>/dev/null || true
# Start nginx
nginx -p $PWD -c bench/lunet/nginx-https.conf

echo "Demo running!"
echo "  Frontend: https://localhost:8443/"
echo "  API:      https://localhost:8443/api/tags"
echo "Press Ctrl+C to stop."

cleanup() {
    echo "Stopping..."
    kill $LUNET_PID 2>/dev/null || true
    nginx -p $PWD -c bench/lunet/nginx-https.conf -s stop 2>/dev/null || true
    rm -f "$SOCKET_PATH"
}
trap cleanup EXIT INT TERM

wait $LUNET_PID

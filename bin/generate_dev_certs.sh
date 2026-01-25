#!/bin/bash
set -e

CERT_DIR=".tmp/certs"
mkdir -p "$CERT_DIR"

if [ -f "$CERT_DIR/server.key" ] && [ -f "$CERT_DIR/server.crt" ]; then
    echo "Certificates already exist in $CERT_DIR"
    exit 0
fi

echo "Generating self-signed development certificates in $CERT_DIR..."

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.crt" \
    -subj "/C=US/ST=State/L=City/O=Development/CN=localhost"

echo "Done."

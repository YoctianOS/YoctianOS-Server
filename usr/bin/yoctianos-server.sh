#!/bin/sh 

FEED_DIR="/root/YoctianOS"
PORT=5678
SCREEN_NAME="yoctianos-server"
SERVER_BIN="/usr/bin/static-web-server"

# Check directory
if [ ! -d "$FEED_DIR" ]; then
  echo "Error: Feed directory '$FEED_DIR' not found."
  exit 1
fi

# Check binary
if [ ! -x "$SERVER_BIN" ]; then
  echo "Error: Static Web Server binary not found at $SERVER_BIN"
  exit 1
fi

# Check screen
if ! command -v screen >/dev/null 2>&1; then
  echo "Error: screen not installed"
  exit 1
fi

# Stop old session
if screen -list | grep -q "$SCREEN_NAME"; then
  echo "Stopping existing screen session..."
  screen -S "$SCREEN_NAME" -X quit
fi

# Start server
echo "Starting YoctianOS-Server on port $PORT..."
screen -dmS "$SCREEN_NAME" sh -c "$SERVER_BIN --directory-listing true --root $FEED_DIR --port $PORT"

IP=$(ip addr show br-lan | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
echo "Server running in screen session '$SCREEN_NAME'."
echo "Access it at: http://$IP:$PORT"

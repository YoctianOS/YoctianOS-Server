#!/bin/bash

# Yocto package feed directory
FEED_DIR="(...)/srv/yocto/deb"

# Port to serve on
PORT=5678

# Check if directory exists
if [ ! -d "$FEED_DIR" ]; then
  echo "Error: Feed directory '$FEED_DIR' not found."
  exit 1
fi

## Screen package ne to be downloaded

# Start server inside screen
SCREEN_NAME="yocto-feed"

# Kill existing screen session if running
if screen -list | grep -q "$SCREEN_NAME"; then
  echo "Stopping existing screen session..."
  screen -S "$SCREEN_NAME" -X quit
fi

# Start new screen session with Static Web Server (need to be downloaded)
echo "Starting Yocto feed server on port $PORT using Static Web Server..."
screen -dmS "$SCREEN_NAME" bash -c "(...)/static-web-server --directory-listing true --root $FEED_DIR --port $PORT"

echo "Server running in screen session '$SCREEN_NAME'."
echo "Access it at: http://$(hostname -I | awk '{print $1}'):$PORT"


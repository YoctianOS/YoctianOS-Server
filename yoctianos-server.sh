#!/bin/bash

# YoctianOS package directory (update if needed)
FEED_DIR="./yoctianos/deb"

# Port to serve on
PORT=5678

# Check if directory exists
if [ ! -d "$FEED_DIR" ]; then
  echo "Error: Feed directory '$FEED_DIR' not found."
  exit 1
fi

# --- Detect package manager ---
install_pkg() {
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y "$@"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$@"
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y "$@"
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y "$@"
    else
        echo "Error: No supported package manager found (apt, dnf, yum, zypper)."
        exit 1
    fi
}

# --- Ensure dependencies ---
for pkg in screen wget tar; do
    if ! command -v $pkg >/dev/null 2>&1; then
        echo "Installing missing package: $pkg"
        install_pkg $pkg
    else
        echo "$pkg already installed."
    fi
done

# --- Screen session name ---
SCREEN_NAME="yoctianos-server"

# Kill existing screen session if running
if screen -list | grep -q "$SCREEN_NAME"; then
  echo "Stopping existing screen session..."
  screen -S "$SCREEN_NAME" -X quit
fi

# --- Static Web Server binary ---
SERVER_BIN="./static-web-server"
VERSION="v2.40.1"
BASE_URL="https://github.com/static-web-server/static-web-server/releases/download/$VERSION"
ARCH=$(uname -m)

case "$ARCH" in
    x86_64) FILE="static-web-server-${VERSION}-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64) FILE="static-web-server-${VERSION}-aarch64-unknown-linux-musl.tar.gz" ;;
    armv7l) FILE="static-web-server-${VERSION}-armv7-unknown-linux-musleabihf.tar.gz" ;;
    i686) FILE="static-web-server-${VERSION}-i686-unknown-linux-musl.tar.gz" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

if [ ! -x "$SERVER_BIN" ]; then
    echo "Downloading $FILE..."
    wget -O /tmp/$FILE "$BASE_URL/$FILE"
    tar -xzf /tmp/$FILE -C /tmp
    mv /tmp/static-web-server "$SERVER_BIN"
    chmod +x "$SERVER_BIN"
    rm -f /tmp/$FILE
    echo "Installed static-web-server to $SERVER_BIN"
else
    echo "static-web-server already present at $SERVER_BIN"
fi

# --- Start server inside screen ---
echo "Starting YoctianOS-Server on port $PORT using Static Web Server..."
screen -dmS "$SCREEN_NAME" bash -c "$SERVER_BIN --directory-listing true --root $FEED_DIR --port $PORT"

echo "Server running in screen session '$SCREEN_NAME'."
echo "Access it at: http://$(hostname -I | awk '{print $1}'):$PORT"

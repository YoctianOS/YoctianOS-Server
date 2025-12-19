#!/bin/sh

# Ensure required packages are installed
if ! command -v screen >/dev/null 2>&1; then
    echo "Installing screen..."
    opkg update && opkg install screen || { echo "Error: failed to install screen"; exit 1; }
else
    echo "screen already installed."
fi

if ! command -v wget >/dev/null 2>&1; then
    echo "Installing wget..."
    opkg update && opkg install wget || { echo "Error: failed to install wget"; exit 1; }
else
    echo "wget already installed."
fi

if ! command -v tar >/dev/null 2>&1; then
    echo "Installing tar..."
    opkg update && opkg install tar || { echo "Error: failed to install tar"; exit 1; }
else
    echo "tar already installed."
fi

# Repo base (current directory)
REPO_DIR="./"

# Target system paths
INITD_DIR="/etc/init.d"
BIN_DIR="/usr/bin"
FEED_DIR="/root"

# --- Install init.d script ---
if [ -f "$REPO_DIR/etc/init.d/yoctianos-server" ]; then
    echo "Installing init.d script..."
    install -m 755 "$REPO_DIR/etc/init.d/yoctianos-server" "$INITD_DIR/yoctianos-server"
else
    echo "Error: $REPO_DIR/etc/init.d/yoctianos-server not found"
    exit 1
fi

# --- Install yoctianos-server.sh ---
if [ -f "$REPO_DIR/usr/bin/yoctianos-server.sh" ]; then
    echo "Installing yoctianos-server.sh..."
    install -m 755 "$REPO_DIR/usr/bin/yoctianos-server.sh" "$BIN_DIR/yoctianos-server.sh"
else
    echo "Error: $REPO_DIR/usr/bin/yoctianos-server.sh not found"
    exit 1
fi

# --- Copy feed directory ---
if [ -d "$REPO_DIR/root/yoctianos/deb" ]; then
    echo "Installing feed directory..."
    mkdir -p "$FEED_DIR/yoctianos/deb"
    cp -r "$REPO_DIR/root/yoctianos/deb/"* "$FEED_DIR/yoctianos/deb/"
else
    echo "Warning: $REPO_DIR/root/yoctianos/deb not found, skipping feed copy"
fi

# --- Install static-web-server binary ---
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

echo "Downloading $FILE..."
wget -O /tmp/$FILE "$BASE_URL/$FILE"
tar -xzf /tmp/$FILE -C /tmp

if [ -f "/tmp/static-web-server" ]; then
    echo "Installing static-web-server..."
    install -m 755 /tmp/static-web-server "$BIN_DIR/static-web-server"
    rm -f /tmp/$FILE /tmp/static-web-server
else
    echo "Error: static-web-server binary not found after extraction"
    exit 1
fi

echo "Installation complete!"
echo "Enable service with: /etc/init.d/yoctianos-server enable && /etc/init.d/yoctianos-server start"

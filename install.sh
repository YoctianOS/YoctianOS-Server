#!/bin/sh
set -euo pipefail

# Cleanup on exit
TMPDIR=""
TMPARCHIVE=""
cleanup() {
    [ -n "${TMPDIR:-}" ] && rm -rf "${TMPDIR}" || true
    [ -n "${TMPARCHIVE:-}" ] && rm -f "${TMPARCHIVE}" || true
}
trap cleanup EXIT

# Ensure required packages are installed (install only once)
need_pkg=""
for pkg in screen wget tar; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        need_pkg="$need_pkg $pkg"
    fi
done

if [ -n "${need_pkg}" ]; then
    echo "Installing missing packages:${need_pkg}"
    opkg update
    for p in $need_pkg; do
        opkg install "$p" || { echo "Error: failed to install $p"; exit 1; }
    done
else
    echo "All required packages present."
fi

# Repo base (current directory)
REPO_DIR="./"

# Target system paths
INITD_DIR="/etc/init.d"
BIN_DIR="/usr/bin"
FEED_DIR="/root"

# Ensure target dirs exist
mkdir -p "$INITD_DIR" "$BIN_DIR" "$FEED_DIR"

# --- Install init.d script ---
if [ -f "$REPO_DIR/etc/init.d/yoctianos-server" ]; then
    echo "Installing init.d script..."
    cp "$REPO_DIR/etc/init.d/yoctianos-server" "$INITD_DIR/yoctianos-server"
    chmod 755 "$INITD_DIR/yoctianos-server"
    echo "Installed $INITD_DIR/yoctianos-server"
else
    echo "Error: $REPO_DIR/etc/init.d/yoctianos-server not found"
    exit 1
fi

# --- Install yoctianos-server.sh ---
if [ -f "$REPO_DIR/usr/bin/yoctianos-server.sh" ]; then
    echo "Installing yoctianos-server.sh..."
    cp "$REPO_DIR/usr/bin/yoctianos-server.sh" "$BIN_DIR/yoctianos-server.sh"
    chmod 755 "$BIN_DIR/yoctianos-server.sh"
    echo "Installed $BIN_DIR/yoctianos-server.sh"
else
    echo "Error: $REPO_DIR/usr/bin/yoctianos-server.sh not found"
    exit 1
fi

# --- Copy feed directory ---
if [ -d "$REPO_DIR/root/YoctianOS" ]; then
    echo "Installing feed directory..."
    mkdir -p "$FEED_DIRYoctianOS"
    cp -r "$REPO_DIR/root/YoctianOS/"* "$FEED_DIR/YoctianOS/" || true
else
    echo "Warning: $REPO_DIR/root/YoctianOS not found, skipping feed copy"
fi

# --- Install static-web-server binary (robust, BusyBox-friendly) ---
VERSION="v2.40.1"
BASE_URL="https://github.com/static-web-server/static-web-server/releases/download/$VERSION"
ARCH=$(uname -m)

case "$ARCH" in
    x86_64) FILE="static-web-server-${VERSION}-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64) FILE="static-web-server-${VERSION}-aarch64-unknown-linux-musl.tar.gz" ;;
    armv7l) FILE="static-web-server-${VERSION}-armv7-unknown-linux-musleabihf.tar.gz" ;;
    i686|i386) FILE="static-web-server-${VERSION}-i686-unknown-linux-musl.tar.gz" ;;
    mips|mipsel|arm*)
        echo "Warning: prebuilt static-web-server may not be available for architecture: $ARCH"
        FILE=""
        ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

if [ -z "$FILE" ]; then
    echo "No suitable prebuilt archive filename for $ARCH; skipping static-web-server install."
else
    TMPDIR="$(mktemp -d)"
    TMPARCHIVE="/tmp/$FILE"

    echo "Downloading $FILE..."
    if command -v wget >/dev/null 2>&1; then
        if ! wget -O "$TMPARCHIVE" "$BASE_URL/$FILE"; then
            echo "Error: download failed for $BASE_URL/$FILE"
            exit 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if ! curl -L -o "$TMPARCHIVE" "$BASE_URL/$FILE"; then
            echo "Error: download failed for $BASE_URL/$FILE"
            exit 1
        fi
    else
        echo "Error: neither wget nor curl available"
        exit 1
    fi

    echo "Extracting to $TMPDIR..."
    if ! tar -xzf "$TMPARCHIVE" -C "$TMPDIR"; then
        echo "Error: failed to extract $TMPARCHIVE"
        exit 1
    fi

    # BusyBox-compatible: find the first matching file and use head
    BIN_PATH="$(find "$TMPDIR" -type f -name static-web-server 2>/dev/null | head -n 1 || true)"

    if [ -n "$BIN_PATH" ]; then
        echo "Installing static-web-server from $BIN_PATH..."
        cp "$BIN_PATH" "$BIN_DIR/static-web-server"
        chmod 755 "$BIN_DIR/static-web-server"
        echo "static-web-server installed to $BIN_DIR/static-web-server"
    else
        echo "Error: static-web-server binary not found after extraction. Listing extracted tree:"
        ls -R "$TMPDIR" || true
        exit 1
    fi
fi

echo "Installation complete!"
echo "Enable service with: /etc/init.d/yoctianos-server enable && /etc/init.d/yoctianos-server start"

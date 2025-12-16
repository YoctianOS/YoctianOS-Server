#!/bin/sh

# Target system paths
INITD_SCRIPT="/etc/init.d/yocto-server"
BIN_SCRIPT="/usr/bin/yocto-server.sh"
BIN_SERVER="/usr/bin/static-web-server"
PIDFILE="/var/run/yocto-server.pid"

echo "Stopping service if running..."
if [ -x "$INITD_SCRIPT" ]; then
    $INITD_SCRIPT stop 2>/dev/null
fi

# Remove init.d script
if [ -f "$INITD_SCRIPT" ]; then
    echo "Removing init.d script..."
    rm -f "$INITD_SCRIPT"
else
    echo "Init.d script not found, skipping."
fi

# Remove yocto-server.sh
if [ -f "$BIN_SCRIPT" ]; then
    echo "Removing yocto-server.sh..."
    rm -f "$BIN_SCRIPT"
else
    echo "yocto-server.sh not found, skipping."
fi

# Remove static-web-server binary
if [ -f "$BIN_SERVER" ]; then
    echo "Removing static-web-server binary..."
    rm -f "$BIN_SERVER"
else
    echo "static-web-server not found, skipping."
fi

# Clean up PID file
if [ -f "$PIDFILE" ]; then
    echo "Removing PID file..."
    rm -f "$PIDFILE"
fi

echo "Uninstallation complete!"
echo "Reminder: If you no longer need dependencies like 'screen', 'wget', or 'tar', you can remove them with:"
echo "   opkg remove screen wget tar"

#!/usr/bin/env bash

# Cortex-Debug invokes this file as the Linux J-Link GDB server executable.
# The probe is attached to WSL with usbipd, so this must never fall back to
# the Windows .exe.
set -euo pipefail

jlink_server=''
if [[ -n "${JLINK_GDB_SERVER:-}" && -x "$JLINK_GDB_SERVER" ]]; then
    jlink_server="$JLINK_GDB_SERVER"
else
    for candidate in \
        /opt/SEGGER/JLink/JLinkGDBServerCLExe \
        /opt/SEGGER/JLink/JLinkGDBServerCL \
        /usr/local/bin/JLinkGDBServerCLExe \
        /usr/local/bin/JLinkGDBServerCL \
        /usr/bin/JLinkGDBServerCLExe \
        /usr/bin/JLinkGDBServerCL; do
        if [[ -x "$candidate" ]]; then
            jlink_server="$candidate"
            break
        fi
    done
fi

if [[ -z "$jlink_server" ]]; then
    echo "Linux SEGGER J-Link GDB Server was not found in WSL." >&2
    echo "Install the SEGGER J-Link Software Pack for Linux and set:" >&2
    echo "  export JLINK_GDB_SERVER=/opt/SEGGER/JLink/JLinkGDBServerCLExe" >&2
    echo "The Windows .exe is intentionally not used because J-Link is attached to WSL." >&2
    exit 127
fi

exec "$jlink_server" "$@"

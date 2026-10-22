#!/usr/bin/env bash
# IONFALL dedicated server launcher (Linux). Arguments go to the server, e.g.
#   ./ionfall_server.sh --name "Office LAN" --map spire --mode tdm --bots 6
# Ctrl+C or SIGTERM (systemd, docker stop) shut the server down gracefully:
# players are told the server is closing instead of timing out.
cd "$(dirname "$0")" || exit 1
STOP_FILE="$PWD/ionfall_server.stop"
rm -f "$STOP_FILE"
./ionfall_server.x86_64 --headless -- --stop-file "$STOP_FILE" "$@" &
PID=$!
trap 'touch "$STOP_FILE"' INT TERM
# `wait` returns early when a trapped signal arrives; keep waiting for the exit.
while kill -0 "$PID" 2>/dev/null; do
	wait "$PID"
done
wait "$PID" 2>/dev/null

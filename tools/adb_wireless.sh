#!/usr/bin/env bash
# Wireless adb to an Android 11+ phone on the same Wi-Fi. This distro's adb
# has no mDNS, so the phone's ports are found with avahi-browse.
#
#   tools/adb_wireless.sh pair 123456   # once: phone > Developer options >
#                                       # Wireless debugging > Pair device with
#                                       # pairing code (keep that screen open)
#   tools/adb_wireless.sh               # connect (again after a restart)
#   tools/adb_wireless.sh status
set -euo pipefail

find_service() {  # $1: _adb-tls-pairing._tcp or _adb-tls-connect._tcp -> "ip:port"
	timeout 6 avahi-browse -rpt "$1" 2>/dev/null \
		| awk -F';' '$1 == "=" && $3 == "IPv4" { print $8 ":" $9; exit }'
}

case "${1:-connect}" in
	pair)
		code="${2:?usage: $0 pair <6-digit code>}"
		target="${3:-$(find_service _adb-tls-pairing._tcp)}"
		[ -n "$target" ] || { echo "No phone is offering pairing: open 'Pair device with pairing code' on it."; exit 1; }
		echo "Pairing with $target"
		adb pair "$target" "$code"
		"$0" connect
		;;
	connect)
		target="${2:-$(find_service _adb-tls-connect._tcp)}"
		[ -n "$target" ] || { echo "No phone found: turn on Wireless debugging (same Wi-Fi as this PC)."; exit 1; }
		adb connect "$target"
		adb devices -l
		;;
	status)
		echo "pairing: $(find_service _adb-tls-pairing._tcp || true)"
		echo "connect: $(find_service _adb-tls-connect._tcp || true)"
		adb devices -l
		;;
	*)
		echo "usage: $0 [pair <code> [ip:port] | connect [ip:port] | status]"
		exit 1
		;;
esac

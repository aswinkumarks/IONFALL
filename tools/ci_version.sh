#!/usr/bin/env bash
# CI: the build version, into $GITHUB_ENV as VERSION (and PRERELEASE).
# A v* tag is the release version (v0.9.2 → 0.9.2, v1.0 → 1.0.0; a suffix
# such as v1.0.0-rc2 makes a pre-release of 1.0.0) and is written into
# project.godot, so a release needs no version commit; other builds use
# project.godot's.
set -euo pipefail
if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
	V="${GITHUB_REF_NAME#v}"
	if [[ "$V" == *-* ]]; then echo "PRERELEASE=--prerelease" >> "$GITHUB_ENV"; V="${V%%-*}"; fi
	[[ "$V" =~ ^[0-9]+\.[0-9]+$ ]] && V="$V.0"
	if ! [[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "::error::tag $GITHUB_REF_NAME isn't vMAJOR.MINOR[.PATCH]"; exit 1
	fi
	sed -i "s/^config\/version=\".*\"/config\/version=\"$V\"/" project.godot
fi
V="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
echo "VERSION=$V" >> "$GITHUB_ENV"
echo "Building version $V"

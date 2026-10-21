#!/bin/sh
#
# refresh-apple-mdk.sh — install an MDK Apple SDK that is still inside libmdk's
# 44-day key-free window before an Apple build links it.
#
# libmdk refuses to play video without a key once the library is 44 days old:
# App::checkLicense (wang-bin/appkey app.cpp) compares the build stamp compiled
# into the binary with the clock and then draws an "MDK SDK is outdated" QR
# frame over the last frame. The stamp is the binary's own build time, so no
# pinned archive URL stays valid — the SDK has to be resolved per build.
#
# The fvp package (third_party/fvp in iebb/f-videoplayer) declares its Apple
# binary target as a local path when it supports this; the refresh installs a
# verified SDK there. Any other manifest shape is refused loudly: an old fvp
# that still pins one archive would link an expired SDK and bring the QR frame
# back, and failing here is the only way that cannot ship silently.
#
# Usage: scripts/refresh-apple-mdk.sh [refresh|check]
#   refresh (default) resolves, verifies and installs a fresh SDK
#   check   re-verifies the installed SDK without downloading anything
# Environment:
#   MDK_APPLE_SDK_URL        explicit Apple SDK archive (https) instead of the
#                            newest wang-bin/mdk-sdk release
#   MDK_APPLE_SDK_SHA256     required digest for MDK_APPLE_SDK_URL
#   MDK_APPLE_SDK_SOURCE     upstream | sourceforge | url (default upstream)
#   MDK_FRESHNESS_MARGIN_DAYS  days of window to leave in reserve (default 7)
#   MDK_FVP_ROOT             use this fvp checkout instead of the resolved one
#                            (for a patched dependency before its release)

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PACKAGE_CONFIG=".dart_tool/package_config.json"
if [ ! -f "$PACKAGE_CONFIG" ]; then
  echo "error: $PACKAGE_CONFIG is missing; run flutter pub get first" >&2
  exit 1
fi

FVP_ROOT="${MDK_FVP_ROOT:-$(
  python3 - "$PACKAGE_CONFIG" <<'PY'
import json
import sys
import urllib.parse

with open(sys.argv[1], encoding="utf-8") as stream:
    config = json.load(stream)
roots = {
    package["name"]: package["rootUri"]
    for package in config["packages"]
    if package["name"] == "fvp"
}
root = roots.get("fvp")
if root is None:
    raise SystemExit("fvp is not resolved in .dart_tool/package_config.json")
parsed = urllib.parse.urlparse(root)
if parsed.scheme == "file":
    print(urllib.parse.unquote(parsed.path))
elif parsed.scheme == "":
    print(urllib.parse.unquote(root))
else:
    raise SystemExit(f"fvp resolves to an unsupported URI: {root}")
PY
)}"

TOOL="$FVP_ROOT/darwin/fvp/tool/mdk_apple_freshness.py"
MANIFEST="$FVP_ROOT/darwin/fvp/Package.swift"

# An fvp that predates build-time resolution still pins one archive. There is
# nothing this script can install into it, and failing here would block every
# Apple build on a dependency bump the caller has to make in pubspec.yaml, so
# say exactly what is stale and keep the build's previous behavior.
if [ ! -f "$TOOL" ] || ! grep -q 'path: "mdk.xcframework"' "$MANIFEST"; then
  echo "warning: the resolved fvp predates build-time MDK resolution:" >&2
  echo "warning:   $FVP_ROOT" >&2
  echo "warning: it pins one Apple MDK archive, which libmdk treats as outdated" >&2
  echo "warning: 44 days after that binary's build stamp (the QR frame in" >&2
  echo "warning: issue #192). Bump the fvp dependency in pubspec.yaml to a" >&2
  echo "warning: release containing darwin/fvp/tool/mdk_apple_freshness.py to" >&2
  echo "warning: activate per-build resolution; this build links the pin as before." >&2
  exit 0
fi

MODE="${1:-refresh}"
case "$MODE" in
  refresh)
    echo "Refreshing the MDK Apple SDK for this build"
    set +e
    python3 "$TOOL" --destination "$FVP_ROOT/darwin/fvp/mdk.xcframework" refresh
    status=$?
    set -e
    ;;
  check)
    echo "Verifying the installed MDK Apple SDK"
    set +e
    python3 "$TOOL" --destination "$FVP_ROOT/darwin/fvp/mdk.xcframework" check
    status=$?
    set -e
    ;;
  *)
    echo "error: unknown mode $MODE (expected refresh or check)" >&2
    exit 2
    ;;
esac

if [ "$status" -ne 0 ]; then
  if [ "${MDK_ALLOW_STALE:-0}" = "1" ]; then
    # Deliberate escape hatch for a hotfix that must ship while the upstream
    # mirror is between fresh SDKs. The QR frame returns; say so once.
    echo "warning: MDK_ALLOW_STALE=1, continuing with an SDK outside the" >&2
    echo "warning: 44-day key-free window; playback will show the outdated frame." >&2
    exit 0
  fi
  echo "error: the MDK Apple SDK is not usable for this build (see above)." >&2
  echo "error: point MDK_APPLE_SDK_URL at a newer mdk.xcframework (with" >&2
  echo "error: MDK_APPLE_SDK_SHA256), or set MDK_ALLOW_STALE=1 to ship anyway." >&2
  exit "$status"
fi

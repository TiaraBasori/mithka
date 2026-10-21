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

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PACKAGE_CONFIG=".dart_tool/package_config.json"
if [ ! -f "$PACKAGE_CONFIG" ]; then
  echo "error: $PACKAGE_CONFIG is missing; run flutter pub get first" >&2
  exit 1
fi

FVP_ROOT="$(
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
)"

TOOL="$FVP_ROOT/darwin/fvp/tool/mdk_apple_freshness.py"
MANIFEST="$FVP_ROOT/darwin/fvp/Package.swift"
if [ ! -f "$TOOL" ]; then
  echo "error: the resolved fvp package has no $TOOL." >&2
  echo "error: it predates build-time MDK resolution, so its Apple binary" >&2
  echo "error: target would link an SDK that expires 44 days after its build." >&2
  echo "error: update the fvp dependency in pubspec.yaml to a release that" >&2
  echo "error: contains darwin/fvp/tool/mdk_apple_freshness.py." >&2
  exit 1
fi
if ! grep -q 'path: "mdk.xcframework"' "$MANIFEST"; then
  echo "error: $MANIFEST does not declare mdk.xcframework as a local" >&2
  echo "error: binary target, so a refreshed SDK would not be the one linked." >&2
  echo "error: update the fvp dependency in pubspec.yaml." >&2
  exit 1
fi

MODE="${1:-refresh}"
case "$MODE" in
  refresh)
    echo "Refreshing the MDK Apple SDK for this build"
    python3 "$TOOL" --destination "$FVP_ROOT/darwin/fvp/mdk.xcframework" refresh
    ;;
  check)
    echo "Verifying the installed MDK Apple SDK"
    python3 "$TOOL" --destination "$FVP_ROOT/darwin/fvp/mdk.xcframework" check
    ;;
  *)
    echo "error: unknown mode $MODE (expected refresh or check)" >&2
    exit 2
    ;;
esac

#!/bin/sh

# Build the same TgVoipWebrtc target used by Telegram iOS, then package its
# device and Apple-silicon simulator slices as an XCFramework for Mithka.

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 TELEGRAM_IOS_SOURCE [OUTPUT_DIRECTORY]" >&2
  exit 2
fi

TELEGRAM_SOURCE="$(cd "$1" && pwd)"
OUTPUT_DIRECTORY="${2:-$PWD/build/tgvoip-ios}"
BUILD_FILE="$TELEGRAM_SOURCE/submodules/TgVoipWebrtc/BUILD"
CONFIGURATION_REPOSITORY="${TELEGRAM_BUILD_CONFIGURATION_REPOSITORY:-$TELEGRAM_SOURCE/build-input/configuration-repository}"

if [ ! -f "$BUILD_FILE" ]; then
  echo "error: Telegram-iOS must be cloned recursively" >&2
  exit 1
fi
if [ ! -d "$CONFIGURATION_REPOSITORY" ]; then
  echo "error: Telegram build configuration repository is missing: $CONFIGURATION_REPOSITORY" >&2
  echo "run Telegram-iOS Make.py generateProject once, or set TELEGRAM_BUILD_CONFIGURATION_REPOSITORY" >&2
  exit 1
fi

if [ -n "${BAZEL:-}" ]; then
  BAZEL_BIN="$BAZEL"
else
  BAZEL_BIN="$(find "$TELEGRAM_SOURCE/build-input" -maxdepth 1 -type f -name 'bazel-*-darwin-*' -perm +111 2>/dev/null | head -1 || true)"
  if [ -z "$BAZEL_BIN" ]; then
    BAZEL_BIN="$(command -v bazel || true)"
  fi
fi
if [ -z "$BAZEL_BIN" ]; then
  echo "error: no Bazel executable found; set BAZEL" >&2
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/mithka-tgvoip.XXXXXX")"
ORIGINAL_BUILD="$TMP/BUILD.original"
cp "$BUILD_FILE" "$ORIGINAL_BUILD"
cleanup() {
  cp "$ORIGINAL_BUILD" "$BUILD_FILE"
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

python3 - "$BUILD_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = 'load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")'
new = 'load("@build_bazel_rules_apple//apple:ios.bzl", "ios_static_framework", "ios_unit_test")'
if old not in text and new not in text:
    raise SystemExit("unexpected Telegram TgVoipWebrtc BUILD load statement")
text = text.replace(old, new, 1)
if 'name = "MithkaTgVoipWebrtcFramework"' not in text:
    text += '''

ios_static_framework(
    name = "MithkaTgVoipWebrtcFramework",
    bundle_name = "TgVoipWebrtc",
    hdrs = glob(["PublicHeaders/**/*.h"]),
    minimum_os_version = "15.0",
    deps = [":TgVoipWebrtc"],
)
'''
path.write_text(text)
PY

TARGET="//submodules/TgVoipWebrtc:MithkaTgVoipWebrtcFramework"
XCODE_VERSION="${BAZEL_XCODE_VERSION:-$(xcodebuild -version | sed -n '1s/^Xcode //p')}"

build_slice() {
  cpu="$1"
  destination="$2"
  (
    cd "$TELEGRAM_SOURCE"
    "$BAZEL_BIN" build "$TARGET" \
      --override_repository="build_configuration=$CONFIGURATION_REPOSITORY" \
      --apple_platform_type=ios \
      --ios_multi_cpus="$cpu" \
      --xcode_version="$XCODE_VERSION" \
      -c opt
  )
  mkdir -p "$destination"
  unzip -q -o \
    "$TELEGRAM_SOURCE/bazel-bin/submodules/TgVoipWebrtc/MithkaTgVoipWebrtcFramework.zip" \
    -d "$destination"
}

build_slice arm64 "$TMP/device"
build_slice sim_arm64 "$TMP/simulator"

rm -rf "$OUTPUT_DIRECTORY"
mkdir -p "$OUTPUT_DIRECTORY"
xcodebuild -create-xcframework \
  -framework "$TMP/device/TgVoipWebrtc.framework" \
  -framework "$TMP/simulator/TgVoipWebrtc.framework" \
  -output "$OUTPUT_DIRECTORY/TgVoipWebrtc.xcframework"
(
  cd "$OUTPUT_DIRECTORY"
  rm -f tgvoip-ios.xcframework.zip
  zip -qry tgvoip-ios.xcframework.zip TgVoipWebrtc.xcframework
)

echo "$OUTPUT_DIRECTORY/TgVoipWebrtc.xcframework"
echo "$OUTPUT_DIRECTORY/tgvoip-ios.xcframework.zip"

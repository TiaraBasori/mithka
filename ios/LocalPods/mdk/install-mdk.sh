#!/bin/sh
set -e

version="0.36.0"
url="${MITHKA_MDK_SDK_URL:-https://github.com/wang-bin/mdk-sdk/releases/download/v${version}/mdk-sdk-apple.tar.xz}"
sha256="${MITHKA_MDK_SDK_SHA256:-b5742718d348b2dbb2bb64282f021529e76ea5d8e22d664b4730960c5e24502a}"
cache_dir="${TMPDIR:-/tmp}/mithka-mdk-cache"
archive="$cache_dir/mdk-sdk-apple-$version.tar.xz"
partial="$archive.partial"

install_headers() {
  rm -rf include
  mkdir -p include/mdk
  cp -R \
    mdk-sdk/lib/mdk.xcframework/ios-arm64/mdk.framework/Headers/. \
    include/mdk/
  test -f include/mdk/Player.h
}

if [ -d mdk-sdk/lib/mdk.xcframework ]; then
  install_headers
  exit 0
fi

mkdir -p "$cache_dir"

checksum() {
  shasum -a 256 "$1" | awk '{print $1}'
}

valid_archive() {
  [ -s "$archive" ] && [ "$(checksum "$archive")" = "$sha256" ]
}

curl_flags="-fL --retry 8 --retry-delay 3 --connect-timeout 20 --speed-time 60 --speed-limit 1024"
if curl --help all 2>/dev/null | grep -q -- '--retry-all-errors'; then
  curl_flags="$curl_flags --retry-all-errors"
fi

attempt=1
delay=5
while ! valid_archive; do
  if [ "$attempt" -gt 4 ]; then
    echo "error: failed to download mdk $version after 4 attempts" >&2
    exit 1
  fi

  echo "downloading mdk $version from $url (attempt $attempt/4)"
  # shellcheck disable=SC2086 # curl_flags is intentionally split.
  if curl $curl_flags -C - -o "$partial" "$url"; then
    actual="$(checksum "$partial")"
    if [ "$actual" = "$sha256" ]; then
      mv "$partial" "$archive"
      break
    fi
    echo "warning: mdk checksum mismatch: expected $sha256, got $actual" >&2
    rm -f "$partial"
  else
    status=$?
    echo "warning: mdk download failed with exit $status" >&2
  fi

  echo "retrying mdk download in ${delay}s" >&2
  sleep "$delay"
  attempt=$((attempt + 1))
  delay=$((delay * 2))
done

rm -rf mdk-sdk
tar -xJf "$archive" mdk-sdk
test -d mdk-sdk/lib/mdk.xcframework
install_headers

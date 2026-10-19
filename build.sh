#!/bin/bash
# Builds PDFBar.app as a universal binary (Apple Silicon + Intel).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="PDFBar"
APP="${APP_NAME}.app"
OUT=".build/universal"
DEPLOYMENT="14.0"

echo "→ Compiling universal binary (arm64 + x86_64)…"
mkdir -p "${OUT}"

# SwiftPM's --arch flag needs to rewrite .build/release, which fails in
# restricted environments. Compiling each slice with swiftc and stitching
# them with lipo is deterministic and works everywhere Xcode CLT exists.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
LIST="$(mktemp)"
trap 'rm -f "${LIST}"' EXIT
find Sources -name "*.swift" -print0 > "${LIST}"

SLICES=()
for ARCH in arm64 x86_64; do
  TARGET="${ARCH}-apple-macosx${DEPLOYMENT}"
  xargs -0 xcrun --sdk macosx swiftc \
    -O -disable-sandbox -sdk "${SDK}" -target "${TARGET}" \
    -o "${OUT}/${APP_NAME}-${ARCH}" < "${LIST}"
  SLICES+=("${OUT}/${APP_NAME}-${ARCH}")
done

lipo -create -output "${OUT}/${APP_NAME}" "${SLICES[@]}"
lipo -archs "${OUT}/${APP_NAME}"

echo "→ Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${OUT}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

echo "→ Signing (ad-hoc)…"
codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || \
  echo "   (ad-hoc signing skipped — the app still runs locally)"

echo "→ Done: $(pwd)/${APP}"

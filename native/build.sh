#!/bin/bash
# Builds Translate.app and a distributable Translate.dmg into ./dist.
#
#   ./build.sh              universal (arm64 + x86_64)
#   ./build.sh --native     this machine's architecture only, much faster
#   ./build.sh --app-only   stop after the .app (the release notarises it first)
#   ./build.sh --dmg-only   package the .app already in ./dist
#
# Release builds go through the same script, with two variables set:
#
#   CODESIGN_IDENTITY="Developer ID Application: …"   real signature + hardened runtime
#   VERSION=1.2.0                                    stamped into the bundle
#
# Without CODESIGN_IDENTITY, a local build signs with the first "Apple
# Development" certificate in the keychain, and ad hoc only if there is none
# (or CODESIGN_IDENTITY=- asks for it). An ad-hoc signature changes on every
# build, so macOS would treat each one as a new app and forget its
# Accessibility grant; a certificate keeps it stable.
#
# That is deliberate: the .dmg the release workflow uploads is built by the
# same code path as the one you build by hand, so a local check means something.
# The two -only flags exist because notarisation has to happen between the two
# halves: the app is signed, notarised and stapled, and only then packaged.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Translate"
BUNDLE_ID="com.lennartbrocki.translate"
DIST="dist"
APP="$DIST/$APP_NAME.app"
ICON_SOURCE="Resources/AppIcon.icns"

ARCH_FLAGS=(--arch arm64 --arch x86_64)
BUILD_APP=1
BUILD_DMG=1
for arg in "$@"; do
  case "$arg" in
    --native) ARCH_FLAGS=() ;;
    --app-only) BUILD_DMG=0 ;;
    --dmg-only) BUILD_APP=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ $BUILD_APP == 1 ]]; then
  echo "==> Compiling"
  swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
  BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

  echo "==> Assembling $APP"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

  cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
  cp Resources-Info.plist "$APP/Contents/Info.plist"
  printf 'APPL????' > "$APP/Contents/PkgInfo"

  if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$APP/Contents/Resources/AppIcon.icns"
  else
    echo "    (no icon at $ICON_SOURCE — shipping without one)"
  fi

  if [[ -n "${VERSION:-}" ]]; then
    echo "==> Stamping version $VERSION"
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
  fi

  # An explicit identity is a release: the hardened runtime and a secure
  # timestamp are what notarisation requires. The fallback development
  # certificate needs neither, and a timestamp would need the network.
  if [[ -n "${CODESIGN_IDENTITY:-}" && "$CODESIGN_IDENTITY" != "-" ]]; then
    echo "==> Signing ($CODESIGN_IDENTITY)"
    codesign --force --sign "$CODESIGN_IDENTITY" \
      --options runtime --timestamp \
      "$APP"
    codesign --verify --strict --verbose=2 "$APP"
  else
    DEV_IDENTITY=""
    if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
      DEV_IDENTITY="$(security find-identity -v -p codesigning \
        | sed -n 's/^.*"\(Apple Development: .*\)"$/\1/p' | head -n 1)"
    fi
    if [[ -n "$DEV_IDENTITY" ]]; then
      echo "==> Signing ($DEV_IDENTITY)"
      codesign --force --sign "$DEV_IDENTITY" --timestamp=none "$APP"
    else
      echo "==> Signing (ad hoc — Accessibility must be re-granted after each build)"
      codesign --force --sign - --timestamp=none "$APP"
    fi
  fi
fi

if [[ $BUILD_DMG == 1 ]]; then
  echo "==> Building the disk image"
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"

  # Brand the mounted volume with the app icon.
  if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$STAGE/.VolumeIcon.icns"
    SetFile -a C "$STAGE" 2>/dev/null || true
  fi

  DMG="$DIST/${APP_NAME}.dmg"
  rm -f "$DMG"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    -quiet \
    "$DMG"
fi

echo
echo "App: $(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
if [[ $BUILD_DMG == 1 ]]; then
  echo "DMG: $(cd "$DIST" && pwd)/${APP_NAME}.dmg"
fi
echo "Identifier: $BUNDLE_ID"

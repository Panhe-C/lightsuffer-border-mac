#!/usr/bin/env bash
#
# scripts/bundle-app.sh - the .app bundle (and the zip and the DMG) of
# Light Suffer Frame.
#
#   scripts/bundle-app.sh [DEST]
#
# DEST is the folder of the artifacts (default: dist). The script needs macOS
# (it uses swift, iconutil, codesign, ditto and hdiutil).
#
# The binaries are built as universal binaries (arm64 + x86_64), the icon is
# drawn by `frame-cli icon` and turned into an .icns by `iconutil`, the bundle
# is signed ad hoc (no Apple account, no certificate) and the artifacts are a
# zip (ditto) and a DMG (hdiutil, UDZO) with the .app and a link to
# /Applications.

set -euo pipefail

# The settings of the bundle.
APP_NAME="Light Suffer Frame"
EXECUTABLE="LightSufferFrame"
HELPER="frame-cli"
BUNDLE_ID="com.lightsuffer.frame"
VERSION="0.1.0"
BUILD_NUMBER="1"
MINIMUM_SYSTEM="13.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The folder of the artifacts.
DEST="${1:-dist}"
case "$DEST" in
  /*) ;;
  *) DEST="$ROOT/$DEST" ;;
esac
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

# A scratch folder for the icon and for the DMG.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lightsuffer-bundle.XXXXXX")"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "==> Light Suffer Frame $VERSION ($BUNDLE_ID)"
echo "    the artifacts go to $DEST"

# MARK: - the binaries

if ! command -v lipo > /dev/null 2>&1; then
  echo "error: lipo is needed (the script only runs on macOS)" >&2
  exit 1
fi

# The architectures of a binary (nothing when lipo cannot read it).
binary_archs() {
  lipo -archs "$1" 2>/dev/null || true
}

# Has the binary both architectures?
has_both_archs() {
  local archs
  archs="$(binary_archs "$1")"
  case " $archs " in
    *" arm64 "*) ;;
    *) return 1 ;;
  esac
  case " $archs " in
    *" x86_64 "*) ;;
    *) return 1 ;;
  esac
  return 0
}

# The built products of a folder, the best first: the release ones of the
# universal build (the .build folder also holds the single architecture
# binaries of the intermediate steps of the build).
product_candidates() {
  local product="$1" dir="$2"
  [ -d "$dir" ] || return 0
  find "$dir" -type f -name "$product" 2>/dev/null \
    | grep -F '/Products/Release/' | sort || true
  find "$dir" -type f -name "$product" 2>/dev/null \
    | grep -F '/release/' | sort || true
  find "$dir" -type f -name "$product" 2>/dev/null | sort || true
}

# Resolves the path of a built product.
#
#   resolve_product PRODUCT DIR [SWIFT BUILD ARGUMENTS...]
#
# The build itself says where the product is (--show-bin-path); the search of
# the .build folder is the fallback. The universal binary comes first: the
# build of the two architectures keeps the single architecture ones in the
# .build folder too.
resolve_product() {
  local product="$1" dir="$2"
  shift 2
  local line candidate best=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ -d "$line" ] || continue
    candidate="$(cd "$line" && pwd)/$product"
    [ -f "$candidate" ] || continue
    if has_both_archs "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [ -z "$best" ]; then
      best="$candidate"
    fi
  done < <(swift build -c release "$@" --product "$product" --show-bin-path 2>/dev/null || true)
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if has_both_archs "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [ -z "$best" ]; then
      best="$candidate"
    fi
  done < <(product_candidates "$product" "$dir")
  printf '%s\n' "$best"
}

echo "==> building the universal release binaries"
swift build -c release --arch arm64 --arch x86_64 --product "$EXECUTABLE"
swift build -c release --arch arm64 --arch x86_64 --product "$HELPER"

APP_BINARY="$(resolve_product "$EXECUTABLE" "$ROOT/.build" --arch arm64 --arch x86_64)"
CLI_BINARY="$(resolve_product "$HELPER" "$ROOT/.build" --arch arm64 --arch x86_64)"
if [ -z "$APP_BINARY" ] || [ ! -f "$APP_BINARY" ] \
  || [ -z "$CLI_BINARY" ] || [ ! -f "$CLI_BINARY" ]; then
  echo "error: the release binaries were not found in $ROOT/.build" >&2
  exit 1
fi
echo "    the application: $APP_BINARY"
echo "    the helper: $CLI_BINARY"

# When the build did not make a universal binary (the two architectures are
# built apart), the two slices are joined with lipo.
if ! has_both_archs "$APP_BINARY" || ! has_both_archs "$CLI_BINARY"; then
  echo "==> the build is not universal, building the two architectures apart"
  for arch in arm64 x86_64; do
    swift build -c release --arch "$arch" --product "$EXECUTABLE" \
      --scratch-path "$ROOT/.build/universal-$arch"
    swift build -c release --arch "$arch" --product "$HELPER" \
      --scratch-path "$ROOT/.build/universal-$arch"
  done
  mkdir -p "$TMP/bin"
  for product in "$EXECUTABLE" "$HELPER"; do
    arm="$(resolve_product "$product" "$ROOT/.build/universal-arm64" \
      --arch arm64 --scratch-path "$ROOT/.build/universal-arm64")"
    intel="$(resolve_product "$product" "$ROOT/.build/universal-x86_64" \
      --arch x86_64 --scratch-path "$ROOT/.build/universal-x86_64")"
    if [ -z "$arm" ] || [ ! -f "$arm" ] || [ -z "$intel" ] || [ ! -f "$intel" ]; then
      echo "error: the $product binary of one architecture is missing" >&2
      exit 1
    fi
    lipo -create "$arm" "$intel" -output "$TMP/bin/$product"
    # lipo does not always keep the mode of the slices.
    chmod +x "$TMP/bin/$product"
  done
  APP_BINARY="$TMP/bin/$EXECUTABLE"
  CLI_BINARY="$TMP/bin/$HELPER"
fi

# The binaries are run by the script and by the bundle.
chmod +x "$APP_BINARY" "$CLI_BINARY" 2>/dev/null || true

# MARK: - the bundle

APP="$DEST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$APP_BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$CLI_BINARY" "$APP/Contents/MacOS/$HELPER"
chmod +x "$APP/Contents/MacOS/$EXECUTABLE" "$APP/Contents/MacOS/$HELPER"

echo "==> writing the Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleExecutable</key>
	<string>$EXECUTABLE</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MINIMUM_SYSTEM</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.photography</string>
	<key>NSHumanReadableCopyright</key>
	<string>Light Suffer Frame - GPLv3</string>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>JPEG picture</string>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.jpeg</string>
			</array>
		</dict>
		<dict>
			<key>CFBundleTypeName</key>
			<string>HEIC picture</string>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.heic</string>
			</array>
		</dict>
		<dict>
			<key>CFBundleTypeName</key>
			<string>PNG picture</string>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.png</string>
			</array>
		</dict>
		<dict>
			<key>CFBundleTypeName</key>
			<string>TIFF picture</string>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.tiff</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"

echo "==> drawing the icon"
if [ ! -x "$CLI_BINARY" ]; then
  chmod +x "$CLI_BINARY" || true
fi
if [ ! -x "$CLI_BINARY" ]; then
  echo "error: the helper $CLI_BINARY is not executable" >&2
  exit 1
fi
"$CLI_BINARY" icon "$TMP/AppIcon.iconset" > /dev/null
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> signing the bundle (ad hoc)"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP" || true

# MARK: - the artifacts

ZIP="$DEST/LightSufferFrame-$VERSION-universal.zip"
DMG="$DEST/LightSufferFrame-$VERSION-universal.dmg"

echo "==> writing the zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> writing the DMG"
STAGE="$TMP/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

# MARK: - the check

echo "==> checking the architectures"
for binary in "$APP/Contents/MacOS/$EXECUTABLE" "$APP/Contents/MacOS/$HELPER"; do
  archs="$(lipo -archs "$binary")"
  echo "    $binary: $archs"
  case " $archs " in
    *" arm64 "*) ;;
    *) echo "error: arm64 is missing in $binary" >&2; exit 1 ;;
  esac
  case " $archs " in
    *" x86_64 "*) ;;
    *) echo "error: x86_64 is missing in $binary" >&2; exit 1 ;;
  esac
done

echo
echo "the artifacts:"
echo "    $APP"
echo "    $ZIP"
echo "    $DMG"

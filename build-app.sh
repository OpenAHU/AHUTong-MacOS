#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

export CLANG_MODULE_CACHE_PATH="$SCRIPT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$SCRIPT_DIR/.build/module-cache"
export XDG_CACHE_HOME="$SCRIPT_DIR/.build/cache"

if [[ ! -f "$SCRIPT_DIR/Libraries/libahutong_rs.a" ]]; then
  if ! command -v cargo >/dev/null 2>&1; then
    echo "Missing Libraries/libahutong_rs.a and Rust cargo is not installed." >&2
    exit 1
  fi
  export CARGO_HOME="$SCRIPT_DIR/.build/cargo-home"
  export CARGO_TARGET_DIR="$SCRIPT_DIR/.build/rust-target"
  MACOSX_DEPLOYMENT_TARGET=14.0 cargo rustc \
    --manifest-path "$SCRIPT_DIR/Vendor/sdk/Cargo.toml" \
    --release \
    --features server \
    -- \
    --crate-type staticlib
  source_library="$(find "$CARGO_TARGET_DIR/release/deps" -name 'libahutong_rs.a' -print -quit)"
  mkdir -p "$SCRIPT_DIR/Libraries"
  cp "$source_library" "$SCRIPT_DIR/Libraries/libahutong_rs.a"
fi

# The debug configuration avoids a SwiftPM/Xcode beta dSYM issue while still
# producing a native, optimized-enough desktop executable with no dependencies.
swift build --disable-sandbox

STAGE_ROOT="$(mktemp -d /private/tmp/ahutong-macos.XXXXXX)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
APP_DIR="$STAGE_ROOT/安大通.app"
FINAL_APP_DIR="$SCRIPT_DIR/dist/安大通.app"
CONTENTS="$APP_DIR/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/debug/AHUTongMac" "$CONTENTS/MacOS/AHUTongMac"
cp "NOTICE" "$CONTENTS/Resources/NOTICE"
cp "LICENSE" "$CONTENTS/Resources/LICENSE"
mkdir -p "$CONTENTS/Resources/ThirdParty"
cp "Vendor/GuiXu-Rust/LICENSE" "$CONTENTS/Resources/ThirdParty/GuiXu-LICENSE" 2>/dev/null || true
cp "Vendor/GuiXu-Rust/NOTICE" "$CONTENTS/Resources/ThirdParty/GuiXu-NOTICE" 2>/dev/null || true

ICON_SOURCE="$SCRIPT_DIR/Assets/AppIconSource.png"
ASSET_CATALOG="$SCRIPT_DIR/.build/AppIcon.xcassets"
ICONSET="$ASSET_CATALOG/AppIcon.appiconset"
if [[ -f "$ICON_SOURCE" ]]; then
  rm -rf "$ASSET_CATALOG"
  mkdir -p "$ICONSET"
  cp "$SCRIPT_DIR/Assets/AppIconContents.json" "$ICONSET/Contents.json"
  cp -R "$SCRIPT_DIR/Assets/AppAssets.xcassets/AHULogo.imageset" "$ASSET_CATALOG/AHULogo.imageset"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  xcrun actool "$ASSET_CATALOG" \
    --compile "$CONTENTS/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$SCRIPT_DIR/.build/AppIconInfo.plist"
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>AHUTongMac</string>
    <key>CFBundleIdentifier</key><string>org.openahu.ahutong.macos</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>安大通</string>
    <key>CFBundleDisplayName</key><string>安大通</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.1.8</string>
    <key>CFBundleVersion</key><string>11</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
rm -rf "$FINAL_APP_DIR"
mkdir -p "$SCRIPT_DIR/dist"
ditto --norsrc "$APP_DIR" "$FINAL_APP_DIR"
xattr -cr "$FINAL_APP_DIR"
codesign --force --deep --sign - "$FINAL_APP_DIR"
# The staged app above is strictly verified. File Provider can immediately
# reattach Finder metadata after this workspace copy, so the distributable is
# strictly verified again from a clean temporary directory during packaging.
echo "Built: $FINAL_APP_DIR"

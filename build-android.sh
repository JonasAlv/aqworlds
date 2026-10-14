#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
if [ -f "$DIR/lib.sh" ]; then
    . "$DIR/lib.sh"
elif [ -f "$DIR/../aqw-mobile-mod/lib.sh" ]; then
    . "$DIR/../aqw-mobile-mod/lib.sh"
fi

resolve_air_env

BUILD="$DIR/build"
STAGING="$BUILD/staging"
OUTPUT_DIR="${OUTPUT_DIR:-$DIR/../android_builds_aqworlds}"

echo "=> Cleaning build sandbox and output directories..."

rm -rf "$STAGING"
rm -f "$BUILD/Pocket.swf"
rm -f "$BUILD"/Mobile-app-*.xml
mkdir -p "$BUILD"
mkdir -p "$STAGING"
mkdir -p "$OUTPUT_DIR"
rm -rf "${OUTPUT_DIR:?}"/*

trap 'rm -rf "$STAGING"' EXIT

if [ -n "${ARCH:-}" ] && [ "$ARCH" != "all" ]; then
    ARCHS=("$ARCH")
else
    ARCHS=("armv8" "armv7")
fi

TARGET_MODES=("$@")
if [ ${#TARGET_MODES[@]} -eq 0 ]; then
    TARGET_MODES=("cpu" "direct" "gpu")
fi

KEYSTORE="${KEYSTORE:-$DIR/aqwpocket_keystore_local.p12}"
HAXE_API_DIR="${HAXE_API_DIR:-$DIR/../aqw-haxe-api}"
HAXE_UI_DIR="${HAXE_UI_DIR:-$DIR/../aqw-haxe-ui}"

if [ "${SKIP_SYNC:-0}" = "1" ]; then
    echo "=> [0/5] SKIP_SYNC=1 - using cached upstream files."
elif ! "$DIR/sync-upstream.sh"; then
    echo "WARNING: Could not sync upstream APK; building with existing loader/ files." >&2
fi

if [ ! -f "$DIR/loader/src/AirShell.as" ]; then
    echo "ERROR: loader/src/AirShell.as is missing." >&2
    exit 1
fi

echo "=> [1/5] Copying repository files to sandbox ($STAGING)..."
mkdir -p "$STAGING/libs"
cp -r "$DIR/loader/src" "$STAGING/src"
cp -r "$DIR/loader/assets" "$STAGING/assets"
cp -r "$DIR/loader/icons" "$STAGING/icons"
cp -r "$DIR/loader/res" "$STAGING/res" 2>/dev/null || true
cp -r "$DIR/loader/META-INF" "$STAGING/META-INF" 2>/dev/null || true
cp "$DIR/loader/Mobile-app.xml" "$STAGING/Mobile-app.xml"
rm -f "$STAGING/assets/game.swf" "$STAGING/assets/AirShell_orig.swf"
rm -rf "$STAGING/assets/interface" "$STAGING/libs/native"

if [ "${SKIP_HAXE_API:-}" != "1" ]; then
    if [ -d "$HAXE_API_DIR" ]; then
        echo "=> [1/5] Compiling Haxe API (aqw-haxe-api)..."
        run_haxe_build "$HAXE_API_DIR"
        cp "$HAXE_API_DIR/bin/AqwApi.swc" "$STAGING/libs/AqwApi.swc"
    fi
    if [ -d "$HAXE_UI_DIR" ]; then
        echo "=> [2/5] Compiling Haxe UI (aqw-haxe-ui)..."
        # Standalone variant: bundles its own ui.Overlay (no aqw-mobile-mod host needed)
        (cd "$HAXE_UI_DIR" && haxe build-standalone.hxml)
        cp "$HAXE_UI_DIR/bin/ModUI-standalone.swc" "$STAGING/libs/ModUI.swc"
    fi
fi

echo "=> [3/5] Compiling AirShell.swf (official launcher + mod)..."
"$AMXMLC" \
    +configname=air \
    -strict=false \
    -debug=true \
    -default-size 960 550 \
    -default-frame-rate 30 \
    -default-background-color 0x000000 \
    -library-path+="$STAGING/libs" \
    -include-libraries+="$STAGING/libs/AqwApi.swc" \
    -include-libraries+="$STAGING/libs/ModUI.swc" \
    -source-path+="$STAGING/src" \
    -output "$STAGING/AirShell.swf" \
    "$STAGING/src/AirShell.as"

cp "$STAGING/AirShell.swf" "$BUILD/AirShell.swf"

echo "=> [4/5] Checking keystore..."
if [ ! -f "$KEYSTORE" ]; then
    echo "   Generating local test keystore..."
    "$ADT" -certificate -cn "AQWPocketLocal" 2048-RSA "$KEYSTORE" password
fi

if [ -z "${UPSTREAM_VERSION:-}" ]; then
    UPSTREAM_VERSION="1.1.0"
fi

BUILD_DATE="${BUILD_DATE:-$(date +'%d-%m-%y')}"

echo "=> Packaging APKs (${TARGET_MODES[*]}) for architectures: ${ARCHS[*]} (version: $UPSTREAM_VERSION, date: $BUILD_DATE)..."

BUILT_APKS=()
for CURRENT_ARCH in "${ARCHS[@]}"; do
    for MODE in "${TARGET_MODES[@]}"; do
        OUTPUT_FILE="aqworlds-$UPSTREAM_VERSION-$BUILD_DATE-$CURRENT_ARCH-$MODE.apk"
        OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILE"
        TMP_APP_XML="$BUILD/Mobile-app-${CURRENT_ARCH}-${MODE}.xml"

        case "$CURRENT_ARCH" in
            armv8) NATIVE_ARCH="arm64-v8a" ;;
            armv7) NATIVE_ARCH="armeabi-v7a" ;;
            x86) NATIVE_ARCH="x86" ;;
            x86_64) NATIVE_ARCH="x86_64" ;;
            *) NATIVE_ARCH="arm64-v8a" ;;
        esac

        echo "   -> Packaging $OUTPUT_FILE (renderMode: $MODE, arch: $CURRENT_ARCH)..."
        cp "$STAGING/Mobile-app.xml" "$TMP_APP_XML"
        sed -i "s|<renderMode>.*</renderMode>|<renderMode>${MODE}</renderMode>|" "$TMP_APP_XML"

        "$ADT" -package \
            -target apk-captive-runtime \
            -arch "$CURRENT_ARCH" \
            -storetype PKCS12 \
            -keystore "$KEYSTORE" \
            -storepass password \
            "$OUTPUT_PATH" \
            "$TMP_APP_XML" \
            -C "$BUILD" AirShell.swf \
            -C "$STAGING" \
                assets \
                icons

        rm -f "$TMP_APP_XML"

        FILE_SIZE=$(du -sh "$OUTPUT_PATH" | cut -f1)
        BUILT_APKS+=("$OUTPUT_FILE ($FILE_SIZE)")
    done
done

echo ""
echo "=> Done! Built Android APKs in ${OUTPUT_DIR:-}:"
for APK_INFO in "${BUILT_APKS[@]}"; do
    echo "   • $APK_INFO"
done
echo ""
echo "   Install on device with: adb install -r ${OUTPUT_DIR:-}/<apk-file>"
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

CLIENT="$DIR/loader"
BUILD="$DIR/build"
STAGING="$BUILD/staging"

HAXE_API_DIR="${HAXE_API_DIR:-$DIR/../aqw-haxe-api}"
HAXE_UI_DIR="${HAXE_UI_DIR:-$DIR/../aqw-haxe-ui}"

for required in "$CLIENT/src/AirShell.as" "$CLIENT/AirShell.swf" "$CLIENT/Mobile-app.xml" "$CLIENT/Desktop-app.xml"; do
    if [ ! -f "$required" ]; then
        echo "ERROR: '$required' is missing - the loader/ tree is incomplete." >&2
        exit 1
    fi
done

if [ "${1:-}" = "--clean" ] || [ "${2:-}" = "--clean" ]; then
    echo "=> Cleaning previous build artifacts..."
    rm -f "$BUILD/AirShell.swf"
fi

mkdir -p "$BUILD"
rm -rf "$STAGING"
mkdir -p "$STAGING"
trap '' EXIT

if [ "${SKIP_SYNC:-0}" = "1" ]; then
    echo "=> [0/5] SKIP_SYNC=1 - using cached upstream files."
elif ! "$DIR/sync-upstream.sh"; then
    echo "WARNING: Could not sync upstream APK; building with existing loader/ files." >&2
fi

echo "=> [1/5] Copying loader/ to sandbox (build/staging/)..."
mkdir -p "$STAGING/libs"
cp -r "$CLIENT/src" "$STAGING/src"

mkdir -p "$STAGING/assets"
if [ -d "$CLIENT/assets" ]; then
    cp -r "$CLIENT/assets/." "$STAGING/assets/"
fi
 2>/dev/null || true
cp -r "$CLIENT/icons" "$STAGING/icons"
cp -r "$CLIENT/res" "$STAGING/res" 2>/dev/null || true
cp -r "$CLIENT/META-INF" "$STAGING/META-INF" 2>/dev/null || true
cp "$CLIENT/Desktop-app.xml" "$STAGING/Desktop-app.xml"
cp "$CLIENT/Mobile-app.xml" "$STAGING/Mobile-app.xml"
rm -f "$STAGING/assets/game.swf" "$STAGING/assets/AirShell_orig.swf"
if [ -d "$CLIENT/libs" ]; then
    cp -r "$CLIENT/libs/." "$STAGING/libs/" 2>/dev/null || true
fi

if [ "${SKIP_HAXE:-}" != "1" ]; then
    if [ -d "$HAXE_API_DIR" ]; then
        echo "=> [1/5] Compiling AqwApi (aqw-haxe-api)..."
        run_haxe_build "$HAXE_API_DIR"
        cp "$HAXE_API_DIR/bin/AqwApi.swc" "$STAGING/libs/AqwApi.swc"
    fi
    if [ -d "$HAXE_UI_DIR" ]; then
        echo "=> [2/5] Compiling ModUI (aqw-haxe-ui)..."
        # Standalone variant: bundles its own ui.Overlay (no aqw-mobile-mod host needed)
        (cd "$HAXE_UI_DIR" && haxe build-standalone.hxml)
        cp "$HAXE_UI_DIR/bin/ModUI-standalone.swc" "$STAGING/libs/ModUI.swc"
    fi
fi

for required_swc in AqwApi.swc ModUI.swc; do
    if [ ! -f "$STAGING/libs/$required_swc" ]; then
        echo "ERROR: libs/$required_swc is missing." >&2
        if [ "$required_swc" = "ModUI.swc" ]; then
            echo "       aqw-haxe-ui did not produce it - run 'haxe build.hxml' in $HAXE_UI_DIR." >&2
        else
            echo "       aqw-haxe-api did not produce it - run 'haxe build.hxml' in $HAXE_API_DIR." >&2
        fi
        exit 1
    fi
done

resolve_flex_tools
echo "=> Toolchain: $(basename "$AMXMLC"), java ${JAVA_HOME##*/}, flex tools in ${FLEX_TOOLS}"

echo "=> [3/5] Compiling AirShell.swf (official logic + mod)..."
"$AMXMLC" \
    +configname=air \
    -strict=false \
    -debug=true \
    -default-size 960 550 \
    -default-frame-rate 120 \
    -default-background-color 0x000000 \
    -library-path+="$STAGING/libs" \
    -include-libraries+="$STAGING/libs/AqwApi.swc" \
    -include-libraries+="$STAGING/libs/ModUI.swc" \
    -source-path+="$STAGING/src" \
    -output "$STAGING/AirShell.swf" \
    "$STAGING/src/AirShell.as"

cp "$STAGING/AirShell.swf" "$BUILD/AirShell.swf"

echo "=> [4/5] Assembling build/ ..."
rm -rf "$BUILD/assets" "$BUILD/icons" "$BUILD/res" "$BUILD/META-INF"
cp -r "$STAGING/assets" "$BUILD/assets"
cp -r "$STAGING/icons" "$BUILD/icons"
cp -r "$STAGING/res" "$BUILD/res" 2>/dev/null || true
cp -r "$STAGING/META-INF" "$BUILD/META-INF" 2>/dev/null || true

write_descriptor "$CLIENT/Desktop-app.xml" "$BUILD/Desktop-app.xml"
sed "s|<renderMode>.*</renderMode>|<renderMode>direct</renderMode>|" \
    "$BUILD/Desktop-app.xml" > "$BUILD/Desktop-app-direct.xml"
sed "s|<renderMode>.*</renderMode>|<renderMode>gpu</renderMode>|" \
    "$BUILD/Desktop-app.xml" > "$BUILD/Desktop-app-gpu.xml"
sed "s|<renderMode>.*</renderMode>|<renderMode>cpu</renderMode>|" \
    "$BUILD/Desktop-app.xml" > "$BUILD/Desktop-app-cpu.xml"

echo "=> Build complete. Artifacts in build/:"
ls -la "$BUILD/AirShell.swf" 2>/dev/null || true
echo "=> Launch with: ./run.sh [--cpu|--direct|--gpu]"
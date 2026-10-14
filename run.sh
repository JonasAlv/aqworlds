#!/bin/bash
# Launch the AQWorlds (official launcher + mod) desktop build through Wine + ADL.
# Usage: ./run.sh [--build|-b] [--auto|--direct|--gpu]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
if [ -f "$DIR/lib.sh" ]; then
    . "$DIR/lib.sh"
elif [ -f "$DIR/../aqw-mobile-mod/lib.sh" ]; then
    . "$DIR/../aqw-mobile-mod/lib.sh"
fi

BUILD="$DIR/build"
BUILD_REQUESTED=0
RENDER_MODE=""

for arg in "$@"; do
    case "$arg" in
        --build|-b) BUILD_REQUESTED=1 ;;
        --cpu|--direct|--gpu)
            if [ -n "$RENDER_MODE" ]; then
                echo "ERROR: Choose only one of --cpu, --direct, or --gpu." >&2
                exit 2
            fi
            RENDER_MODE="${arg#--}"
            ;;
        --help|-h)
            echo "Usage: ./run.sh [--build|-b] [--cpu|--direct|--gpu]"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option '$arg'." >&2
            echo "Usage: ./run.sh [--build|-b] [--cpu|--direct|--gpu]" >&2
            exit 2
            ;;
    esac
done

if [ "$BUILD_REQUESTED" -eq 1 ] || [ ! -f "$BUILD/AirShell.swf" ] || [ ! -f "$BUILD/Desktop-app.xml" ]; then
    [ "$BUILD_REQUESTED" -eq 1 ] || echo "=> Build artifacts not found. Building before launch..."
    "$DIR/build.sh"
fi

resolve_air_windows

# The API log belongs to the running build: build/assets/api.log, linked from convenient places.
LOG_DIR="$BUILD/assets"
mkdir -p "$LOG_DIR"
: > "$LOG_DIR/api.log"
ln -sfn "$LOG_DIR/api.log" "$DIR/api.log"

# Wine's AIR "Local Store" (applicationStorageDirectory) for com.aqw.spider
WINE_PREFIX="${WINEPREFIX:-$HOME/.wine}"
if [ -d "$WINE_PREFIX" ]; then
    WINE_LOCAL_STORE="$WINE_PREFIX/drive_c/users/${USER:-$(whoami)}/AppData/Roaming/com.aqw.spider/Local Store"
    mkdir -p "$WINE_LOCAL_STORE/assets"
    ln -sfn "$LOG_DIR/api.log" "$WINE_LOCAL_STORE/api.log" 2>/dev/null || true
    ln -sfn "$LOG_DIR/api.log" "$WINE_LOCAL_STORE/assets/api.log" 2>/dev/null || true
fi

# ADL resolves the descriptor's content (AirShell.swf), assets/ and icons/ relative to build/.
APP_XML="Desktop-app.xml"
if [ -n "$RENDER_MODE" ]; then
    sed -E "s|<renderMode>[^<]*</renderMode>|<renderMode>$RENDER_MODE</renderMode>|" \
        "$BUILD/Desktop-app.xml" > "$BUILD/Desktop-app-run.xml"
    APP_XML="Desktop-app-run.xml"
fi

echo "=> Launching AQWorlds via Wine + ADL (render mode: ${RENDER_MODE:-descriptor default})..."
echo "   Log: $LOG_DIR/api.log"
cd "$BUILD"
wine "$ADL" -profile extendedDesktop "$APP_XML"
echo "=> ADL closed."

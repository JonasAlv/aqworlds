#!/usr/bin/env bash
# Shared helpers for the build/launch scripts. Source, don't execute.
#
# Toolchain locations come from the environment. Nothing here hardcodes a path into someone's home
# directory: guessing at $HOME/.airsdk or $HOME/.sdkman works on exactly one machine and fails
# silently everywhere else. Each resolver tries, in order:
#   1. the documented environment variable
#   2. the tool already on PATH
#   3. a clear error naming the variable to set
# Exported variables:
#   AIR_HOME, AMXMLC, ADT   AIR SDK (Linux/desktop + Android packaging)
#   JAVA_HOME              JDK used by amxmlc/adt
#   FLEX_TOOLS             directory holding abcexport / abcreplace
#   AIRSDK_WINDOWS, ADL    Windows AIR SDK used to launch through Wine

# Echoes the executable path for $2, using environment variable $1 as an SDK root.
# Fails with an actionable message rather than guessing.
resolve_tool() {
    local var_name="$1" tool="$2" hint="$3"
    local sdk_root="${!var_name:-}"

    if [ -n "$sdk_root" ]; then
        local candidate="$sdk_root/bin/$tool"
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
        if [ -f "$sdk_root" ]; then
            echo "$sdk_root"
            return 0
        fi
        echo "ERROR: $var_name points at '$sdk_root', but '$candidate' was not found." >&2
        return 1
    fi

    local on_path
    on_path="$(command -v "$tool" 2>/dev/null || true)"
    if [ -n "$on_path" ]; then
        echo "$on_path"
        return 0
    fi

    {
        echo "ERROR: Could not locate '$tool'."
        echo "       Either put it on PATH, or set $var_name to the SDK directory that contains it."
        [ -n "$hint" ] && echo "       $hint"
    } >&2
    return 1
}

# JAVA_HOME from the environment, else derived from `java` on PATH.
# Deriving beats a hardcoded sdkman path: on Arch `java` is a symlink into /usr/lib/jvm/<jdk>, so
# the real JDK root is recoverable. The javac check guards against a JRE-only or unresolvable java.
resolve_java_home() {
    if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
        echo "$JAVA_HOME"
        return 0
    fi

    local java_bin resolved
    java_bin="$(command -v java 2>/dev/null || true)"
    if [ -n "$java_bin" ]; then
        resolved="$(readlink -f "$java_bin" 2>/dev/null || echo "$java_bin")"
        case "$resolved" in
            */bin/java)
                if [ -x "${resolved%/bin/java}/bin/javac" ]; then
                    echo "${resolved%/bin/java}"
                    return 0
                fi
                ;;
        esac
    fi

    {
        echo "ERROR: Could not determine JAVA_HOME."
        echo "       Set JAVA_HOME to a JDK (not just a JRE - amxmlc and adt need javac)."
    } >&2
    return 1
}

# AIR SDK for Linux desktop and Android packaging.
resolve_air_env() {
    local amxmlc adt
    amxmlc="$(resolve_tool AIR_HOME amxmlc "AIRSDK_HOME is also accepted for older layouts.")" || return 1
    adt="$(command -v adt 2>/dev/null || true)"
    if [ -z "$adt" ] && [ -f "${AIR_HOME:-}/bin/adt" ]; then
        adt="${AIR_HOME}/bin/adt"
    fi

    JAVA_HOME="$(resolve_java_home)" || return 1
    AMXMLC="$amxmlc"
    ADT="${adt:-}"
    # Declared here so `set -u` callers can report on it before resolve_flex_tools has run.
    FLEX_TOOLS="${FLEX_TOOLS:-}"

    export AIR_HOME JAVA_HOME
    export PATH="$(dirname "$AMXMLC"):$JAVA_HOME/bin:$PATH"
    return 0
}

# abcexport / abcreplace come from the Flex SDK, not the AIR SDK.
# FLEX_HOME / FLEX_SDK if set, otherwise whatever is on PATH.
resolve_flex_tools() {
    local flex_var="" candidate
    for var_name in FLEX_HOME FLEX_SDK; do
        if [ -n "${!var_name:-}" ]; then
            flex_var="$var_name"
            break
        fi
    done

    for tool in abcexport abcreplace; do
        local path=""
        if [ -n "$flex_var" ]; then
            candidate="${!flex_var}/bin/$tool"
            [ -f "$candidate" ] && path="$candidate"
        fi
        if [ -z "$path" ]; then
            path="$(command -v "$tool" 2>/dev/null || true)"
        fi
        if [ -z "$path" ]; then
            {
                echo "ERROR: Could not locate '$tool'."
                echo "       These ship with the Flex SDK. Set FLEX_HOME to the directory containing"
                echo "       bin/$tool, or put them on PATH."
            } >&2
            return 1
        fi
        FLEX_TOOLS="$(dirname "$path")"
        export FLEX_TOOLS
        export PATH="$FLEX_TOOLS:$PATH"
    done
    return 0
}

# Windows AIR SDK, used to launch the desktop app through Wine.
resolve_air_windows() {
    local adl_exe
    for var_name in AIRSDK_WINDOWS AIR_WINDOWS_HOME; do
        if [ -n "${!var_name:-}" ]; then
            AIRSDK_WINDOWS="${!var_name}"
            break
        fi
    done

    adl_exe="$(resolve_tool AIRSDK_WINDOWS adl.exe "Set AIRSDK_WINDOWS to the Windows AIR SDK directory.")" || return 1
    ADL="$adl_exe"
    export AIRSDK_WINDOWS ADL
    return 0
}

# AQW Mobile's Desktop-app.xml declares the Discord RPC ANE:
#   <extensionID>fi.joniaromaa.adobeair.discordrpc</extensionID>
# The bare loader/libs/DiscordRPC.ane satisfies amxmlc at compile time, but adl cannot load it as a
# runtime extension descriptor and aborts before the app starts with
# "Requested extension ... could not be found". Stripping the <extensions> block fixes that.
# DiscordRichPresence.enable() already returns early unless the user opts in, so nothing else changes.
strip_extensions() {
    python3 -c '
import re
import sys

sys.stdout.write(re.sub(r"[ \t]*<extensions>.*?</extensions>\s*", "", sys.stdin.read(), flags=re.S))
'
}

# adl resolves native extension descriptors relative to the build directory, so the stripped
# descriptor must be written next to the SWF rather than used in place from loader/.
write_descriptor() {
    strip_extensions < "$1" > "$2"
}

# The haxe launcher differs between installs (standalone, pnpm, npx), and the same probe appears in
# every script that compiles the mod, so keep one copy.
run_haxe_build() {
    (
        cd "$1"
        if command -v haxe >/dev/null 2>&1; then
            haxe build.hxml
        elif command -v pnpm >/dev/null 2>&1; then
            pnpm exec haxe build.hxml
        else
            npx haxe build.hxml
        fi
    )
}

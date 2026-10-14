#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_DIR="$DIR/upstream"
CLIENT_DIR="$DIR/loader"
PAGE_URL="https://www.artix.com/experiments/aqwandroid/"
FALLBACK_APK_URL="https://chaoslabs.artix.com/AQWorldsAndroid/AQWorlds-1_1_0.apk"

mkdir -p "$UPSTREAM_DIR" "$CLIENT_DIR/src"

for tool in curl unzip ffdec python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: Required tool '$tool' not found on PATH." >&2
        exit 1
    fi
done

echo "=> [1/4] Checking official AQWorlds Android APK..."
APK_URL="${1:-${OFFICIAL_APK_URL:-}}"
if [[ -z "$APK_URL" ]]; then
    # Try detecting the latest APK link from Artix experiments page
    DETECTED_URL="$(curl -s -L --max-time 10 "$PAGE_URL" 2>/dev/null | grep -oPm1 'https://chaoslabs\.artix\.com/AQWorldsAndroid/AQWorlds-[0-9_]+\.apk' || true)"
    if [[ -n "$DETECTED_URL" ]]; then
        APK_URL="$DETECTED_URL"
        echo "   Detected APK link on Artix page: $APK_URL"
    else
        APK_URL="$FALLBACK_APK_URL"
        echo "   Using default/fallback APK link: $APK_URL"
    fi
fi

APK_FILENAME="$(basename "$APK_URL")"
LOCAL_APK="$UPSTREAM_DIR/$APK_FILENAME"
VERSION_UNDERSCORE="$(echo "$APK_FILENAME" | grep -oPm1 '(?<=AQWorlds-)[0-9_]+(?=\.apk)' || echo "1_1_0")"
VERSION_DOTTED="${VERSION_UNDERSCORE//_/.}"

# Download if not cached or if empty
if [[ ! -s "$LOCAL_APK" ]]; then
    echo "=> [2/4] Downloading $APK_FILENAME..."
    TMP_DL="$LOCAL_APK.part"
    curl --fail --show-error --location \
        --retry 3 \
        --retry-delay 2 \
        --max-time 300 \
        "$APK_URL" \
        --output "$TMP_DL"
    mv "$TMP_DL" "$LOCAL_APK"
    echo "   Saved to $LOCAL_APK"
else
    echo "=> [2/4] Using cached upstream APK: $LOCAL_APK (version $VERSION_DOTTED)"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aqw-sync.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=> [3/4] Extracting AirShell.swf and decompiling with ffdec..."
unzip -p "$LOCAL_APK" assets/AirShell.swf > "$TMP_DIR/AirShell.swf"
cp "$TMP_DIR/AirShell.swf" "$CLIENT_DIR/AirShell.swf"

# Decompile ActionScript classes headlessly
DISPLAY="" ffdec -export script "$TMP_DIR/extracted" "$TMP_DIR/AirShell.swf" >/dev/null 2>&1

DECOMPILED_AIRSHELL="$(find "$TMP_DIR/extracted" -name "AirShell.as" | head -n 1)"
if [[ -z "$DECOMPILED_AIRSHELL" || ! -f "$DECOMPILED_AIRSHELL" ]]; then
    echo "ERROR: Decompilation did not produce AirShell.as" >&2
    exit 1
fi

echo "=> [4/4] Removing SoftKeys and injecting mod bootstrap into AirShell.as..."
python3 - "$DECOMPILED_AIRSHELL" "$CLIENT_DIR/src/AirShell.as" << 'PY'
import sys
import re

src_file = sys.argv[1]
dst_file = sys.argv[2]

with open(src_file, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Strip SoftKeys references
content = re.sub(r'^\s*private var softKeys:SoftKeys;\s*\n', '', content, flags=re.MULTILINE)
content = re.sub(r'^\s*softKeys = new SoftKeys\(stage\);\s*\n', '', content, flags=re.MULTILINE)
content = re.sub(r'^\s*stage\.addChild\(softKeys\);\s*\n', '', content, flags=re.MULTILINE)
content = re.sub(r'^\s*softKeys\.content = content;\s*\n', '', content, flags=re.MULTILINE)

# 2. Add Haxe / Mod imports
imports = """
   import com.aqwapi.Api;
   import ui.ApiMenus;
"""
content = re.sub(r'(import flash\.utils\.getTimer;\s*\n)', r'\1' + imports, content, count=1)

# 3. Add shims and runtime init in init()
shims = """
         try {
            var haxeBoot:* = getDefinitionByName("haxe");
            if (haxeBoot != null && haxeBoot.initSwc != null) {
               haxeBoot.initSwc(null);
            }
         } catch (e:Error) {}

         try {
            Api.ensureMathShims();
         } catch (e:Error) {}

         try {
            Api.preloadAssets();
         } catch (e:Error) {}

         try {
            Security.allowDomain("*");
            Security.allowInsecureDomain("*");
         } catch (e:Error) {}
"""
content = re.sub(r'(t0 = getTimer\(\);\s*\n)', r'\1' + shims, content, count=1)

# 4. Inject initMod call in onGameComplete after stage.addChildAt(content, 0);
mod_call = """
         // Initialize our mod after game loads
         initMod(Game);
"""
content = re.sub(r'(stage\.addChildAt\(content,\s*0\);\s*\n)', r'\1' + mod_call, content, count=1)

# 5. Append initMod helper method
init_mod_method = """
      private function initMod(gameInstance:Object) : void
      {
         try
         {
            var apiClass:Class = getDefinitionByName("com.aqwapi.Api") as Class;
            if (apiClass != null && apiClass.init != null)
            {
               apiClass.init(Game);
            }
         }
         catch (e:Error)
         {
            trace("API init error: " + e);
         }

         try
         {
            var apiMenusClass:Class = getDefinitionByName("ui.ApiMenus") as Class;
            if (apiMenusClass != null && apiMenusClass.injectStandalone != null)
            {
               apiMenusClass.injectStandalone(stage);
            }
         }
         catch (e:Error)
         {
            trace("Menu inject error: " + e);
            if (status != null)
            {
               status.appendText("\\nMenu inject error: " + e);
            }
         }
      }
"""
idx = content.rfind("}")
idx2 = content.rfind("}", 0, idx)
content = content[:idx2] + init_mod_method + "\n   }\n}\n"

with open(dst_file, "w", encoding="utf-8") as f:
    f.write(content)

print(f"   Saved patched AirShell.as ({len(content)} bytes)")
PY

# Update version in Mobile-app.xml and Desktop-app.xml
for xml_file in "$CLIENT_DIR/Mobile-app.xml" "$CLIENT_DIR/Desktop-app.xml"; do
    if [[ -f "$xml_file" ]]; then
        sed -i -E "s|<versionNumber>[^<]+</versionNumber>|<versionNumber>$VERSION_DOTTED</versionNumber>|" "$xml_file"
    fi
done

echo "=> Upstream sync complete: official AirShell.as patched (no SoftKeys + mod bootstrap attached)."

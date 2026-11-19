
#!/usr/bin/env bash
# Crystal Guideline — APK Patch Builder
# Usage: ./patch.sh <game.apk>

set -Eeuo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
RST='\033[0m'

ok()   { echo -e "${GRN}[✓]${RST} $*"; }
info() { echo -e "${BLU}[i]${RST} $*"; }
warn() { echo -e "${YLW}[!]${RST} $*"; }
die()  { echo -e "${RED}[✗]${RST} $*" >&2; exit 1; }

trap 'die "Patch failed at line $LINENO. Check the error above."' ERR

echo -e "${CYN}
  ██████╗██████╗ ██╗   ██╗███████╗████████╗ █████╗ ██╗
 ██╔════╝██╔══██╗╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔══██╗██║
 ██║     ██████╔╝ ╚████╔╝ ███████╗   ██║   ███████║██║
 ██║     ██╔══██╗  ╚██╔╝  ╚════██║   ██║   ██╔══██║██║
 ╚██████╗██║  ██║   ██║   ███████║   ██║   ██║  ██║███████╗
  ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝
           Crystal Guideline — ARM64 Builder
${RST}"

# ─── Paths ────────────────────────────────────────────────────

APK_IN="${1:-}"
[[ -z "$APK_IN" ]] && die "Usage: ./patch.sh <game.apk>"
[[ ! -f "$APK_IN" ]] && die "APK not found: $APK_IN"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
WORK_DIR="$DIST_DIR/work"
DECOMPILED="$WORK_DIR/decompiled"

SO_SRC="$DIST_DIR/libcrystal_guideline.so"
SMALI_SRC="$SCRIPT_DIR/smali/com/crystal"

KEYSTORE="$SCRIPT_DIR/keystore/crystal.jks"
APK_UNSIGNED="$WORK_DIR/crystal_unsigned.apk"
APK_ALIGNED="$WORK_DIR/crystal_aligned.apk"
APK_OUT="$DIST_DIR/crystal_patched_signed.apk"

MANIFEST="$DECOMPILED/AndroidManifest.xml"

# ─── Dependencies ─────────────────────────────────────────────

info "Checking dependencies..."

for cmd in apktool java keytool zipalign apksigner python3; do
    command -v "$cmd" >/dev/null 2>&1 \
        || die "Missing dependency: $cmd"
done

ok "Dependencies found"

# ─── Check required files ─────────────────────────────────────

[[ -f "$SO_SRC" ]] \
    || die "Missing native library: $SO_SRC"

[[ -d "$SMALI_SRC" ]] \
    || die "Missing Crystal Smali directory: $SMALI_SRC"

find "$SMALI_SRC" -type f -name '*.smali' -print -quit | grep -q . \
    || die "No Smali files found in $SMALI_SRC"

ok "Native library found: $(du -sh "$SO_SRC" | cut -f1)"
ok "Crystal Smali files found"

# ─── Clean workspace ──────────────────────────────────────────

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$DIST_DIR"

# ═══════════════════════════════════════════════════════════════
# STEP 1 — DECOMPILE
# ═══════════════════════════════════════════════════════════════

info "Step 1/7 — Decompiling APK..."

if ! apktool d "$APK_IN" -o "$DECOMPILED" ; then
    warn "First decompile attempt failed; retrying normally..."
    rm -rf "$DECOMPILED"
    apktool d "$APK_IN" -o "$DECOMPILED"
fi

[[ -f "$MANIFEST" ]] || die "AndroidManifest.xml not found"

ok "APK decompiled successfully"

# ═══════════════════════════════════════════════════════════════
# STEP 2 — FIND CLASS AND INJECT LIBRARY
# ═══════════════════════════════════════════════════════════════

info "Step 2/7 — Detecting Application and Launcher..."

python3 - "$MANIFEST" "$DECOMPILED" <<'PYEOF'
import os
import re
import sys
import xml.etree.ElementTree as ET

manifest_path = sys.argv[1]
decompiled = sys.argv[2]

ANDROID = "{http://schemas.android.com/apk/res/android}"

def fail(message):
    print("ERROR:", message)
    sys.exit(1)

def normalize(name, package):
    if not name:
        return None
    if name.startswith("."):
        return package + name
    if "." not in name:
        return package + "." + name
    return name

try:
    root = ET.parse(manifest_path).getroot()
except Exception as e:
    fail("Cannot parse manifest: " + str(e))

package = root.get("package", "")
application = root.find("application")

if application is None:
    fail("Application element not found")

app_name = normalize(application.get(ANDROID + "name"), package)

target = app_name
mode = "APPLICATION"

if not target:
    print("No custom Application class; searching launcher Activity...")
    mode = "ACTIVITY"

    for element in list(application):
        if element.tag not in ("activity", "activity-alias"):
            continue

        is_launcher = False

        for intent in element.findall("intent-filter"):
            actions = [
                x.get(ANDROID + "name")
                for x in intent.findall("action")
            ]
            categories = [
                x.get(ANDROID + "name")
                for x in intent.findall("category")
            ]

            if (
                "android.intent.action.MAIN" in actions
                and "android.intent.category.LAUNCHER" in categories
            ):
                is_launcher = True
                break

        if is_launcher:
            if element.tag == "activity-alias":
                name = element.get(ANDROID + "targetActivity")
            else:
                name = element.get(ANDROID + "name")

            target = normalize(name, package)
            break

if not target:
    fail("Cannot identify Application or launcher Activity")

relative = target.replace(".", "/") + ".smali"

matches = []

for root_dir, dirs, files in os.walk(decompiled):
    if relative in os.path.join(root_dir, relative):
        candidate = os.path.join(root_dir, relative)
        if os.path.isfile(candidate):
            matches.append(candidate)

if not matches:
    fail("Smali class not found: " + relative)

target_smali = matches[0]

print("TARGET_CLASS=" + target)
print("TARGET_MODE=" + mode)
print("TARGET_SMALI=" + target_smali)

# Save detected information for the next shell step.
with open(os.path.join(decompiled, ".crystal_target"), "w") as f:
    f.write(mode + "\n")
    f.write(target_smali + "\n")
PYEOF

[[ -f "$DECOMPILED/.crystal_target" ]] \
    || die "Target detection did not produce its result"

mapfile -t TARGET_INFO < "$DECOMPILED/.crystal_target"

INJECT_TARGET="${TARGET_INFO[0]}"
TARGET_SMALI="${TARGET_INFO[1]}"

[[ -f "$TARGET_SMALI" ]] || die "Target Smali file not found"

ok "Injection target: $TARGET_SMALI"

# ─── Inject loadLibrary and initialize Crystal ────────────────

python3 - "$TARGET_SMALI" "$INJECT_TARGET" <<'PYEOF'
import re
import sys

path = sys.argv[1]
mode = sys.argv[2]

with open(path, encoding="utf-8") as f:
    content = f.read()

if mode == "APPLICATION":
    signature = r'onCreate\(\)V'
    params = 1
    super_signature = "onCreate()V"
else:
    signature = r'onCreate\(Landroid/os/Bundle;\)V'
    params = 2
    super_signature = "onCreate(Landroid/os/Bundle;)V"

method_match = re.search(
    r'(?m)^\.method\b[^\n]*\b' + signature + r'[^\n]*$',
    content
)

if "crystal_guideline" in content:
    print("Crystal injection already exists; skipping duplicate injection.")
    sys.exit(0)

def get_super():
    match = re.search(r'(?m)^\.super\s+(L[^;]+;)', content)
    if not match:
        raise SystemExit("ERROR: Cannot identify superclass")
    return match.group(1)

super_class = get_super()

if not method_match:
    print("Creating onCreate method...")

    if mode == "APPLICATION":
        declaration = ".method public onCreate()V"
        super_call = (
            f"    invoke-super {{p0}}, "
            f"{super_class}->{super_signature}"
        )
    else:
        declaration = (
            ".method protected onCreate(Landroid/os/Bundle;)V"
        )
        super_call = (
            f"    invoke-super {{p0, p1}}, "
            f"{super_class}->{super_signature}"
        )

    new_method = f"""
{declaration}
    .locals 1
{super_call}
    const-string v0, "crystal_guideline"
    invoke-static {{v0}}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
    invoke-static {{p0}}, Lcom/crystal/CrystalGuideline;->init(Landroid/content/Context;)V
    return-void
.end method
"""

    end_class = re.search(r'(?m)^\.end class\s*$', content)

    if not end_class:
        raise SystemExit("ERROR: .end class not found")

    content = (
        content[:end_class.start()]
        + new_method
        + "\n"
        + content[end_class.start():]
    )

else:
    start = method_match.start()
    end_match = re.search(r'(?m)^\.end method\s*$', content[method_match.end():])

    if not end_match:
        raise SystemExit("ERROR: onCreate method is incomplete")

    end = method_match.end() + end_match.end()
    block = content[start:end]

    locals_match = re.search(r'(?m)^(\s*)\.locals\s+(\d+)', block)
    registers_match = re.search(r'(?m)^(\s*)\.registers\s+(\d+)', block)

    if locals_match:
        old = int(locals_match.group(2))
        register = f"v{old}"
        block = (
            block[:locals_match.start(2)]
            + str(old + 1)
            + block[locals_match.end(2):]
        )

    elif registers_match:
        old = int(registers_match.group(2))
        local_count = old - params

        if local_count < 0:
            raise SystemExit("ERROR: Invalid register count")

        register = f"v{local_count}"

        block = (
            block[:registers_match.start(2)]
            + str(old + 1)
            + block[registers_match.end(2):]
        )

    else:
        raise SystemExit("ERROR: No .locals or .registers declaration")

    injection = f"""
    const-string {register}, "crystal_guideline"
    invoke-static {{{register}}}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
    invoke-static {{p0}}, Lcom/crystal/CrystalGuideline;->init(Landroid/content/Context;)V
"""

    super_match = re.search(r'(?m)^.*invoke-super.*$', block)

    if super_match:
        position = super_match.end()
        block = block[:position] + "\n" + injection + block[position:]
    else:
        return_match = re.search(r'(?m)^.*return-void\s*$', block)

        if not return_match:
            raise SystemExit("ERROR: No suitable injection point")

        position = return_match.start()
        block = block[:position] + injection + block[position:]

    content = content[:start] + block + content[end:]

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("Crystal injection successful.")
PYEOF

ok "Smali injection complete"

# ═══════════════════════════════════════════════════════════════
# STEP 3 — COPY CRYSTAL SMALI
# ═══════════════════════════════════════════════════════════════

info "Step 3/7 — Copying Crystal Smali files..."

LAST_SMALI_DIR=$(
    find "$DECOMPILED" -maxdepth 1 -type d -name 'smali*' \
        | sort -V | tail -n 1
)

[[ -n "$LAST_SMALI_DIR" ]] \
    || die "No Smali directory found"

mkdir -p "$LAST_SMALI_DIR/com/crystal"

cp -a "$SMALI_SRC/." "$LAST_SMALI_DIR/com/crystal/"

ok "Crystal Smali files copied"

# ═══════════════════════════════════════════════════════════════
# STEP 4 — COPY NATIVE LIBRARY
# ═══════════════════════════════════════════════════════════════

info "Step 4/7 — Installing ARM64 native library..."

mkdir -p "$DECOMPILED/lib/arm64-v8a"

cp "$SO_SRC" \
    "$DECOMPILED/lib/arm64-v8a/libcrystal_guideline.so"

ok "Native library copied"

# ═══════════════════════════════════════════════════════════════
# STEP 5 — PATCH MANIFEST
# ═══════════════════════════════════════════════════════════════

info "Step 5/7 — Updating AndroidManifest.xml..."

python3 - "$MANIFEST" <<'PYEOF'
import re
import sys

path = sys.argv[1]

with open(path, encoding="utf-8") as f:
    content = f.read()

def add_permission(name):
    global content

    pattern = (
        r'<uses-permission\b[^>]*android:name\s*=\s*["\']'
        + re.escape(name)
        + r'["\'][^>]*/?>'
    )

    if re.search(pattern, content):
        print("Permission already exists:", name)
        return

    root = re.search(r'<manifest\b[^>]*>', content)

    if not root:
        raise SystemExit("ERROR: Manifest root not found")

    content = (
        content[:root.end()]
        + '\n    <uses-permission android:name="' + name + '"/>'
        + content[root.end():]
    )

    print("Added permission:", name)

add_permission("android.permission.SYSTEM_ALERT_WINDOW")
add_permission("android.permission.FOREGROUND_SERVICE")

service = '''    <service
        android:name="com.crystal.GuidelineService"
        android:enabled="true"
        android:exported="false"
        android:stopWithTask="true"/>'''

if "com.crystal.GuidelineService" not in content:
    closing = re.search(r'</application\s*>', content)

    if not closing:
        raise SystemExit("ERROR: Application closing tag not found")

    content = (
        content[:closing.start()]
        + service + "\n"
        + content[closing.start():]
    )

    print("GuidelineService registered")
else:
    print("GuidelineService already registered")

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("Manifest update complete")
PYEOF

ok "Manifest patched"

# ═══════════════════════════════════════════════════════════════
# STEP 6 — REBUILD AND ALIGN
# ═══════════════════════════════════════════════════════════════

info "Step 6/7 — Rebuilding APK..."

apktool b "$DECOMPILED" -o "$APK_UNSIGNED"

[[ -s "$APK_UNSIGNED" ]] || die "Rebuilt APK is missing or empty"

ok "APK rebuilt"

info "Running zipalign..."

zipalign -f -v 4 "$APK_UNSIGNED" "$APK_ALIGNED"

zipalign -c -v 4 "$APK_ALIGNED"

ok "APK aligned"

# ═══════════════════════════════════════════════════════════════
# STEP 7 — SIGN
# ═══════════════════════════════════════════════════════════════

info "Step 7/7 — Signing APK..."

if [[ ! -f "$KEYSTORE" ]]; then
    warn "Generating signing keystore..."

    mkdir -p "$(dirname "$KEYSTORE")"

    keytool -genkeypair -v \
        -keystore "$KEYSTORE" \
        -alias crystal \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -storepass crystal2024 \
        -keypass crystal2024 \
        -dname "CN=Crystal, OU=Mod, O=Crystal, L=ID, S=ID, C=ID"
fi

apksigner sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:crystal2024 \
    --key-pass pass:crystal2024 \
    --ks-key-alias crystal \
    --out "$APK_OUT" \
    "$APK_ALIGNED"

[[ -s "$APK_OUT" ]] || die "Signed APK was not created"

apksigner verify --verbose "$APK_OUT"

ok "APK signed and verified"

# ═══════════════════════════════════════════════════════════════
# FINAL RESULT
# ═══════════════════════════════════════════════════════════════

SIZE=$(du -sh "$APK_OUT" | cut -f1)

echo ""
echo -e "${GRN}============================================${RST}"
echo -e "${GRN}       CRYSTAL GUIDELINE BUILD COMPLETE     ${RST}"
echo -e "${GRN}============================================${RST}"
echo -e "Output: ${CYN}$APK_OUT${RST}"
echo -e "Size:   ${CYN}$SIZE${RST}"
echo ""

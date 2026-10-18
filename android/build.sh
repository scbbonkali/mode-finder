#!/usr/bin/env bash
#
# Build Mode Finder as an installable APK using nothing but the Android SDK
# build-tools. No Gradle, no AndroidX, no dependencies, no network.
#
#   aapt2      compiles res/ and links the APK (resources + assets + manifest)
#   javac      compiles the one Activity (a JDK 17+ javac, --release 17)
#   d8         turns those classes into classes.dex for API 26+
#   python3    stores that dex inside the APK (no `zip` needed)
#   zipalign   aligns the archive
#   apksigner  signs it with the project's own key
#
# The HTML is copied from ../mobile.html on every build, so the app always
# carries exactly the file the browser prototype was measured against.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# --- toolchain -------------------------------------------------------------
# Everything is discovered, and everything can be pinned from the outside:
#
#   ANDROID_SDK_ROOT / ANDROID_HOME   where the SDK lives
#   BT_VERSION                        build-tools to use (default: newest)
#   PLATFORM_API                      platform to link against (default: newest)
#   JAVA_HOME                         a JDK with javac (default: first found)
#
# Pinning matters twice over. This build is byte-for-byte reproducible, but only
# while the tools are the same ones: `aapt2` and `d8` output can change between
# build-tools releases, and `javac` writes a differently shaped anonymous class
# in different JDK majors. So another machine -- F-Droid's build server, say --
# must be told which versions the published APK was made with, not left to guess.
find_sdk() {
  for d in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" \
           /opt/android-sdk "$HOME/Projects/android-sdk" \
           "$HOME/Android/Sdk" /usr/lib/android-sdk; do
    [ -n "$d" ] && [ -d "$d/build-tools" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}
SDK="$(find_sdk)" || { echo "ERROR: no Android SDK found (set ANDROID_SDK_ROOT)"; exit 1; }

BT_VERSION="${BT_VERSION:-$(ls "$SDK/build-tools" | sort -V | tail -1)}"
BT="$SDK/build-tools/$BT_VERSION"
[ -x "$BT/aapt2" ] || { echo "ERROR: build-tools $BT_VERSION not installed under $SDK"; exit 1; }

PLATFORM_API="${PLATFORM_API:-$(ls "$SDK/platforms" | sed 's/^android-//' | sort -n | tail -1)}"
PLATFORM_JAR="$SDK/platforms/android-$PLATFORM_API/android.jar"
[ -f "$PLATFORM_JAR" ] || { echo "ERROR: no android.jar for platform $PLATFORM_API"; exit 1; }

find_jdk() {
  for c in "${JAVA_HOME:-}" /usr/lib/jvm/* /opt/java/* /opt/jdk/*; do
    [ -n "$c" ] && [ -x "$c/bin/javac" ] && { printf '%s\n' "$c"; return 0; }
  done
  if command -v javac >/dev/null 2>&1; then
    printf '%s\n' "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
    return 0
  fi
  return 1
}
JDK="$(find_jdk)" || { echo "ERROR: no JDK with javac found (set JAVA_HOME)"; exit 1; }

APK_NAME="mode-finder"
KS="$HERE/modes.keystore"
# The keystore password is deliberately not in this repository. It lives in the
# file below, which is ignored, alongside the backups of the key. The environment
# overrides it, so a build server can supply its own.
KS_PASS="${KS_PASS:-}"
if [ -z "$KS_PASS" ] && [ -r "$HERE/../.keystore-password" ]; then
  KS_PASS="$(tr -d '\r\n' < "$HERE/../.keystore-password")"
fi
[ -n "$KS_PASS" ] || {
  echo "ERROR: no keystore password: set KS_PASS, or write it to ../.keystore-password"
  exit 1
}
OUT="$HERE/build"

echo "toolchain : $BT"
echo "platform  : android-$PLATFORM_API   $PLATFORM_JAR"
echo "jdk       : $JDK   $("$JDK/bin/javac" -version 2>&1 | head -1)"

# --- 1. the page itself ----------------------------------------------------
mkdir -p "$HERE/assets"
cp "$HERE/../mobile.html" "$HERE/assets/mobile.html"
SRC_MD5=$(md5sum "$HERE/../mobile.html" | cut -d' ' -f1)
echo "asset     : mobile.html ($(wc -c < "$HERE/assets/mobile.html") bytes, md5 $SRC_MD5)"

# --- 2. resources and the APK shell ---------------------------------------
rm -rf "$OUT"; mkdir -p "$OUT/classes" "$OUT/dex"
"$BT/aapt2" compile --dir "$HERE/res" -o "$OUT/res.zip"
"$BT/aapt2" link \
  -o "$OUT/base.apk" \
  -I "$PLATFORM_JAR" \
  --manifest "$HERE/AndroidManifest.xml" \
  -A "$HERE/assets" \
  "$OUT/res.zip"

# --- 3. the one Activity --------------------------------------------------
"$JDK/bin/javac" --release 17 -nowarn -encoding UTF-8 \
  -classpath "$PLATFORM_JAR" -d "$OUT/classes" \
  $(find "$HERE/src" -name '*.java')

"$BT/d8" --min-api 26 --lib "$PLATFORM_JAR" \
  --output "$OUT/dex" $(find "$OUT/classes" -name '*.class')

python3 - "$OUT/base.apk" "$OUT/dex/classes.dex" <<'PY'
import sys, zipfile
apk, dex = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk, "a", zipfile.ZIP_STORED) as z:
    zi = zipfile.ZipInfo("classes.dex")
    zi.compress_type = zipfile.ZIP_STORED   # dex stays mapped, not extracted
    zi.external_attr = 0o644 << 16
    z.writestr(zi, open(dex, "rb").read())
PY

# --- 4. align and sign ----------------------------------------------------
"$BT/zipalign" -f -p 4 "$OUT/base.apk" "$OUT/aligned.apk"

if [ ! -f "$KS" ]; then
  "$JDK/bin/keytool" -genkeypair -keystore "$KS" -alias modes -keyalg RSA \
    -keysize 2048 -validity 10000 -storepass "$KS_PASS" -keypass "$KS_PASS" \
    -dname "CN=Mode Finder, OU=modes, O=scbb, C=IE" >/dev/null 2>&1
  echo "key       : new signing key written to $KS (password '$KS_PASS')"
fi

"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$KS_PASS" --key-pass "pass:$KS_PASS" \
  --out "$HERE/$APK_NAME.apk" "$OUT/aligned.apk"

# --- 5. report what was actually built ------------------------------------
APK="$HERE/$APK_NAME.apk"
BUNDLED_MD5=$(python3 -c "
import zipfile, hashlib
print(hashlib.md5(zipfile.ZipFile('$APK').read('assets/mobile.html')).hexdigest())")

echo
echo "=== built ==============================================================="
"$BT/aapt2" dump badging "$APK" | grep -E "^(package|sdkVersion|targetSdkVersion|application-label:|launchable-activity|uses-permission)" | sed 's/^/  /'
PERMS=$("$BT/aapt2" dump permissions "$APK" | grep -c "^uses-permission" || true)
echo "  permissions declared : $PERMS"
echo "  apk                  : $APK"
echo "  size                 : $(du -h "$APK" | cut -f1) ($(wc -c < "$APK") bytes)"
echo "  entries              :"
python3 -c "
import zipfile
for i in sorted(zipfile.ZipFile('$APK').infolist(), key=lambda x: x.filename):
    print('      %-46s %6d bytes  %s' % (i.filename, i.file_size, 'stored' if i.compress_type==0 else 'deflated'))"
echo "  source mobile.html   : $SRC_MD5"
echo "  bundled in the APK   : $BUNDLED_MD5"
if [ "$SRC_MD5" = "$BUNDLED_MD5" ]; then echo "  -> the app carries the exact file we tested"; else echo "  -> MISMATCH"; exit 1; fi
grep -c MainActivity "$OUT/dex/classes.dex" >/dev/null && echo "  dex                  : MainActivity present"
"$BT/apksigner" verify --print-certs "$APK" | head -4 | sed 's/^/  /'
echo "=========================================================================="

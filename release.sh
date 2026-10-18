#!/usr/bin/env bash
#
# Publish a new version in one command.
#
#   ./release.sh 1.1 "The neck now centres on tall screens"
#
# It bumps the version in the manifest (the single source of truth), rebuilds
# the APK, commits, tags, pushes, and attaches the signed APK to a GitHub
# release. The next time the app is opened through Obtainium, the phone offers
# the update.
#
# The APK is the artefact and mobile.html is the source: android/build.sh copies
# the page into the app and prints the md5 of both, so a release that does not
# match the tested page cannot slip out.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
export GIT_TERMINAL_PROMPT=0

VERSION="${1:-}"
NOTES="${2:-}"
[ -n "$VERSION" ] || { echo "usage: $0 <versionName> [\"release notes\"]"; exit 2; }

REPO_SLUG="$(git remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
TOK="$(sed -n 's#^https://[^:]*:\([^@]*\)@github\.com$#\1#p' "$HOME/.git-credentials" | tail -1)"
[ -n "$TOK" ] || { echo "ERROR: no GitHub token in ~/.git-credentials"; exit 1; }
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "ERROR: tag v$VERSION already exists"; exit 1; }

# --- bump the version ------------------------------------------------------
MAN="$HERE/android/AndroidManifest.xml"
VC="$(sed -n 's/.*android:versionCode="\([0-9]*\)".*/\1/p' "$MAN" | head -1)"
NEW=$((VC + 1))
sed -i "s/android:versionCode=\"$VC\"/android:versionCode=\"$NEW\"/; \
        s/android:versionName=\"[^\"]*\"/android:versionName=\"$VERSION\"/" "$MAN"
echo "version  : $VERSION   (versionCode $VC -> $NEW)"

# --- build -----------------------------------------------------------------
"$HERE/android/build.sh" | tail -16
APK="$HERE/android/mode-finder.apk"
MD5="$(md5sum "$APK" | cut -d' ' -f1)"
SHA="$(sha256sum "$APK" | cut -d' ' -f1)"
SIZE="$(wc -c < "$APK")"

# --- keep the README's hashes true -----------------------------------------
python3 - "$VERSION" "$SIZE" "$MD5" "$SHA" <<'PY'
import re, sys
ver, size, md5, sha = sys.argv[1:5]
block = "```\n%s bytes\nmd5    %s\nsha256 %s\n```\n\nMode Finder %s" % (size, md5, sha, ver)
text = open("README.md").read()
text, n = re.subn(r"(?s)(<!-- hashes:start -->\n).*?(\n<!-- hashes:end -->)",
                  lambda m: m.group(1) + block + m.group(2), text)
open("README.md", "w").write(text)
print("readme   : hash block", "updated" if n else "MARKERS NOT FOUND")
PY

# --- commit, tag, push -----------------------------------------------------
git add -A
git commit -q -m "$VERSION: ${NOTES:-release}"
git tag -a "v$VERSION" -m "Mode Finder $VERSION"
git push -q origin HEAD
git push -q origin "v$VERSION"
echo "pushed   : $(git rev-parse --short HEAD)  $(git rev-parse --abbrev-ref HEAD)  tag v$VERSION"

# --- release with the APK attached -----------------------------------------
python3 - "$TOK" "$REPO_SLUG" "$VERSION" "$MD5" "$SHA" "$SIZE" "$NOTES" "$APK" <<'PY'
import json, sys, urllib.request

tok, slug, ver, md5, sha, size, notes, apk = sys.argv[1:9]
body = ((notes + "\n\n") if notes else "") + (
    "**Install:** download the APK below and open it — Android will ask to allow "
    "installs from this source. Install it over the previous version: the "
    "signature matches, so nothing is lost.\n\n"
    "**Update:** in Obtainium, add `https://github.com/%s` once and it will "
    "offer every future release.\n\n"
    "```\n%s bytes\nmd5    %s\nsha256 %s\n```\n\n"
    "minSdk 26, targetSdk 34" % (slug, size, md5, sha))


def api(url, data=None, ctype="application/json"):
    req = urllib.request.Request(url, data=data)
    req.add_header("Authorization", "token " + tok)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Content-Type", ctype)
    return json.load(urllib.request.urlopen(req, timeout=120))


rel = api("https://api.github.com/repos/%s/releases" % slug, json.dumps({
    "tag_name": "v" + ver, "name": "Mode Finder " + ver, "body": body,
    "draft": False, "prerelease": False}).encode())
print("release  :", rel["html_url"])

asset = api("https://uploads.github.com/repos/%s/releases/%d/assets?name=mode-finder.apk"
            % (slug, rel["id"]),
            open(apk, "rb").read(), "application/vnd.android.package-archive")
print("asset    :", asset["name"], asset["size"], "bytes")
print("download :", asset["browser_download_url"])
PY

# Mode Finder — Android wrapper

The phone app is **the same `mobile.html`** that has been developed and measured
in the browser, carried inside a WebView. One Activity, one asset, no
dependencies, no permissions, no network.

```
android/
  AndroidManifest.xml          identity, versions, minSdk 26 / targetSdk 34
  src/net/scbb/modefinder/
    MainActivity.java          the WebView host (~90 lines, platform APIs only)
  res/values/                  app name, palette copy, dark theme
  res/drawable/                launcher icon (six strings, a note and a root)
  res/mipmap-anydpi-v26/       adaptive icon; -v33 adds the monochrome layer
  assets/mobile.html           copied from ../mobile.html by every build
  build.sh                     the whole build: aapt2 -> javac -> d8 -> sign
  modes.keystore               this app's signing key (not in the repo)
  build/                       intermediates (throwaway)
  mode-finder.apk              the output
```

## Build

```sh
./build.sh          # ~5 seconds, prints what it made
```

It needs only the Android SDK build-tools (aapt2, d8, zipalign, apksigner), a JDK
with `javac`, and `python3`. Gradle is deliberately not used — Gradle 8.9 does not
run on the JDK 26 installed here, and nothing in this app needs a dependency
manager.

Nothing is read from a config file: the tools are found by looking in the usual
places, and each one can be pinned from outside, so another machine can be told
exactly what to build with.

| variable | default | meaning |
|---|---|---|
| `ANDROID_SDK_ROOT` / `ANDROID_HOME` | searched (incl. `/opt/android-sdk`) | where the SDK is |
| `BT_VERSION` | newest build-tools | which `aapt2` and `d8` to use |
| `PLATFORM_API` | newest platform | which `android.jar` to link against |
| `JAVA_HOME` | first JDK with `javac` | which compiler to use |
| `UNSIGNED` | off | set to `1` to stop after aligning: no key, no signature |

`UNSIGNED=1` writes `mode-finder-unsigned.apk` instead of `mode-finder.apk`: the
same contents, aligned, but unsigned, with no key read, made or used. That is what
a build service wants — F-Droid's `output:` field asks for "the resulting unsigned
release APK", and F-Droid signs whatever it publishes with its own key.

An unknown version fails immediately rather than quietly building with something
else:

```
ERROR: build-tools 99.9.9 not installed under /home/scbb/Projects/android-sdk
```

## Reproducible builds

Two builds of this source, seconds apart, produce APKs with the same md5:
`e7121b791205a754d540a71c7330ed28`, the file published as v1.0. Nothing in the
chain writes a clock or a random value — `aapt2` stamps every zip entry
1980-01-01, `d8` is deterministic, and an RSA signature is deterministic too.

What does and does not change the output, measured rather than assumed:

| input | matters? | how much |
|---|---|---|
| build-tools version (`aapt2`, `d8`) | yes | they write the resources and the dex |
| platform version (`android.jar`) | yes | it is the link target |
| the compiler (`javac`) | **yes** | JDK 26 writes `MainActivity$1.class` at 944 bytes, JDK 17 at 903. One anonymous inner class, and the dex moves with it: 3700 vs 3584 bytes |
| the JVM that runs `d8` | **no** | identical dex under JDK 17, JDK 26 and Temurin 17 — `d8` reads class files, not the runtime |

So reproducing a published release means naming the three that matter, not two.
The v1.0 APK was built with JDK 26:

```sh
JAVA_HOME=/usr/lib/jvm/java-26-openjdk BT_VERSION=36.0.0 PLATFORM_API=36 ./build.sh
md5sum mode-finder.apk        # must equal the md5 printed on the release page
```

`JAVA_HOME` selects the compiler, and the compiler half of a JDK is the half that
matters. The `d8` script ignores `JAVA_HOME` and runs whatever `java` is on
`PATH` — which, happily, makes no difference at all.

That is what would let F-Droid verify and redistribute *this* signed APK rather
than signing a copy of its own, provided its build server compiles with the same
`javac`. It is also the reason this wrapper is plain platform API with nothing to
fetch: the fewer inputs, the fewer things to pin.

## Install on the phone

```sh
# from the phone's browser, on the same wifi:
#   http://192.168.0.102:8080/android/mode-finder.apk
```

Or, with the phone on USB: `$SDK/platform-tools/adb install -r android/mode-finder.apk`

## What the wrapper decides, and why

| decision | reason |
|---|---|
| `minSdk 26` | adaptive icons and a modern WebView everywhere; the WebView is updatable through Play, so the page's CSS is current on any Android 8+ phone |
| `targetSdk 34`, not 35+ | Android 15 forces edge-to-edge for target 35+, which would put the page under the status bar and change the viewport every measurement in this project was taken in (390×844). Sideloading does not need a newer target; a Play release would, and would need insets handling added |
| `textZoom 100`, `minimumFontSize 1` | the layout is tuned to the pixel; the system font-size setting must not inflate it |
| `setBlockNetworkLoads(true)`, no permissions | the page is entirely local. The APK declares zero permissions |
| `setAlgorithmicDarkeningAllowed(false)` / `FORCE_DARK_OFF` | the page is already dark; the WebView must never repaint it (the same fight we won against Chrome's force-dark) |
| `setOverScrollMode(NEVER)` | no blue glow when dragging the neck |
| `configChanges=...` | rotating does not recreate the WebView, so the page keeps its state and scroll |
| Back button | asks the page whether a menu is open; if so it dispatches a body click, which the page's *own* document click handler uses to close it. The wrapper never edits the page's DOM, so its internal state stays consistent. Back again exits |
| icon | six strings, a green scale note and an outlined warm root — the app's own visual language. Motif corners sit 29.4px from centre, inside the 33px adaptive-icon safe radius |

## Updating

`mobile.html` is the single source of truth: edit it, iterate in the browser as
before, then

```sh
./build.sh && cp mode-finder.apk ..    # or serve android/ over the LAN server
```

and reinstall. `build.sh` prints the md5 of the source file and of the copy
inside the APK, so a stale build is impossible to miss.

To publish instead:

```sh
./release.sh 1.1 "Variant shapes for harmonic minor"
```

which bumps the version in the manifest, builds, commits, tags, pushes, and
attaches the signed APK to a GitHub release — the thing the phone's updater
watches. The APK keeps the same signing key, so the update installs over the
installed app.

## Signing key

`modes.keystore` is this app's identity, and it is deliberately **not** in this
repository — it is ignored, and it lives only where releases are signed. Android
refuses to update an installed app with a differently signed APK, so the file has
to survive; anyone forking this project to publish their own builds should make
their own key rather than reuse this one. It is a sideloading key; a Play release
would want a properly kept upload key instead.

A clone has neither the key nor its password, and that is not an error: the first
build generates a key, invents a password, and writes it to the ignored
`.keystore-password` beside the repository. So `git clone` and `android/build.sh`
produce an installable APK anywhere — this project's app, signed by somebody else,
which Android treats as a different app.

### Why the dexer may be run twice

javac 21 and later write a `MethodParameters` attribute into every method. The
`d8` in build-tools 34 cannot read it: it dies with an internal
NullPointerException, which is exactly what happened when F-Droid's build server
(build-tools 34, javac 21) first built this app. `strip-parameters.py` removes
that one attribute and `build.sh` calls it **only after `d8` has actually refused
the classes** -- so with build-tools 36 nothing is dropped and the APK stays
byte-for-byte the published one. The attribute carries parameter names, and a dex
carries none, so nothing the app does depends on it.

The F-Droid recipe for this app is `metadata/net.scbb.modefinder.yml` in
`fdroid/fdroiddata` (filed as merge request !53009). It installs
`platforms;android-36` and `build-tools;34.0.0` -- the newest pair F-Droid's SDK
transparency log can verify -- builds with `UNSIGNED=1`, and leaves the APK for
F-Droid to sign with its own key.

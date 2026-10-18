# Mode Finder

A guitar mode and scale reference that fits in one HTML file — and an Android
app that carries that file, offline, with no permissions at all.

Pick a **root** and a **mode**: the neck shows every note of the scale, the root
outlined, and the 3rd and 5th marked as chord tones. Three families of modes
(the major scale, harmonic minor and melodic minor), a spelling preference
(auto / sharps / flats) that governs the root, and **variants** — drop two notes
from any mode and see which five-note shape comes out (minor pentatonic, major
pentatonic, Hirajoshi, In-sen and the rest).

- **25 frets**, 0 to 24, double markers at 12 and 24.
- **No network, no permissions, no analytics, no ads.** The app cannot reach the
  internet — it does not even ask for the `INTERNET` permission — because
  everything it needs is inside the file.
- Theory is computed, not typed in: the parent scale by rotating the mode's step
  pattern, note spellings by letter-walk with the fewest accidentals, and
  variants by masking two degrees and looking the resulting pitch-class set up
  in a shape table.

## The repository

| path | what it is |
|---|---|
| `mobile.html` | **the app** — markup, styles, theory and interaction in one file |
| `android/` | the Android wrapper ([its own README](android/README.md)) |
| `mobile-chips.html` | a frozen earlier layout, kept for comparison |
| `mode-finder.html` | the original single-file version this grew from |

## Building

```sh
cd android
./build.sh          # about five seconds; it prints everything it made
```

It needs only what a Linux box with the Android SDK already has: the SDK's
build-tools (`aapt2`, `d8`, `zipalign`, `apksigner`), a JDK with `javac`, and
`python3`. No Gradle, no dependencies, no network, nothing to download.

The result is a ~29 KB APK whose entire user interface is `mobile.html`, copied
in byte for byte at build time — the script prints the md5 of the source file
and of the copy inside the signed APK, so a stale build is impossible to miss.

## Licence

MIT — see [LICENSE](LICENSE).

# Freeco

*Pleco, but free xD*

A free, minimal, camera-first iPhone app for reading Chinese text. Point the camera at
simplified or traditional Chinese, capture a frame, then tap any word to see its
pinyin (with tone marks) and English meaning. Sentence-level translations are
shown too — all processed on device.

## How it works

- **Capture & OCR** — `AVCaptureSession` grabs a still frame; Apple **Vision**
  (`VNRecognizeTextRequest`, languages `zh-Hans` + `zh-Hant`) recognizes the text
  and returns per-line candidates with sub-range bounding boxes.
- **Segmentation** — forward maximum-matching against the CC-CEDICT headword set
  splits each line into words; boxes are resolved per word so they're tappable in
  place over the frozen frame.
- **Dictionary** — CC-CEDICT is bundled offline (as an asset-catalog data set),
  indexed by both simplified and traditional forms. Numeric pinyin is converted to
  tone-marked pinyin at display time.
- **Translation** — Apple's **Translation** framework translates sentences on
  device (zh → en).

No accounts, no history, no network calls at runtime.

## Project layout

```
ChineseOCR/
  App/            App entry point
  Camera/         AVCapture controller + SwiftUI preview
  OCR/            Vision recognition + per-word boxes
  Dictionary/     CC-CEDICT loading, pinyin, segmentation
  Translation/    Translation-framework wrapper
  UI/             Camera screen, frozen-frame result, panels
  Assets.xcassets/cedict.dataset  Bundled dictionary
```

## Build & run

Requires Xcode 16+ and an iPhone running iOS 18+. Xcode must also support the
phone's iOS version: an iPhone on iOS 27 needs Xcode 27 (Xcode 26.x fails with
"The developer disk image could not be mounted on this device").

The camera does not work in the Simulator (the app shows "No camera" there), and
Apple's Translation framework does not run in the Simulator either.

### Running on your iPhone

1. Open `ChineseOCR.xcodeproj`, select the **ChineseOCR** target ›
   **Signing & Capabilities**, keep "Automatically manage signing" on, and pick
   your **Team** (a free Personal Team from your Apple ID works).
2. If Xcode says the bundle identifier is unavailable, change
   `com.ricky.ChineseOCR` to something unique.
3. Plug in the iPhone, unlock it, tap **Trust** if asked, choose it as the run
   destination, and press Run.
4. First run with a Personal Team: on the phone open **Settings › General ›
   VPN & Device Management**, tap your developer profile, and tap **Trust**.
   Then launch the app again.
5. Allow camera access. The first sentence translation may ask to download
   the Chinese → English language pack; accept it.

Personal Team builds expire after 7 days; just run from Xcode again.

### Checks

```
# pinyin tone marks (real PinyinFormatter)
swiftc -o /tmp/pinyin_check ChineseOCR/Dictionary/PinyinFormatter.swift build_tools/pinyin_check/main.swift && /tmp/pinyin_check
# segmentation, lookup, line joining and sentence splitting (real app code)
swiftc -O -o /tmp/text_check ChineseOCR/Dictionary/ChineseDictionary.swift ChineseOCR/Dictionary/PinyinFormatter.swift ChineseOCR/OCR/TextLayout.swift build_tools/text_check/main.swift && /tmp/text_check
```

## Attribution

Dictionary data is CC-CEDICT, licensed CC BY-SA 4.0. See [NOTICE.md](NOTICE.md).

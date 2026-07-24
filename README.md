# MSheet — search and download public-domain sheet music

An iOS app for finding free, public-domain sheet music by composer or title —
typed or spoken — and saving the PDF to your phone for offline reading. Your
saved Library is stored locally in a SwiftData (SQLite) database inside the
app's sandbox; only the Search and Download screens talk to the network, and
only to [IMSLP](https://imslp.org) (the Petrucci Music Library).

## What it does

- **Search** by composer, title, or both — type in the field or tap the mic
  to speak it, with live on-device transcription.
- **Results** show each matching work with its composer, pulled from IMSLP's
  page-title convention.
- **Tap a result** to see its detail page, with a link to view the real page
  on IMSLP.
- **Tap Download PDF** to save the score straight into your **Library** tab
  for offline reading — no account, no server of ours in the middle.
- Some editions are still under copyright in certain countries; IMSLP gates
  those behind a one-time notice a person has to read and accept themselves.
  MSheet doesn't script past that — it tells you and opens the real IMSLP
  page in-app so you can accept it and download from there instead.
- **Library** lists everything you've downloaded, opens each PDF in a
  built-in reader, and deletes with a swipe.

## Why this design

- **IMSLP's `opensearch` API** — a public, keyless MediaWiki endpoint — is
  the whole search backend. It only returns titles and page links, not
  structured composer/instrumentation data, so `IMSLPService.swift` parses
  IMSLP's own `"Work Title (Last, First)"` page-title convention to split out
  a composer, and `ScoreDetailView` links out to the real page for anything
  it doesn't have.
- **No scripted bypass of IMSLP's copyright notice.** Ungated scores expose
  a direct, page-relative PDF link (`/images/.../Something.pdf`) that
  `IMSLPService.resolveDownloadURL` downloads straight into the app. Gated
  scores only link to `Special:IMSLPDisclaimerAccept`, which requires a
  person to read and accept a per-country notice — MSheet detects that case
  and routes you to the real IMSLP page instead of working around it.
  See the doc comment on `resolveDownloadURL` in
  `Sources/MSheet/Services/IMSLPService.swift`.
- **SwiftData**, local-only, for the Library — same on-device SQLite pattern
  as [ThoughtsApp](../ThoughtsApp), just tracking downloaded scores instead
  of notes. Downloaded PDFs live in `Documents/Scores/` inside the app's own
  sandbox.
- **Voice search stays on-device** when the phone/language supports it, via
  the same `DictationController` pattern as ThoughtsApp —
  `requiresOnDeviceRecognition` is set whenever
  `SFSpeechRecognizer.supportsOnDeviceRecognition` is true.
- **Two tabs, no settings screen** — Search and Library, nothing else, so
  there's nothing to configure before typing (or saying) a search.

Minimum target: **iOS 17** (required by SwiftData).

## Option A — build it yourself, with a Mac + Xcode 15+

This repo only contains Swift source files, not a generated `.xcodeproj` —
Xcode project files are binary-ish and fragile to hand-write, so the reliable
path is to create the project shell in Xcode itself and drop these files in:

1. Open Xcode → **File → New → Project → iOS → App**.
2. Product Name: `MSheet`. Interface: **SwiftUI**. Language: **Swift**.
   Storage: leave as "None" (we're adding SwiftData manually).
3. Delete the auto-generated `ContentView.swift`, `<ProjectName>App.swift`,
   and `Info.plist` (if Xcode created one) — we're using this repo's own
   `Info.plist`, which already has the microphone/speech recognition entries.
4. Drag everything under `Sources/MSheet/` in this folder (all the `.swift`
   files, `Info.plist`, and `Assets.xcassets`) into the Xcode project
   navigator (check "Copy items if needed") — `Assets.xcassets` has the app
   icon and accent color.
5. Select the project → target **MSheet** → **Build Settings** → search
   "Info.plist File" → point it at `Sources/MSheet/Info.plist`. Also check
   **General** → App Icons and Launch Images → App Icon Source is set to
   **AppIcon** (Xcode usually picks this up automatically once the asset
   catalog is added).
6. Still in target settings → **Signing & Capabilities** → set your Apple ID
   team so it can install to your device.
7. Plug in your iPhone (or use a Simulator first — dictation needs a real
   device, Simulator has no microphone input), select it as the run
   destination, and hit **Run** (⌘R).
8. On first run to a physical device: on your iPhone go to
   **Settings → General → VPN & Device Management** and trust your developer
   certificate if prompted.

## Option B — no Mac at all: cloud build + sideload

This repo also includes `project.yml` (an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
spec) and `.github/workflows/build-ipa.yml`, so GitHub's free macOS runners
can generate the Xcode project and compile the app for you — no Apple
credentials touch GitHub at all, because the build is **unsigned**. Signing
happens later, on your own PC, when you install it.

1. **Create a GitHub repo and push this folder.** From inside `MSheetApp/`:
   ```bash
   git init
   git add .
   git commit -m "MSheet app"
   ```
   Then create an empty repo at github.com/new (private is fine), and run
   the `git remote add origin …` + `git push` commands GitHub shows you
   after creating it.
2. GitHub Actions starts automatically on push. Open the **Actions** tab on
   your repo, wait for the "Build unsigned IPA" run to go green (a few
   minutes), then open it → **Artifacts** → download `MSheet-unsigned-ipa`.
   Unzip it to get `MSheet-unsigned.ipa`.
3. **Install AltServer for Windows**: [altstore.io](https://altstore.io) →
   download AltServer, install it (it needs iTunes or Apple Devices app
   installed first, for the USB drivers).
4. Plug your iPhone into your PC via USB, trust the computer on the phone
   if prompted, then in AltServer's system-tray icon: **Install AltStore →
   [your iPhone]**, sign in with your Apple ID when it asks (an app-specific
   password may be required — AltServer's site walks through that).
5. Once AltStore is on your phone: in the tray icon choose the equivalent
   "Install .ipa" option (or open the AltStore app on your iPhone → My Apps
   → **+** → pick the file over the same Wi-Fi network) and select
   `MSheet-unsigned.ipa`. AltServer signs it on the fly with your Apple ID
   and installs it — same trust step as Option A applies
   (**Settings → General → VPN & Device Management**).

**The catch with a free Apple ID:** apps sideloaded this way expire after
**7 days** and need re-signing. AltStore can do this automatically in the
background if your phone can reach AltServer on the same Wi-Fi network
periodically — otherwise, reconnect via USB and reinstall the same `.ipa`
weekly. A paid Apple Developer account ($99/year) extends that to a year and
removes this step, if it's worth it to you later.

## Files

| File | Purpose |
|---|---|
| `Sources/MSheet/MSheetApp.swift` | App entry point, sets up the local-only SwiftData container |
| `Sources/MSheet/Models/SearchResult.swift` | A single IMSLP search hit, plus title/composer parsing |
| `Sources/MSheet/Models/SavedScore.swift` | The `SavedScore` SwiftData model + the local `Scores/` folder helper |
| `Sources/MSheet/Services/IMSLPService.swift` | Search via IMSLP's `opensearch` API; resolves direct PDF links |
| `Sources/MSheet/Services/DictationController.swift` | Wraps `Speech`/`AVAudioEngine` for on-device speech-to-text |
| `Sources/MSheet/Views/RootTabView.swift` | Search / Library tab bar |
| `Sources/MSheet/Views/SearchView.swift` | Search field (with mic), debounced live search, results list |
| `Sources/MSheet/Views/ScoreDetailView.swift` | Score detail, download flow, disclaimer-gate handling |
| `Sources/MSheet/Views/LibraryView.swift` | List of downloaded scores, swipe to delete |
| `Sources/MSheet/Views/PDFPreviewView.swift` | In-app PDF reader (PDFKit) for a downloaded score |
| `Sources/MSheet/Views/SafariView.swift` | In-app browser for viewing/accepting IMSLP pages |
| `Sources/MSheet/Info.plist` | App metadata + the microphone/speech-recognition privacy strings |
| `Sources/MSheet/Assets.xcassets/` | Asset catalog holding the app icon and accent color |
| `project.yml` | XcodeGen spec — only used by the Option B cloud build |
| `.github/workflows/build-ipa.yml` | GitHub Actions workflow that builds the unsigned `.ipa` |

## Possible next steps (not built, in case you want them later)

- A second source (CPDL for choral works, Musopen) alongside IMSLP, behind
  the same `Download` button.
- Letting you pick which edition to download when a work has several (right
  now it grabs the first PDF link IMSLP lists).
- A "Browse by instrument/era" tab.
- Filtering search by composer vs. title vs. instrument, rather than one
  combined field.
- Sorting/tagging the Library (by composer, by instrument, by date added).

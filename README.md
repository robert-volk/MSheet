# MSheet — search and download public-domain sheet music

An iOS app for finding free, public-domain sheet music by composer or title —
typed or spoken — and saving the PDF to your phone for offline reading. Your
saved Library is stored locally in a SwiftData (SQLite) database inside the
app's sandbox; only the Search and Download screens talk to the network, and
only to [Mutopia Project](https://www.mutopiaproject.org).

Search results currently come from **Mutopia only** — every one of its files
is pre-cleared public domain/CC with a direct download link, so a result is
always a one-tap download. Both [IMSLP](https://imslp.org) and
[CPDL](https://cpdl.org) (the Choral Public Domain Library) support are
fully built and still in the codebase — `IMSLPService.swift` and
`CPDLService.swift` — just not called from `SearchView`, by request. See
"Why this design" below for how to bring either back.

## What it does

- **Search** by composer, title, or both — type in the field or tap the mic
  to speak it, with live on-device transcription.
- **Results** show each matching work with its composer.
- **Tap a result** to see its detail page, with a link to view the real page
  on Mutopia.
- **Tap Download PDF** to save the score straight into your **Library** tab
  for offline reading — no account, no server of ours in the middle. Every
  Mutopia result downloads directly, no extra steps.
- **Library** lists everything you've downloaded, opens each PDF in a
  built-in reader, and deletes with a swipe.

## Why this design

- **CPDL was chosen over other candidates after checking each one live**,
  not from a search-results summary — `sheetmusicinternational.com` turned
  out to gate clean (unwatermarked) downloads behind an account and mix
  purchasable copyrighted works into search results (plus marketing copy
  visibly written to influence how AI tools evaluate the site, which is
  itself a reason for caution); `sheetmusiceden.com` mixes genuine free PDFs
  with commercial/affiliate listings on the same results page and its
  download links aren't stable direct file URLs; `musopen.org` sits behind a
  Cloudflare bot-challenge page that blocks automated access outright. CPDL
  had none of these problems — confirmed by actually downloading a file and
  checking for a real `%PDF-` header before building anything against it.
  It was briefly wired into search and then unwired again by request; the
  code is untouched, just not called.
- **IMSLP and CPDL are both built but disabled, not deleted.** Both were
  merged sources alongside Mutopia at different points — IMSLP's catalog is
  far bigger (~700k+ scanned works) but gates some editions behind a
  per-country copyright notice; CPDL adds choral/vocal depth neither Mutopia
  nor IMSLP cover well. Both ended up scoped back out to keep search to
  Mutopia only. To bring either back: in `SearchView.runSearch()`, add
  `IMSLPService.search` and/or `CPDLService.search` as additional concurrent
  calls alongside Mutopia (straightforward — `SearchResult` already carries
  a `source` field for tagging each in the UI, and
  `ScoreDetailView.download()` already switches on `source` to pick the
  right page-scraping logic for whichever sources are active).
- **CPDL and IMSLP are the same MediaWiki software, but not the same
  conventions.** Both expose a keyless full-text `list=search` API and a
  page-relative `/images/.../Something.pdf` link pattern once a score is
  ungated — but IMSLP page titles read `"Work Title (Last, First)"` while
  CPDL's already read `"Work Title (First Last)"`, and CPDL's page URLs are
  `/wiki/index.php?title=...` where IMSLP's are `/wiki/<Title>`. Every one
  of these details was checked against the live sites (not assumed) before
  `CPDLService.swift` was written, including downloading a real CPDL PDF to
  confirm its bytes.
- **IMSLP's full-text `list=search` API** — a public, keyless MediaWiki
  endpoint — is IMSLP's half of the search backend. It only returns page
  titles, not structured composer/instrumentation data, so
  `IMSLPService.swift` parses IMSLP's own `"Work Title (Last, First)"`
  page-title convention to split out a composer. (An earlier version used
  the `opensearch` endpoint, which only prefix-matches the start of a title
  — so composer-first queries never matched anything, and on top of that it
  returns a shorter JSON shape for zero-result queries that crashed a naive
  decoder. `list=search` does real full-text matching and degrades to an
  empty result list instead.)
- **Mutopia has no JSON API**, only an HTML results table, so
  `MutopiaService.swift` parses that page directly — verified against the
  live markup first rather than guessed, and parsed block-by-block (one
  `<table class="table-bordered result-table">` per result) so a markup
  change breaks individual results instead of the whole search.
- **Downloads are verified, not trusted.** Whatever URL a source resolves to
  gets checked for a real `%PDF-` header before it's written to disk or
  added to the Library. Early on, a scraped IMSLP link that actually served
  an interstitial page got saved with a `.pdf` name anyway, and PDFKit
  silently rendered it blank — this check, plus an explicit error state in
  `PDFPreviewView` if a file still won't open, turns that into a clear
  "couldn't download automatically, open on `<source>`" prompt instead of a
  blank screen.
- **No scripted bypass of IMSLP's copyright notice.** Ungated scores expose
  a direct, page-relative PDF link (`/images/.../Something.pdf`) that
  `IMSLPService.resolveDownloadURL` downloads straight into the app. Gated
  scores only link to `Special:IMSLPDisclaimerAccept`, which requires a
  person to read and accept a per-country notice — MSheet detects that case
  and routes you to the real IMSLP page instead of working around it. CPDL's
  `resolveDownloadURL` never encountered this while testing (every score
  checked had a direct link), so it doesn't special-case a gate — if CPDL
  ever does gate a work, it just falls back to "open on CPDL" like
  everything else. Mutopia never needs a resolve step at all —
  `MutopiaService` hands back a direct PDF link from search results, so
  `ScoreDetailView` skips straight to downloading for Mutopia results.
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
- **Navigation chrome is tinted with `.tint(Color("NavigationGold"))` on
  each `NavigationStack`**, not `UINavigationBar.appearance()`. The
  appearance-proxy approach was tried first and silently didn't work — a
  SwiftUI `NavigationStack`'s own back button doesn't reliably read it. The
  mic buttons and `HomeButton` use `Color("AccentColor")` (an explicit
  named-asset lookup) rather than `Color.accentColor`, specifically so this
  ambient gold `.tint()` can't also recolor them — `ScoreDetailView`'s
  Download button keeps its own local `.tint(Color("DownloadBrown"))` the
  same way, overriding the ambient tint for just that one button.

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
| `Sources/MSheet/Models/SearchResult.swift` | A single search hit from either source, already split into title/composer |
| `Sources/MSheet/Models/SavedScore.swift` | The `SavedScore` SwiftData model + the local `Scores/` folder helper |
| `Sources/MSheet/Services/IMSLPService.swift` | Search via IMSLP's full-text API; resolves direct PDF links, respecting the copyright gate — built, but not currently called from `SearchView` |
| `Sources/MSheet/Services/MutopiaService.swift` | Search + direct PDF links via Mutopia's HTML results page |
| `Sources/MSheet/Services/CPDLService.swift` | Search via CPDL's full-text API; resolves direct PDF links (choral/vocal) — built, but not currently called from `SearchView` |
| `Sources/MSheet/Services/DictationController.swift` | Wraps `Speech`/`AVAudioEngine` for on-device speech-to-text |
| `Sources/MSheet/Views/RootTabView.swift` | Search / Library tab bar |
| `Sources/MSheet/Views/SearchView.swift` | Search field (with mic), debounced Mutopia search, results list |
| `Sources/MSheet/Views/ScoreDetailView.swift` | Score detail, download flow (validated), disclaimer-gate handling |
| `Sources/MSheet/Views/LibraryView.swift` | List of downloaded scores, swipe to delete |
| `Sources/MSheet/Views/PDFPreviewView.swift` | In-app PDF reader (PDFKit) for a downloaded score |
| `Sources/MSheet/Views/SafariView.swift` | In-app browser for viewing/accepting IMSLP pages |
| `Sources/MSheet/Info.plist` | App metadata + the microphone/speech-recognition privacy strings |
| `Sources/MSheet/Assets.xcassets/` | Asset catalog holding the app icon and accent color |
| `project.yml` | XcodeGen spec — only used by the Option B cloud build |
| `.github/workflows/build-ipa.yml` | GitHub Actions workflow that builds the unsigned `.ipa` |

## Possible next steps (not built, in case you want them later)

- Re-enabling IMSLP and/or CPDL as additional sources (see "Why this
  design" above).
- Letting you pick which edition to download when a work has several (right
  now it grabs the first PDF link the source lists).
- Importing a PDF you downloaded manually (e.g. after accepting IMSLP's
  copyright notice in Safari) into the Library, via the system document
  picker — right now a manual download doesn't make it back into the app.
- A "Browse by instrument/era" tab.
- Filtering search by composer vs. title vs. instrument, rather than one
  combined field.
- Sorting/tagging the Library (by composer, by instrument, by date added).

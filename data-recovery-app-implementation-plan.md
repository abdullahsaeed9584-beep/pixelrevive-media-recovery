# Data Recovery App — Full Implementation Plan

**Positioning:** "Don't recover, prevent." — Protection Mode (proactive vault) + realistic non-root recovery + root bonus tier.
**Stack:** Flutter (UI/logic) + Kotlin (native Android heavy ops) + Platform Channels. 100% free tools/libs, no paid SDK.

Each phase below is self-contained: goal, required packages, native tasks, Flutter tasks, UI screens, and a **test checkpoint**. Developer builds phase → tests independently using the checkpoint → moves to next phase. Do not skip test checkpoints.

---

## PHASE 0 — Foundation & Project Shell

**Goal:** App skeleton, permission flow, root detection, base UI shell — nothing functional yet, just scaffolding.

**Packages:**
- `permission_handler` — runtime permission requests
- `device_info_plus` — Android version detection (needed for scoped storage branching)
- `libsu` (native Kotlin dependency, via Gradle: `com.github.topjohnwu.libsu`) — root check + root shell

**Native (Kotlin) tasks:**
1. Set up `MethodChannel` named `com.nowdigiverse.recovery/core` for Flutter↔Kotlin bridge.
2. Implement `checkRootAccess()` using `libsu` → `Shell.isAppGrantedRoot()` → returns Boolean to Flutter.
3. Implement `getAndroidApiLevel()` → returns int (needed to branch storage strategy: API ≤28 legacy, API 29-30 scoped, API 31+ MediaStore trash available).

**Flutter tasks:**
1. App shell: bottom nav or drawer with 4 sections — Home/Scan, Protection Mode, Vault, Settings.
2. Onboarding screen (first launch only): 3-slide explainer — what app does, why storage permission needed, no-data-leaves-device statement.
3. Permission request screen: clear per-permission explanation before system dialog fires (pre-permission priming screen), then trigger `permission_handler` request for:
   - Storage (`Permission.storage` legacy) / `MANAGE_EXTERNAL_STORAGE` (Android 11+)
   - Notification (`Permission.notification`)
4. Call `checkRootAccess()` on app start, store result in app state (Provider/Riverpod/Bloc — pick one, keep consistent across app).

**UI to build:**
- Splash screen
- 3-slide onboarding carousel
- Permission priming screen (icon + 2-line explanation + "Allow" button)
- Empty Home screen shell with nav (no functionality yet, just navigation working)

**Test checkpoint:** App installs, onboarding shows once, permissions requested properly, nav between empty tabs works, root status printed in debug log (`true`/`false` correctly on rooted vs non-rooted test device).

---

## PHASE 1 — Tier 1: Non-Root Recovery (MediaStore Trash + WhatsApp Media)

**Goal:** Core recovery feature working for majority of users, no root needed.

**Packages:**
- `photo_manager` OR direct `MethodChannel` to native `MediaStore` query (native recommended for trash-flag access — `photo_manager` may not expose `isTrashed()` reliably, verify first)
- `path_provider`

**Native (Kotlin) tasks:**
1. `scanMediaStoreTrash()`: query `MediaStore.Files.getContentUri("external")` with `MediaStore.MediaColumns.IS_TRASHED` filter (API 30+) → return list of `{uri, name, dateDeleted, size, mimeType}`.
2. `scanWhatsAppMedia()`: scan these paths (handle both old `WhatsApp/Media/` and new scoped `Android/media/com.whatsapp/WhatsApp/Media/` per Android version):
   - `WhatsApp Images/`, `WhatsApp Video/`, `WhatsApp Audio/`, `WhatsApp Documents/`, `.Statuses/`
   - Compare against MediaStore index → files present on disk but not in MediaStore/gallery index = "recoverable" candidates (edge case: use file existence + last-modified as heuristic, since these aren't technically "deleted" — just gallery-invisible).
3. Return combined scan results as JSON list to Flutter via MethodChannel.

**Flutter tasks:**
1. Scan trigger screen (Home tab): big "Start Scan" button, category chips (Photos / Videos / WhatsApp / Documents / Audio — multi-select filter BEFORE scan starts, per earlier decision).
2. Scanning screen: progress bar + live thumbnail grid populating as results stream in (don't wait for full scan to finish before showing results — stream results as found).
3. Results screen: grid view, thumbnail + filename + size + date, checkbox multi-select, "Recover Selected" button.
4. Recover action: copy selected files from scanned location to user-chosen restore folder (`Download/Recovered/`), show success toast + "Open File" / "Share" buttons.

**UI to build:**
- Home/Scan screen with category filter chips
- Live scanning screen (progress bar + streaming thumbnail grid)
- Results grid screen (multi-select, recover button)
- Recovery success screen (with direct share/export buttons — per earlier decision, no extra gallery-hunting step)

**Test checkpoint:** On non-rooted test device — delete a photo via gallery, delete a WhatsApp media file, run scan, both appear in results within trash window, recover successfully, file lands in `Download/Recovered/`, opens correctly.

---

## PHASE 2 — Protection Mode + Encrypted Vault (with Password)

**Goal:** Proactive protection — main differentiator. Selective folder monitor + password-locked vault.

**Packages:**
- `androidx.security.crypto` (native, `EncryptedFile` + `EncryptedSharedPreferences`) — free AndroidX lib
- `local_auth` (Flutter) — biometric unlock option
- `sqflite` — vault metadata DB
- `flutter_local_notifications` — protection alerts

**Native (Kotlin) tasks:**
1. `ContentObserver` registered on `MediaStore.Files.getContentUri` — detects delete events reliably (more reliable than `FileObserver` per earlier decision — avoids race condition on raw unlink).
2. On detected delete (only for folders user enabled monitoring on): copy file into vault directory BEFORE OS fully purges (best-effort — note in code comments this is timing-sensitive, test on multiple OEMs).
3. Encrypt copied file using `EncryptedFile` (AES-256-GCM), key auto-managed by Android Keystore.
4. Fire local notification: "File protected: [filename]" with tap action → opens vault entry.

**Flutter tasks:**
1. Protection Mode setup flow: toggle ON → **first show PIN/password creation screen** (per earlier decision — set password BEFORE protection activates).
   - PIN stored via `EncryptedSharedPreferences`, never plain text.
   - Add biometric-unlock toggle as alternative to PIN (optional, `local_auth`).
2. Folder selection screen: checklist of foldersto monitor — DCIM, WhatsApp Images, WhatsApp Video, WhatsApp Status, Downloads, Documents (granular per-folder toggle, per earlier decision — not blanket monitor).
3. Vault screen: locked by default, requires PIN/biometric to open. Shows protected files grid (thumbnail, date protected, source folder).
4. Vault entry actions: restore to original location, delete from vault, share.
5. Failed-password lockout: 5 wrong attempts → 30-second temporary lock, counter resets on correct entry.

**UI to build:**
- PIN/password creation screen (numeric keypad style, confirm step)
- Folder selection checklist screen
- Vault lock screen (PIN pad or biometric prompt)
- Vault contents grid (post-unlock)
- Notification tap → deep link to vault entry

**Test checkpoint:** Enable Protection Mode, set PIN, select DCIM folder only, delete a photo from DCIM via gallery → notification fires → vault contains encrypted copy → vault locked without PIN → correct PIN opens it → wrong PIN 5x triggers lockout → restore works.

---

## PHASE 3 — Tier 2: SAF Extended Scan (Non-Root Deeper Scan)

**Goal:** Slightly deeper scan for non-root users via user-granted folder access, clearly labeled "Extended Scan" (not "deep scan" — avoid false marketing per earlier decision).

**Packages:**
- Native: `DocumentFile`, `ACTION_OPEN_DOCUMENT_TREE` intent
- `permission_handler` (already added)

**Native (Kotlin) tasks:**
1. Launch SAF folder picker intent, receive tree URI, persist permission (`takePersistableUriPermission`).
2. Scan chosen folder tree using `DocumentFile` traversal, signature-match on file headers (JPEG `FFD8FF`, PNG `89504E47`, MP4 `66747970`) against any file not indexed in MediaStore.
3. Note in code comments: on API 29+, this does NOT reach raw unallocated space — only surfaces user-accessible-but-unindexed files. Label accordingly in UI, do not oversell.

**Flutter tasks:**
1. "Extended Scan" entry point on Home screen, separate from Tier 1 quick scan, with 1-line explainer text: "Scans a folder you choose for additional recoverable files."
2. Folder picker trigger → native SAF intent.
3. Reuse Phase 1's streaming results UI component (build Phase 1 result screen as reusable widget for this reason).

**UI to build:**
- "Extended Scan" card/button on Home (visually distinct tier, e.g., different badge color from Quick Scan)
- Folder picker confirmation screen
- Reuses Phase 1 results/recovery UI

**Test checkpoint:** Non-rooted device, pick a folder via SAF, place a test file with valid JPEG header but stripped from MediaStore index, run extended scan, confirm it surfaces and recovers correctly.

---

## PHASE 4 — Tier 3: Root Deep Recovery Engine

**Goal:** Root-only advanced carving — real differentiator for rooted users, clearly gated behind root detection from Phase 0.

**Packages/Tools:**
- `libsu` (already added Phase 0) — root shell execution
- NDK / JNI (C) module for signature-carving performance (Kotlin loop too slow on GB-scale partitions per earlier decision)
- Reference algorithm logic: study open-source `PhotoRec` approach (GPL-licensed — **do not copy-paste code**, reimplement logic independently, or dual-license this specific module GPL if reusing structure directly — flag this decision to project lead before implementation)

**Native (Kotlin + C/JNI) tasks:**
1. Root-gated UI entry point calls native method `startDeepScan(partitionPath)`.
2. Kotlin requests root shell via `libsu`, streams raw block data in chunks (avoid full `dd` image dump — stream-read + carve on-the-fly per earlier decision, saves storage space).
3. Pass byte chunks to JNI/C carving function — signature match + basic file-boundary detection (EOF markers per format).
4. Return carved file list with confidence heuristic: "% of expected file size found intact" → feeds Phase 5's confidence score UI.

**Flutter tasks:**
1. Root-only unlock screen: if `checkRootAccess()` (Phase 0) returns false, show "Root Required" explainer screen instead of scan button — include link to Magisk install guide (`https://topjohnwu.github.io/Magisk/install.html`) with clear warning: "This wipes your device and voids warranty — advanced users only." **Never attempt to root the device from within the app** (confirmed earlier — not technically possible without bootloader unlock + data wipe, doing so covertly would be malware behavior).
2. Deep scan progress screen (reuse Phase 1 streaming UI, add confidence % badge per result — ties into Phase 5).

**UI to build:**
- Root-gate explainer screen (non-rooted users see this instead of scan button)
- Deep scan progress (extends Phase 1 UI component with confidence badges)

**Test checkpoint:** On rooted test device, delete a file, wipe it from MediaStore/trash entirely (simulate old deletion), run deep scan, confirm signature-carved recovery works and confidence % roughly matches actual file integrity.

---

## PHASE 5 — Smart Scan UX Layer (Priority Order + Confidence Score + Resume)

**Goal:** Polish scan experience — recent-first priority, confidence scoring, checkpoint/resume (this was the missing piece from original plan).

**Packages:**
- `sqflite` (already added) — checkpoint storage

**Native tasks:**
1. Sort scan results by `dateDeleted` descending before returning to Flutter (recent = higher recovery chance = shown first).
2. During Phase 4 deep scan specifically: write scan checkpoint (last processed block offset) to a local file/DB every N MB processed.
3. On scan resume request: read checkpoint, resume `startDeepScan()` from saved offset instead of block 0.

**Flutter tasks:**
1. Add confidence % badge to every result card (color-coded: green >80%, yellow 40-80%, red <40%).
2. Add pause/resume button to deep scan progress screen — pause writes current state, resume calls native resume method.
3. On app relaunch after crash/kill during scan: detect incomplete checkpoint on start, prompt "Resume previous scan?" dialog.

**UI to build:**
- Confidence badge component (reusable across all result screens)
- Pause/Resume button on scan progress screen
- "Resume previous scan?" dialog on relaunch

**Test checkpoint:** Start deep scan, force-kill app mid-scan, relaunch, confirm resume prompt appears and continues from checkpoint (not from zero) — verify via log timestamps/offsets.

---

## PHASE 6 — Scheduled Auto-Vault Backup + Export + Quick Actions

**Goal:** Automation layer — reduces manual work, matches "prevention-first" positioning.

**Packages:**
- `workmanager` — scheduled background backup task
- `share_plus` — direct export to WhatsApp/Drive/Email
- `android_alarm_manager_plus` OR home screen widget via native `AppWidgetProvider` (for quick-tile/widget action)

**Native tasks:**
1. `AppWidgetProvider` native implementation: home screen widget with single tap → triggers `MethodChannel` call into quick-recovery flow (opens app directly to Phase 1 scan screen).
2. Scheduled task handler (`workmanager` periodic task, e.g. daily/weekly per user setting): re-scan monitored folders (Phase 2 selection), auto-copy any new files matching protection criteria into vault — even if Protection Mode's real-time observer missed something.

**Flutter tasks:**
1. Settings: "Auto-backup frequency" selector (Off / Daily / Weekly).
2. Vault entry screen: add direct share buttons (WhatsApp/Drive/Email icons via `share_plus`) — per earlier decision, skip the "go find it in gallery" step.
3. Widget setup instructions screen (Android widgets can't be auto-placed — show user how to long-press home screen and add it).

**UI to build:**
- Auto-backup frequency setting row
- Share button row on vault/recovery result screens
- Widget add-instructions screen (illustrated steps)

**Test checkpoint:** Set weekly auto-backup, fast-forward system clock (or trigger manually via `workmanager` test API), confirm new matching files land in vault without manual scan. Confirm widget added to home screen launches quick scan directly.

---

## PHASE 7 — Stability, Crash Handling, Resource Guards

**Goal:** Production-grade reliability — this phase touches every screen built so far, not a new feature set.

**Packages:**
- `firebase_crashlytics` (free tier)
- Native: `BatteryManager` API (built-in Android, no extra dep)

**Native tasks:**
1. Wrap all `MethodChannel` calls in try/catch, return structured error codes to Flutter instead of crashing.
2. `Thread.setDefaultUncaughtExceptionHandler` for native-side crash capture → forward to Crashlytics.
3. Before starting Phase 4 deep scan: check `BatteryManager.isCharging()` / battery level / thermal status (`PowerManager.getCurrentThermalStatus()`, API 29+) — if battery <15% and not charging, or thermal status elevated, show warning dialog before allowing scan start.
4. Convert Phase 4 deep scan execution into a **Foreground Service** with persistent notification (not `WorkManager` — per earlier decision, long deep scans need foreground service to survive Doze mode; `WorkManager` stays reserved for lightweight Phase 6 periodic checks only).

**Flutter tasks:**
1. `FlutterError.onError` global handler → forward to Crashlytics.
2. Storage-space pre-check before any file recovery/save action (per earlier decision) — if insufficient space, block action with clear dialog instead of letting it fail mid-copy.
3. Battery/thermal warning dialog UI (triggered by native check above) before deep scan start, with "Proceed Anyway" override option.

**UI to build:**
- Low battery/thermal warning dialog
- Insufficient storage dialog (pre-recovery check)
- Foreground service persistent notification (scan progress shown in notification tray too)

**Test checkpoint:** Force a native exception, confirm it appears in Crashlytics dashboard instead of crashing app. Drain test device battery below 15%, attempt deep scan, confirm warning fires. Fill device storage near-full, attempt recovery, confirm pre-check blocks with clear message.

---

## PHASE 8 — Play Store Compliance & Release Build

**Goal:** Ready for submission — legal/policy layer, no new user-facing features.

**Tasks (no packages, documentation + build config):**
1. Write privacy policy page (host on simple static page — GitHub Pages free) using the broad-but-honest wording from earlier decision:
   > "This app accesses device storage to scan for and recover deleted media files, and optionally monitor selected folders to protect files from accidental deletion (Protection Mode, user-enabled). No data leaves your device."
2. Fill Play Console "Permissions declaration form" for `MANAGE_EXTERNAL_STORAGE` — justify as core file-recovery functionality, link privacy policy.
3. Build config: switch to Android App Bundle (`.aab`) instead of flat APK — enables per-ABI splitting, reduces download size (native/NDK libs from Phase 4 otherwise bloat a universal APK).
4. Prepare rejection-appeal doc in advance (short justification doc: what app does, why permission needed, no server upload) — Google sometimes rejects data-recovery-category apps on first submit, per earlier discussion.
5. Final QA pass: run through every phase's test checkpoint on at least 2 different OEM devices (e.g. Samsung + Xiaomi) — root behavior and storage paths vary by OEM, confirmed risk from earlier discussion.

**Test checkpoint:** `.aab` builds clean, installs via internal testing track, privacy policy live and linked correctly in Play Console, permissions form submitted.

---

## Build Order Summary

```
Phase 0 → Foundation (permissions, root detect, shell)
Phase 1 → Non-root core recovery (MediaStore trash + WhatsApp media)      ← MVP milestone
Phase 2 → Protection Mode + encrypted vault + password
Phase 3 → SAF Extended Scan (non-root tier 2)
Phase 4 → Root deep carving engine (JNI/C)
Phase 5 → Confidence score + resume/checkpoint UX
Phase 6 → Scheduled auto-backup + widget + export
Phase 7 → Stability, crash handling, resource guards
Phase 8 → Play Store compliance + release build
```

Each phase ships with its own working UI — testable in isolation before moving forward. Phase 1 alone = shippable MVP if timeline pressure hits.

# RAW SUBAGENT REPORT: TOTALS-CRITIC 5-ECHELON ADVERSARIAL AUDIT
# TARGET: /Users/manar/AIII/projects/keytamer
# DATE: 2026-10-25
# CALLER: 25e8cde6-7b1c-4077-a899-16408d98c930
# INVARIANTS: Subagent-Only Invariant, No-Question Invariant, Zero-Emoji Invariant, Russian Language

================================================================================
1. EXECUTION TRACES & ENTRYPOINT VALIDATION
================================================================================

1.1. Build App Execution:
Command: KEYTAMER_SIGN_ID="-" bash /Users/manar/AIII/projects/keytamer/build-app.sh
Exit Code: 0
Build Log Highlights:
- Swift compiler invoked: swiftc -O Sources/Keytamer/*.swift
- Target architecture: arm64-apple-macos14.0
- SDK: MacOSX15.5.sdk
- Linked frameworks: AppKit, Carbon, ServiceManagement, ApplicationServices, IOKit, AVFoundation, CoreAudio, AudioToolbox, Metal, MetalKit, Accelerate, CoreML, SwiftUI, Sparkle, FluidAudio, whisper, ggml
- Codesign verification: codesign --deep --strict OK
- Generated App Bundle: /Users/manar/AIII/projects/keytamer/Keytamer.app

Compiler Warnings Captured:
- Sources/Keytamer/VoiceHistory.swift:311:9: warning: 'SecKeychainGetUserInteractionAllowed' was deprecated in macOS 10.10: SecKeychain is deprecated
- Sources/Keytamer/VoiceController.swift:263:56: warning: capture of 'self' with non-sendable type 'VoiceController?' in a '@Sendable' closure
- Sources/Keytamer/VoiceController.swift:429:34: warning: reference to captured var 'text' in concurrently-executing code; this is an error in the Swift 6 language mode
- Sources/Keytamer/TextReplacer.swift:422:17: warning: variable 'u' was never mutated; consider changing to 'let' constant
- Sources/Keytamer/NotchIsland.swift:458:31: warning: immutable value 'nH' was never used; consider replacing with '_' or removing it
- Sources/Keytamer/AppBanner.swift:190:13: warning: variable 'w' was never mutated; consider changing to 'let' constant
- Sources/Keytamer/Engine.swift:1828:53: warning: expression shuffles the elements of this tuple; this behavior is deprecated
- Sources/Keytamer/AudioDevices.swift:37:77: warning: forming 'UnsafeMutableRawPointer' to a variable of type 'Optional<CFString>'

1.2. Automated Runner Execution:
Command: bash /Users/manar/AIII/SKILLs/totals-critic/totals-critic.sh --target /Users/manar/AIII/projects/keytamer --full-cascade
Exit Code: 1
Static Checker Output:
- Echelon 1: FAIL (install-local.sh line 20 flagged for "rm -rf /")
- Echelon 2: PASS (all tools found in PATH)
- Echelon 3: WARNING (build-app.sh missing trap handler)
- Echelon 4: WARNING (vendor/FluidAudio/Scripts/run_benchmarks.py subprocess without timeout)
- Echelon 5: FAIL (3 defects found by heuristic regex)

================================================================================
2. ECHELON-BY-ECHELON ADVERSARIAL AUDIT
================================================================================

--------------------------------------------------------------------------------
ECHELON 1: PRIMARY CRITIC (Line-by-Line Code Review & Contract Verification)
--------------------------------------------------------------------------------
Focus Areas:
- TextReplacer.pasteViaClipboard
- VoiceIndicator.swift
- MenuBarController.swift
- AppSettings.swift
- EventTap.swift
- VoiceController.swift
- LayoutManager.swift

Key Findings:
1. TextReplacer.pasteViaClipboard (lines 241-298):
   - Method executes on DispatchQueue.main.
   - Saves pasteboard snapshot: `let snapshot: [[(type: NSPasteboard.PasteboardType, data: Data)]] = (pb.pasteboardItems ?? []).map ...`
   - Injects `org.nspasteboard.TransientType` when writing dictation text.
   - Posts `sendCmdV` via `CGEventSource(stateID: .privateState)`.
   - On line 291: In the restoration block, it maps snapshot items back into `NSPasteboardItem` and injects `org.nspasteboard.TransientType` into USER'S ORIGINAL ITEMS. This marks the user's previously copied data as transient, causing clipboard managers (Maccy, Raycast, Alfred, Paste) to discard them or fail to record them.
   - On line 282: If `pb.changeCount != ours`, restoration is skipped. The user's original data is dropped forever because `pb.clearContents()` already wiped the pasteboard.
   - `sendCmdV`: `vKey = 9`. Keycode 9 is ANSI V. On Dvorak, key 9 is '.' (period), resulting in `⌘.` (Command-Period, Cancel) instead of Paste.

2. MenuBarController.swift:
   - `badgeWithPlate` (lines 150-184):
     `private static var plateCache: [String: NSImage] = [:]`
     Mutable dictionary accessed without NSLock or isolation.
   - Submenu hardcoded strings: "Русский (RU)" and "English (EN)" are hardcoded rather than utilizing `L10n.t`.

3. Documentation vs Reality:
   - README.md & CHANGELOG.md claim full rebranding to `com.keytamer.tamer` and Keytamer.
   - Reality: 365+ occurrences of `Keyboop` and `ru.keyboop.app` remain across `Sources/`.
   - Divergent paths:
     * AppDelegate singleInstance lock: `~/Library/Application Support/Keytamer/singleton.lock`
     * VoiceHistory storage: `~/Library/Application Support/Keyboop/history.enc`
     * VoiceController busyMarker: `~/Library/Application Support/Keyboop/voice-busy`
     * VoiceClips storage: `~/Library/Application Support/Keytamer/voice/`
   - Consequence: Keyboop and Keytamer can run simultaneously because they lock different files. Two active CGEventTaps cause double typing and catastrophic input corruption.

--------------------------------------------------------------------------------
ECHELON 2: PROTOCOLS SCOUT (Low-Level macOS System Calls & Concurrency)
--------------------------------------------------------------------------------
Focus Areas:
- CGEventTap (session, headInsert, defaultTap)
- NSPasteboard ownership and changeCount
- CoreAudio & AVCaptureSession
- IOHID (CapsLED, SPU)
- GCD Deadlocks & Thread Safety
- TCC & Dev Bundle Isolation

Key Findings:
1. Concurrency Gap in TextReplacer:
   - `TextReplacer.insert` and `TextReplacer.replace` run on serial queue `com.keytamer.synth` (qos: .userInteractive).
   - `TextReplacer.pasteViaClipboard` runs on `DispatchQueue.main`.
   - There is NO synchronization or mutual exclusion between `synthQueue` and `pasteViaClipboard`. If a boundary replacement or typo fix is in flight on `synthQueue`, and dictation pastes via clipboard, synthetic backspaces and `⌘V` can interleave.
2. NSPasteboard Ownership Window:
   - `PasteboardOwnership.beginOwnedWindow()` suppresses `ClipboardWatcher` for 250ms. Any clipboard write during this window is ignored.
3. Audio Subsystem:
   - AVCaptureSession properly configured for 16 kHz Float32 mono.
   - Dual watchdog (2.0s buffer timeout, 3.0s dead signal silence detection).
   - No mach port leaks in IOHIDEventSystemClient.

--------------------------------------------------------------------------------
ECHELON 3: META-CRITIC (Blindspot Detection & False Positive Pruning)
--------------------------------------------------------------------------------
Focus Areas:
- Modifier language override fast repetition and state machine
- Secure Input policy
- Web/Electron vs Native AppKit focus loss
- Pruning oversensitive regex findings

Key Findings:
1. CRITICAL Blindspot in Modifier Override:
   - File: `Sources/Keytamer/EventTap.swift`, lines 977-980:
     ```swift
     if voiceModArmed {
         let vm = relevantMods(CGEventFlags(rawValue: s.voiceHotkeyModifiers))
         if !relevantMods(flags).subtracting(vm).isEmpty { voiceModArmed = false }
     }
     ```
   - When holding Command (the override modifier) and tapping the voice modkey (e.g. Right Option):
     * `flagsChanged` fires for Right Option down -> `voiceModArmed = true`, `voiceModArmedOverride = true`.
     * User releases Right Option -> `flagsChanged` fires for Right Option up.
     * Line 978: `vm` is Option.
     * Line 979: `relevantMods(flags)` still contains Command (held by user).
     * `subtracting(vm)` leaves Command in `extra`.
     * `!extra.isEmpty` evaluates to TRUE!
     * `voiceModArmed` is set to FALSE!
     * At line 1009: `else if voiceModArmed` evaluates to FALSE!
     * `toggleVoice(override: voiceModArmedOverride)` is NEVER CALLED!
   - Result: In toggle mode, holding Command and tapping the modifier NEVER starts dictation with override. The override feature is completely broken for modifier toggle mode.

2. False Positive Pruning:
   - The static analyzer flagged `install-local.sh:20` for `rm -rf /`.
   - Inspection proves this is `rm -rf /Applications/Keytamer.app`. The regex `if "rm -rf /" in line` is overly broad. It is a false positive for catastrophic system deletion, though best practice warrants `rm -rf "${APP_PATH:?}"`.

--------------------------------------------------------------------------------
ECHELON 4: RECURSIVE INQUISITOR (Stress Testing & Failure Modes)
--------------------------------------------------------------------------------
Focus Areas:
- Whisper / Parakeet crashes
- Clipboard changeCount race conditions
- External microphone sudden disconnection
- Display reconfiguration & Dynamic Island

Key Findings:
1. Whisper / Parakeet Failure:
   - If `whisper_full` returns non-zero, `WhisperBridge.transcribe` returns `""`.
   - `VoiceController.deliver` handles `clean.isEmpty` by playing `failSound`, deleting orphan audio clip, and returning cleanly without crash. Handled safely.
2. Clipboard changeCount Race:
   - If `pb.changeCount != ours` at 250ms, the previous user snapshot is dropped without restoration. This leads to user data loss if any background app updates pasteboard during dictation paste.
3. Microphone Disconnection:
   - AVCaptureDevice.wasDisconnectedNotification triggers `handleDeviceChange(reason: "устройство отключено")`.
   - Existing samples are preserved. Session switches to default system input or built-in mic. Handled safely.
4. Screen Resolution / External Monitor Changes:
   - No observer for `NSApplication.didChangeScreenParametersNotification`.
   - If displays change during active indicator display, `NotchIsland` frame remains anchored to old coordinates.

--------------------------------------------------------------------------------
ECHELON 5: TOTALS ARBITER & SYNTHESIS (Final Canonical Registry & Action Plan)
--------------------------------------------------------------------------------

CANONICAL DEFECT REGISTRY:

1. [CRITICAL] Sources/Keytamer/EventTap.swift:977-980
   Premature clearing of `voiceModArmed` on release when override modifier is held.
   Fix: `if !relevantMods(flags).subtracting(vm).subtracting(overMod).isEmpty { voiceModArmed = false }`.

2. [CRITICAL] Sources/Keytamer/AppDelegate.swift:1152 & VoiceHistory.swift:21, 295
   Storage path fragmentation: `Keytamer/singleton.lock` vs `Keyboop/history.enc` and `Keyboop/voice-busy`.
   Allows concurrent execution of Keyboop and Keytamer, causing double event taps and input mangling.

3. [HIGH] Sources/Keytamer/TextReplacer.swift:241, 253
   Thread synchronization hazard: `pasteViaClipboard` runs on `DispatchQueue.main` while `insert`/`replace` run on `synthQueue`. Lack of mutual exclusion causes interleaved synthetic key events.

4. [HIGH] Sources/Keytamer/TextReplacer.swift:291
   Restoring user's pasteboard items marks them with `org.nspasteboard.TransientType`, corrupting clipboard history tools.

5. [HIGH] Sources/Keytamer/TextReplacer.swift:222-234
   Hardcoded `vKey = 9` in `sendCmdV`. Fails on Dvorak/Colemak layouts by sending `⌘.` instead of `⌘V`.

6. [MEDIUM] Sources/Keytamer/TextReplacer.swift:277-285
   Fixed 250ms delay for clipboard restore. Slow Electron apps paste restored clipboard instead of speech text.

7. [MEDIUM] Sources/Keytamer/VoiceIndicator.swift:416-421 & NotchIsland.swift:243
   Lack of `NSApplication.didChangeScreenParametersNotification` observation causes visual drift on display reconfiguration.

8. [MEDIUM] Sources/Keytamer/MenuBarController.swift:151
   Static `plateCache` dictionary accessed without thread synchronization lock.

9. [MEDIUM] build-app.sh:1 & install-local.sh:1
   Missing `trap` handlers for process interruption (SIGINT, SIGTERM, EXIT).

10. [LOW] install-local.sh:20
    Raw `rm -rf /Applications/Keytamer.app` without guarded variable expansion.

11. [LOW] Sources/Keytamer/MenuBarController.swift:980-986
    Mixed localization keys and hardcoded language names in voiceLanguageSubmenu.

12. [LOW] Sources/Keytamer/TextReplacer.swift:422 & NotchIsland.swift:458
    Swift compiler warnings for unused mutable/immutable bindings.

ACTION PLAN:
P0:
- Fix line 979 in `EventTap.swift` to exclude `overMod`.
- Unify Application Support paths to `Keytamer` and add cross-checking for `Keyboop/singleton.lock` in `AppDelegate.swift`.
P1:
- Remove `TransientType` on pasteboard restore in `TextReplacer.swift:291`.
- Synchronize `pasteViaClipboard` with `synthQueue`.
- Resolve dynamic keyCode for 'V' based on active input source.
P2:
- Subscribe to screen parameter changes in `VoiceIndicator.swift`.
- Protect `plateCache` with `NSLock`.
- Add shell traps to build scripts.

FINAL VERDICT: CONDITIONAL_FAIL.
Production release blocked until P0 and P1 items are resolved.
================================================================================

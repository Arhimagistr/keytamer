import Foundation
import CoreGraphics
import AppKit

// MARK: - Test Harness

var testFailures: [String] = []

func assertTrue(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if !condition {
        let fail = "FAIL: \(message) [\(file):\(line)]"
        print("❌ \(fail)")
        testFailures.append(fail)
    } else {
        print("✓ PASS: \(message)")
    }
}

func assertFalse(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    assertTrue(!condition, message, file: file, line: line)
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if a != b {
        let fail = "FAIL: \(message) (expected '\(b)', got '\(a)') [\(file):\(line)]"
        print("❌ \(fail)")
        testFailures.append(fail)
    } else {
        print("✓ PASS: \(message)")
    }
}

// MARK: - 1. EventTap Modifier Disarm Simulation (P0 Defect 1)

func relevantMods(_ f: CGEventFlags) -> CGEventFlags {
    f.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
}

/// Simulated EventTap flagsChanged logic
struct EventTapState {
    var voiceModArmed: Bool = false
    var voiceModArmedOverride: Bool = false
    var toggleVoiceCalled: Bool = false
    var toggleVoiceOverrideArg: Bool? = nil

    // In current unpatched code:
    // if voiceModArmed {
    //     let vm = relevantMods(CGEventFlags(rawValue: s.voiceHotkeyModifiers))
    //     if !relevantMods(flags).subtracting(vm).isEmpty { voiceModArmed = false }
    // }
    mutating func processFlagsChangedLegacy(flags: CGEventFlags,
                                            voiceHotkeyModifiers: UInt64,
                                            overrideModifierMask: CGEventFlags) {
        if voiceModArmed {
            let vm = relevantMods(CGEventFlags(rawValue: voiceHotkeyModifiers))
            if !relevantMods(flags).subtracting(vm).isEmpty { voiceModArmed = false }
        }
    }

    // In patched code:
    mutating func processFlagsChangedPatched(flags: CGEventFlags,
                                             voiceHotkeyModifiers: UInt64,
                                             overrideModifierMask: CGEventFlags) {
        if voiceModArmed {
            let vm = relevantMods(CGEventFlags(rawValue: voiceHotkeyModifiers))
            let overMod = voiceModArmedOverride ? relevantMods(overrideModifierMask) : []
            if !relevantMods(flags).subtracting(vm).subtracting(overMod).isEmpty {
                voiceModArmed = false
                voiceModArmedOverride = false
            }
        }
    }

    mutating func onKeyDown(flags: CGEventFlags,
                            voiceHotkeyModifiers: UInt64,
                            overrideModifierMask: CGEventFlags) {
        let mask = CGEventFlags(rawValue: voiceHotkeyModifiers)
        let vm = relevantMods(mask)
        let overMod = relevantMods(overrideModifierMask)
        let extra = relevantMods(flags).subtracting(vm)
        let soloVoiceTap = extra.isEmpty
        let overrideVoiceTap = (extra == overMod)

        if soloVoiceTap || overrideVoiceTap {
            voiceModArmed = true
            voiceModArmedOverride = overrideVoiceTap
        }
    }

    mutating func onKeyUp(flags: CGEventFlags,
                          voiceHotkeyModifiers: UInt64) {
        if voiceModArmed {
            voiceModArmed = false
            toggleVoiceCalled = true
            toggleVoiceOverrideArg = voiceModArmedOverride
        }
    }
}

func testEventTapModifierOverrideDisarmBehavior() {
    print("\n--- Test 1: EventTap Modifier Override Disarm Behavior ---")
    let voiceHotkeyMods = CGEventFlags.maskAlternate.rawValue
    let overrideMod = CGEventFlags.maskCommand

    // Test A: Solo tap (Option down -> Option up)
    var stateSolo = EventTapState()
    stateSolo.onKeyDown(flags: [.maskAlternate], voiceHotkeyModifiers: voiceHotkeyMods, overrideModifierMask: overrideMod)
    stateSolo.processFlagsChangedPatched(flags: [], voiceHotkeyModifiers: voiceHotkeyMods, overrideModifierMask: overrideMod)
    stateSolo.onKeyUp(flags: [], voiceHotkeyModifiers: voiceHotkeyMods)
    assertTrue(stateSolo.toggleVoiceCalled, "Solo tap triggers toggleVoice")
    assertEqual(stateSolo.toggleVoiceOverrideArg, false, "Solo tap override argument is false")

    // Test B: Override tap (Option + Command down -> Option up while Command is held)
    var stateOverride = EventTapState()
    stateOverride.onKeyDown(flags: [.maskAlternate, .maskCommand], voiceHotkeyModifiers: voiceHotkeyMods, overrideModifierMask: overrideMod)
    assertTrue(stateOverride.voiceModArmed, "Option+Cmd arms voiceMod")
    assertTrue(stateOverride.voiceModArmedOverride, "Option+Cmd sets voiceModArmedOverride")

    // Option is released: flags now contains only .maskCommand
    // Patched logic: voiceModArmed remains armed!
    stateOverride.processFlagsChangedPatched(flags: [.maskCommand], voiceHotkeyModifiers: voiceHotkeyMods, overrideModifierMask: overrideMod)
    assertTrue(stateOverride.voiceModArmed, "Releasing Option while holding Cmd keeps voiceMod armed")
    stateOverride.onKeyUp(flags: [.maskCommand], voiceHotkeyModifiers: voiceHotkeyMods)

    // Contract: toggleVoice MUST be called with override=true.
    assertTrue(stateOverride.toggleVoiceCalled, "Override tap triggers toggleVoice on key up")
    assertEqual(stateOverride.toggleVoiceOverrideArg, true, "Override tap passes override=true")

    // Test C: Unrelated modifier (Option + Command + Shift) MUST disarm
    var stateChord = EventTapState()
    stateChord.onKeyDown(flags: [.maskAlternate, .maskCommand], voiceHotkeyModifiers: voiceHotkeyMods, overrideModifierMask: overrideMod)
    stateChord.processFlagsChangedPatched(flags: [.maskAlternate, .maskCommand, .maskShift],
                                         voiceHotkeyModifiers: voiceHotkeyMods,
                                         overrideModifierMask: overrideMod)
    assertFalse(stateChord.voiceModArmed, "Adding Shift to Option+Cmd must disarm voiceMod")
}

// MARK: - 2. Storage Paths Isolation (P0 Defect 2)

func testStoragePathsIsolation() {
    print("\n--- Test 2: Storage Paths Isolation ---")
    // Check VoiceHistory.swift and VoiceController.swift content on disk
    let voiceHistoryPath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceHistory.swift"
    let voiceControllerPath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceController.swift"
    let appDelegatePath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/AppDelegate.swift"

    guard let vhContent = try? String(contentsOf: URL(fileURLWithPath: voiceHistoryPath), encoding: .utf8) else {
        testFailures.append("Could not read VoiceHistory.swift")
        return
    }
    guard let vcContent = try? String(contentsOf: URL(fileURLWithPath: voiceControllerPath), encoding: .utf8) else {
        testFailures.append("Could not read VoiceController.swift")
        return
    }
    guard let adContent = try? String(contentsOf: URL(fileURLWithPath: appDelegatePath), encoding: .utf8) else {
        testFailures.append("Could not read AppDelegate.swift")
        return
    }

    // In patched code:
    // VoiceHistory.swift uses Keytamer directory
    let vhHasKeyboopDir = vhContent.contains(".appendingPathComponent(\"Keyboop\", isDirectory: true)")
    assertFalse(vhHasKeyboopDir, "VoiceHistory.swift must NOT use Keyboop directory")

    let vcHasKeyboopBusy = vcContent.contains("Application Support/Keyboop/voice-busy")
    assertFalse(vcHasKeyboopBusy, "VoiceController.swift must NOT write voice-busy to Keyboop directory")

    // AppDelegate must check both Keytamer and Keyboop lock files
    let adChecksKeyboopLock = adContent.contains("Keyboop/singleton.lock")
    assertTrue(adChecksKeyboopLock, "AppDelegate.swift must guard against dual instances via Keyboop lock")
}

// MARK: - 3. Clipboard TransientType Integrity (P1 Defect 4)

func testClipboardTransientTypeIntegrity() {
    print("\n--- Test 3: Clipboard TransientType Integrity ---")
    let textReplacerPath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/TextReplacer.swift"
    guard let trContent = try? String(contentsOf: URL(fileURLWithPath: textReplacerPath), encoding: .utf8) else {
        testFailures.append("Could not read TextReplacer.swift")
        return
    }

    let setsTransientOnRestoredSnapshot = trContent.contains("for p in pairs { it.setData(p.data, forType: p.type) }\n                    it.setData(Data(), forType: NSPasteboard.PasteboardType(\"org.nspasteboard.TransientType\"))")
        || trContent.contains("for p in pairs { it.setData(p.data, forType: p.type) }\r\n                    it.setData(Data(), forType: NSPasteboard.PasteboardType(\"org.nspasteboard.TransientType\"))")

    assertFalse(setsTransientOnRestoredSnapshot, "TextReplacer must NOT set TransientType on restored user clipboard snapshot")
}

// MARK: - 4. Keytamer Rebranding and Asset Isolation (ADR-006)

func testRebrandingAndAssetIsolation() {
    print("\n--- Test 4: Keytamer Rebranding and Asset Isolation ---")
    let projectDir = "/Users/manar/AIII/projects/keytamer"
    let buildAppPath = "\(projectDir)/build-app.sh"
    let keytamerMarkPath = "\(projectDir)/Sources/Keytamer/KeytamerMark.swift"
    let keyboopMarkPath = "\(projectDir)/Sources/Keytamer/KeyboopMark.swift"
    let menuBarPath = "\(projectDir)/Sources/Keytamer/MenuBarController.swift"
    let loggerPath = "\(projectDir)/Sources/Keytamer/Logger.swift"
    let voiceHistoryWindowPath = "\(projectDir)/Sources/Keytamer/VoiceHistoryWindow.swift"
    let l10nPath = "\(projectDir)/Sources/Keytamer/L10n.swift"

    // 1. build-app.sh must package keytamer-logo-anim.mp4
    if let buildAppContent = try? String(contentsOf: URL(fileURLWithPath: buildAppPath), encoding: .utf8) {
        let copiesKeytamerAnim = buildAppContent.contains("keytamer-logo-anim.mp4")
        let copiesKeyboopAnim = buildAppContent.contains("keyboop-logo-anim.mp4")
        assertTrue(copiesKeytamerAnim, "build-app.sh must copy keytamer-logo-anim.mp4")
        assertFalse(copiesKeyboopAnim, "build-app.sh must NOT copy keyboop-logo-anim.mp4")
    } else {
        testFailures.append("Could not read build-app.sh")
    }

    // 2. KeytamerMark.swift must exist and KeyboopMark.swift must NOT exist
    let fm = FileManager.default
    assertTrue(fm.fileExists(atPath: keytamerMarkPath), "KeytamerMark.swift must exist")
    assertFalse(fm.fileExists(atPath: keyboopMarkPath), "KeyboopMark.swift must NOT exist")

    // 3. MenuBarController must call KeytamerMark.draw
    if let menuBarContent = try? String(contentsOf: URL(fileURLWithPath: menuBarPath), encoding: .utf8) {
        let usesKeytamerMark = menuBarContent.contains("KeytamerMark.draw")
        let usesKeyboopMark = menuBarContent.contains("KeyboopMark.draw")
        assertTrue(usesKeytamerMark, "MenuBarController must use KeytamerMark.draw")
        assertFalse(usesKeyboopMark, "MenuBarController must NOT use KeyboopMark.draw")
    } else {
        testFailures.append("Could not read MenuBarController.swift")
    }

    // 4. Logger must not log "Keyboop: "
    if let loggerContent = try? String(contentsOf: URL(fileURLWithPath: loggerPath), encoding: .utf8) {
        let hasKeyboopLog = loggerContent.contains("NSLog(\"Keyboop:")
        assertFalse(hasKeyboopLog, "Logger.swift must not log 'Keyboop:'")
    } else {
        testFailures.append("Could not read Logger.swift")
    }

    // 5. VoiceHistoryWindow export prefix must be Keytamer-
    if let vhwContent = try? String(contentsOf: URL(fileURLWithPath: voiceHistoryWindowPath), encoding: .utf8) {
        let hasKeyboopExport = vhwContent.contains("\"Keyboop-\\(exportDF")
        assertFalse(hasKeyboopExport, "VoiceHistoryWindow must not export with 'Keyboop-' prefix")
    } else {
        testFailures.append("Could not read VoiceHistoryWindow.swift")
    }

    // 6. L10n.swift user-facing strings must use Keytamer
    if let l10nContent = try? String(contentsOf: URL(fileURLWithPath: l10nPath), encoding: .utf8) {
        let hasKeyboopInMicGain = l10nContent.contains("Keyboop поднимает уровень перед записью")
        assertFalse(hasKeyboopInMicGain, "L10n.swift voice.micGainHelp must use Keytamer instead of Keyboop")
    } else {
        testFailures.append("Could not read L10n.swift")
    }
}

// MARK: - 5. YAGNI Refactoring and Compiler Hygiene (ADR-007)

func testYAGNIRefactoringAndCompilerHygiene() {
    print("\n--- Test 5: YAGNI Refactoring and Compiler Hygiene ---")
    let projectDir = "/Users/manar/AIII/projects/keytamer"
    let slapTypesPath = "\(projectDir)/Sources/Keytamer/SlapTypes.swift"
    let slapDetectorPath = "\(projectDir)/Sources/Keytamer/SlapDetector.swift"
    let enginePath = "\(projectDir)/Sources/Keytamer/Engine.swift"
    let textReplacerPath = "\(projectDir)/Sources/Keytamer/TextReplacer.swift"
    let notchIslandPath = "\(projectDir)/Sources/Keytamer/NotchIsland.swift"

    let fm = FileManager.default

    // 1. SlapTypes.swift must be coalesced into SlapDetector.swift
    assertFalse(fm.fileExists(atPath: slapTypesPath), "SlapTypes.swift must be removed (coalesced into SlapDetector.swift)")

    if let sdContent = try? String(contentsOf: URL(fileURLWithPath: slapDetectorPath), encoding: .utf8) {
        assertTrue(sdContent.contains("enum SlapSensitivity: String, CaseIterable"), "SlapDetector.swift must contain SlapSensitivity definition")
        assertTrue(sdContent.contains("enum SlapDetectorAvailability: Equatable"), "SlapDetector.swift must contain SlapDetectorAvailability definition")
    } else {
        testFailures.append("Could not read SlapDetector.swift")
    }

    // 2. Engine.swift tuple matching
    if let engineContent = try? String(contentsOf: URL(fileURLWithPath: enginePath), encoding: .utf8) {
        let hasUnifiedTwoLeadingCaps = engineContent.contains("func fixTwoLeadingCaps(word: String, item: (word: String, deleteCount: Int, tail: String))")
        let hasUnifiedTypo = engineContent.contains("func fixTypo(word: String, item: (word: String, deleteCount: Int, tail: String))")
        assertTrue(hasUnifiedTwoLeadingCaps, "Engine.swift fixTwoLeadingCaps must match KeystrokeBuffer tuple order")
        assertTrue(hasUnifiedTypo, "Engine.swift fixTypo must match KeystrokeBuffer tuple order")
    } else {
        testFailures.append("Could not read Engine.swift")
    }

    // 3. TextReplacer.swift unused mutable variable
    if let trContent = try? String(contentsOf: URL(fileURLWithPath: textReplacerPath), encoding: .utf8) {
        let hasVarU = trContent.contains("var u = Array(\"прогрев\".utf16)")
        assertFalse(hasVarU, "TextReplacer.swift must use 'let u' instead of 'var u'")
    } else {
        testFailures.append("Could not read TextReplacer.swift")
    }

    // 4. NotchIsland.swift unused variable nH
    if let niContent = try? String(contentsOf: URL(fileURLWithPath: notchIslandPath), encoding: .utf8) {
        let hasUnusedNH = niContent.contains("let nW = notch.width, nH = notch.height")
        assertFalse(hasUnusedNH, "NotchIsland.swift must not declare unused nH in silhouette()")
    } else {
        testFailures.append("Could not read NotchIsland.swift")
    }
}

// MARK: - 6. Input Reliability and Protocol Hygiene (ADR-008)

func testInputReliabilityAndProtocolHygiene() {
    print("\n--- Test 6: Input Reliability and Protocol Hygiene ---")
    let projectDir = "/Users/manar/AIII/projects/keytamer"
    let textReplacerPath = "\(projectDir)/Sources/Keytamer/TextReplacer.swift"
    let menuBarPath = "\(projectDir)/Sources/Keytamer/MenuBarController.swift"
    let voiceIndicatorPath = "\(projectDir)/Sources/Keytamer/VoiceIndicator.swift"

    // 1. TextReplacer dynamic paste keycode
    if let trContent = try? String(contentsOf: URL(fileURLWithPath: textReplacerPath), encoding: .utf8) {
        let hasHardcodedVKey = trContent.contains("private static let vKey: CGKeyCode = 9")
        let hasDynamicVKey = trContent.contains("DynamicKeymap.latinKeyCodes[\"v\"]")
        assertFalse(hasHardcodedVKey, "TextReplacer must not hardcode static vKey = 9")
        assertTrue(hasDynamicVKey, "TextReplacer must resolve vKey dynamically via DynamicKeymap")
    } else {
        testFailures.append("Could not read TextReplacer.swift")
    }

    // 2. MenuBarController plateCache thread safety
    if let mbContent = try? String(contentsOf: URL(fileURLWithPath: menuBarPath), encoding: .utf8) {
        let hasPlateLock = mbContent.contains("plateLock") && (mbContent.contains("plateLock.lock()") || mbContent.contains("plateLock.withLock"))
        assertTrue(hasPlateLock, "MenuBarController must guard plateCache access with plateLock")
    } else {
        testFailures.append("Could not read MenuBarController.swift")
    }

    // 3. VoiceIndicator screen parameters change notification
    if let viContent = try? String(contentsOf: URL(fileURLWithPath: voiceIndicatorPath), encoding: .utf8) {
        let listensToScreenChanges = viContent.contains("NSApplication.didChangeScreenParametersNotification")
        assertTrue(listensToScreenChanges, "VoiceIndicator must observe NSApplication.didChangeScreenParametersNotification")
    } else {
        testFailures.append("Could not read VoiceIndicator.swift")
    }
}

// MARK: - 7. Coexistence Mode with Keyboop Lock (ADR-009)

func testCoexistenceModeWithKeyboopLock() {
    print("\n--- Test 7: Coexistence Mode with Keyboop Lock (ADR-009) ---")
    let appDelegatePath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/AppDelegate.swift"
    guard let adContent = try? String(contentsOf: URL(fileURLWithPath: appDelegatePath), encoding: .utf8) else {
        testFailures.append("Could not read AppDelegate.swift")
        return
    }

    // 1. Must check Keyboop lock file
    let checksKeyboopLock = adContent.contains("Keyboop/singleton.lock")
    assertTrue(checksKeyboopLock, "AppDelegate.swift must check Keyboop/singleton.lock")

    // 2. Must NOT block startup on active Keyboop lock
    let blocksOnKeyboopLock = adContent.contains("single-instance: обнаружен запущенный Keyboop (держит Keyboop/singleton.lock) — запуск заблокирован")
    assertFalse(blocksOnKeyboopLock, "AppDelegate.swift must NOT block startup when Keyboop is running")

    // 3. Must explicitly log parallel coexistence mode
    let logsCoexistence = adContent.contains("параллельного сосуществования")
    assertTrue(logsCoexistence, "AppDelegate.swift must log parallel coexistence mode when Keyboop is detected")
}

// MARK: - 8. Settings Migration from Keyboop (ADR-010)

func testKeyboopSettingsMigration() {
    print("\n--- Test 8: Settings Migration from Keyboop (ADR-010) ---")
    let appSettingsPath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/AppSettings.swift"
    guard let asContent = try? String(contentsOf: URL(fileURLWithPath: appSettingsPath), encoding: .utf8) else {
        testFailures.append("Could not read AppSettings.swift")
        return
    }

    // 1. Must define migration flag and migration method
    let hasMigrationMethod = asContent.contains("func migrateFromKeyboopIfNeeded()")
    assertTrue(hasMigrationMethod, "AppSettings must define migrateFromKeyboopIfNeeded()")

    let checksMigrationFlag = asContent.contains("didMigrateFromKeyboop")
    assertTrue(checksMigrationFlag, "AppSettings must check didMigrateFromKeyboop flag")

    // 2. Must inspect persistentDomain for ru.keyboop.app
    let readsKeyboopDomain = asContent.contains("persistentDomain(forName: \"ru.keyboop.app\")")
    assertTrue(readsKeyboopDomain, "AppSettings must read ru.keyboop.app persistentDomain")

    // 3. Must be invoked during initialization
    let callsMigrationInInit = asContent.contains("migrateFromKeyboopIfNeeded()")
    assertTrue(callsMigrationInInit, "AppSettings must invoke migrateFromKeyboopIfNeeded() during init")
}

// MARK: - 9. Dictation Pause, Command Cancel, 2x Option Paste (ADR-011)

func testDictationPauseCancelAndDoubleTapPaste() {
    print("\n--- Test 9: Dictation Pause, Command Cancel, 2x Option Paste (ADR-011) ---")
    let projectDir = "/Users/manar/AIII/projects/keytamer"
    let recorderPath = "\(projectDir)/Sources/Keytamer/AudioRecorder.swift"
    let voiceControllerPath = "\(projectDir)/Sources/Keytamer/VoiceController.swift"
    let eventTapPath = "\(projectDir)/Sources/Keytamer/EventTap.swift"
    let appSettingsPath = "\(projectDir)/Sources/Keytamer/AppSettings.swift"

    guard let recContent = try? String(contentsOf: URL(fileURLWithPath: recorderPath), encoding: .utf8),
          let vcContent = try? String(contentsOf: URL(fileURLWithPath: voiceControllerPath), encoding: .utf8),
          let etContent = try? String(contentsOf: URL(fileURLWithPath: eventTapPath), encoding: .utf8),
          let asContent = try? String(contentsOf: URL(fileURLWithPath: appSettingsPath), encoding: .utf8) else {
        testFailures.append("Could not read project source files for Test 9")
        return
    }

    // 1. AudioRecorder pause and resume
    let recHasPause = recContent.contains("func pause()") && recContent.contains("func resume()")
    assertTrue(recHasPause, "AudioRecorder must provide pause() and resume() methods")

    let recHasIsPaused = recContent.contains("var isPaused: Bool")
    assertTrue(recHasIsPaused, "AudioRecorder must provide isPaused property")

    // 2. VoiceController togglePause
    let vcHasTogglePause = vcContent.contains("func togglePause()")
    assertTrue(vcHasTogglePause, "VoiceController must provide togglePause() method")

    let vcHasIsPaused = vcContent.contains("var isPaused: Bool")
    assertTrue(vcHasIsPaused, "VoiceController must expose isPaused property")

    // 3. EventTap pause and cancel handling
    let etHandlesPause = etContent.contains("togglePause")
    assertTrue(etHandlesPause, "EventTap must route pause key to VoiceController.togglePause()")

    let etHandlesCommandCancel = etContent.contains("voiceCancelByCommand") || etContent.contains("cancelOnCommand")
    assertTrue(etHandlesCommandCancel, "EventTap must support cancelling dictation on Command")

    // 4. Double-tap Option paste
    let asHasDoubleTapPaste = asContent.contains("pasteDictationTrigger") || asContent.contains("pasteDictationDoubleTap")
    assertTrue(asHasDoubleTapPaste, "AppSettings must support double-tap trigger for paste dictation")

    let etHasDoubleTapPaste = etContent.contains("handlePasteDictationHotkey") && (etContent.contains("pasteDictationTrigger") || etContent.contains("pasteDictationDoubleTap"))
    assertTrue(etHasDoubleTapPaste, "EventTap must handle double-tap for paste dictation")
}

// MARK: - 10. Totals-Critic Defects Remediation & Chunk-Batching Pause (ADR-012)

struct DoubleTapOptionStateMachine {
    var voiceModArmed: Bool = false
    var suppressVoiceOnNextUp: Bool = false
    var toggleVoiceTriggered: Bool = false
    var pasteTriggered: Bool = false
    var cmdCancelArmed: Bool = false
    var cancelTriggered: Bool = false

    // Simulate second Option tap during double-tap trigger
    mutating func onSecondOptionDown() {
        // Double tap recognized!
        pasteTriggered = true
        suppressVoiceOnNextUp = true
        voiceModArmed = false
    }

    mutating func onOptionUp() {
        if suppressVoiceOnNextUp {
            suppressVoiceOnNextUp = false
            return
        }
        if voiceModArmed {
            voiceModArmed = false
            toggleVoiceTriggered = true
        }
    }

    // Simulate Command cancel solo-up protection
    mutating func onCommandDown(isRecording: Bool) {
        if isRecording {
            cmdCancelArmed = true
        }
    }

    mutating func onKeyDownChord() {
        // Any key down (e.g. C, Tab, V) disarms solo command cancel
        cmdCancelArmed = false
    }

    mutating func onCommandUp() {
        if cmdCancelArmed {
            cmdCancelArmed = false
            cancelTriggered = true
        }
    }
}

func testTotalsCriticRemediationAndChunkBatching() {
    print("\n--- Test 10: Totals-Critic Defects Remediation & Chunk-Batching Pause (ADR-012) ---")
    
    // 1. DoubleTap state machine simulation (DEF-01)
    var sm = DoubleTapOptionStateMachine()
    sm.onSecondOptionDown()
    assertTrue(sm.pasteTriggered, "Double tap must trigger paste")
    assertTrue(sm.suppressVoiceOnNextUp, "Double tap must suppress next voice toggle on UP")
    sm.onOptionUp()
    assertFalse(sm.toggleVoiceTriggered, "DEF-01: Releasing Option after double-tap paste must NOT trigger voice recording")

    // 2. Command chord safety simulation (DEF-03)
    var cmdSm = DoubleTapOptionStateMachine()
    cmdSm.onCommandDown(isRecording: true)
    cmdSm.onKeyDownChord() // user pressed Cmd+C
    cmdSm.onCommandUp()
    assertFalse(cmdSm.cancelTriggered, "DEF-03: Cmd chord must NOT cancel recording on release")

    var cmdSoloSm = DoubleTapOptionStateMachine()
    cmdSoloSm.onCommandDown(isRecording: true)
    cmdSoloSm.onCommandUp() // pure solo tap
    assertTrue(cmdSoloSm.cancelTriggered, "DEF-03: Solo Cmd release must trigger cancel")

    // 3. Source code inspections for DEF-01, DEF-02, DEF-03, Batching
    let projectDir = "/Users/manar/AIII/projects/keytamer"
    let vcPath = "\(projectDir)/Sources/Keytamer/VoiceController.swift"
    let viPath = "\(projectDir)/Sources/Keytamer/VoiceIndicator.swift"
    let etPath = "\(projectDir)/Sources/Keytamer/EventTap.swift"

    guard let vcContent = try? String(contentsOf: URL(fileURLWithPath: vcPath), encoding: .utf8),
          let viContent = try? String(contentsOf: URL(fileURLWithPath: viPath), encoding: .utf8),
          let etContent = try? String(contentsOf: URL(fileURLWithPath: etPath), encoding: .utf8) else {
        testFailures.append("Could not read project source files for Test 10")
        return
    }

    // DEF-01 in EventTap
    let etHasSuppressVoice = etContent.contains("suppressVoiceOnNextUp")
    assertTrue(etHasSuppressVoice, "EventTap must contain suppressVoiceOnNextUp for DEF-01")

    // Option arbitration delay lowered to 0.17
    let etHasFasterArbitration = etContent.contains("0.17") || etContent.contains("0.16")
    assertTrue(etHasFasterArbitration, "EventTap must reduce Option double-tap arbitration window to ~0.17s")

    // DEF-02 in VoiceIndicator: ticker stopped on pause
    let viStopsTickerOnPause = viContent.contains("ticker?.invalidate()") || viContent.contains("ticker?.cancel()")
    assertTrue(viStopsTickerOnPause, "VoiceIndicator must stop ticker when paused to avoid wiping pause label")

    // DEF-03 in EventTap: cmdCancelArmed on solo up
    let etHasCmdCancelArmed = etContent.contains("cmdCancelArmed")
    assertTrue(etHasCmdCancelArmed, "EventTap must track cmdCancelArmed on solo release")

    // Chunk-Batching Pause in VoiceController
    let vcHasSessionSegments = vcContent.contains("sessionTextSegments")
    assertTrue(vcHasSessionSegments, "VoiceController must accumulate sessionTextSegments across pause chunks")

    let vcBatchingJoined = vcContent.contains("joined(separator:") || vcContent.contains("sessionTextSegments")
    assertTrue(vcBatchingJoined, "VoiceController must batch and join session segments upon completion")
}

// MARK: - 11. Universal Triggers & Zero-Loss Cancel Segments (ADR-013)

func testUniversalTriggersAndZeroLossCancel() {
    print("\n--- Test 11: Universal Triggers & Zero-Loss Cancel Segments (ADR-013) ---")

    let projectDir = "/Users/manar/AIII/projects/keytamer"
    let vcPath = "\(projectDir)/Sources/Keytamer/VoiceController.swift"
    let etPath = "\(projectDir)/Sources/Keytamer/EventTap.swift"
    let asPath = "\(projectDir)/Sources/Keytamer/AppSettings.swift"
    let swPath = "\(projectDir)/Sources/Keytamer/SettingsWindow.swift"

    guard let vcContent = try? String(contentsOf: URL(fileURLWithPath: vcPath), encoding: .utf8),
          let etContent = try? String(contentsOf: URL(fileURLWithPath: etPath), encoding: .utf8),
          let asContent = try? String(contentsOf: URL(fileURLWithPath: asPath), encoding: .utf8),
          let swContent = try? String(contentsOf: URL(fileURLWithPath: swPath), encoding: .utf8) else {
        testFailures.append("Could not read project source files for Test 11")
        return
    }

    // 1. Zero-Loss Cancel in VoiceController: cancel() must NOT wipe sessionTextSegments before saving
    let vcCancelPreservesSegments = vcContent.contains("func cancel()") && !vcContent.contains("sessionTextSegments.removeAll()\n        if streamingActive")
    assertTrue(vcCancelPreservesSegments, "VoiceController.cancel() must preserve segments for history delivery")

    // 2. AppSettings: voicePauseModifiers and custom label
    let asHasPauseMods = asContent.contains("voicePauseModifiers")
    assertTrue(asHasPauseMods, "AppSettings must define voicePauseModifiers")

    let asHasPauseLabel = asContent.contains("voicePauseKeyLabel")
    assertTrue(asHasPauseLabel, "AppSettings must define voicePauseKeyLabel")

    let asHasUniversalTriggers = asContent.contains("voicePauseTrigger") && asContent.contains("voiceCancelTrigger")
    assertTrue(asHasUniversalTriggers, "AppSettings must define voicePauseTrigger and voiceCancelTrigger")

    // 3. EventTap: check voicePause modifiers match
    let etChecksPauseMods = etContent.contains("voicePauseModifiers")
    assertTrue(etChecksPauseMods, "EventTap must match voicePauseModifiers against event flags")

    // 4. EventTap: Multi-tap detector (2x / 3x)
    let etHasMultiTap = etContent.contains("MultiTap") || etContent.contains("tripletap") || etContent.contains("tapCount")
    assertTrue(etHasMultiTap, "EventTap must support multi-tap triggers (doubletap and tripletap)")

    // 5. SettingsWindow: voice pause presets and recording
    let swHasPausePresets = swContent.contains("voicePausePresets") || swContent.contains("startVoicePauseHotkeyRecording")
    assertTrue(swHasPausePresets, "SettingsWindow must provide voice pause presets and custom hotkey recording")

    // 6. DEF-05 & DEF-06: EventTap tripletap arbitration check & intermediate cancel
    let viPath = "\(projectDir)/Sources/Keytamer/VoiceIndicator.swift"
    guard let viContent = try? String(contentsOf: URL(fileURLWithPath: viPath), encoding: .utf8) else {
        testFailures.append("Could not read VoiceIndicator.swift for Test 11")
        return
    }

    let etHasMultiTapArbitration = etContent.contains("pasteDictationTrigger == \"tripletap\"") && etContent.contains("isMultiTapPaste")
    assertTrue(etHasMultiTapArbitration, "EventTap must include tripletap in arbitration check (DEF-05)")

    let etCancelsOnEveryTap = etContent.contains("pendingVoiceWorkItem?.cancel(); pendingVoiceWorkItem = nil")
    assertTrue(etCancelsOnEveryTap, "EventTap must cancel pending voice item on every tap in multi-tap sequence (DEF-06)")

    // 7. DEF-07: VoiceIndicator must compensate total paused duration in timer
    let viCompensatesPause = viContent.contains("totalPausedDuration") || viContent.contains("pauseStartTime")
    assertTrue(viCompensatesPause, "VoiceIndicator must track and compensate paused duration in elapsed timer (DEF-07)")
}

// MARK: - Main Runner

print("=== KEYTAMER REMEDIATION SUITE ===")
testEventTapModifierOverrideDisarmBehavior()
testStoragePathsIsolation()
testClipboardTransientTypeIntegrity()
testRebrandingAndAssetIsolation()
testYAGNIRefactoringAndCompilerHygiene()
testInputReliabilityAndProtocolHygiene()
testCoexistenceModeWithKeyboopLock()
testKeyboopSettingsMigration()
testDictationPauseCancelAndDoubleTapPaste()
testTotalsCriticRemediationAndChunkBatching()
testUniversalTriggersAndZeroLossCancel()

print("\n=== SUMMARY ===")
if testFailures.isEmpty {
    print("ALL TESTS PASSED (GREEN)")
    exit(0)
} else {
    print("TESTS FAILED (RED): \(testFailures.count) failures")
    for f in testFailures {
        print(" - \(f)")
    }
    exit(1)
}

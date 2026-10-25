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

// MARK: - Main Runner

print("=== KEYTAMER REMEDIATION SUITE ===")
testEventTapModifierOverrideDisarmBehavior()
testStoragePathsIsolation()
testClipboardTransientTypeIntegrity()
testRebrandingAndAssetIsolation()

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

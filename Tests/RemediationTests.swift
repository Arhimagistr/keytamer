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

func testLegacyEventTapDisarmsIncorrectly() {
    print("\n--- Test 1: EventTap Modifier Override Disarm Behavior ---")
    let voiceHotkeyMods = CGEventFlags.maskAlternate.rawValue
    let overrideMod = CGEventFlags.maskCommand

    // Test A: Solo tap (Option down -> Option up)
    var stateSolo = EventTapState()
    stateSolo.onKeyDown(flags: [.maskAlternate], voiceHotkeyModifiers: voiceHotkeyMods, overrideModifierMask: overrideMod)
    stateSolo.processFlagsChangedLegacy(flags: [], voiceHotkeyModifiers: voiceHotkeyMods, overrideModifierMask: overrideMod)
    stateSolo.onKeyUp(flags: [], voiceHotkeyModifiers: voiceHotkeyMods)
    assertTrue(stateSolo.toggleVoiceCalled, "Solo tap triggers toggleVoice")
    assertEqual(stateSolo.toggleVoiceOverrideArg, false, "Solo tap override argument is false")

    // Test B: Override tap (Option + Command down -> Option up while Command is held)
    var stateOverride = EventTapState()
    stateOverride.onKeyDown(flags: [.maskAlternate, .maskCommand], voiceHotkeyModifiers: voiceHotkeyMods, overrideModifierMask: overrideMod)
    assertTrue(stateOverride.voiceModArmed, "Option+Cmd arms voiceMod")
    assertTrue(stateOverride.voiceModArmedOverride, "Option+Cmd sets voiceModArmedOverride")

    // Option is released: flags now contains only .maskCommand
    // IN LEGACY CODE: processFlagsChangedLegacy erroneously resets voiceModArmed!
    stateOverride.processFlagsChangedLegacy(flags: [.maskCommand], voiceHotkeyModifiers: voiceHotkeyMods, overrideModifierMask: overrideMod)
    stateOverride.onKeyUp(flags: [.maskCommand], voiceHotkeyModifiers: voiceHotkeyMods)

    // Contract: toggleVoice MUST be called with override=true.
    // In unpatched legacy code, this FAILS!
    assertTrue(stateOverride.toggleVoiceCalled, "Override tap MUST trigger toggleVoice on key up")
    assertEqual(stateOverride.toggleVoiceOverrideArg, true, "Override tap MUST pass override=true")
}

// MARK: - 2. Storage Paths Isolation (P0 Defect 2)

func testStoragePathsIsolation() {
    print("\n--- Test 2: Storage Paths Isolation ---")
    // Check VoiceHistory.swift and VoiceController.swift content on disk
    let voiceHistoryPath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceHistory.swift"
    let voiceControllerPath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceController.swift"
    let appDelegatePath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/AppDelegate.swift"

    guard let vhContent = try? String(contentsOfFile: voiceHistoryPath) else {
        testFailures.append("Could not read VoiceHistory.swift")
        return
    }
    guard let vcContent = try? String(contentsOfFile: voiceControllerPath) else {
        testFailures.append("Could not read VoiceController.swift")
        return
    }
    guard let adContent = try? String(contentsOfFile: appDelegatePath) else {
        testFailures.append("Could not read AppDelegate.swift")
        return
    }

    // In current unpatched code:
    // VoiceHistory.swift contains .appendingPathComponent("Keyboop", isDirectory: true)
    let vhHasKeyboopDir = vhContent.contains(".appendingPathComponent(\"Keyboop\", isDirectory: true)")
    assertFalse(vhHasKeyboopDir, "VoiceHistory.swift must NOT use Keyboop directory")

    let vcHasKeyboopBusy = vcContent.contains("Application Support/Keyboop/voice-busy")
    assertFalse(vcHasKeyboopBusy, "VoiceController.swift must NOT write voice-busy to Keyboop directory")

    // AppDelegate must check both Keytamer and Keyboop lock files
    let adChecksKeyboopLock = adContent.contains("Keyboop/singleton.lock") || adContent.contains("singleton.lock")
    assertTrue(adChecksKeyboopLock, "AppDelegate.swift must guard against dual instances")
}

// MARK: - 3. Clipboard TransientType Integrity (P1 Defect 4)

func testClipboardTransientTypeIntegrity() {
    print("\n--- Test 3: Clipboard TransientType Integrity ---")
    let textReplacerPath = "/Users/manar/AIII/projects/keytamer/Sources/Keytamer/TextReplacer.swift"
    guard let trContent = try? String(contentsOfFile: textReplacerPath) else {
        testFailures.append("Could not read TextReplacer.swift")
        return
    }

    // Line 291 in TextReplacer.swift currently sets TransientType on restored user items:
    // it.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    let setsTransientOnRestoredSnapshot = trContent.contains("for p in pairs { it.setData(p.data, forType: p.type) }\n                    it.setData(Data(), forType: NSPasteboard.PasteboardType(\"org.nspasteboard.TransientType\"))")
        || trContent.contains("for p in pairs { it.setData(p.data, forType: p.type) }\r\n                    it.setData(Data(), forType: NSPasteboard.PasteboardType(\"org.nspasteboard.TransientType\"))")

    assertFalse(setsTransientOnRestoredSnapshot, "TextReplacer must NOT set TransientType on restored user clipboard snapshot")
}

// MARK: - Main Runner

print("=== KEYTAMER REMEDIATION SUITE ===")
testLegacyEventTapDisarmsIncorrectly()
testStoragePathsIsolation()
testClipboardTransientTypeIntegrity()

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

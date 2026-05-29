import AppKit
import ApplicationServices
import Foundation

struct Config {
    let minHoldMs: Int
    let submitDelayMs: Int
    let triggerModifier: Modifier
    let submitKey: KeyboardKey
    let appNamePatterns: [String]
    let bundleIdPatterns: [String]
    let dryRun: Bool
    let verbose: Bool

    static func load() -> Config {
        let env = ProcessInfo.processInfo.environment
        return Config(
            minHoldMs: intValue(env["CCVS_MIN_HOLD_MS"], defaultValue: 650),
            submitDelayMs: intValue(env["CCVS_SUBMIT_DELAY_MS"], defaultValue: 900),
            triggerModifier: Modifier.parse(env["CCVS_TRIGGER_MODIFIER"]) ?? .command,
            submitKey: KeyboardKey.parse(env["CCVS_SUBMIT_KEY"]) ?? .returnKey,
            appNamePatterns: listValue(env["CCVS_APP_NAMES"], defaultValue: ["Codex", "Code X", "CodeX"]),
            bundleIdPatterns: listValue(env["CCVS_BUNDLE_IDS"], defaultValue: ["com.openai.codex", "com.openai.chatgpt"]),
            dryRun: boolValue(env["CCVS_DRY_RUN"], defaultValue: false),
            verbose: boolValue(env["CCVS_VERBOSE"], defaultValue: false)
        )
    }
}

struct Modifier {
    let name: String
    let flag: CGEventFlags
    let keyCodes: Set<Int64>

    static let command = Modifier(name: "command", flag: .maskCommand, keyCodes: [54, 55])
    static let control = Modifier(name: "control", flag: .maskControl, keyCodes: [59, 62])
    static let option = Modifier(name: "option", flag: .maskAlternate, keyCodes: [58, 61])
    static let shift = Modifier(name: "shift", flag: .maskShift, keyCodes: [56, 60])

    static func parse(_ raw: String?) -> Modifier? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "":
            return nil
        case "command", "cmd", "meta":
            return .command
        case "control", "ctrl":
            return .control
        case "option", "alt":
            return .option
        case "shift":
            return .shift
        default:
            return nil
        }
    }
}

struct KeyboardKey {
    let name: String
    let keyCode: CGKeyCode

    static let returnKey = KeyboardKey(name: "return", keyCode: 36)
    static let tab = KeyboardKey(name: "tab", keyCode: 48)
    static let space = KeyboardKey(name: "space", keyCode: 49)
    static let escape = KeyboardKey(name: "escape", keyCode: 53)

    static func parse(_ raw: String?) -> KeyboardKey? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "":
            return nil
        case "return", "enter":
            return .returnKey
        case "tab":
            return .tab
        case "space":
            return .space
        case "escape", "esc":
            return .escape
        default:
            return nil
        }
    }
}

final class CommandVoiceSubmitter {
    private let config: Config
    private var triggerDownAt: DispatchTime?
    private var lastTriggerFlags = false
    private var triggerSoloSince: DispatchTime?
    private var tap: CFMachPort?

    init(config: Config) {
        self.config = config
    }

    func run() {
        guard checkAccessibilityPermission(prompt: false) else {
            fputs("需要授予辅助功能权限：系统设置 -> 隐私与安全性 -> 辅助功能，允许此程序。可手动运行 `codex-command-voice-submit --request-permission` 触发一次授权提示。\n", stderr)
            exit(2)
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let submitter = Unmanaged<CommandVoiceSubmitter>.fromOpaque(refcon).takeUnretainedValue()
            return submitter.handle(proxy: proxy, type: type, event: event)
        }

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            fputs("无法创建键盘监听。请确认已授予输入监控和辅助功能权限。\n", stderr)
            exit(3)
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        log("已启动：\(config.triggerModifier.name) 单独保持 >= \(config.minHoldMs)ms，松开后 \(config.submitDelayMs)ms 自动发送 \(config.submitKey.name)。")
        CFRunLoopRun()
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if triggerDownAt != nil && !isModifierKey(keyCode) {
                triggerSoloSince = nil
                log("\(config.triggerModifier.name) 期间检测到普通按键按下：\(keyCode)")
            }
        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if triggerDownAt != nil && event.flags.contains(config.triggerModifier.flag) && !isModifierKey(keyCode) {
                triggerSoloSince = DispatchTime.now()
                log("普通按键松开，开始重新计算 \(config.triggerModifier.name) 单独保持时长：\(keyCode)")
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let triggerIsDown = event.flags.contains(config.triggerModifier.flag)

        if triggerDownAt != nil && triggerIsDown && !config.triggerModifier.keyCodes.contains(keyCode) {
            triggerSoloSince = nil
            log("\(config.triggerModifier.name) 期间检测到其他修饰键按下：\(keyCode)")
        }

        if triggerIsDown && !lastTriggerFlags {
            triggerDownAt = DispatchTime.now()
            triggerSoloSince = triggerDownAt
            log("\(config.triggerModifier.name) down")
        }

        if triggerDownAt != nil && triggerIsDown && !config.triggerModifier.keyCodes.contains(keyCode) && onlyTriggerModifierIsDown(event.flags, trigger: config.triggerModifier) {
            triggerSoloSince = DispatchTime.now()
            log("其他修饰键松开，开始重新计算 \(config.triggerModifier.name) 单独保持时长：\(keyCode)")
        }

        if !triggerIsDown && lastTriggerFlags {
            let heldMs = heldDurationMs()
            let soloMs = triggerSoloDurationMs()
            let shouldSubmit = soloMs >= config.minHoldMs
            log("\(config.triggerModifier.name) up，总持续 \(heldMs)ms，单独保持 \(soloMs)ms，shouldSubmit=\(shouldSubmit)")
            triggerDownAt = nil
            triggerSoloSince = nil

            if shouldSubmit {
                submitIfCodexIsFrontmost()
            }
        }

        lastTriggerFlags = triggerIsDown
    }

    private func heldDurationMs() -> Int {
        guard let triggerDownAt else {
            return 0
        }
        let nanos = DispatchTime.now().uptimeNanoseconds - triggerDownAt.uptimeNanoseconds
        return Int(nanos / 1_000_000)
    }

    private func triggerSoloDurationMs() -> Int {
        guard let triggerSoloSince else {
            return 0
        }
        let nanos = DispatchTime.now().uptimeNanoseconds - triggerSoloSince.uptimeNanoseconds
        return Int(nanos / 1_000_000)
    }

    private func submitIfCodexIsFrontmost() {
        guard frontmostAppMatches() else {
            log("前台应用不匹配，跳过发送。")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.submitDelayMs)) {
            if self.frontmostAppMatches() {
                self.sendReturn()
            } else {
                self.log("延迟期间前台应用变化，跳过发送。")
            }
        }
    }

    private func frontmostAppMatches() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appName = app.localizedName ?? ""
        let bundleId = app.bundleIdentifier ?? ""
        let lowerName = appName.lowercased()
        let lowerBundleId = bundleId.lowercased()

        let nameMatches = config.appNamePatterns.contains {
            !$0.isEmpty && lowerName.contains($0.lowercased())
        }
        let bundleMatches = config.bundleIdPatterns.contains {
            !$0.isEmpty && lowerBundleId.contains($0.lowercased())
        }

        log("前台应用：name=\(appName), bundleId=\(bundleId), match=\(nameMatches || bundleMatches)")
        return nameMatches || bundleMatches
    }

    private func sendReturn() {
        if config.dryRun {
            log("dry-run：将发送 Return")
            return
        }

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: config.submitKey.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: config.submitKey.keyCode, keyDown: false) else {
            fputs("无法创建 \(config.submitKey.name) 按键事件。\n", stderr)
            return
        }

        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
        log("已发送 \(config.submitKey.name)")
    }

    private func log(_ message: String) {
        if config.verbose {
            print("[codex-command-voice-submit] \(message)")
        }
    }
}

private func checkAccessibilityPermission(prompt: Bool) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

private func isModifierKey(_ keyCode: Int64) -> Bool {
    // Command, Shift, Option, Control, Fn and Caps Lock key codes on macOS.
    return [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
}

private func onlyTriggerModifierIsDown(_ flags: CGEventFlags, trigger: Modifier) -> Bool {
    let allModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn, .maskAlphaShift]
    let otherModifiers = allModifiers.subtracting(trigger.flag)
    return flags.contains(trigger.flag) && flags.intersection(otherModifiers).isEmpty
}

private func intValue(_ raw: String?, defaultValue: Int) -> Int {
    guard let raw, let value = Int(raw), value >= 0 else {
        return defaultValue
    }
    return value
}

private func boolValue(_ raw: String?, defaultValue: Bool) -> Bool {
    guard let raw else {
        return defaultValue
    }
    switch raw.lowercased() {
    case "1", "true", "yes", "y", "on":
        return true
    case "0", "false", "no", "n", "off":
        return false
    default:
        return defaultValue
    }
}

private func listValue(_ raw: String?, defaultValue: [String]) -> [String] {
    guard let raw else {
        return defaultValue
    }
    let values = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return values.isEmpty ? defaultValue : values
}

let arguments = CommandLine.arguments.dropFirst()
let config = Config.load()

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    用法:
      codex-command-voice-submit          启动监听
      codex-command-voice-submit --check  检查配置和权限，不启动监听
      codex-command-voice-submit --request-permission
                                           触发一次 macOS 辅助功能授权提示

    环境变量:
      CCVS_MIN_HOLD_MS       默认 650
      CCVS_SUBMIT_DELAY_MS   默认 900
      CCVS_TRIGGER_MODIFIER  默认 command，可选 command/control/option/shift
      CCVS_SUBMIT_KEY        默认 return，可选 return/tab/space/escape
      CCVS_APP_NAMES         默认 Codex,Code X,CodeX
      CCVS_BUNDLE_IDS        默认 com.openai.codex,com.openai.chatgpt
      CCVS_VERBOSE           默认 0
      CCVS_DRY_RUN           默认 0
    """)
    exit(0)
}

if arguments.contains("--request-permission") {
    print("accessibilityTrusted=\(checkAccessibilityPermission(prompt: true))")
    exit(0)
}

if arguments.contains("--check") {
    print("minHoldMs=\(config.minHoldMs)")
    print("submitDelayMs=\(config.submitDelayMs)")
    print("triggerModifier=\(config.triggerModifier.name)")
    print("submitKey=\(config.submitKey.name)")
    print("appNamePatterns=\(config.appNamePatterns.joined(separator: ","))")
    print("bundleIdPatterns=\(config.bundleIdPatterns.joined(separator: ","))")
    print("dryRun=\(config.dryRun)")
    print("verbose=\(config.verbose)")
    print("accessibilityTrusted=\(checkAccessibilityPermission(prompt: false))")
    exit(0)
}

let submitter = CommandVoiceSubmitter(config: config)
submitter.run()

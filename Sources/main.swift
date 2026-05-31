import AppKit
import ApplicationServices
import Foundation

struct Config {
    let minHoldMs: Int
    let submitDelayMs: Int
    let triggerModifier: Modifier
    let triggerSide: TriggerSide
    let submitKey: KeyboardKey
    let cancelKey: KeyboardKey?
    let showHint: Bool
    let hintText: String
    let hintDurationMs: Int
    let appNamePatterns: [String]
    let bundleIdPatterns: [String]
    let dryRun: Bool
    let verbose: Bool

    static func load() -> Config {
        let env = ProcessInfo.processInfo.environment
        return Config(
            minHoldMs: intValue(env["CCVS_MIN_HOLD_MS"], defaultValue: 2000),
            submitDelayMs: intValue(env["CCVS_SUBMIT_DELAY_MS"], defaultValue: 900),
            triggerModifier: Modifier.parse(env["CCVS_TRIGGER_MODIFIER"]) ?? .command,
            triggerSide: TriggerSide.parse(env["CCVS_TRIGGER_SIDE"]) ?? .left,
            submitKey: KeyboardKey.parse(env["CCVS_SUBMIT_KEY"]) ?? .returnKey,
            cancelKey: KeyboardKey.parseOptional(env["CCVS_CANCEL_KEY"], defaultValue: .escape),
            showHint: boolValue(env["CCVS_SHOW_HINT"], defaultValue: true),
            hintText: stringValue(env["CCVS_HINT_TEXT"], defaultValue: defaultHintText(cancelKey: KeyboardKey.parseOptional(env["CCVS_CANCEL_KEY"], defaultValue: .escape))),
            hintDurationMs: intValue(env["CCVS_HINT_DURATION_MS"], defaultValue: 1200),
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
    let leftKeyCode: Int64
    let rightKeyCode: Int64
    let keyCodes: Set<Int64>

    static let command = Modifier(name: "command", flag: .maskCommand, leftKeyCode: 55, rightKeyCode: 54, keyCodes: [54, 55])
    static let control = Modifier(name: "control", flag: .maskControl, leftKeyCode: 59, rightKeyCode: 62, keyCodes: [59, 62])
    static let option = Modifier(name: "option", flag: .maskAlternate, leftKeyCode: 58, rightKeyCode: 61, keyCodes: [58, 61])
    static let shift = Modifier(name: "shift", flag: .maskShift, leftKeyCode: 56, rightKeyCode: 60, keyCodes: [56, 60])

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

enum TriggerSide: String {
    case left
    case right
    case any

    static func parse(_ raw: String?) -> TriggerSide? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "":
            return nil
        case "left", "l":
            return .left
        case "right", "r":
            return .right
        case "any", "both", "all":
            return .any
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

    static func parseOptional(_ raw: String?, defaultValue: KeyboardKey?) -> KeyboardKey? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "":
            return defaultValue
        case "none", "off", "disabled", "disable":
            return nil
        default:
            return parse(raw) ?? defaultValue
        }
    }
}

final class CommandVoiceSubmitter {
    private let config: Config
    private var triggerDownAt: DispatchTime?
    private var lastTriggerFlags = false
    private var triggerSoloSince: DispatchTime?
    private var currentGestureCanceled = false
    private var currentGestureId = 0
    private var pendingSubmissionId = 0
    private let hintOverlay: HintOverlay?
    private var tap: CFMachPort?

    init(config: Config) {
        self.config = config
        self.hintOverlay = config.showHint ? HintOverlay() : nil
    }

    func run() {
        guard checkAccessibilityPermission(prompt: false) else {
            fputs("需要授予辅助功能权限：系统设置 -> 隐私与安全性 -> 辅助功能，允许此程序。可手动运行 `codex-voice-auto-send --request-permission` 触发一次授权提示。\n", stderr)
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

        let cancelDescription = config.cancelKey.map { "，\( $0.name ) 可取消本次发送" } ?? ""
        log("已启动：\(config.triggerSide.rawValue) \(config.triggerModifier.name) 单独保持 >= \(config.minHoldMs)ms，松开后 \(config.submitDelayMs)ms 自动发送 \(config.submitKey.name)\(cancelDescription)。")
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
            if shouldCancel(keyCode: keyCode) {
                cancelCurrentOrPendingSubmission()
                return Unmanaged.passUnretained(event)
            }
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
        let triggerKeyChanged = isConfiguredTriggerKey(keyCode)

        if triggerDownAt != nil && triggerIsDown && !triggerKeyChanged {
            triggerSoloSince = nil
            log("\(config.triggerModifier.name) 期间检测到其他修饰键按下：\(keyCode)")
        }

        if triggerIsDown && !lastTriggerFlags && triggerKeyChanged {
            currentGestureId += 1
            triggerDownAt = DispatchTime.now()
            triggerSoloSince = triggerDownAt
            currentGestureCanceled = false
            scheduleHint(for: currentGestureId)
            log("\(config.triggerModifier.name) down")
        }

        if triggerDownAt != nil && triggerIsDown && !triggerKeyChanged && onlyTriggerModifierIsDown(event.flags, trigger: config.triggerModifier) {
            triggerSoloSince = DispatchTime.now()
            log("其他修饰键松开，开始重新计算 \(config.triggerModifier.name) 单独保持时长：\(keyCode)")
        }

        if !triggerIsDown && lastTriggerFlags {
            let heldMs = heldDurationMs()
            let soloMs = triggerSoloDurationMs()
            let shouldSubmit = soloMs >= config.minHoldMs && !currentGestureCanceled
            log("\(config.triggerModifier.name) up，总持续 \(heldMs)ms，单独保持 \(soloMs)ms，shouldSubmit=\(shouldSubmit)")
            triggerDownAt = nil
            triggerSoloSince = nil
            currentGestureCanceled = false
            currentGestureId += 1

            if shouldSubmit {
                submitIfCodexIsFrontmost()
            } else {
                hideHint()
            }
        }

        lastTriggerFlags = triggerIsDown
    }

    private func isConfiguredTriggerKey(_ keyCode: Int64) -> Bool {
        switch config.triggerSide {
        case .any:
            return config.triggerModifier.keyCodes.contains(keyCode)
        case .left:
            return keyCode == config.triggerModifier.leftKeyCode
        case .right:
            return keyCode == config.triggerModifier.rightKeyCode
        }
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
            hideHint()
            return
        }

        pendingSubmissionId += 1
        let submissionId = pendingSubmissionId
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.submitDelayMs)) {
            guard submissionId == self.pendingSubmissionId else {
                self.log("本次发送已取消。")
                self.hideHint()
                return
            }
            if self.frontmostAppMatches() {
                self.sendReturn()
            } else {
                self.log("延迟期间前台应用变化，跳过发送。")
            }
            if submissionId == self.pendingSubmissionId {
                self.pendingSubmissionId = 0
            }
            self.hideHint()
        }
    }

    private func shouldCancel(keyCode: Int64) -> Bool {
        guard let cancelKey = config.cancelKey else {
            return false
        }
        return keyCode == Int64(cancelKey.keyCode) && (triggerDownAt != nil || pendingSubmissionId != 0)
    }

    private func cancelCurrentOrPendingSubmission() {
        if triggerDownAt != nil {
            currentGestureCanceled = true
            triggerSoloSince = nil
            currentGestureId += 1
        }
        if pendingSubmissionId != 0 {
            pendingSubmissionId += 1
        }
        hideHint()
        log("已取消本次自动发送。")
    }

    private func showHintToast() {
        guard config.cancelKey != nil else {
            return
        }
        DispatchQueue.main.async {
            self.hintOverlay?.show(text: self.config.hintText, durationMs: self.config.hintDurationMs)
        }
    }

    private func scheduleHint(for gestureId: Int) {
        guard config.cancelKey != nil else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.minHoldMs)) {
            guard gestureId == self.currentGestureId,
                  self.triggerDownAt != nil,
                  !self.currentGestureCanceled,
                  self.triggerSoloDurationMs() >= self.config.minHoldMs else {
                return
            }
            self.showHintToast()
        }
    }

    private func hideHint() {
        DispatchQueue.main.async {
            self.hintOverlay?.hide()
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
            print("[codex-voice-auto-send] \(message)")
        }
    }
}

final class HintOverlay {
    private let window: NSPanel
    private let toastView: ToastView
    private var toastGeneration = 0

    init() {
        toastView = ToastView()

        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.contentView = toastView
    }

    func show(text: String, durationMs: Int) {
        toastGeneration += 1
        let generation = toastGeneration
        toastView.text = text
        window.setFrame(NSRect(origin: window.frame.origin, size: toastView.preferredSize), display: true)
        positionNearBottom()
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(durationMs)) {
            guard generation == self.toastGeneration else {
                return
            }
            self.hide()
        }
    }

    func hide() {
        toastGeneration += 1
        window.orderOut(nil)
    }

    private func positionNearBottom() {
        guard let screen = NSScreen.main else {
            return
        }
        let frame = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 82
        )
        window.setFrameOrigin(origin)
    }
}

final class ToastView: NSView {
    var text = "" {
        didSet {
            needsDisplay = true
        }
    }

    private let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private let horizontalPadding: CGFloat = 18
    private let verticalPadding: CGFloat = 8
    private let minWidth: CGFloat = 112
    private let maxWidth: CGFloat = 260

    var preferredSize: NSSize {
        let textWidth = ceil((text as NSString).size(withAttributes: attributes).width)
        return NSSize(
            width: min(max(textWidth + horizontalPadding * 2, minWidth), maxWidth),
            height: ceil(font.ascender - font.descender + verticalPadding * 2)
        )
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.68).setFill()
        background.fill()

        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let textRect = NSRect(
            x: 0,
            y: floor((bounds.height - textSize.height) / 2),
            width: bounds.width,
            height: ceil(textSize.height)
        )
        attributedText.draw(in: textRect)
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        return [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
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

private func stringValue(_ raw: String?, defaultValue: String) -> String {
    guard let raw else {
        return defaultValue
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? defaultValue : trimmed
}

private func defaultHintText(cancelKey: KeyboardKey?) -> String {
    guard let cancelKey else {
        return ""
    }
    return "\(displayName(for: cancelKey)) 取消自动发送"
}

private func displayName(for key: KeyboardKey) -> String {
    switch key.name {
    case "escape":
        return "Esc"
    case "return":
        return "Return"
    case "tab":
        return "Tab"
    case "space":
        return "Space"
    default:
        return key.name
    }
}

let arguments = CommandLine.arguments.dropFirst()
let config = Config.load()

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    用法:
      codex-voice-auto-send          启动监听
      codex-voice-auto-send --check  检查配置和权限，不启动监听
      codex-voice-auto-send --request-permission
                                           触发一次 macOS 辅助功能授权提示

    环境变量:
      CCVS_MIN_HOLD_MS       默认 2000
      CCVS_SUBMIT_DELAY_MS   默认 900
      CCVS_TRIGGER_MODIFIER  默认 command，可选 command/control/option/shift
      CCVS_TRIGGER_SIDE      默认 left，可选 left/right/any
      CCVS_SUBMIT_KEY        默认 return，可选 return/tab/space/escape
      CCVS_CANCEL_KEY        默认 escape，可选 return/tab/space/escape/none
      CCVS_SHOW_HINT         默认 1
      CCVS_HINT_TEXT         默认按取消键生成提示文案
      CCVS_HINT_DURATION_MS  默认 1200
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
    print("triggerSide=\(config.triggerSide.rawValue)")
    print("submitKey=\(config.submitKey.name)")
    print("cancelKey=\(config.cancelKey?.name ?? "none")")
    print("showHint=\(config.showHint)")
    print("hintText=\(config.hintText)")
    print("hintDurationMs=\(config.hintDurationMs)")
    print("appNamePatterns=\(config.appNamePatterns.joined(separator: ","))")
    print("bundleIdPatterns=\(config.bundleIdPatterns.joined(separator: ","))")
    print("dryRun=\(config.dryRun)")
    print("verbose=\(config.verbose)")
    print("accessibilityTrusted=\(checkAccessibilityPermission(prompt: false))")
    exit(0)
}

let submitter = CommandVoiceSubmitter(config: config)
submitter.run()

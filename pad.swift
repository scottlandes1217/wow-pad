// wow-pad: a PS5 / any controller as plain keys for WoW, so WoW never sees a gamepad (its Gamepad UI
// taints with map addons). Each button is one fixed key nobody types; the PadBar addon binds them.
// L2/R2 hold Alt/Ctrl (the addon's layers), the left stick walks/runs, the right stick turns (WoW's
// turn bindings) and tilts the camera (the addon's MoveView calls), Options is Escape. Only while WoW is the frontmost app.
import AppKit
import GameController

// calibration knobs
let deadzone: Float = 0.25        // stick travel ignored
let moveAt: Float = 0.35          // stick axis that counts as a direction
let runAt: Float = 0.75           // stick tilt that runs (below: walks)
let tick = 1.0 / 60

// macOS virtual key codes. Buttons: F13-F19 then keypad keys; the addon maps the same names.
enum K {
    static let f13: CGKeyCode = 0x69, f14: CGKeyCode = 0x6B, f15: CGKeyCode = 0x71, f16: CGKeyCode = 0x6A
    static let f17: CGKeyCode = 0x40, f18: CGKeyCode = 0x4F, f19: CGKeyCode = 0x50
    static let kp0: CGKeyCode = 0x52, kp1: CGKeyCode = 0x53, kp3: CGKeyCode = 0x55, kp7: CGKeyCode = 0x59
    static let kp9: CGKeyCode = 0x5C, kpDecimal: CGKeyCode = 0x41, kpMultiply: CGKeyCode = 0x43
    static let kp8: CGKeyCode = 0x5B, kp5: CGKeyCode = 0x57, kp4: CGKeyCode = 0x56, kp6: CGKeyCode = 0x58
    static let kpDivide: CGKeyCode = 0x4B, kpPlus: CGKeyCode = 0x45, kpMinus: CGKeyCode = 0x4E
    static let kpClear: CGKeyCode = 0x47, kpEquals: CGKeyCode = 0x51, kp2: CGKeyCode = 0x54
    static let option: CGKeyCode = 0x3A, control: CGKeyCode = 0x3B, escape: CGKeyCode = 0x35
}
let keypad: Set<CGKeyCode> = [K.kp0, K.kp1, K.kp3, K.kp4, K.kp5, K.kp6, K.kp7, K.kp8, K.kp9,
                              K.kpDecimal, K.kpMultiply, K.kpDivide, K.kpPlus, K.kpMinus, K.kpClear, K.kpEquals, K.kp2]

func buttons(_ g: GCExtendedGamepad) -> [(Bool, CGKeyCode)] {
    [(g.buttonA.isPressed, K.f13),                    // cross
     (g.buttonB.isPressed, K.f14),                    // circle
     (g.buttonX.isPressed, K.f15),                    // square
     (g.buttonY.isPressed, K.f16),                    // triangle
     (g.dpad.up.isPressed, K.f17), (g.dpad.down.isPressed, K.f18),
     (g.dpad.left.isPressed, K.f19), (g.dpad.right.isPressed, K.kp0),
     (g.leftShoulder.isPressed, K.kp1),               // L1
     (g.rightShoulder.isPressed, K.kp3),              // R1
     (g.leftThumbstickButton?.isPressed ?? false, K.kp7),   // L3
     (g.rightThumbstickButton?.isPressed ?? false, K.kp9),  // R3
     (g.buttonOptions?.isPressed ?? false, K.kpDecimal),    // Create
     ((g as? GCDualSenseGamepad)?.touchpadButton.isPressed ?? false, K.kpMultiply),
     (g.buttonMenu.isPressed, K.escape)]              // Options
}

let src = CGEventSource(stateID: .hidSystemState)
var down: Set<CGKeyCode> = []
var flags: CGEventFlags = []

func post(_ code: CGKeyCode, _ isDown: Bool) {
    guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: isDown) else { return }
    if code == K.option || code == K.control {
        let f: CGEventFlags = code == K.option ? .maskAlternate : .maskControl
        if isDown { flags.insert(f) } else { flags.remove(f) }
        e.type = .flagsChanged
    }
    e.flags = keypad.contains(code) ? flags.union(.maskNumericPad) : flags
    e.post(tap: .cghidEventTap)
}
func set(_ code: CGKeyCode, _ isDown: Bool) {
    guard down.contains(code) != isDown else { return }
    if isDown { down.insert(code) } else { down.remove(code) }
    post(code, isDown)
}

// Right stick: turn left/right, tilt the camera up/down (keys the addon binds)
func look(_ x: Float, _ y: Float) {
    let on = hypotf(x, y) > deadzone
    set(K.kpPlus, on && x < -moveAt); set(K.kpMinus, on && x > moveAt)
    set(K.kpClear, on && y > moveAt); set(K.kpEquals, on && y < -moveAt)
}

// Left stick: movement keys, and walk (slight tilt) or run (full tilt). WoW has only a run/walk
// toggle, so this sends what the stick wants (kpDivide: walk, kp2: run) and PadBar, which knows from
// your speed which mode you're in, binds only the one that changes it to the toggle.
var wantWalk: Bool?
var settling: Bool?, settled = 0
let settleTicks = 9   // ~0.15 s in one zone before asking (pushing to full passes through "walk")
func move(_ x: Float, _ y: Float) {
    let mag = hypotf(x, y)
    let on = mag > deadzone
    set(K.kp8, on && y > moveAt); set(K.kp5, on && y < -moveAt)
    set(K.kp4, on && x < -moveAt); set(K.kp6, on && x > moveAt)
    guard on else { wantWalk = nil; settling = nil; return }
    let walk = wantWalk == true ? mag < runAt + 0.05 : mag < runAt - 0.05   // a little hysteresis
    guard walk != wantWalk else { settling = nil; return }
    if walk == settling { settled += 1 } else { settling = walk; settled = 1 }
    if settled >= settleTicks { tap(walk ? K.kpDivide : K.kp2); wantWalk = walk; settling = nil }
}

func releaseAll() {
    for c in down where c != K.option && c != K.control { post(c, false) }
    if down.contains(K.option) { post(K.option, false) }
    if down.contains(K.control) { post(K.control, false) }
    down.removeAll()
}

func wowInFront() -> Bool {
    NSWorkspace.shared.frontmostApplication?.bundleURL?.lastPathComponent == "World of Warcraft.app"
}

// --calibrate: PadBar learns what WoW calls each key (/padbar learn), sent in PadBar's ORDER.
let calibration: [CGKeyCode] = [K.f13, K.f14, K.f15, K.f16, K.f17, K.f18, K.f19, K.kp0,   // ✕ ○ □ △, d-pad
                                K.kp1, K.kp3, K.kp7, K.kp9, K.kpDecimal, K.kpMultiply,    // L1 R1 L3 R3 Create Pad
                                K.kp8, K.kp5, K.kp4, K.kp6, K.kpDivide,                   // move, run/walk
                                K.kpPlus, K.kpMinus, K.kpClear, K.kpEquals, K.kp2]        // turn, tilt, run
func type(_ text: String) {
    for ch in text.utf16 {
        for isDown in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: isDown) else { continue }
            var c = ch
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e.post(tap: .cghidEventTap)
        }
        usleep(15_000)
    }
}
func tap(_ code: CGKeyCode) { post(code, true); usleep(40_000); post(code, false) }

if CommandLine.arguments.contains("--selftest") {
    precondition(Set(keypad).count == 17 && Set(calibration).count == 24)
    print("ok"); exit(0)
}
if CommandLine.arguments.contains("--calibrate") {
    guard let wow = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.lastPathComponent == "World of Warcraft.app" })
    else { print("wow-pad: WoW isn't running"); exit(1) }
    wow.activate()
    usleep(1_500_000)
    guard wowInFront() else { print("wow-pad: couldn't bring WoW to the front"); exit(1) }
    tap(0x2C); usleep(400_000)                    // "/" opens chat with the slash (Return may be bound)
    type("padbar learn"); tap(0x24); usleep(1_000_000)
    for code in calibration { tap(code); usleep(250_000) }
    print("wow-pad: sent \(calibration.count) keys"); exit(0)
}

setvbuf(stdout, nil, _IONBF, 0)
_ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
GCController.shouldMonitorBackgroundEvents = true
NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { n in
    print("wow-pad: \((n.object as? GCController)?.vendorName ?? "controller") connected")
}
Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { _ in
    guard wowInFront(), let g = GCController.controllers().compactMap(\.extendedGamepad).first else {
        if !down.isEmpty { releaseAll() }
        return
    }
    set(K.option, g.leftTrigger.isPressed)
    set(K.control, g.rightTrigger.isPressed)
    for (pressed, code) in buttons(g) { set(code, pressed) }
    move(g.leftThumbstick.xAxis.value, g.leftThumbstick.yAxis.value)
    look(g.rightThumbstick.xAxis.value, g.rightThumbstick.yAxis.value)
}
// L2/R2 hold Alt/Ctrl only virtually: the real mouse's events would still say "not held", and WoW
// would drop the layer the moment the mouse moves (dragging a spell onto it, say). While a trigger is
// held, add its modifier to the mouse's events too.
let mouseEvents: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown,
                                  .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: CGEventMask(mouseEvents.reduce(0) { $0 | (1 << $1.rawValue) }),
                               callback: { _, _, e, _ in
                                   if !flags.isEmpty { e.flags.formUnion(flags) }
                                   return Unmanaged.passUnretained(e)
                               }, userInfo: nil) {
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
} else { print("wow-pad: no mouse tap (Accessibility?): L2/R2 layers drop while the mouse moves") }
print("wow-pad: running")
app.run()

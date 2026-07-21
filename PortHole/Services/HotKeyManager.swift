import AppKit
import Carbon.HIToolbox
import os.log

/// Registers a single system-wide hotkey through the Carbon Hot Key API.
///
/// Why Carbon and not an `NSEvent` global monitor: PortHole runs as a
/// background accessory (`LSUIElement`), and it must open on the hotkey even
/// when another app is frontmost or fullscreen. `RegisterEventHotKey` delivers
/// that system-wide, on the main run loop, *without* the Accessibility
/// permission that keyboard `NSEvent` monitors require. There is no modern
/// Swift replacement for this specific capability.
final class HotKeyManager {
    /// Carbon virtual key codes we need. `kVK_ANSI_P` etc. live in
    /// `Carbon.HIToolbox`; we expose the one we use by name for readability.
    static let keyP = UInt32(kVK_ANSI_P)

    /// Carbon modifier masks (see `Events.h`). Combine with `|`.
    static let cmdKey = UInt32(Carbon.cmdKey)
    static let optionKey = UInt32(Carbon.optionKey)
    static let controlKey = UInt32(Carbon.controlKey)
    static let shiftKey = UInt32(Carbon.shiftKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onFire: () -> Void
    private let log = Logger(subsystem: "io.github.yash121l.PortHole", category: "hotkey")
    /// Four-char signature identifying our hotkey ('PHTk').
    private static let signature: OSType = 0x5048_546B

    /// Registers `keyCode` + `modifiers` globally. `onFire` is invoked on the
    /// main thread each time the combo is pressed.
    init(keyCode: UInt32, modifiers: UInt32, onFire: @escaping () -> Void) {
        self.onFire = onFire

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // The handler must be a capture-less C function pointer, so it routes
        // back to this instance through the userData pointer we hand it.
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers hotkey events on the main run loop already; this
            // hop only guards against a surprise.
            if Thread.isMainThread {
                manager.onFire()
            } else {
                DispatchQueue.main.async { manager.onFire() }
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        log.notice("hotkey registered: install=\(installStatus) register=\(registerStatus) ref=\(self.hotKeyRef != nil)")
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

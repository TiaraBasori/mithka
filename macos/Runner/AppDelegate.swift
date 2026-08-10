import Cocoa
import FlutterMacOS
import multi_window_manager

@main
class AppDelegate: FlutterAppDelegate {
  private var rightControlMonitor: Any?
  private var statusItem: NSStatusItem?
  /// Keep the original Flutter engine/window alive while the app is hidden in
  /// the menu bar. Recreating it on every Dock launch can race the still-live
  /// TDLib process and its database locks.
  private var retainedMainWindow: MainFlutterWindow?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Flutter's macOS engine tracks right-Control with device bit 0x200, but
    // AppKit reports NX_DEVICERCTLKEYMASK = 0x2000, so the engine never sees
    // the key go down and right-Ctrl shortcuts (e.g. Ctrl+Enter to send) only
    // work with the left key (flutter/flutter#148936). Mirror the real bit
    // onto the one the engine checks for every keyboard event; each keyDown
    // re-syncs modifier state, so the fix covers shortcuts in all windows.
    rightControlMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .keyUp, .flagsChanged]
    ) { event in
      Self.mirrorRightControlFlag(event)
    }
    super.applicationDidFinishLaunching(notification)
    _ = resolveMainWindow()
    installStatusItem()
  }

  private func resolveMainWindow() -> MainFlutterWindow? {
    if let retainedMainWindow {
      return retainedMainWindow
    }
    guard
      let window = mainFlutterWindow as? MainFlutterWindow
        ?? NSApp.windows.first(where: { $0 is MainFlutterWindow })
          as? MainFlutterWindow
    else {
      return nil
    }
    window.isReleasedWhenClosed = false
    retainedMainWindow = window
    return window
  }

  private func installStatusItem() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(
      withLength: NSStatusItem.squareLength
    )
    if let button = item.button {
      button.image = Self.makeStatusItemImage()
      button.image?.accessibilityDescription = "Mithka"
      button.toolTip = "Mithka"
    }

    let menu = NSMenu()
    let showItem = NSMenuItem(
      title: NSLocalizedString(
        "Show Mithka",
        comment: "Menu bar action that reopens Mithka's main window"
      ),
      action: #selector(showMainWindow),
      keyEquivalent: ""
    )
    showItem.target = self
    menu.addItem(showItem)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: NSLocalizedString(
        "Quit Mithka",
        comment: "Menu bar action that terminates Mithka"
      ),
      action: #selector(quitApplication),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)
    item.menu = menu
    statusItem = item
  }

  /// An owned monochrome speech-mark keeps the status item legible in both
  /// menu-bar appearances without depending on a platform icon catalogue.
  private static func makeStatusItemImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    NSColor.black.setStroke()
    NSColor.black.setFill()

    let bubble = NSBezierPath(
      roundedRect: NSRect(x: 1.75, y: 3.75, width: 14.5, height: 10.5),
      xRadius: 4,
      yRadius: 4
    )
    bubble.lineWidth = 1.55
    bubble.stroke()

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 5.25, y: 4.15))
    tail.line(to: NSPoint(x: 3.45, y: 1.9))
    tail.line(to: NSPoint(x: 7.1, y: 4.05))
    tail.lineWidth = 1.55
    tail.lineJoinStyle = .round
    tail.lineCapStyle = .round
    tail.stroke()

    for x in [6.0, 9.0, 12.0] {
      NSBezierPath(
        ovalIn: NSRect(x: x - 0.8, y: 8.2, width: 1.6, height: 1.6)
      ).fill()
    }
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  @discardableResult
  private func bringMainWindowToFront(
    using application: NSApplication = NSApp
  ) -> Bool {
    guard let primaryWindow = resolveMainWindow() else { return false }
    application.unhide(nil)
    if primaryWindow.isMiniaturized {
      primaryWindow.deminiaturize(nil)
    }
    primaryWindow.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)
    return true
  }

  @objc private func showMainWindow() {
    bringMainWindowToFront()
  }

  @objc private func quitApplication() {
    NSApp.terminate(nil)
  }

  override func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
  ) -> Bool {
    guard HandoffBridge.shared.accept(userActivity) else { return false }
    bringMainWindowToFront(using: application)
    return true
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    // A Dock click always restores the retained engine/window. Never create a
    // replacement window or a second TDLib client just because it was hidden.
    bringMainWindowToFront(using: sender)
    // The reopen AppleEvent is fully handled above. Returning false prevents
    // AppKit from following up with its default untitled-window creation.
    return false
  }

  private static func mirrorRightControlFlag(_ event: NSEvent) -> NSEvent {
    let deviceRightControl: UInt = 0x2000  // NX_DEVICERCTLKEYMASK
    let engineRightControl: UInt = 0x200  // bit Flutter's engine matches against
    let raw = event.modifierFlags.rawValue
    guard raw & deviceRightControl != 0, raw & engineRightControl == 0 else {
      return event
    }
    let isFlagsChanged = event.type == .flagsChanged
    let patched = NSEvent.keyEvent(
      with: event.type,
      location: event.locationInWindow,
      modifierFlags: NSEvent.ModifierFlags(rawValue: raw | engineRightControl),
      timestamp: event.timestamp,
      windowNumber: event.windowNumber,
      context: nil,
      characters: isFlagsChanged ? "" : (event.characters ?? ""),
      charactersIgnoringModifiers: isFlagsChanged
        ? "" : (event.charactersIgnoringModifiers ?? ""),
      isARepeat: isFlagsChanged ? false : event.isARepeat,
      keyCode: event.keyCode
    )
    return patched ?? event
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // The menu-bar item remains available to reopen the retained main window.
    // Explicit Quit in either native menu still terminates normally.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

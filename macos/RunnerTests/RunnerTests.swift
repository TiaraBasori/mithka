import Cocoa
import FlutterMacOS
import XCTest
@testable import Mithka

class RunnerTests: XCTestCase {
  @MainActor
  func testMainWindowCloseHidesWithoutDestroyingWindow() {
    let window = makeMainWindow()
    window.orderFront(nil)

    window.close()

    XCTAssertFalse(window.isVisible)
    XCTAssertFalse(window.isReleasedWhenClosed)
    XCTAssertNotNil(window.contentViewController)
  }

  @MainActor
  func testMainWindowMinimizeHidesInsteadOfCreatingDockThumbnail() {
    let window = makeMainWindow()
    window.orderFront(nil)

    window.miniaturize(nil)

    XCTAssertFalse(window.isVisible)
    XCTAssertFalse(window.isMiniaturized)
    XCTAssertNotNil(window.contentViewController)
  }

  @MainActor
  func testDockReopenRestoresTheRetainedPrimaryWindow() throws {
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let window = try XCTUnwrap(delegate.mainFlutterWindow as? MainFlutterWindow)
    window.close()
    XCTAssertFalse(window.isVisible)

    let shouldRunDefaultReopen = delegate.applicationShouldHandleReopen(
      NSApp,
      hasVisibleWindows: false
    )

    XCTAssertFalse(shouldRunDefaultReopen)
    XCTAssertTrue(window.isVisible)
  }

  @MainActor
  func testStatusItemShowRestoresTheRetainedPrimaryWindow() throws {
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let window = try XCTUnwrap(delegate.mainFlutterWindow as? MainFlutterWindow)
    window.close()
    XCTAssertFalse(window.isVisible)

    let showMainWindow = NSSelectorFromString("showMainWindow")
    XCTAssertTrue(delegate.responds(to: showMainWindow))
    _ = delegate.perform(showMainWindow)

    XCTAssertTrue(window.isVisible)
  }

  @MainActor
  private func makeMainWindow() -> MainFlutterWindow {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = NSViewController()
    window.isReleasedWhenClosed = false
    addTeardownBlock { @MainActor in
      window.orderOut(nil)
    }
    return window
  }
}

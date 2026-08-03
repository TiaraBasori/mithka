import Cocoa
import FlutterMacOS
import multi_window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    MultiWindowManagerPlugin.RegisterGeneratedPlugins = RegisterGeneratedPlugins

    super.awakeFromNib()

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    minSize = NSSize(width: 820, height: 560)
    if #available(macOS 11.0, *) {
      titlebarSeparatorStyle = .none
    }
  }
}

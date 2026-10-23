import Cocoa
import FlutterMacOS

// The BizHub POS window: opens at 1280×800 in the middle of the screen; never smaller than 1024×680
// (the tablet layout of the POS needs that much room).
class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let size = NSSize(width: 1280, height: 800)
    if let screen = NSScreen.main?.visibleFrame {
      let w = min(size.width, screen.width), h = min(size.height, screen.height)
      self.setFrame(NSRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h), display: true)
    } else {
      self.setContentSize(size)
    }
    self.minSize = NSSize(width: 1024, height: 680)
    self.title = "BizHub POS"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

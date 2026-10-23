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
    CustomerDisplay.shared.attach(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

// The screen facing the customer, on a second monitor — the same "bizhub/display" channel as the Android
// dual-screen terminals (lib/core/customer_display.dart):
//   available  → is a second monitor plugged in
//   show(json) → open a full-screen window there (once) and draw this picture
//   hide       → close it
// The window runs a second Flutter engine at displayMain (lib/main.dart), which says "hello" on
// "bizhub/display_view" when it starts and then gets each picture as "pic". It never becomes the key window,
// so the cashier (and the USB scanner) keep typing into the counter window.
final class CustomerDisplay {
  static let shared = CustomerDisplay()

  private var channel: FlutterMethodChannel?
  private var viewChannel: FlutterMethodChannel?
  private var engine: FlutterEngine?
  private var window: NSWindow?
  private var last: String?

  func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "bizhub/display", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "available":
        result(self.secondScreen() != nil)
      case "show":
        self.last = call.arguments as? String
        let shown = self.show()
        self.send()
        result(shown)
      case "hide":
        self.hide()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  // the first screen that is not the main one (with the menu bar); nil when only one is plugged in
  private func secondScreen() -> NSScreen? {
    let screens = NSScreen.screens
    guard let main = screens.first else { return nil }
    return screens.first { $0 != main }
  }

  private func show() -> Bool {
    if window != nil { return true }
    guard let screen = secondScreen() else { return false }
    let engine = FlutterEngine(name: "customer-display", project: nil)
    guard engine.run(withEntrypoint: "displayMain") else { return false }
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    RegisterGeneratedPlugins(registry: controller)

    let view = FlutterMethodChannel(name: "bizhub/display_view", binaryMessenger: engine.binaryMessenger)
    view.setMethodCallHandler { [weak self] call, result in
      if call.method == "hello" { self?.send() }  // the screen just started: give it the picture now
      result(nil)
    }

    let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
    w.contentViewController = controller
    w.setFrame(screen.frame, display: true)
    w.isReleasedWhenClosed = false
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    w.orderFrontRegardless()  // shown, but the counter window keeps the keyboard

    self.engine = engine
    self.viewChannel = view
    self.window = w
    return true
  }

  private func hide() {
    window?.orderOut(nil)
    window?.contentViewController = nil
    window = nil
    viewChannel = nil
    engine?.shutDownEngine()
    engine = nil
  }

  private func send() {
    guard let pic = last, let view = viewChannel else { return }
    view.invokeMethod("pic", arguments: pic)
  }
}

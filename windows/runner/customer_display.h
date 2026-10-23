#ifndef RUNNER_CUSTOMER_DISPLAY_H_
#define RUNNER_CUSTOMER_DISPLAY_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>

class FlutterWindow;

// The screen facing the customer, on a second monitor — the same "bizhub/display" channel as the Android
// dual-screen terminals (lib/core/customer_display.dart):
//   available  → is a second monitor plugged in
//   show(json) → open a full-screen window there (once) and draw this picture
//   hide       → close it
// The window runs a second Flutter engine at displayMain (lib/main.dart), which says "hello" on
// "bizhub/display_view" when it starts and then gets each picture as "pic". It never takes the keyboard,
// so the cashier (and the USB scanner) keep typing into the counter window.
class CustomerDisplay {
 public:
  explicit CustomerDisplay(flutter::BinaryMessenger* messenger);
  ~CustomerDisplay();

 private:
  std::optional<RECT> SecondMonitor() const;
  bool Show();
  void Hide();
  void Send();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> view_channel_;
  std::unique_ptr<FlutterWindow> window_;
  std::string last_;
};

#endif  // RUNNER_CUSTOMER_DISPLAY_H_

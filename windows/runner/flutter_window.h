#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "customer_display.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // main = the counter window (it also runs the customer screen on a second monitor); the customer screen
  // itself is a FlutterWindow with main = false, shown without taking the keyboard.
  explicit FlutterWindow(const flutter::DartProject& project, bool main = true);
  virtual ~FlutterWindow();

  flutter::FlutterViewController* controller() { return flutter_controller_.get(); }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  bool main_;

  // the screen facing the customer (only in the main window)
  std::unique_ptr<CustomerDisplay> display_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

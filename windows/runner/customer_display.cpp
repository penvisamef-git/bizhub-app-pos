#include "customer_display.h"

#include <flutter/dart_project.h>
#include <flutter/standard_method_codec.h>

#include <vector>

#include "flutter_window.h"

namespace {

using flutter::EncodableValue;

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  auto* out = reinterpret_cast<std::vector<MONITORINFO>*>(data);
  MONITORINFO info{};
  info.cbSize = sizeof(MONITORINFO);
  if (::GetMonitorInfo(monitor, &info)) {
    out->push_back(info);
  }
  return TRUE;
}

}  // namespace

CustomerDisplay::CustomerDisplay(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "bizhub/display",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();
        if (method == "available") {
          result->Success(EncodableValue(SecondMonitor().has_value()));
        } else if (method == "show") {
          if (const auto* pic = std::get_if<std::string>(call.arguments())) {
            last_ = *pic;
          }
          const bool shown = Show();
          Send();
          result->Success(EncodableValue(shown));
        } else if (method == "hide") {
          Hide();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

CustomerDisplay::~CustomerDisplay() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
  Hide();
}

// the first monitor that is not the main one (null when only one is plugged in)
std::optional<RECT> CustomerDisplay::SecondMonitor() const {
  std::vector<MONITORINFO> monitors;
  ::EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                        reinterpret_cast<LPARAM>(&monitors));
  for (const auto& m : monitors) {
    if ((m.dwFlags & MONITORINFOF_PRIMARY) == 0) {
      return m.rcMonitor;
    }
  }
  return std::nullopt;
}

bool CustomerDisplay::Show() {
  if (window_) {
    return true;
  }
  const std::optional<RECT> rect = SecondMonitor();
  if (!rect) {
    return false;
  }

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint("displayMain");
  auto window = std::make_unique<FlutterWindow>(project, /*main=*/false);
  // created small, then moved over the whole second monitor (in its real pixels)
  if (!window->Create(L"BizHub POS - Customer", Win32Window::Point(10, 10),
                      Win32Window::Size(800, 600))) {
    return false;
  }
  window->SetQuitOnClose(false);
  HWND hwnd = window->GetHandle();
  ::SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
  ::SetWindowLongPtr(hwnd, GWL_EXSTYLE,
                     ::GetWindowLongPtr(hwnd, GWL_EXSTYLE) | WS_EX_NOACTIVATE |
                         WS_EX_TOOLWINDOW);
  ::SetWindowPos(hwnd, HWND_TOP, rect->left, rect->top,
                 rect->right - rect->left, rect->bottom - rect->top,
                 SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOACTIVATE);

  view_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      window->controller()->engine()->messenger(), "bizhub/display_view",
      &flutter::StandardMethodCodec::GetInstance());
  view_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        // the screen just started: give it the picture now
        if (call.method_name() == "hello") {
          Send();
        }
        result->Success();
      });
  window_ = std::move(window);
  return true;
}

void CustomerDisplay::Hide() {
  view_channel_ = nullptr;
  if (window_) {
    window_->Destroy();
    window_ = nullptr;
  }
}

void CustomerDisplay::Send() {
  if (!view_channel_ || last_.empty()) {
    return;
  }
  view_channel_->InvokeMethod("pic", std::make_unique<EncodableValue>(last_));
}

#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

void ConstrainMaximizedWindowToWorkArea(HWND window, LPARAM lparam) {
  auto* min_max_info = reinterpret_cast<MINMAXINFO*>(lparam);
  const HMONITOR monitor =
      MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  if (monitor == nullptr) {
    return;
  }

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return;
  }

  const RECT& monitor_bounds = monitor_info.rcMonitor;
  const RECT& work_area = monitor_info.rcWork;
  min_max_info->ptMaxPosition.x = work_area.left - monitor_bounds.left;
  min_max_info->ptMaxPosition.y = work_area.top - monitor_bounds.top;
  min_max_info->ptMaxSize.x = work_area.right - work_area.left;
  min_max_info->ptMaxSize.y = work_area.bottom - work_area.top;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  std::optional<LRESULT> plugin_result = std::nullopt;
  if (flutter_controller_) {
    plugin_result = flutter_controller_->HandleTopLevelWindowProc(
        hwnd, message, wparam, lparam);
  }

  if (message == WM_GETMINMAXINFO) {
    ConstrainMaximizedWindowToWorkArea(hwnd, lparam);
    return plugin_result.value_or(0);
  }

  if (plugin_result) {
    return *plugin_result;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

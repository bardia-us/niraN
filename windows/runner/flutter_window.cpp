#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "windows/native/windows_backend_bridge.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayOpen = 41001;
constexpr UINT kTrayStatus = 41002;
constexpr UINT kTraySetProxy = 41003;
constexpr UINT kTrayClearProxy = 41004;
constexpr UINT kTrayTun = 41005;
constexpr UINT kTrayExit = 41006;
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
  windows_backend_ = std::make_unique<niran::WindowsBackendBridge>(
      flutter_controller_->engine()->messenger(), GetHandle());
  AddTrayIcon();
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
  RemoveTrayIcon();
  if (windows_backend_) {
    windows_backend_->Shutdown();
    windows_backend_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == niran::WindowsBackendBridge::kAsyncCompletionMessage &&
      windows_backend_) {
    return windows_backend_->HandleAsyncCompletion(lparam) ? 0 : 1;
  }
  if (message == kTrayMessage) {
    if (LOWORD(lparam) == WM_LBUTTONUP) {
      ShowFromTray();
    } else if (LOWORD(lparam) == WM_RBUTTONUP ||
               LOWORD(lparam) == WM_CONTEXTMENU) {
      ShowTrayMenu();
    }
    return 0;
  }
  if (message == WM_CLOSE && !exit_requested_) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::AddTrayIcon() {
  tray_icon_ = {};
  tray_icon_.cbSize = sizeof(tray_icon_);
  tray_icon_.hWnd = GetHandle();
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  tray_icon_.uCallbackMessage = kTrayMessage;
  tray_icon_.hIcon = LoadIconW(GetModuleHandleW(nullptr),
                               MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"niraN");
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_) == TRUE;
  if (tray_added_) {
    tray_icon_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_);
  }
  return tray_added_;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) return;
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  tray_added_ = false;
  if (tray_icon_.hIcon) DestroyIcon(tray_icon_.hIcon);
  tray_icon_.hIcon = nullptr;
}

void FlutterWindow::ShowFromTray() {
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::ShowTrayMenu() {
  if (!windows_backend_) return;
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  const bool core = windows_backend_->IsCoreRunning();
  const bool tun = windows_backend_->IsTunRunning();
  const auto proxy = windows_backend_->ProxyState();
  const std::wstring status = core
                                  ? (tun ? L"Status: Core + TUN running"
                                         : L"Status: Core running")
                                  : L"Status: Core stopped";
  AppendMenuW(menu, MF_STRING, kTrayOpen, L"Open niraN");
  AppendMenuW(menu, MF_STRING | MF_GRAYED, kTrayStatus, status.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu,
              MF_STRING | (proxy == niran::SystemProxyState::kNiran
                               ? MF_CHECKED
                               : MF_UNCHECKED),
              kTraySetProxy, L"Set System Proxy");
  AppendMenuW(menu,
              MF_STRING | (proxy == niran::SystemProxyState::kClear
                               ? MF_CHECKED
                               : MF_UNCHECKED),
              kTrayClearProxy, L"Clear System Proxy");
  AppendMenuW(menu, MF_STRING | (tun ? MF_CHECKED : MF_UNCHECKED), kTrayTun,
              L"TUN");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExit, L"Exit");
  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(GetHandle());
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x, cursor.y,
      0, GetHandle(), nullptr);
  DestroyMenu(menu);
  switch (command) {
    case kTrayOpen:
      ShowFromTray();
      break;
    case kTraySetProxy:
      windows_backend_->RequestTrayAction("setProxy");
      break;
    case kTrayClearProxy:
      windows_backend_->RequestTrayAction("clearProxy");
      break;
    case kTrayTun:
      windows_backend_->RequestTrayAction("toggleTun");
      break;
    case kTrayExit:
      exit_requested_ = true;
      windows_backend_->Shutdown();
      DestroyWindow(GetHandle());
      break;
  }
}

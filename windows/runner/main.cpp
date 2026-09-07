#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cstdint>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kWindowStateKey[] = L"Software\\niraN\\Window";

bool ReadWindowValue(HKEY key, const wchar_t* name, DWORD* value) {
  DWORD type = 0;
  DWORD size = sizeof(*value);
  return RegQueryValueExW(key, name, nullptr, &type,
                          reinterpret_cast<BYTE*>(value), &size) ==
             ERROR_SUCCESS &&
         type == REG_DWORD;
}

void ApplySavedWindowBounds(HWND window) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kWindowStateKey, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return;
  }
  DWORD raw_x = 0, raw_y = 0, raw_width = 0, raw_height = 0, raw_state = 0;
  const bool complete = ReadWindowValue(key, L"X", &raw_x) &&
                        ReadWindowValue(key, L"Y", &raw_y) &&
                        ReadWindowValue(key, L"Width", &raw_width) &&
                        ReadWindowValue(key, L"Height", &raw_height);
  ReadWindowValue(key, L"State", &raw_state);
  RegCloseKey(key);
  if (!complete) return;

  RECT desired = {static_cast<LONG>(static_cast<int32_t>(raw_x)),
                  static_cast<LONG>(static_cast<int32_t>(raw_y)), 0, 0};
  desired.right = desired.left + static_cast<LONG>(raw_width);
  desired.bottom = desired.top + static_cast<LONG>(raw_height);
  HMONITOR monitor = MonitorFromRect(&desired, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(info)};
  if (!GetMonitorInfoW(monitor, &info)) return;
  const int work_width = info.rcWork.right - info.rcWork.left;
  const int work_height = info.rcWork.bottom - info.rcWork.top;
  const int width = std::clamp(static_cast<int>(raw_width), 760, work_width);
  const int height = std::clamp(static_cast<int>(raw_height), 560, work_height);
  const int work_left = static_cast<int>(info.rcWork.left);
  const int work_top = static_cast<int>(info.rcWork.top);
  const int work_right = static_cast<int>(info.rcWork.right);
  const int work_bottom = static_cast<int>(info.rcWork.bottom);
  const int x =
      std::clamp(static_cast<int>(desired.left), work_left, work_right - width);
  const int y = std::clamp(static_cast<int>(desired.top), work_top,
                           work_bottom - height);
  SetWindowPos(window, nullptr, x, y, width, height,
               SWP_NOACTIVATE | SWP_NOZORDER);
  if (raw_state == 1) ShowWindow(window, SW_MAXIMIZE);
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, L"Local\\niraN-bardia-us-v0");
  if (single_instance == nullptr || ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (single_instance != nullptr) ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1180, 760);
  if (!window.Create(L"niraN", origin, size)) {
    return EXIT_FAILURE;
  }
  ApplySavedWindowBounds(window.GetHandle());
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::ReleaseMutex(single_instance);
  ::CloseHandle(single_instance);
  return EXIT_SUCCESS;
}

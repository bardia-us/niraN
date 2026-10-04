#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shellapi.h>
#include <windows.h>

#include <algorithm>
#include <cstdint>
#include <string>

#include "flutter_window.h"
#include "window_size_limits.h"
#include "utils.h"
#include "windows/proxy/system_proxy_manager.h"

namespace {
constexpr wchar_t kWindowStateKey[] = L"Software\\niraN\\Window";
constexpr wchar_t kInstanceMutex[] = L"Local\\niraN-bardia-us-v0";

std::wstring CurrentExecutablePath() {
  std::wstring path(32768, L'\0');
  const DWORD length = GetModuleFileNameW(
      nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) return {};
  path.resize(length);
  return path;
}

bool HasArgument(const wchar_t* expected) {
  int count = 0;
  LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  if (arguments == nullptr) return false;
  bool found = false;
  for (int index = 1; index < count; ++index) {
    if (_wcsicmp(arguments[index], expected) == 0) {
      found = true;
      break;
    }
  }
  LocalFree(arguments);
  return found;
}

void RunUninstallCleanup() {
  std::wstring ignored;
  niran::SystemProxyManager proxy;
  proxy.RecoverStale(&ignored);
  HKEY run_key = nullptr;
  if (RegOpenKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
          KEY_SET_VALUE, &run_key) == ERROR_SUCCESS) {
    RegDeleteValueW(run_key, L"niraN");
    RegCloseKey(run_key);
  }
  RegDeleteTreeW(HKEY_CURRENT_USER, kWindowStateKey);
}

struct ExistingWindowSearch {
  std::wstring executable;
  bool found = false;
};

BOOL CALLBACK ShowExistingWindow(HWND window, LPARAM parameter) {
  auto* search = reinterpret_cast<ExistingWindowSearch*>(parameter);
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               process_id);
  if (process == nullptr) return TRUE;
  std::wstring path(32768, L'\0');
  DWORD length = static_cast<DWORD>(path.size());
  const bool matches =
      QueryFullProcessImageNameW(process, 0, path.data(), &length) &&
      _wcsicmp(std::wstring(path.data(), length).c_str(),
               search->executable.c_str()) == 0;
  CloseHandle(process);
  if (!matches) return TRUE;
  ShowWindow(window, SW_RESTORE);
  SetForegroundWindow(window);
  search->found = true;
  return FALSE;
}

void BringExistingInstanceToFront() {
  ExistingWindowSearch search{CurrentExecutablePath()};
  if (!search.executable.empty()) {
    EnumWindows(ShowExistingWindow, reinterpret_cast<LPARAM>(&search));
  }
}

bool ReadWindowValue(HKEY key, const wchar_t* name, DWORD* value) {
  DWORD type = 0;
  DWORD size = sizeof(*value);
  return RegQueryValueExW(key, name, nullptr, &type,
                          reinterpret_cast<BYTE*>(value), &size) ==
             ERROR_SUCCESS &&
         type == REG_DWORD;
}

void ApplySavedWindowBounds(HWND window) {
  RECT desired = {};
  if (!GetWindowRect(window, &desired)) return;
  DWORD raw_width = static_cast<DWORD>(std::clamp<int64_t>(
      static_cast<int64_t>(desired.right) - desired.left, 1, INT_MAX));
  DWORD raw_height = static_cast<DWORD>(std::clamp<int64_t>(
      static_cast<int64_t>(desired.bottom) - desired.top, 1, INT_MAX));
  DWORD raw_state = 0;
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kWindowStateKey, 0, KEY_READ, &key) ==
      ERROR_SUCCESS) {
    DWORD x = 0, y = 0, width = 0, height = 0, state = 0;
    const bool complete = ReadWindowValue(key, L"X", &x) &&
                          ReadWindowValue(key, L"Y", &y) &&
                          ReadWindowValue(key, L"Width", &width) &&
                          ReadWindowValue(key, L"Height", &height);
    ReadWindowValue(key, L"State", &state);
    RegCloseKey(key);
    if (complete) {
      desired.left = static_cast<int32_t>(x);
      desired.top = static_cast<int32_t>(y);
      raw_width = width;
      raw_height = height;
      raw_state = state;
      desired.right = niran::SafeWindowEdge(desired.left, width);
      desired.bottom = niran::SafeWindowEdge(desired.top, height);
    }
  }
  HMONITOR monitor = MonitorFromRect(&desired, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(info)};
  if (!GetMonitorInfoW(monitor, &info)) return;
  const auto limits = niran::GetWindowSizeLimits(window, monitor, true);
  const auto bounds = niran::CalculateWindowBounds(
      desired.left, desired.top, raw_width, raw_height,
      info.rcWork.left, info.rcWork.top, limits);
  SetWindowPos(window, nullptr, bounds.x, bounds.y, bounds.width, bounds.height,
               SWP_NOACTIVATE | SWP_NOZORDER);
  if (raw_state == 1) ShowWindow(window, SW_MAXIMIZE);
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (HasArgument(L"--uninstall-cleanup")) {
    RunUninstallCleanup();
    return EXIT_SUCCESS;
  }
  HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, kInstanceMutex);
  if (single_instance == nullptr || ::GetLastError() == ERROR_ALREADY_EXISTS) {
    BringExistingInstanceToFront();
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

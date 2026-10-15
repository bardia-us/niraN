#ifndef RUNNER_STARTUP_TRACE_H_
#define RUNNER_STARTUP_TRACE_H_

#include <windows.h>

#include <chrono>
#include <cstdio>
#include <iterator>
#include <mutex>
#include <string>

namespace niran {

// Opt-in diagnostics only. No user data or method arguments enter the trace.
// Process creation includes loader/engine time before the Dart isolate exists.
class NativeStartupTrace {
 public:
  NativeStartupTrace() {
    wchar_t path[32768]{};
    const DWORD length = GetEnvironmentVariableW(
        L"NIRAN_STARTUP_TRACE_FILE", path, static_cast<DWORD>(std::size(path)));
    if (length == 0 || length >= std::size(path)) return;
    path_ = path;
    FILETIME created{}, exited{}, kernel{}, user{}, now{};
    if (GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user)) {
      GetSystemTimePreciseAsFileTime(&now);
      ULARGE_INTEGER start{}, current{};
      start.LowPart = created.dwLowDateTime;
      start.HighPart = created.dwHighDateTime;
      current.LowPart = now.dwLowDateTime;
      current.HighPart = now.dwHighDateTime;
      if (current.QuadPart >= start.QuadPart) {
        process_offset_us_ = (current.QuadPart - start.QuadPart) / 10;
      }
    }
    started_ = std::chrono::steady_clock::now();
  }

  void Mark(const char* phase) {
    if (path_.empty()) return;
    const auto elapsed = process_offset_us_ +
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - started_).count();
    char line[256]{};
    const int length = snprintf(
        line, sizeof(line),
        "{\"origin\":\"process\",\"phase\":\"%s\",\"elapsedUs\":%llu}\n",
        phase, static_cast<unsigned long long>(elapsed));
    if (length <= 0 || length >= static_cast<int>(sizeof(line))) return;
    std::scoped_lock lock(mutex_);
    const HANDLE file = CreateFileW(path_.c_str(), FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    DWORD written = 0;
    WriteFile(file, line, static_cast<DWORD>(length), &written, nullptr);
    CloseHandle(file);
  }

 private:
  std::wstring path_;
  std::chrono::steady_clock::time_point started_{};
  unsigned long long process_offset_us_ = 0;
  std::mutex mutex_;
};

inline void TraceNativeStartup(const char* phase) {
  static NativeStartupTrace trace;
  trace.Mark(phase);
}

}  // namespace niran

#endif  // RUNNER_STARTUP_TRACE_H_

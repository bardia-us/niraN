#ifndef NIRAN_WINDOW_SIZE_LIMITS_H_
#define NIRAN_WINDOW_SIZE_LIMITS_H_

#include <algorithm>
#include <climits>
#include <cstdint>
#ifdef _WIN32
#include <windows.h>
#include <shellscalingapi.h>
#endif

namespace niran {
struct WindowSizeLimits {
  int min_width;
  int min_height;
  int max_width;
  int max_height;
};

// Minimum client geometry is exercised by Flutter UI tests at 800x600.
// Inputs/outputs are physical pixels; frame extents exclude the client.
inline WindowSizeLimits CalculateWindowSizeLimits(
    int work_width, int work_height, unsigned int dpi,
    int frame_width, int frame_height) {
  const auto scale = static_cast<int64_t>(dpi == 0 ? 96 : dpi);
  const int max_width = std::max(1, work_width);
  const int max_height = std::max(1, work_height);
  const auto min_width = (800 * scale + 48) / 96 + std::max(0, frame_width);
  const auto min_height = (600 * scale + 48) / 96 + std::max(0, frame_height);
  return {static_cast<int>(std::clamp<int64_t>(min_width, 1, max_width)),
          static_cast<int>(std::clamp<int64_t>(min_height, 1, max_height)),
          max_width, max_height};
}

// Registry dimensions are unsigned DWORDs; never add them in signed LONG.
inline int SafeWindowEdge(int position, uint32_t extent) {
  return static_cast<int>(std::clamp<int64_t>(
      static_cast<int64_t>(position) + extent, INT_MIN, INT_MAX));
}

struct WindowBounds { int x; int y; int width; int height; };
inline WindowBounds CalculateWindowBounds(
    int x, int y, uint32_t width, uint32_t height,
    int work_left, int work_top, WindowSizeLimits limits) {
  const int w = static_cast<int>(std::clamp<int64_t>(
      width, limits.min_width, limits.max_width));
  const int h = static_cast<int>(std::clamp<int64_t>(
      height, limits.min_height, limits.max_height));
  const auto right = std::min<int64_t>(INT_MAX,
      static_cast<int64_t>(work_left) + limits.max_width - w);
  const auto bottom = std::min<int64_t>(INT_MAX,
      static_cast<int64_t>(work_top) + limits.max_height - h);
  return {static_cast<int>(std::clamp<int64_t>(x, work_left, right)),
          static_cast<int>(std::clamp<int64_t>(y, work_top, bottom)), w, h};
}

#ifdef _WIN32
inline WindowSizeLimits GetWindowSizeLimits(
    HWND window, HMONITOR monitor, bool use_monitor_dpi = false) {
  UINT dpi = GetDpiForWindow(window);
  if (use_monitor_dpi) {
    UINT monitor_x = 96, monitor_y = 96;
    if (SUCCEEDED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI,
                                  &monitor_x, &monitor_y))) {
      dpi = monitor_x;
    }
  }
  if (dpi == 0) dpi = 96;
  RECT frame = {};
  AdjustWindowRectExForDpi(
      &frame, static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE)),
      GetMenu(window) != nullptr,
      static_cast<DWORD>(GetWindowLongPtrW(window, GWL_EXSTYLE)), dpi);
  MONITORINFO info = {sizeof(info)};
  RECT work = {};
  if (GetMonitorInfoW(monitor, &info)) {
    work = info.rcWork;
  } else {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  }
  return CalculateWindowSizeLimits(
      work.right - work.left, work.bottom - work.top, dpi,
      frame.right - frame.left, frame.bottom - frame.top);
}
#endif
}  // namespace niran
#endif

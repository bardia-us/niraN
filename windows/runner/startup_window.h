#ifndef RUNNER_STARTUP_WINDOW_H_
#define RUNNER_STARTUP_WINDOW_H_

#include <windows.h>

namespace niran {

template <typename RequestFrame>
void PresentStartupWindow(HWND window, RequestFrame request_frame) {
  // A hidden Flutter surface can defer rasterization indefinitely. Present
  // after saved bounds have been applied, then request the actual loader frame.
  // SW_SHOW preserves restored/maximized placement; never normalize an already
  // visible saved window from a delayed first-frame callback.
  if (!IsWindowVisible(window)) ShowWindow(window, SW_SHOW);
  request_frame();
}

}  // namespace niran

#endif  // RUNNER_STARTUP_WINDOW_H_

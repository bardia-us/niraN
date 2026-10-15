#define NOMINMAX
#include <windows.h>

#include <cstdio>

#include "../../windows/runner/startup_window.h"

int main() {
  // A one-pixel, offscreen, non-activating fixture cannot touch app state or
  // steal foreground focus. Exercise real Win32 visibility before redraw.
  HWND window = CreateWindowExW(WS_EX_NOACTIVATE, L"STATIC", L"startup fixture",
      WS_POPUP, -32000, -32000, 1, 1, nullptr, nullptr,
      GetModuleHandleW(nullptr), nullptr);
  if (window == nullptr) return 2;
  RECT saved{}, first{}, after{};
  GetWindowRect(window, &saved);
  int redraws = 0;
  bool visible_at_redraw = false;
  niran::PresentStartupWindow(window, [&] {
    ++redraws;
    visible_at_redraw = IsWindowVisible(window) != FALSE;
  });
  const bool first_presented = IsWindowVisible(window) != FALSE;
  GetWindowRect(window, &first);
  niran::PresentStartupWindow(window, [&] { ++redraws; });
  GetWindowRect(window, &after);
  DestroyWindow(window);
  if (!first_presented || !visible_at_redraw || redraws != 2) {
    std::fputs("FAIL startup surface must be visible before redraw\n", stderr);
    return 1;
  }
  if (!EqualRect(&saved, &first) || !EqualRect(&first, &after)) {
    std::fputs("FAIL presenting an existing surface changed saved bounds\n", stderr);
    return 1;
  }
  std::puts("PASS startup visibility before redraw and preserved bounds");
  return 0;
}

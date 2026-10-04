#define NOMINMAX
#include <cassert>
#include <iostream>
#include "../../windows/runner/window_size_limits.h"

int main() {
  // A title bar/border must not eat into the tested 800x600 client area.
  auto normal = niran::CalculateWindowSizeLimits(1920, 1040, 96, 16, 39);
  assert(normal.min_width == 816 && normal.min_height == 639);
  assert(normal.max_width == 1920 && normal.max_height == 1040);
  auto scaled = niran::CalculateWindowSizeLimits(2560, 1400, 144, 24, 59);
  assert(scaled.min_width == 1224 && scaled.min_height == 959);
  assert(scaled.max_width == 2560 && scaled.max_height == 1400);
  // Low-resolution/high-DPI monitors must never produce min > max or invalid
  // std::clamp bounds. A tiny work area is capped to what Windows can show.
  auto constrained_monitor = niran::CalculateWindowSizeLimits(1024, 728, 192, 32, 78);
  assert(constrained_monitor.min_width == 1024 && constrained_monitor.min_height == 728);
  assert(constrained_monitor.max_width == 1024 && constrained_monitor.max_height == 728);
  auto invalid = niran::CalculateWindowSizeLimits(0, -1, 0, 0, 0);
  assert(invalid.min_width == 1 && invalid.min_height == 1);
  assert(invalid.max_width == 1 && invalid.max_height == 1);
  assert(niran::SafeWindowEdge(100, UINT32_MAX) == INT_MAX);
  assert(niran::SafeWindowEdge(-1920, 816) == -1104);
  const auto restored = niran::CalculateWindowBounds(-4000, 2000,
      UINT32_MAX, UINT32_MAX, -1920, 0, normal);
  assert(restored.x == -1920 && restored.y == 0);
  assert(restored.width == 1920 && restored.height == 1040);
  const auto initial = niran::CalculateWindowBounds(10, 10, 1180, 760,
      0, 0, constrained_monitor);
  assert(initial.x == 0 && initial.y == 0);
  assert(initial.width == 1024 && initial.height == 728);
  std::cout << "8 window geometry cases passed\n";
}

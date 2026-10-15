// Standalone clock/file probe. Does not load Flutter, app state, or networking.
#include "windows/runner/startup_trace.h"

int main() {
  niran::TraceNativeStartup("probe_started");
  niran::TraceNativeStartup("probe_finished");
  return 0;
}

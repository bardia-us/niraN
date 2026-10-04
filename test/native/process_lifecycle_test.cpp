#include "windows/xray/xray_process_manager.h"

#include <atomic>
#include <cstdio>
#include <thread>
#include <vector>

// Isolated helper child: no proxy, routing, network, or user configuration.
int wmain(int argc, wchar_t**) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  if (argc > 1) {
    SetConsoleCtrlHandler(nullptr, TRUE);
    Sleep(30000);
    return 0;
  }
  wchar_t executable[MAX_PATH]{};
  wchar_t directory[MAX_PATH]{};
  wchar_t config[MAX_PATH]{};
  GetModuleFileNameW(nullptr, executable, MAX_PATH);
  GetTempPathW(MAX_PATH, directory);
  GetTempFileNameW(directory, L"npt", 0, config);
  int result = 0;
  for (int round = 0; round < 6; ++round) {
    niran::XrayProcessManager manager;
    std::wstring error;
    if (!manager.Start(executable, config, &error, L"Lifecycle test helper")) {
      std::fwprintf(stderr, L"Start failed: %ls\n", error.c_str());
      result = 1;
      break;
    }
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::atomic<bool> failed{false};
    std::vector<std::thread> callers;
    for (int index = 0; index < 4; ++index) {
      callers.emplace_back([&] {
        ++ready;
        while (!go.load()) std::this_thread::yield();
        std::wstring detail;
        if (!manager.Stop(&detail)) failed = true;
      });
    }
    while (ready.load() != 4) std::this_thread::yield();
    go = true;
    for (auto& caller : callers) caller.join();
    if (failed.load() || manager.IsRunning()) {
      std::fprintf(stderr, "Concurrent stop failed at round %d\n", round);
      result = 1;
      break;
    }
  }
  DeleteFileW(config);
  if (result == 0) std::puts("Concurrent native lifecycle: 6 rounds passed");
  return result;
}

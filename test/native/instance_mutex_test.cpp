#define NOMINMAX
#include <windows.h>
#include <cstdio>
#include <string>
#include "../../windows/runner/instance_mutex.h"

int wmain(int argc, wchar_t** argv) {
  if (argc == 3) {
    HANDLE owner = CreateMutexW(nullptr, TRUE, argv[1]);
    HANDLE ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, argv[2]);
    if (!owner || !ready) return 2;
    SetEvent(ready);
    Sleep(INFINITE); // Only this disposable child is terminated by the test.
    return 3;
  }
  const std::wstring name = L"Local\\niran-fixture-" + std::to_wstring(GetCurrentProcessId());
  const std::wstring signal = name + L"-ready";
  HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, signal.c_str());
  wchar_t executable[MAX_PATH]{};
  GetModuleFileNameW(nullptr, executable, MAX_PATH);
  std::wstring command = L"\"" + std::wstring(executable) + L"\" \"" + name + L"\" \"" + signal + L"\"";
  STARTUPINFOW startup{sizeof(startup)};
  PROCESS_INFORMATION child{};
  if (!CreateProcessW(executable, command.data(), nullptr, nullptr, FALSE,
      CREATE_NO_WINDOW, nullptr, nullptr, &startup, &child)) return 2;
  const DWORD signaled = WaitForSingleObject(ready, 3000);
  HANDLE retained = OpenMutexW(SYNCHRONIZE, FALSE, name.c_str());
  HANDLE duplicate = niran::AcquireInstanceMutex(name.c_str());
  const bool rejected_live_owner = duplicate == nullptr;
  if (duplicate) { ReleaseMutex(duplicate); CloseHandle(duplicate); }
  // Exact disposable fixture process, never niraN, a core, or user state.
  TerminateProcess(child.hProcess, 0);
  WaitForSingleObject(child.hProcess, 3000);
  HANDLE recovered = niran::AcquireInstanceMutex(name.c_str());
  const bool recovered_owner = recovered != nullptr;
  if (recovered) { ReleaseMutex(recovered); CloseHandle(recovered); }
  if (retained) CloseHandle(retained);
  CloseHandle(child.hThread);
  CloseHandle(child.hProcess);
  CloseHandle(ready);
  if (signaled != WAIT_OBJECT_0 || !retained) return 2;
  if (!rejected_live_owner || !recovered_owner) {
    std::fprintf(stderr, "FAIL live-owner rejected=%d; terminated-owner recovered=%d\n",
        rejected_live_owner, recovered_owner);
    return 1;
  }
  std::puts("PASS live duplicate rejected; terminated owner recovered");
  return 0;
}

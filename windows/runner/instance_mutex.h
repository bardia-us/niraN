#ifndef RUNNER_INSTANCE_MUTEX_H_
#define RUNNER_INSTANCE_MUTEX_H_
#include <windows.h>

namespace niran {
// Acquire ownership, not just a named object. An observer may retain a handle
// after the previous process was terminated; the resulting mutex is abandoned.
inline HANDLE AcquireInstanceMutex(const wchar_t* name) {
  HANDLE mutex = CreateMutexW(nullptr, FALSE, name);
  if (mutex == nullptr) return nullptr;
  const DWORD acquired = WaitForSingleObject(mutex, 0);
  if (acquired == WAIT_OBJECT_0 || acquired == WAIT_ABANDONED) return mutex;
  CloseHandle(mutex);
  return nullptr;
}
}  // namespace niran
#endif

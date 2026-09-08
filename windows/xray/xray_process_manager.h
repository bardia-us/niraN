#ifndef RUNNER_XRAY_XRAY_PROCESS_MANAGER_H_
#define RUNNER_XRAY_XRAY_PROCESS_MANAGER_H_

#include <windows.h>

#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace niran {

class XrayProcessManager {
 public:
  XrayProcessManager() = default;
  ~XrayProcessManager();

  bool Start(const std::wstring& executable, const std::wstring& config_path,
             std::wstring* error,
             const std::wstring& process_label = L"Xray");
  bool Stop(std::wstring* error);
  bool IsRunning();
  DWORD ExitCode();
  std::vector<std::string> DrainLogs();

 private:
  void ReadOutput(HANDLE pipe);
  bool RequestGracefulStop(DWORD process_id, HANDLE process);
  void CloseHandles();

  std::mutex mutex_;
  HANDLE process_ = nullptr;
  HANDLE job_ = nullptr;
  HANDLE output_read_ = nullptr;
  DWORD process_id_ = 0;
  DWORD exit_code_ = 0;
  std::thread output_thread_;
  std::vector<std::string> pending_logs_;
};

}  // namespace niran

#endif  // RUNNER_XRAY_XRAY_PROCESS_MANAGER_H_

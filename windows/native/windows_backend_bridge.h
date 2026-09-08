#ifndef RUNNER_NATIVE_WINDOWS_BACKEND_BRIDGE_H_
#define RUNNER_NATIVE_WINDOWS_BACKEND_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "windows/proxy/system_proxy_manager.h"
#include "windows/xray/xray_process_manager.h"

namespace niran {

class WindowsBackendBridge {
 public:
  static constexpr UINT kAsyncCompletionMessage = WM_APP + 42;
  static constexpr UINT kExitApplicationMessage = WM_APP + 43;

  WindowsBackendBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~WindowsBackendBridge();

  void Shutdown();
  bool HandleAsyncCompletion(LPARAM lparam);
  void RequestTrayAction(const std::string& action);
  bool IsCoreRunning();
  bool IsTunRunning() const;
  SystemProxyState ProxyState();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void RunProcessOperation(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
      std::string error_code,
      std::function<bool(std::wstring*)> operation);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  XrayProcessManager xray_;
  XrayProcessManager singbox_tun_;
  XrayProcessManager speedtest_xray_;
  SystemProxyManager proxy_;
  std::mutex shutdown_mutex_;
  bool shutdown_ = false;
  bool startup_proxy_recovered_ = false;
  std::wstring startup_proxy_error_;
  HWND window_ = nullptr;
  std::vector<std::thread> workers_;
  std::atomic_bool tun_running_ = false;
  unsigned short local_http_port_ = 10809;
};

}  // namespace niran

#endif  // RUNNER_NATIVE_WINDOWS_BACKEND_BRIDGE_H_

#ifndef RUNNER_PROXY_SYSTEM_PROXY_MANAGER_H_
#define RUNNER_PROXY_SYSTEM_PROXY_MANAGER_H_

#include <string>

namespace niran {

enum class SystemProxyState { kClear, kNiran, kOther };

// Owns the per-user WinINet/System Proxy lease. The original settings are
// persisted before any change so the next launch can recover after a crash.
class SystemProxyManager {
 public:
  SystemProxyManager() = default;
  ~SystemProxyManager() = default;

  bool Enable(unsigned short http_port, std::wstring* error);
  bool Disable(std::wstring* error);
  bool Clear(std::wstring* error);
  bool RecoverStale(std::wstring* error);
  bool IsManaged() const;
  bool QueryState(unsigned short http_port, SystemProxyState* state,
                  std::wstring* error) const;

 private:
  struct Settings {
    unsigned long flags = 0;
    std::wstring proxy_server;
    std::wstring proxy_bypass;
    std::wstring auto_config_url;
  };

  bool QueryCurrent(Settings* settings, std::wstring* error) const;
  bool Apply(const Settings& settings, std::wstring* error) const;
  bool SaveBackup(const Settings& settings, std::wstring* error) const;
  bool LoadBackup(Settings* settings, std::wstring* error) const;
  bool ClearBackup(std::wstring* error) const;
};

}  // namespace niran

#endif  // RUNNER_PROXY_SYSTEM_PROXY_MANAGER_H_

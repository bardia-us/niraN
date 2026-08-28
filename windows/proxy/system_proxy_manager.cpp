#include "windows/proxy/system_proxy_manager.h"

#include <windows.h>
#include <wininet.h>

#include <array>
#include <string>
#include <vector>

namespace niran {
namespace {

constexpr wchar_t kBackupKey[] = L"Software\\niraN\\ProxyBackup";
constexpr wchar_t kActiveValue[] = L"Active";
constexpr wchar_t kFlagsValue[] = L"Flags";
constexpr wchar_t kServerValue[] = L"ProxyServer";
constexpr wchar_t kBypassValue[] = L"ProxyBypass";
constexpr wchar_t kAutoConfigValue[] = L"AutoConfigUrl";

void SetError(std::wstring* error, const wchar_t* operation, DWORD code) {
  if (error != nullptr) {
    *error = std::wstring(operation) + L" failed (" + std::to_wstring(code) +
             L")";
  }
}

bool WriteDword(HKEY key, const wchar_t* name, DWORD value) {
  return RegSetValueExW(key, name, 0, REG_DWORD,
                        reinterpret_cast<const BYTE*>(&value), sizeof(value)) ==
         ERROR_SUCCESS;
}

bool WriteString(HKEY key, const wchar_t* name, const std::wstring& value) {
  const DWORD size = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  return RegSetValueExW(key, name, 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(value.c_str()), size) ==
         ERROR_SUCCESS;
}

bool ReadDword(HKEY key, const wchar_t* name, DWORD* value) {
  DWORD size = sizeof(*value);
  DWORD type = 0;
  return RegQueryValueExW(key, name, nullptr, &type,
                          reinterpret_cast<BYTE*>(value), &size) ==
             ERROR_SUCCESS &&
         type == REG_DWORD;
}

bool ReadString(HKEY key, const wchar_t* name, std::wstring* value) {
  DWORD size = 0;
  DWORD type = 0;
  if (RegQueryValueExW(key, name, nullptr, &type, nullptr, &size) !=
          ERROR_SUCCESS ||
      (type != REG_SZ && type != REG_EXPAND_SZ)) {
    return false;
  }
  std::vector<wchar_t> buffer((size / sizeof(wchar_t)) + 1, L'\0');
  if (RegQueryValueExW(key, name, nullptr, nullptr,
                       reinterpret_cast<BYTE*>(buffer.data()), &size) !=
      ERROR_SUCCESS) {
    return false;
  }
  *value = buffer.data();
  return true;
}

std::wstring CopyAndFree(LPWSTR value) {
  const std::wstring result = value == nullptr ? L"" : value;
  if (value != nullptr) {
    GlobalFree(value);
  }
  return result;
}

}  // namespace

bool SystemProxyManager::Enable(unsigned short http_port,
                                std::wstring* error) {
  if (http_port == 0) {
    if (error != nullptr) {
      *error = L"The HTTP proxy port is invalid";
    }
    return false;
  }

  if (!IsManaged()) {
    Settings current;
    if (!QueryCurrent(&current, error) || !SaveBackup(current, error)) {
      return false;
    }
  }

  const std::wstring endpoint =
      L"127.0.0.1:" + std::to_wstring(http_port);
  Settings desired;
  desired.flags = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;
  desired.proxy_server = L"http=" + endpoint + L";https=" + endpoint;
  desired.proxy_bypass = L"<local>;localhost;127.*;[::1]";
  desired.auto_config_url.clear();
  return Apply(desired, error);
}

bool SystemProxyManager::Disable(std::wstring* error) {
  if (!IsManaged()) {
    return true;
  }
  Settings backup;
  if (!LoadBackup(&backup, error) || !Apply(backup, error)) {
    return false;
  }
  return ClearBackup(error);
}

bool SystemProxyManager::Clear(std::wstring* error) {
  Settings direct;
  direct.flags = PROXY_TYPE_DIRECT;
  if (!Apply(direct, error)) return false;
  return ClearBackup(error);
}

bool SystemProxyManager::RecoverStale(std::wstring* error) {
  return IsManaged() ? Disable(error) : false;
}

bool SystemProxyManager::IsManaged() const {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kBackupKey, 0, KEY_QUERY_VALUE, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  DWORD active = 0;
  const bool result = ReadDword(key, kActiveValue, &active) && active == 1;
  RegCloseKey(key);
  return result;
}

bool SystemProxyManager::QueryState(unsigned short http_port,
                                    SystemProxyState* state,
                                    std::wstring* error) const {
  Settings current;
  if (!QueryCurrent(&current, error)) {
    return false;
  }
  const bool proxy_enabled = (current.flags & PROXY_TYPE_PROXY) != 0;
  const bool auto_proxy_enabled =
      (current.flags & PROXY_TYPE_AUTO_PROXY_URL) != 0 ||
      !current.auto_config_url.empty();
  if (!proxy_enabled && !auto_proxy_enabled) {
    *state = SystemProxyState::kClear;
    return true;
  }
  const std::wstring endpoint =
      L"127.0.0.1:" + std::to_wstring(http_port);
  *state = proxy_enabled && current.proxy_server.find(endpoint) !=
                                std::wstring::npos
               ? SystemProxyState::kNiran
               : SystemProxyState::kOther;
  return true;
}

bool SystemProxyManager::QueryCurrent(Settings* settings,
                                      std::wstring* error) const {
  std::array<INTERNET_PER_CONN_OPTION, 4> options{};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS_UI;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;

  INTERNET_PER_CONN_OPTION_LIST list{};
  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();
  DWORD size = sizeof(list);
  const BOOL queried = InternetQueryOptionW(
      nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, &size);
  if (!queried) {
    const DWORD code = GetLastError();
    for (size_t index = 1; index < options.size(); ++index) {
      if (options[index].Value.pszValue != nullptr) {
        GlobalFree(options[index].Value.pszValue);
      }
    }
    SetError(error, L"Reading Windows proxy settings", code);
    return false;
  }

  settings->flags = options[0].Value.dwValue;
  settings->proxy_server = CopyAndFree(options[1].Value.pszValue);
  settings->proxy_bypass = CopyAndFree(options[2].Value.pszValue);
  settings->auto_config_url = CopyAndFree(options[3].Value.pszValue);
  return true;
}

bool SystemProxyManager::Apply(const Settings& settings,
                               std::wstring* error) const {
  std::array<INTERNET_PER_CONN_OPTION, 4> options{};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS_UI;
  options[0].Value.dwValue = settings.flags;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue =
      const_cast<LPWSTR>(settings.proxy_server.c_str());
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue =
      const_cast<LPWSTR>(settings.proxy_bypass.c_str());
  options[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
  options[3].Value.pszValue =
      const_cast<LPWSTR>(settings.auto_config_url.c_str());

  INTERNET_PER_CONN_OPTION_LIST list{};
  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();
  if (!InternetSetOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION,
                          &list, sizeof(list))) {
    SetError(error, L"Updating Windows proxy settings", GetLastError());
    return false;
  }
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
  return true;
}

bool SystemProxyManager::SaveBackup(const Settings& settings,
                                    std::wstring* error) const {
  HKEY key = nullptr;
  DWORD disposition = 0;
  const LSTATUS opened = RegCreateKeyExW(
      HKEY_CURRENT_USER, kBackupKey, 0, nullptr, REG_OPTION_NON_VOLATILE,
      KEY_SET_VALUE, nullptr, &key, &disposition);
  if (opened != ERROR_SUCCESS) {
    SetError(error, L"Creating proxy recovery data", opened);
    return false;
  }
  const bool saved =
      WriteDword(key, kFlagsValue, settings.flags) &&
      WriteString(key, kServerValue, settings.proxy_server) &&
      WriteString(key, kBypassValue, settings.proxy_bypass) &&
      WriteString(key, kAutoConfigValue, settings.auto_config_url) &&
      WriteDword(key, kActiveValue, 1);
  if (saved) {
    RegFlushKey(key);
  } else {
    SetError(error, L"Saving proxy recovery data", GetLastError());
  }
  RegCloseKey(key);
  return saved;
}

bool SystemProxyManager::LoadBackup(Settings* settings,
                                    std::wstring* error) const {
  HKEY key = nullptr;
  const LSTATUS opened = RegOpenKeyExW(HKEY_CURRENT_USER, kBackupKey, 0,
                                       KEY_QUERY_VALUE, &key);
  if (opened != ERROR_SUCCESS) {
    SetError(error, L"Opening proxy recovery data", opened);
    return false;
  }
  DWORD flags = 0;
  const bool loaded = ReadDword(key, kFlagsValue, &flags) &&
                      ReadString(key, kServerValue, &settings->proxy_server) &&
                      ReadString(key, kBypassValue, &settings->proxy_bypass) &&
                      ReadString(key, kAutoConfigValue,
                                 &settings->auto_config_url);
  settings->flags = flags;
  if (!loaded) {
    SetError(error, L"Reading proxy recovery data", GetLastError());
  }
  RegCloseKey(key);
  return loaded;
}

bool SystemProxyManager::ClearBackup(std::wstring* error) const {
  const LSTATUS removed = RegDeleteTreeW(HKEY_CURRENT_USER, kBackupKey);
  if (removed == ERROR_SUCCESS || removed == ERROR_FILE_NOT_FOUND) {
    return true;
  }
  SetError(error, L"Clearing proxy recovery data", removed);
  return false;
}

}  // namespace niran

#include "windows/native/windows_backend_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windows.h>

#include <algorithm>
#include <memory>
#include <string>
#include <utility>

#include "private_config.h"

namespace niran {
namespace {

struct AsyncCompletion {
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
  bool success = false;
  std::string error_code;
  std::string error_message;
};

std::string Utf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                         static_cast<int>(value.size()), nullptr,
                                         0, nullptr, nullptr);
  if (length <= 0) return {};
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), length,
                      nullptr, nullptr);
  return result;
}

std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         value.c_str(),
                                         static_cast<int>(value.size()), nullptr,
                                         0);
  if (length <= 0) return {};
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}

std::wstring ExecutableDirectory() {
  std::wstring path(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                          static_cast<DWORD>(path.size()));
  if (length == 0 || static_cast<size_t>(length) >= path.size()) return {};
  path.resize(length);
  const size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? L"" : path.substr(0, separator);
}

const flutter::EncodableValue* Argument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) return nullptr;
  const auto found = arguments->find(flutter::EncodableValue(key));
  return found == arguments->end() ? nullptr : &found->second;
}

std::string StringArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key) {
  const flutter::EncodableValue* value = Argument(call, key);
  const auto* string =
      value == nullptr ? nullptr : std::get_if<std::string>(value);
  return string == nullptr ? "" : *string;
}

int IntegerArgument(const flutter::MethodCall<flutter::EncodableValue>& call,
                    const char* key) {
  const flutter::EncodableValue* value = Argument(call, key);
  if (value == nullptr) return 0;
  if (const auto* number = std::get_if<int32_t>(value)) return *number;
  if (const auto* number = std::get_if<int64_t>(value)) {
    return static_cast<int>(*number);
  }
  return 0;
}

bool BoolArgument(const flutter::MethodCall<flutter::EncodableValue>& call,
                  const char* key) {
  const flutter::EncodableValue* value = Argument(call, key);
  const auto* boolean =
      value == nullptr ? nullptr : std::get_if<bool>(value);
  return boolean != nullptr && *boolean;
}

bool IsProcessElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  TOKEN_ELEVATION elevation{};
  DWORD size = 0;
  const BOOL queried = GetTokenInformation(
      token, TokenElevation, &elevation, sizeof(elevation), &size);
  CloseHandle(token);
  return queried && elevation.TokenIsElevated != 0;
}

}  // namespace

WindowsBackendBridge::WindowsBackendBridge(flutter::BinaryMessenger* messenger,
                                           HWND window)
    : window_(window) {
  if (proxy_.IsManaged()) {
    startup_proxy_recovered_ = proxy_.RecoverStale(&startup_proxy_error_);
  }
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "dev.niran.windows/host",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

WindowsBackendBridge::~WindowsBackendBridge() {
  Shutdown();
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

void WindowsBackendBridge::Shutdown() {
  std::scoped_lock lock(shutdown_mutex_);
  if (shutdown_) return;
  for (auto& worker : workers_) {
    if (worker.joinable()) worker.join();
  }
  workers_.clear();
  std::wstring ignored;
  proxy_.Disable(&ignored);
  speedtest_xray_.Stop(&ignored);
  xray_.Stop(&ignored);
  shutdown_ = true;
}

void WindowsBackendBridge::RunProcessOperation(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    std::string error_code,
    std::function<bool(std::wstring*)> operation) {
  workers_.emplace_back(
      [window = window_, result = std::move(result),
       error_code = std::move(error_code),
       operation = std::move(operation)]() mutable {
        std::wstring error;
        auto* completion = new AsyncCompletion{
            std::move(result), operation(&error), std::move(error_code),
            Utf8(error)};
        if (!PostMessageW(window, kAsyncCompletionMessage, 0,
                          reinterpret_cast<LPARAM>(completion))) {
          delete completion;
        }
      });
}

bool WindowsBackendBridge::HandleAsyncCompletion(LPARAM lparam) {
  auto* completion = reinterpret_cast<AsyncCompletion*>(lparam);
  if (completion == nullptr) return false;
  std::unique_ptr<AsyncCompletion> owned(completion);
  if (owned->success) {
    owned->result->Success(flutter::EncodableValue(true));
  } else {
    owned->result->Error(owned->error_code, owned->error_message);
  }
  return true;
}

void WindowsBackendBridge::RequestTrayAction(const std::string& action) {
  if (!channel_) return;
  channel_->InvokeMethod(
      "trayAction", std::make_unique<flutter::EncodableValue>(action));
}

bool WindowsBackendBridge::IsCoreRunning() { return xray_.IsRunning(); }

bool WindowsBackendBridge::IsTunRunning() const { return tun_running_.load(); }

SystemProxyState WindowsBackendBridge::ProxyState() {
  SystemProxyState state = SystemProxyState::kOther;
  std::wstring ignored;
  proxy_.QueryState(local_http_port_, &state, &ignored);
  return state;
}

void WindowsBackendBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "getBuildConfig") {
    flutter::EncodableMap values;
    values[flutter::EncodableValue("subscriptionUrl")] =
        flutter::EncodableValue(Utf8(private_config::kSubscriptionUrl));
    values[flutter::EncodableValue("telegramUrl")] =
        flutter::EncodableValue(Utf8(private_config::kTelegramUrl));
    values[flutter::EncodableValue("telegramContact")] =
        flutter::EncodableValue(Utf8(private_config::kTelegramContact));
    values[flutter::EncodableValue("appVersion")] =
        flutter::EncodableValue(FLUTTER_VERSION);
    result->Success(flutter::EncodableValue(values));
    return;
  }
  if (method == "validateTunPrerequisites") {
    if (!IsProcessElevated()) {
      result->Error(
          "tun_privilege",
          "TUN mode requires administrator privileges. Restart niraN as administrator.");
      return;
    }
    if (GetFileAttributesW((ExecutableDirectory() + L"\\xray\\wintun.dll").c_str()) ==
        INVALID_FILE_ATTRIBUTES) {
      result->Error("tun_driver", "Bundled wintun.dll is missing");
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "startXray") {
    const std::wstring config = Wide(StringArgument(call, "configPath"));
    const std::wstring executable = ExecutableDirectory() + L"\\xray\\xray.exe";
    const bool tun_mode = BoolArgument(call, "tunMode");
    if (config.empty()) {
      result->Error("invalid_config", "Generated Xray config path is invalid");
      return;
    }
    if (tun_mode && !IsProcessElevated()) {
      result->Error(
          "tun_privilege",
          "TUN mode requires administrator privileges. Restart niraN as administrator.");
      return;
    }
    if (tun_mode &&
        GetFileAttributesW((ExecutableDirectory() + L"\\xray\\wintun.dll").c_str()) ==
            INVALID_FILE_ATTRIBUTES) {
      result->Error("tun_driver", "Bundled wintun.dll is missing");
      return;
    }
    RunProcessOperation(
        std::move(result), "xray_start",
        [this, executable, config, tun_mode](std::wstring* error) {
          const bool started = xray_.Start(executable, config, error);
          tun_running_.store(started && tun_mode);
          return started;
        });
    return;
  }
  if (method == "stopXray") {
    RunProcessOperation(std::move(result), "xray_stop",
                        [this](std::wstring* error) {
                          const bool stopped = xray_.Stop(error);
                          if (stopped) tun_running_.store(false);
                          return stopped;
                        });
    return;
  }
  if (method == "startSpeedtestXray") {
    const std::wstring config = Wide(StringArgument(call, "configPath"));
    const std::wstring executable = ExecutableDirectory() + L"\\xray\\xray.exe";
    if (config.empty()) {
      result->Error("invalid_config", "Speed-test config path is invalid");
      return;
    }
    RunProcessOperation(
        std::move(result), "xray_speedtest_start",
        [this, executable, config](std::wstring* error) {
          return speedtest_xray_.Start(executable, config, error);
        });
    return;
  }
  if (method == "stopSpeedtestXray") {
    RunProcessOperation(std::move(result), "xray_speedtest_stop",
                        [this](std::wstring* error) {
                          return speedtest_xray_.Stop(error);
                        });
    return;
  }
  if (method == "getXrayStatus") {
    const bool running = xray_.IsRunning();
    flutter::EncodableMap status;
    status[flutter::EncodableValue("running")] =
        flutter::EncodableValue(running);
    status[flutter::EncodableValue("exitCode")] = running
        ? flutter::EncodableValue()
        : flutter::EncodableValue(
              static_cast<int64_t>(static_cast<int32_t>(xray_.ExitCode())));
    result->Success(flutter::EncodableValue(status));
    return;
  }
  if (method == "drainXrayLogs") {
    flutter::EncodableList lines;
    for (std::string& line : xray_.DrainLogs()) {
      lines.emplace_back(std::move(line));
    }
    result->Success(flutter::EncodableValue(lines));
    return;
  }
  if (method == "getXrayVersion") {
    result->Success(
        flutter::EncodableValue(Utf8(private_config::kXrayVersion)));
    return;
  }
  if (method == "enableSystemProxy") {
    const int port = IntegerArgument(call, "httpPort");
    if (port < 1 || port > 65535) {
      result->Error("proxy", "The System Proxy port is invalid");
      return;
    }
    local_http_port_ = static_cast<unsigned short>(port);
    std::wstring error;
    if (!proxy_.Enable(static_cast<unsigned short>(port), &error)) {
      result->Error("proxy", Utf8(error));
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "disableSystemProxy") {
    std::wstring error;
    if (!proxy_.Disable(&error)) {
      result->Error("proxy_restore", Utf8(error));
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "clearSystemProxy") {
    std::wstring error;
    if (!proxy_.Clear(&error)) {
      result->Error("proxy_clear", Utf8(error));
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "getSystemProxyState") {
    const int port = IntegerArgument(call, "httpPort");
    if (port < 1 || port > 65535) {
      result->Error("proxy", "The System Proxy port is invalid");
      return;
    }
    local_http_port_ = static_cast<unsigned short>(port);
    SystemProxyState state = SystemProxyState::kOther;
    std::wstring error;
    if (!proxy_.QueryState(static_cast<unsigned short>(port), &state, &error)) {
      result->Error("proxy_query", Utf8(error));
      return;
    }
    const char* value = state == SystemProxyState::kNiran
                            ? "niran"
                            : state == SystemProxyState::kClear ? "clear"
                                                               : "other";
    result->Success(flutter::EncodableValue(value));
    return;
  }
  if (method == "recoverSystemProxy") {
    if (!startup_proxy_error_.empty()) {
      result->Error("proxy_recovery", Utf8(startup_proxy_error_));
      startup_proxy_error_.clear();
      return;
    }
    if (startup_proxy_recovered_) {
      startup_proxy_recovered_ = false;
      result->Success(flutter::EncodableValue(true));
      return;
    }
    const bool was_managed = proxy_.IsManaged();
    std::wstring error;
    if (was_managed && !proxy_.RecoverStale(&error)) {
      result->Error("proxy_recovery", Utf8(error));
      return;
    }
    result->Success(flutter::EncodableValue(was_managed));
    return;
  }
  if (method == "openExternalUrl") {
    const std::wstring url = Wide(StringArgument(call, "url"));
    if (url.empty()) {
      result->Error("invalid_url", "The URL is invalid");
      return;
    }
    const HINSTANCE opened = ShellExecuteW(nullptr, L"open", url.c_str(),
                                           nullptr, nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(opened) <= 32) {
      result->Error("unavailable", "Windows could not open this link");
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }
  result->NotImplemented();
}

}  // namespace niran

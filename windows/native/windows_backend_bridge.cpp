#ifndef SECURITY_WIN32
#define SECURITY_WIN32
#endif

#include "windows/native/windows_backend_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windows.h>
#include <security.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.System.Profile.h>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <lmcons.h>
#include <memory>
#include <sstream>
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

std::string RuntimeCoreVersion(const std::wstring& relative_executable,
                               const std::string& marker,
                               bool prepend_v,
                               const std::wstring& core_name,
                               std::wstring* error) {
  const std::wstring executable = ExecutableDirectory() + relative_executable;
  if (GetFileAttributesW(executable.c_str()) == INVALID_FILE_ATTRIBUTES) {
    if (error != nullptr) *error = L"Bundled " + core_name + L" is missing";
    return {};
  }

  SECURITY_ATTRIBUTES security{};
  security.nLength = sizeof(security);
  security.bInheritHandle = TRUE;
  HANDLE read_pipe = nullptr;
  HANDLE write_pipe = nullptr;
  if (!CreatePipe(&read_pipe, &write_pipe, &security, 0) ||
      !SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0)) {
    if (read_pipe != nullptr) CloseHandle(read_pipe);
    if (write_pipe != nullptr) CloseHandle(write_pipe);
    if (error != nullptr) *error = L"Could not create Core version pipe";
    return {};
  }

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  startup.hStdOutput = write_pipe;
  startup.hStdError = write_pipe;
  PROCESS_INFORMATION process{};
  std::wstring command = L"\"" + executable + L"\" version";
  const BOOL started = CreateProcessW(
      executable.c_str(), command.data(), nullptr, nullptr, TRUE,
      CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, nullptr,
      ExecutableDirectory().c_str(), &startup, &process);
  CloseHandle(write_pipe);
  if (!started) {
    CloseHandle(read_pipe);
    if (error != nullptr) {
      *error = L"Could not execute the bundled " + core_name;
    }
    return {};
  }

  const DWORD wait = WaitForSingleObject(process.hProcess, 3000);
  if (wait == WAIT_TIMEOUT) TerminateProcess(process.hProcess, 1);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);

  std::string output;
  std::array<char, 512> buffer{};
  DWORD bytes_read = 0;
  while (ReadFile(read_pipe, buffer.data(), static_cast<DWORD>(buffer.size()),
                  &bytes_read, nullptr) &&
         bytes_read != 0) {
    output.append(buffer.data(), bytes_read);
  }
  CloseHandle(read_pipe);
  if (wait != WAIT_OBJECT_0) {
    if (error != nullptr) *error = core_name + L" version check timed out";
    return {};
  }

  const size_t marker_offset = output.find(marker);
  if (marker_offset == std::string::npos) {
    if (error != nullptr) *error = core_name + L" returned an unknown version";
    return {};
  }
  const size_t begin = marker_offset + marker.size();
  const size_t end = output.find_first_of(" \t\r\n", begin);
  std::string version = output.substr(begin, end - begin);
  if (prepend_v && !version.empty() && version.front() != 'v') {
    version.insert(0, "v");
  }
  return version;
}

std::string RuntimeXrayVersion(std::wstring* error) {
  return RuntimeCoreVersion(L"\\xray\\xray.exe", "Xray ", true,
                            L"Xray Core", error);
}

std::string RuntimeSingBoxVersion(std::wstring* error) {
  return RuntimeCoreVersion(L"\\sing-box\\sing-box.exe", "sing-box version ",
                            false, L"sing-box", error);
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

std::wstring RegistryString(HKEY root, const wchar_t* path,
                            const wchar_t* name) {
  DWORD size = 0;
  const LSTATUS measured = RegGetValueW(root, path, name, RRF_RT_REG_SZ,
                                        nullptr, nullptr, &size);
  if (measured != ERROR_SUCCESS || size < sizeof(wchar_t)) return {};
  std::wstring value(size / sizeof(wchar_t), L'\0');
  if (RegGetValueW(root, path, name, RRF_RT_REG_SZ, nullptr, value.data(),
                   &size) != ERROR_SUCCESS) {
    return {};
  }
  while (!value.empty() && value.back() == L'\0') value.pop_back();
  return value;
}

DWORD RegistryDword(HKEY root, const wchar_t* path, const wchar_t* name) {
  DWORD value = 0;
  DWORD size = sizeof(value);
  if (RegGetValueW(root, path, name, RRF_RT_REG_DWORD, nullptr, &value,
                   &size) != ERROR_SUCCESS) {
    return 0;
  }
  return value;
}

std::wstring DeviceName() {
  DWORD size = 0;
  GetComputerNameExW(ComputerNamePhysicalDnsHostname, nullptr, &size);
  if (size != 0) {
    std::wstring value(static_cast<size_t>(size), L'\0');
    if (GetComputerNameExW(ComputerNamePhysicalDnsHostname, value.data(),
                           &size)) {
      value.resize(size);
      return value;
    }
  }
  wchar_t fallback[MAX_COMPUTERNAME_LENGTH + 1]{};
  size = MAX_COMPUTERNAME_LENGTH + 1;
  if (GetComputerNameW(fallback, &size)) return std::wstring(fallback, size);
  return L"Windows PC";
}

std::wstring WindowsUserName() {
  ULONG size = 0;
  GetUserNameExW(NameDisplay, nullptr, &size);
  if (size != 0) {
    std::wstring value(static_cast<size_t>(size), L'\0');
    if (GetUserNameExW(NameDisplay, value.data(), &size)) {
      while (!value.empty() && value.back() == L'\0') value.pop_back();
      if (!value.empty()) return value;
    }
  }
  wchar_t fallback[UNLEN + 1]{};
  DWORD fallback_size = UNLEN + 1;
  if (GetUserNameW(fallback, &fallback_size) && fallback_size > 0) {
    return std::wstring(fallback, fallback_size - 1);
  }
  return L"Unknown user";
}

std::wstring WindowsVersion() {
  constexpr wchar_t kWindowsPath[] =
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";
  std::wstring product =
      RegistryString(HKEY_LOCAL_MACHINE, kWindowsPath, L"ProductName");
  const std::wstring display =
      RegistryString(HKEY_LOCAL_MACHINE, kWindowsPath, L"DisplayVersion");
  const std::wstring build =
      RegistryString(HKEY_LOCAL_MACHINE, kWindowsPath, L"CurrentBuildNumber");
  const DWORD revision =
      RegistryDword(HKEY_LOCAL_MACHINE, kWindowsPath, L"UBR");
  const unsigned long build_number =
      build.empty() ? 0 : std::wcstoul(build.c_str(), nullptr, 10);
  if (product.find(L"Windows Server") == std::wstring::npos) {
    const wchar_t* detected =
        build_number >= 22000 ? L"Windows 11" : L"Windows 10";
    const size_t edition_separator = product.find(L' ', 8);
    const std::wstring edition = edition_separator == std::wstring::npos
                                     ? L""
                                     : product.substr(edition_separator);
    product = detected + edition;
  }
  std::wostringstream value;
  value << (product.empty() ? L"Windows" : product);
  if (!display.empty()) value << L" " << display;
  if (!build.empty()) {
    value << L" (build " << build;
    if (revision != 0) value << L"." << revision;
    value << L")";
  }
  return value.str();
}

std::pair<std::string, std::string> WindowsPublisherSystemIdentity() {
  try {
    const auto info =
        winrt::Windows::System::Profile::SystemIdentification::
            GetSystemIdForPublisher();
    if (!info || !info.Id()) return {};
    const auto encoded =
        winrt::Windows::Security::Cryptography::CryptographicBuffer::
            EncodeToHexString(info.Id());
    std::string source = "unknown";
    switch (info.Source()) {
      case winrt::Windows::System::Profile::SystemIdentificationSource::Tpm:
        source = "tpm";
        break;
      case winrt::Windows::System::Profile::SystemIdentificationSource::Uefi:
        source = "uefi";
        break;
      case winrt::Windows::System::Profile::SystemIdentificationSource::Registry:
        source = "registry";
        break;
      default:
        break;
    }
    return {Utf8(std::wstring(encoded.c_str(), encoded.size())), source};
  } catch (const winrt::hresult_error&) {
    return {};
  }
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
  singbox_tun_.Stop(&ignored);
  tun_running_.store(false);
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
    values[flutter::EncodableValue("telegramUrl")] =
        flutter::EncodableValue(Utf8(private_config::kTelegramUrl));
    values[flutter::EncodableValue("telegramContact")] =
        flutter::EncodableValue(Utf8(private_config::kTelegramContact));
    values[flutter::EncodableValue("appVersion")] =
        flutter::EncodableValue(FLUTTER_VERSION);
    values[flutter::EncodableValue("expectedCoreVersion")] =
        flutter::EncodableValue(Utf8(private_config::kXrayVersion));
    values[flutter::EncodableValue("expectedSingBoxVersion")] =
        flutter::EncodableValue(Utf8(private_config::kSingBoxVersion));
    result->Success(flutter::EncodableValue(values));
    return;
  }
  if (method == "getDeviceRegistrationInfo") {
    const auto [system_id, system_id_source] =
        WindowsPublisherSystemIdentity();
    flutter::EncodableMap values;
    values[flutter::EncodableValue("deviceName")] =
        flutter::EncodableValue(Utf8(DeviceName()));
    values[flutter::EncodableValue("windowsUsername")] =
        flutter::EncodableValue(Utf8(WindowsUserName()));
    values[flutter::EncodableValue("windowsVersion")] =
        flutter::EncodableValue(Utf8(WindowsVersion()));
    values[flutter::EncodableValue("appVersion")] =
        flutter::EncodableValue(FLUTTER_VERSION);
    values[flutter::EncodableValue("systemId")] =
        flutter::EncodableValue(system_id);
    values[flutter::EncodableValue("systemIdSource")] =
        flutter::EncodableValue(system_id_source);
    result->Success(flutter::EncodableValue(values));
    return;
  }
  if (method == "exitApplication") {
    result->Success();
    PostMessageW(window_, kExitApplicationMessage, 0, 0);
    return;
  }
  if (method == "validateTunPrerequisites") {
    if (!IsProcessElevated()) {
      result->Error(
          "tun_privilege",
          "TUN mode requires administrator privileges. Restart niraN as administrator.");
      return;
    }
    if (GetFileAttributesW(
            (ExecutableDirectory() + L"\\xray\\wintun.dll").c_str()) ==
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
          return xray_.Start(executable, config, error);
        });
    return;
  }
  if (method == "stopXray") {
    RunProcessOperation(std::move(result), "xray_stop",
                        [this](std::wstring* error) {
                          const bool stopped = xray_.Stop(error);
                          return stopped;
                        });
    return;
  }
  if (method == "startTunFrontend") {
    const std::wstring config = Wide(StringArgument(call, "configPath"));
    const std::wstring executable =
        ExecutableDirectory() + L"\\sing-box\\sing-box.exe";
    if (config.empty()) {
      result->Error("invalid_config", "Generated sing-box TUN config path is invalid");
      return;
    }
    if (!IsProcessElevated()) {
      result->Error(
          "tun_privilege",
          "TUN mode requires administrator privileges. Restart niraN as administrator.");
      return;
    }
    RunProcessOperation(
        std::move(result), "tun_startup",
        [this, executable, config](std::wstring* error) {
          const bool started =
              singbox_tun_.Start(executable, config, error, L"sing-box");
          tun_running_.store(started);
          return started;
        });
    return;
  }
  if (method == "stopTunFrontend") {
    RunProcessOperation(std::move(result), "tun_stop",
                        [this](std::wstring* error) {
                          const bool stopped = singbox_tun_.Stop(error);
                          if (stopped) tun_running_.store(false);
                          return stopped;
                        });
    return;
  }
  if (method == "getTunFrontendStatus") {
    const bool running = singbox_tun_.IsRunning();
    flutter::EncodableMap status;
    status[flutter::EncodableValue("running")] =
        flutter::EncodableValue(running);
    status[flutter::EncodableValue("exitCode")] = running
        ? flutter::EncodableValue()
        : flutter::EncodableValue(static_cast<int64_t>(
              static_cast<int32_t>(singbox_tun_.ExitCode())));
    result->Success(flutter::EncodableValue(status));
    return;
  }
  if (method == "drainTunFrontendLogs") {
    flutter::EncodableList lines;
    for (std::string& line : singbox_tun_.DrainLogs()) {
      lines.emplace_back(std::move(line));
    }
    result->Success(flutter::EncodableValue(lines));
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
    std::wstring error;
    const std::string version = RuntimeXrayVersion(&error);
    if (version.empty()) {
      result->Error("core_version", Utf8(error));
      return;
    }
    result->Success(flutter::EncodableValue(version));
    return;
  }
  if (method == "getSingBoxVersion") {
    std::wstring error;
    const std::string version = RuntimeSingBoxVersion(&error);
    if (version.empty()) {
      result->Error("tun_version", Utf8(error));
      return;
    }
    result->Success(flutter::EncodableValue(version));
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

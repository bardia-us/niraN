#include "windows/xray/xray_process_manager.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace niran {
namespace {

std::wstring Quote(const std::wstring& value) {
  std::wstring result = L"\"";
  size_t backslashes = 0;
  for (const wchar_t character : value) {
    if (character == L'\\') {
      ++backslashes;
    } else if (character == L'\"') {
      result.append(backslashes * 2 + 1, L'\\');
      result.push_back(L'\"');
      backslashes = 0;
    } else {
      result.append(backslashes, L'\\');
      backslashes = 0;
      result.push_back(character);
    }
  }
  result.append(backslashes * 2, L'\\');
  result.push_back(L'\"');
  return result;
}

std::wstring ErrorCode(const wchar_t* operation, DWORD code) {
  return std::wstring(operation) + L" failed (" + std::to_wstring(code) + L")";
}

std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}

}  // namespace

XrayProcessManager::~XrayProcessManager() {
  std::wstring ignored;
  Stop(&ignored);
}

bool XrayProcessManager::Start(const std::wstring& executable,
                               const std::wstring& config_path,
                               std::wstring* error) {
  std::wstring stop_error;
  if (!Stop(&stop_error)) {
    if (error != nullptr) {
      *error = L"Unable to stop the previous niraN Xray process: " +
               stop_error;
    }
    return false;
  }

  if (GetFileAttributesW(executable.c_str()) == INVALID_FILE_ATTRIBUTES) {
    if (error != nullptr) {
      *error = L"Bundled xray.exe is missing";
    }
    return false;
  }
  if (GetFileAttributesW(config_path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    if (error != nullptr) {
      *error = L"Generated Xray config is missing";
    }
    return false;
  }

  SECURITY_ATTRIBUTES security{};
  security.nLength = sizeof(security);
  security.bInheritHandle = TRUE;
  HANDLE output_read = nullptr;
  HANDLE output_write = nullptr;
  if (!CreatePipe(&output_read, &output_write, &security, 0) ||
      !SetHandleInformation(output_read, HANDLE_FLAG_INHERIT, 0)) {
    const DWORD code = GetLastError();
    if (output_read != nullptr) CloseHandle(output_read);
    if (output_write != nullptr) CloseHandle(output_write);
    if (error != nullptr) *error = ErrorCode(L"Creating Xray log pipe", code);
    return false;
  }

  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (job == nullptr) {
    const DWORD code = GetLastError();
    CloseHandle(output_read);
    CloseHandle(output_write);
    if (error != nullptr) *error = ErrorCode(L"Creating Xray job", code);
    return false;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                               sizeof(limits))) {
    const DWORD code = GetLastError();
    CloseHandle(job);
    CloseHandle(output_read);
    CloseHandle(output_write);
    if (error != nullptr) *error = ErrorCode(L"Configuring Xray job", code);
    return false;
  }

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  startup.hStdOutput = output_write;
  startup.hStdError = output_write;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  PROCESS_INFORMATION process_info{};
  std::wstring command = Quote(executable) + L" run -c " + Quote(config_path);
  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  const std::wstring working_directory =
      executable.substr(0, executable.find_last_of(L"\\/"));

  const DWORD creation_flags = CREATE_NEW_PROCESS_GROUP | CREATE_NEW_CONSOLE |
                               CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT;
  const BOOL created = CreateProcessW(
      executable.c_str(), mutable_command.data(), nullptr, nullptr, TRUE,
      creation_flags, nullptr, working_directory.c_str(), &startup, &process_info);
  CloseHandle(output_write);
  if (!created) {
    const DWORD code = GetLastError();
    CloseHandle(job);
    CloseHandle(output_read);
    if (error != nullptr) *error = ErrorCode(L"Starting Xray", code);
    return false;
  }

  if (!AssignProcessToJobObject(job, process_info.hProcess)) {
    const DWORD code = GetLastError();
    TerminateProcess(process_info.hProcess, code);
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    CloseHandle(job);
    CloseHandle(output_read);
    if (error != nullptr) *error = ErrorCode(L"Assigning Xray job", code);
    return false;
  }

  {
    std::scoped_lock lock(mutex_);
    process_ = process_info.hProcess;
    job_ = job;
    output_read_ = output_read;
    process_id_ = process_info.dwProcessId;
    exit_code_ = STILL_ACTIVE;
  }
  output_thread_ = std::thread(&XrayProcessManager::ReadOutput, this, output_read);
  ResumeThread(process_info.hThread);
  CloseHandle(process_info.hThread);

  if (WaitForSingleObject(process_info.hProcess, 300) == WAIT_OBJECT_0) {
    const DWORD early_exit = ExitCode();
    std::wstring ignored;
    Stop(&ignored);
    if (error != nullptr) {
      const int32_t normalized_exit = static_cast<int32_t>(early_exit);
      *error = L"Xray exited during startup";
      if (normalized_exit != -1) {
        *error += L" (" + std::to_wstring(normalized_exit) + L")";
      }
      const auto logs = DrainLogs();
      if (!logs.empty()) {
        *error += L": " + Wide(logs.back());
      }
    }
    return false;
  }
  return true;
}

bool XrayProcessManager::Stop(std::wstring* error) {
  HANDLE process = nullptr;
  HANDLE job = nullptr;
  HANDLE output_read = nullptr;
  DWORD process_id = 0;
  {
    std::scoped_lock lock(mutex_);
    process = process_;
    job = job_;
    output_read = output_read_;
    process_id = process_id_;
  }
  if (process == nullptr) {
    if (output_thread_.joinable()) output_thread_.join();
    return true;
  }

  bool stopped = true;
  DWORD code = 0;
  if (GetExitCodeProcess(process, &code) && code == STILL_ACTIVE) {
    RequestGracefulStop(process_id, process);
    if (WaitForSingleObject(process, 700) == WAIT_TIMEOUT) {
      if (!TerminateJobObject(job, ERROR_CANCELLED)) {
        const DWORD terminate_error = GetLastError();
        if (!TerminateProcess(process, ERROR_CANCELLED)) {
          stopped = false;
        }
        if (!stopped && error != nullptr) {
          *error = ErrorCode(L"Stopping Xray", terminate_error);
        }
      }
      WaitForSingleObject(process, 500);
    }
  }
  GetExitCodeProcess(process, &code);
  {
    std::scoped_lock lock(mutex_);
    exit_code_ = code;
  }
  // Never let a synchronous pipe read make Disconnect/Restart or app shutdown
  // wait forever. The child has already been signalled or terminated above.
  if (output_thread_.joinable()) {
    CancelSynchronousIo(output_thread_.native_handle());
    if (output_read != nullptr) {
      CancelIoEx(output_read, nullptr);
      {
        std::scoped_lock lock(mutex_);
        if (output_read_ == output_read) output_read_ = nullptr;
      }
      CloseHandle(output_read);
    }
    output_thread_.join();
  }
  CloseHandles();
  return stopped;
}

bool XrayProcessManager::IsRunning() {
  std::scoped_lock lock(mutex_);
  if (process_ == nullptr) return false;
  DWORD code = 0;
  if (!GetExitCodeProcess(process_, &code)) return false;
  exit_code_ = code;
  return code == STILL_ACTIVE;
}

DWORD XrayProcessManager::ExitCode() {
  std::scoped_lock lock(mutex_);
  if (process_ != nullptr) {
    DWORD code = 0;
    if (GetExitCodeProcess(process_, &code)) exit_code_ = code;
  }
  return exit_code_;
}

std::vector<std::string> XrayProcessManager::DrainLogs() {
  std::scoped_lock lock(mutex_);
  std::vector<std::string> result;
  result.swap(pending_logs_);
  return result;
}

void XrayProcessManager::ReadOutput(HANDLE pipe) {
  std::array<char, 4096> buffer{};
  std::string pending;
  DWORD read = 0;
  while (ReadFile(pipe, buffer.data(), static_cast<DWORD>(buffer.size()), &read,
                  nullptr) &&
         read > 0) {
    pending.append(buffer.data(), read);
    size_t newline = 0;
    while ((newline = pending.find_first_of("\r\n")) != std::string::npos) {
      std::string line = pending.substr(0, newline);
      const size_t remainder = pending.find_first_not_of("\r\n", newline);
      pending = remainder == std::string::npos ? "" : pending.substr(remainder);
      if (line.empty()) continue;
      if (line.size() > 1200) line.resize(1200);
      std::scoped_lock lock(mutex_);
      pending_logs_.push_back(std::move(line));
      if (pending_logs_.size() > 500) {
        pending_logs_.erase(pending_logs_.begin(), pending_logs_.begin() + 100);
      }
    }
  }
  if (!pending.empty()) {
    if (pending.size() > 1200) pending.resize(1200);
    std::scoped_lock lock(mutex_);
    pending_logs_.push_back(std::move(pending));
  }
}

bool XrayProcessManager::RequestGracefulStop(DWORD process_id,
                                             HANDLE process) {
  if (GetConsoleWindow() != nullptr || !AttachConsole(process_id)) {
    return false;
  }
  SetConsoleCtrlHandler(nullptr, TRUE);
  const BOOL sent = GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, process_id);
  FreeConsole();
  SetConsoleCtrlHandler(nullptr, FALSE);
  return sent == TRUE;
}

void XrayProcessManager::CloseHandles() {
  std::scoped_lock lock(mutex_);
  if (output_read_ != nullptr) CloseHandle(output_read_);
  if (process_ != nullptr) CloseHandle(process_);
  if (job_ != nullptr) CloseHandle(job_);
  output_read_ = nullptr;
  process_ = nullptr;
  job_ = nullptr;
  process_id_ = 0;
}

}  // namespace niran

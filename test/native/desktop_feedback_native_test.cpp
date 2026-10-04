#include <windows.h>
#include <mmsystem.h>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <stdexcept>
#include <vector>
#include <flutter/method_result_functions.h>

namespace {
bool play_succeeds = true;
int playback_calls = 0;
const uint8_t* retained_wave = nullptr;
BOOL TestPlaySoundW(LPCWSTR wave, HMODULE, DWORD flags) {
  if (wave == nullptr) return TRUE;
  if ((flags & (SND_MEMORY | SND_ASYNC | SND_NODEFAULT)) !=
      (SND_MEMORY | SND_ASYNC | SND_NODEFAULT))
    throw std::runtime_error("Playback flags changed");
  ++playback_calls;
  retained_wave = reinterpret_cast<const uint8_t*>(wave);
  return play_succeeds ? TRUE : FALSE;
}
}

// Real method handler and Flutter codec; replace only external boundaries.
#define PlaySoundW TestPlaySoundW
#include "windows/native/windows_backend_bridge.cpp"
#undef PlaySoundW

namespace niran {
XrayProcessManager::~XrayProcessManager() = default;
bool XrayProcessManager::Start(const std::wstring&, const std::wstring&,
                               std::wstring*, const std::wstring&) { return false; }
bool XrayProcessManager::Stop(std::wstring*) { return true; }
bool XrayProcessManager::IsRunning() { return false; }
DWORD XrayProcessManager::ExitCode() { return 0; }
std::vector<std::string> XrayProcessManager::DrainLogs() { return {}; }
bool SystemProxyManager::IsManaged() const { return false; }
bool SystemProxyManager::Enable(unsigned short, std::wstring*) { return false; }
bool SystemProxyManager::Disable(std::wstring*) { return true; }
bool SystemProxyManager::Clear(std::wstring*) { return false; }
bool SystemProxyManager::RecoverStale(std::wstring*) { return false; }
bool SystemProxyManager::QueryState(unsigned short, SystemProxyState*,
                                  std::wstring*) const { return false; }
}

class TestMessenger final : public flutter::BinaryMessenger {
 public:
  void Send(const std::string&, const uint8_t*, size_t,
            flutter::BinaryReply = nullptr) const override {}
  void SetMessageHandler(const std::string& name,
                         flutter::BinaryMessageHandler handler) override {
    handlers[name] = std::move(handler);
  }
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
};
struct FeedbackResult { bool success = false; std::string error; };
FeedbackResult Dispatch(TestMessenger& messenger, const std::vector<uint8_t>* wave) {
  const auto& codec = flutter::StandardMethodCodec::GetInstance();
  flutter::EncodableMap args;
  args[flutter::EncodableValue("notification")] = flutter::EncodableValue(false);
  if (wave) args[flutter::EncodableValue("sound")] = flutter::EncodableValue(*wave);
  auto encoded = codec.EncodeMethodCall(flutter::MethodCall<flutter::EncodableValue>(
      "showDesktopFeedback", std::make_unique<flutter::EncodableValue>(args)));
  FeedbackResult outcome;
  flutter::MethodResultFunctions<flutter::EncodableValue> result(
      [&](const flutter::EncodableValue* value) {
        if (value) {
          if (const auto* success = std::get_if<bool>(value)) outcome.success = *success;
        }
      },
      [&](const std::string& code, const std::string&, const flutter::EncodableValue*) {
        outcome.error = code;
      }, [] {});
  messenger.handlers.at("dev.niran.windows/host")(
      encoded->data(), encoded->size(), [&](const uint8_t* reply, size_t size) {
        if (!codec.DecodeAndProcessResponseEnvelope(reply, size, &result))
          throw std::runtime_error("Native result could not be decoded");
      });
  return outcome;
}
void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
void Write32(std::vector<uint8_t>& wave, size_t offset, uint32_t value) {
  for (size_t i = 0; i < 4; ++i) wave[offset + i] = static_cast<uint8_t>(value >> (i * 8));
}
std::vector<uint8_t> ShortMonoWave() {
  std::vector<uint8_t> wave = {
      'R','I','F','F', 0xD0,0x14,0,0, 'W','A','V','E',
      'f','m','t',' ', 16,0,0,0, 1,0, 1,0, 0x22,0x56,0,0,
      0x44,0xAC,0,0, 2,0, 16,0, 'd','a','t','a', 0xAC,0x14,0,0};
  wave.resize(5336);
  return wave;
}
int main(int argc, char** argv) {
  if (argc != 2) return 2;
  std::ifstream stream(argv[1], std::ios::binary);
  std::vector<uint8_t> original((std::istreambuf_iterator<char>(stream)), {});
  if (original.size() != 109686) return 2;
  int failures = 0;
  const auto run = [&](const char* name, const auto& test) {
    try { test(); std::cout << "PASS " << name << '\n'; }
    catch (const std::exception& error) {
      ++failures; std::cout << "FAIL " << name << ": " << error.what() << '\n';
    }
  };
  TestMessenger messenger;
  niran::WindowsBackendBridge bridge(&messenger, nullptr);
  run("real Codex WAV reaches playback and retains its buffer", [&] {
    playback_calls = 0;
    const auto outcome = Dispatch(messenger, &original);
    Require(playback_calls == 1, "109686-byte Codex cue was rejected before playback");
    Require(retained_wave != original.data(), "Async playback borrowed caller memory");
    Require(std::equal(original.begin(), original.end(), retained_wave),
            "Retained waveform differs from original");
    Require(outcome.success, "Accepted audio is incorrectly reported as failure");
  });
  run("muted feedback does not call playback", [&] {
    playback_calls = 0; Dispatch(messenger, nullptr);
    Require(playback_calls == 0, "Muted feedback played audio");
  });
  run("classic-sized mono PCM reaches playback", [&] {
    playback_calls = 0;
    const auto mono = ShortMonoWave();
    const auto outcome = Dispatch(messenger, &mono);
    Require(playback_calls == 1 && outcome.success, "Valid short mono PCM was rejected");
  });
  run("odd metadata chunk padding preserves PCM playback", [&] {
    playback_calls = 0;
    auto mono = ShortMonoWave();
    const std::vector<uint8_t> junk = {'J','U','N','K',1,0,0,0,0,0};
    mono.insert(mono.begin() + 36, junk.begin(), junk.end());
    Write32(mono, 4, static_cast<uint32_t>(mono.size() - 8));
    const auto outcome = Dispatch(messenger, &mono);
    Require(playback_calls == 1 && outcome.success, "Padded metadata prevented valid playback");
  });
  run("playback rejection has a meaningful error", [&] {
    play_succeeds = false;
    const auto outcome = Dispatch(messenger, &original);
    play_succeeds = true;
    Require(outcome.error == "audio_unavailable", "PlaySound failure was silently discarded");
  });
  run("malformed WAV is rejected before OS reads it", [&] {
    playback_calls = 0;
    auto malformed = original; malformed[8] = 'X';
    const auto outcome = Dispatch(messenger, &malformed);
    Require(playback_calls == 0, "Non-WAVE RIFF reached playback");
    Require(outcome.error == "invalid_audio", "Malformed WAV lacks validation result");
  });
  run("truncated data chunk cannot reach playback", [&] {
    playback_calls = 0;
    auto truncated = original;
    truncated.resize(100);
    Write32(truncated, 4, 92);
    const auto outcome = Dispatch(messenger, &truncated);
    Require(playback_calls == 0 && outcome.error == "invalid_audio",
            "Truncated chunk reached OS playback");
  });
  run("incorrect PCM frame alignment cannot reach playback", [&] {
    playback_calls = 0;
    auto invalid = ShortMonoWave();
    invalid[32] = 1;
    const auto outcome = Dispatch(messenger, &invalid);
    Require(playback_calls == 0 && outcome.error == "invalid_audio",
            "Invalid PCM frame alignment reached OS playback");
  });
  run("oversized PCM remains bounded", [&] {
    playback_calls = 0;
    auto oversized = ShortMonoWave();
    oversized.resize(1024 * 1024 + 4);
    Write32(oversized, 4, static_cast<uint32_t>(oversized.size() - 8));
    Write32(oversized, 40, static_cast<uint32_t>(oversized.size() - 44));
    const auto outcome = Dispatch(messenger, &oversized);
    Require(playback_calls == 0 && outcome.error == "invalid_audio",
            "Oversized audio allocation was accepted");
  });
  return failures == 0 ? 0 : 1;
}

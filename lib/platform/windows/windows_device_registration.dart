import '../../core/registration/device_registration.dart';
import 'windows_native_host.dart';

final class WindowsDeviceRegistrationInfoProvider
    implements DeviceRegistrationInfoProvider {
  WindowsDeviceRegistrationInfoProvider({WindowsNativeHostApi? host})
    : _host = host ?? MethodChannelWindowsNativeHost();

  final WindowsNativeHostApi _host;

  /// Version checks need build metadata only, not a TPM/publisher identity read.
  Future<String> readAppVersion() async =>
      '${(await _host.getBuildConfig())['appVersion'] ?? ''}';

  @override
  Future<DeviceRegistrationInfo> read() async {
    final values = await _host.getDeviceRegistrationInfo();
    return DeviceRegistrationInfo(
      deviceName: '${values['deviceName'] ?? ''}',
      windowsUsername: '${values['windowsUsername'] ?? ''}',
      windowsVersion: '${values['windowsVersion'] ?? ''}',
      appVersion: '${values['appVersion'] ?? ''}',
      systemId: '${values['systemId'] ?? ''}',
      systemIdSource: '${values['systemIdSource'] ?? 'unknown'}',
    );
  }

  @override
  Future<void> exitApplication() => _host.exitApplication();
}

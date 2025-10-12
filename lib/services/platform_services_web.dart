// Minimal web stub for platform-specific services used by app.

class PlatformServices {
  static final PlatformServices instance = PlatformServices._();
  PlatformServices._();

  Future<String> getDeviceId() async => 'web-device';
  Future<String> getMachineId() async => 'web-machine';
}

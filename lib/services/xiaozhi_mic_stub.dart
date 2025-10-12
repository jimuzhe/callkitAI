// Minimal stub for non-web platforms. Real implementation should provide
// microphone audio frames as Stream<List<int>> or similar. This stub keeps
// the project analyzable.

class XiaozhiMic {
  /// Returns a stream of audio chunks. Stub emits nothing.
  Stream<List<int>> audioStream() async* {}

  Future<void> start() async {}
  Future<void> stop() async {}
}

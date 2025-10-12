// Web implementation of XiaozhiMic using getUserMedia + AudioContext.
// Captures mono 16k PCM frames and streams them back to Dart.

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:typed_data';
import 'dart:js_util' as js_util;

import 'package:js/js.dart';

@JS('MicRecorder.start')
external Object _micStart(Function onData);

@JS('MicRecorder.stop')
external void _micStop();

class XiaozhiMic {
  XiaozhiMic();

  final StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();
  bool _running = false;

  Stream<List<int>> audioStream() => _controller.stream;

  Future<void> start() async {
    if (_running) return;

    try {
      // Start JS recorder, convert returned Promise to Future.
      await js_util.promiseToFuture<void>(
        _micStart(
          allowInterop(
            (dynamic buffer) {
              try {
                Uint8List? bytes;
                if (buffer is ByteBuffer) {
                  bytes = Uint8List.view(buffer);
                } else if (buffer is Uint8List) {
                  bytes = buffer;
                } else if (buffer is List) {
                  bytes = Uint8List.fromList(buffer.cast<int>());
                }

                if (bytes != null && bytes.isNotEmpty) {
                  _controller.add(bytes); // Already PCM16 LE
                }
              } catch (err) {
                // ignore and continue streaming
                // ignore: avoid_print
                print('MicRecorder callback error: $err');
              }
            },
          ),
        ),
      );
      _running = true;
    } catch (err) {
      _running = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    try {
      _micStop();
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    if (_controller.isClosed) return;
    await stop();
    await _controller.close();
  }
}

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Describe one chunk of PCM data pushed into the stream player.
class PCMChunk {
  PCMChunk(this.pcmBytes, {required this.sampleRate, this.channels = 1});

  final Uint8List pcmBytes;
  final int sampleRate;
  final int channels;

  int get frameCount => pcmBytes.length ~/ (2 * channels);
}

/// A continuous PCM stream player built on top of [just_audio].
///
/// Uses a continuous audio stream approach similar to mainstream platforms:
/// - Single StreamAudioSource that stays active throughout the session
/// - Continuous buffer feeding for low-latency playback
/// - No frequent audio source switching or playlist management
class PCMStreamPlayer {
  PCMStreamPlayer({
    required AudioPlayer player,
    required ValueChanged<bool> onPlaybackStateChanged,
    VoidCallback? onPlaybackCompleted,
  }) : _player = player,
       _onPlaybackStateChanged = onPlaybackStateChanged,
       _onPlaybackCompleted = onPlaybackCompleted;

  final AudioPlayer _player;
  final ValueChanged<bool> _onPlaybackStateChanged;
  final VoidCallback? _onPlaybackCompleted;

  bool _initialized = false;
  StreamSubscription<PlayerState>? _playerStateSub;
  _ContinuousPCMStreamSource? _streamSource;

  // Continuous buffer for streaming audio data
  final List<int> _audioBuffer = <int>[];
  static const int _bufferThreshold = 6400; // ~200ms at 16kHz mono
  static const int _maxBufferSize = 25600; // ~800ms max buffer

  // Stream controller for feeding audio data
  StreamController<List<int>>? _audioDataController;
  bool _isStreaming = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    debugPrint('🚀 PCMStreamPlayer: 初始化连续流播放器...');
    final stopwatch = Stopwatch()..start();

    try {
      // Initialize continuous stream source
      _streamSource = _ContinuousPCMStreamSource();
      await _player.setAudioSource(_streamSource!);
      debugPrint('✅ PCMStreamPlayer: 音频源设置成功');
    } catch (e) {
      debugPrint('❌ PCMStreamPlayer: 设置音频源失败: $e');
      rethrow;
    }

    // Set up player state monitoring
    await _playerStateSub?.cancel();
    _playerStateSub = _player.playerStateStream.listen((state) {
      final playing = state.playing;
      _onPlaybackStateChanged(playing);

      if (state.processingState == ProcessingState.completed) {
        _onPlaybackCompleted?.call();
      }
    });

    // 修复：不覆盖现有的音频会话配置，只确保会话激活
    // 这样可以保持 AudioService 中设置的语音聊天模式
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      debugPrint('✅ PCMStreamPlayer: 保持现有音频会话配置并激活');
    } catch (e) {
      debugPrint('⚠️ PCMStreamPlayer: 激活音频会话失败: $e');
    }

    stopwatch.stop();
    debugPrint('✅ PCMStreamPlayer: 初始化完成 (${stopwatch.elapsedMilliseconds}ms)');
    _initialized = true;
  }

  Future<void> enqueuePcm(PCMChunk chunk) async {
    if (chunk.pcmBytes.isEmpty) return;
    await ensureInitialized();

    // Convert to List<int> and add to buffer
    final pcmInts = chunk.pcmBytes.map((b) => b).toList();
    _audioBuffer.addAll(pcmInts);

    // Maintain buffer size
    if (_audioBuffer.length > _maxBufferSize) {
      final excess = _audioBuffer.length - _maxBufferSize;
      _audioBuffer.removeRange(0, excess);
    }

    // Start streaming if we have enough data and not already streaming
    if (_audioBuffer.length >= _bufferThreshold && !_isStreaming) {
      await _startStreaming();
    }

    // Feed data to stream if already streaming
    if (_isStreaming &&
        _audioDataController != null &&
        !_audioDataController!.isClosed) {
      _audioDataController!.add(List<int>.from(pcmInts));
    }

    debugPrint(
      '🌀 PCMStreamPlayer: 缓冲区=$_audioBuffer.length bytes (~${(_audioBuffer.length / 2 / chunk.sampleRate * 1000).round()}ms), 流式=$_isStreaming',
    );
  }

  Future<void> _startStreaming() async {
    if (_isStreaming) return;

    debugPrint('🎵 PCMStreamPlayer: 开始连续流式播放');

    _audioDataController = StreamController<List<int>>();
    _isStreaming = true;

    // Feed initial buffer data
    if (_audioBuffer.isNotEmpty) {
      _audioDataController!.add(List<int>.from(_audioBuffer));
    }

    // Set up the stream source with our data controller
    _streamSource?.setDataStream(_audioDataController!.stream);

    // Start playback
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      await _player.play();
      debugPrint('✅ PCMStreamPlayer: 流式播放开始');
    } catch (e) {
      debugPrint('❌ PCMStreamPlayer: 播放启动失败: $e');
      await _stopStreaming();
    }
  }

  Future<void> _stopStreaming() async {
    if (!_isStreaming) return;

    debugPrint('🛑 PCMStreamPlayer: 停止连续流式播放');

    _isStreaming = false;

    if (_audioDataController != null && !_audioDataController!.isClosed) {
      await _audioDataController!.close();
    }
    _audioDataController = null;

    try {
      await _player.stop();
    } catch (e) {
      debugPrint('⚠️ PCMStreamPlayer: 停止播放警告: $e');
    }
  }

  Future<void> flush() async {
    await ensureInitialized();

    if (_audioBuffer.isEmpty) return;

    // If streaming, feed remaining data
    if (_isStreaming &&
        _audioDataController != null &&
        !_audioDataController!.isClosed) {
      _audioDataController!.add(List<int>.from(_audioBuffer));
    }

    _audioBuffer.clear();
    debugPrint('🧹 PCMStreamPlayer: 缓冲区已清空');
  }

  Future<void> dispose() async {
    await _playerStateSub?.cancel();
    _playerStateSub = null;

    await _stopStreaming();
    _audioBuffer.clear();

    _initialized = false;
    debugPrint('🗑️ PCMStreamPlayer: 已清理');
  }

  /// Immediately stop playback and clear any buffered/queued audio.
  Future<void> clearAndStop() async {
    await ensureInitialized();

    _audioBuffer.clear();
    await _stopStreaming();

    try {
      await _player.stop();
    } catch (_) {}
  }
}

/// Continuous PCM stream source that maintains a persistent audio stream.
/// Similar to how WebRTC or native audio engines handle continuous streaming.
class _ContinuousPCMStreamSource extends StreamAudioSource {
  _ContinuousPCMStreamSource();

  Stream<List<int>>? _dataStream;
  StreamSubscription<List<int>>? _dataSubscription;
  final List<int> _streamBuffer = <int>[];
  bool _isStreamEnded = false;

  void setDataStream(Stream<List<int>> stream) {
    _dataStream = stream;
    _dataSubscription?.cancel();
    _dataSubscription = _dataStream!.listen(
      (data) {
        _streamBuffer.addAll(data);
      },
      onDone: () {
        _isStreamEnded = true;
      },
      onError: (error) {
        debugPrint('❌ ContinuousPCMStreamSource: 流错误: $error');
        _isStreamEnded = true;
      },
    );
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // Wait for some data if buffer is empty and stream is active
    if (_streamBuffer.isEmpty && !_isStreamEnded) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final totalLength = _streamBuffer.length;
    if (totalLength == 0) {
      // Return empty response if no data available
      return StreamAudioResponse(
        sourceLength: null, // Unknown length for streaming
        contentLength: 0,
        offset: 0,
        stream: Stream.empty(),
        contentType: 'audio/pcm',
      );
    }

    final actualStart = (start ?? 0).clamp(0, totalLength);
    final clampedEnd = end == null ? totalLength : end.clamp(0, totalLength);
    final actualEnd = clampedEnd < actualStart ? actualStart : clampedEnd;

    if (actualStart >= totalLength) {
      // Request beyond available data
      return StreamAudioResponse(
        sourceLength: null,
        contentLength: 0,
        offset: actualStart,
        stream: Stream.empty(),
        contentType: 'audio/pcm',
      );
    }

    final slice = _streamBuffer.sublist(actualStart, actualEnd);

    // Remove consumed data to prevent memory growth
    if (actualEnd >= totalLength) {
      _streamBuffer.clear();
    } else {
      _streamBuffer.removeRange(0, actualEnd);
    }

    return StreamAudioResponse(
      sourceLength: null, // Streaming source, length unknown
      contentLength: slice.length,
      offset: actualStart,
      stream: Stream.value(slice),
      contentType: 'audio/pcm',
    );
  }

  Future<void> dispose() async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    _streamBuffer.clear();
    _isStreamEnded = true;
  }
}

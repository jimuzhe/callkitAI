import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// 音频流管理器 - 处理实时音频流播放
///
/// 功能类似Python版本的AudioCodec：
/// 1. 接收来自WebSocket的音频数据（Opus编码）
/// 2. 管理音频缓冲队列
/// 3. 顺序播放音频片段
class AudioStreamManager {
  static final AudioStreamManager instance = AudioStreamManager._();

  AudioStreamManager._();

  final Queue<AudioChunk> _audioQueue = Queue<AudioChunk>();
  final AudioPlayer _streamPlayer = AudioPlayer();

  bool _isProcessing = false;
  bool _isEnabled = false;
  int _chunkCounter = 0;

  /// 启用音频流模式
  Future<void> enable() async {
    if (_isEnabled) return;

    try {
      await _streamPlayer.setVolume(1.0);
      _isEnabled = true;
      debugPrint('🎙️ 音频流管理器已启用');

      // 开始处理队列
      _processQueue();
    } catch (e) {
      debugPrint('❌ 启用音频流管理器失败: $e');
    }
  }

  /// 禁用音频流模式
  Future<void> disable() async {
    if (!_isEnabled) return;

    _isEnabled = false;
    _audioQueue.clear();
    _chunkCounter = 0;

    try {
      await _streamPlayer.stop();
      debugPrint('🛑 音频流管理器已禁用');
    } catch (e) {
      debugPrint('❌ 禁用音频流管理器失败: $e');
    }
  }

  /// 添加音频数据到队列
  ///
  /// [audioData] - 音频字节数据（可能是Opus编码）
  /// [format] - 音频格式（opus, wav, pcm等）
  /// [sequenceNumber] - 序列号（可选，用于排序）
  void enqueueAudio(
    List<int> audioData, {
    String? format,
    int? sequenceNumber,
  }) {
    if (!_isEnabled) {
      debugPrint('⚠️ 音频流管理器未启用，忽略音频数据');
      return;
    }

    final chunk = AudioChunk(
      data: audioData,
      format: format ?? 'unknown',
      sequenceNumber: sequenceNumber ?? _chunkCounter++,
      timestamp: DateTime.now(),
    );

    _audioQueue.add(chunk);
    debugPrint(
      '📥 音频块入队: #${chunk.sequenceNumber}, 大小: ${audioData.length} bytes, 格式: ${chunk.format}',
    );
    debugPrint('📊 队列长度: ${_audioQueue.length}');

    // 如果当前没有在处理，立即开始处理
    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// 处理音频队列
  Future<void> _processQueue() async {
    if (_isProcessing || _audioQueue.isEmpty) return;

    _isProcessing = true;
    debugPrint('🔄 开始处理音频队列...');

    while (_audioQueue.isNotEmpty && _isEnabled) {
      final chunk = _audioQueue.removeFirst();

      try {
        debugPrint('▶️ 播放音频块: #${chunk.sequenceNumber}');
        await _playChunk(chunk);
        debugPrint('✅ 音频块播放完成: #${chunk.sequenceNumber}');
      } catch (e) {
        debugPrint('❌ 播放音频块失败: #${chunk.sequenceNumber}, 错误: $e');
      }

      // 检查是否还有待处理的音频
      if (_audioQueue.isEmpty) {
        // 等待一小段时间，看是否有新的音频数据到达
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    _isProcessing = false;
    debugPrint('🏁 音频队列处理完成');
  }

  /// 播放单个音频块
  Future<void> _playChunk(AudioChunk chunk) async {
    // 这里可以根据格式进行处理
    // 对于Opus，just_audio应该能够自动处理
    // 如果需要，可以在这里添加解码逻辑

    try {
      // 使用临时文件方式播放
      final tempFile = await chunk.toTempFile();

      await _streamPlayer.setFilePath(tempFile.path);
      await _streamPlayer.setVolume(1.0);

      // 播放并等待完成
      await _streamPlayer.play();

      // 简单等待：根据音频大小估算播放时间
      // 假设16kHz采样率，16bit，单声道
      final estimatedDuration = (chunk.data.length / (16000 * 2) * 1000).ceil();
      final waitDuration = Duration(milliseconds: estimatedDuration + 500);

      debugPrint('⏱️ 预计播放时长: ${estimatedDuration}ms');

      // 使用超时监听完成事件
      final completer = Completer<void>();
      StreamSubscription? subscription;

      subscription = _streamPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (!completer.isCompleted) {
            completer.complete();
            subscription?.cancel();
          }
        }
      });

      // 等待播放完成或超时
      await completer.future.timeout(
        waitDuration,
        onTimeout: () {
          debugPrint('⚠️ 音频播放超时，继续下一块');
          subscription?.cancel();
        },
      );

      // 清理临时文件
      try {
        await tempFile.delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ 播放音频块出错: $e');
      rethrow;
    }
  }

  /// 获取队列状态
  Map<String, dynamic> getStatus() {
    return {
      'enabled': _isEnabled,
      'processing': _isProcessing,
      'queueLength': _audioQueue.length,
      'chunkCounter': _chunkCounter,
    };
  }

  /// 清空队列
  void clearQueue() {
    _audioQueue.clear();
    debugPrint('🗑️ 音频队列已清空');
  }
}

/// 音频块数据类
class AudioChunk {
  final List<int> data;
  final String format;
  final int sequenceNumber;
  final DateTime timestamp;

  AudioChunk({
    required this.data,
    required this.format,
    required this.sequenceNumber,
    required this.timestamp,
  });

  /// 将音频数据写入临时文件
  Future<File> toTempFile() async {
    final tempDir = await getTemporaryDirectory();
    final ext = _getFileExtension();
    final filePath =
        '${tempDir.path}/audio_chunk_${sequenceNumber}_${timestamp.millisecondsSinceEpoch}.$ext';

    final file = File(filePath);
    await file.writeAsBytes(data, flush: true);

    return file;
  }

  String _getFileExtension() {
    switch (format.toLowerCase()) {
      case 'opus':
      case 'ogg':
        return 'ogg';
      case 'wav':
        return 'wav';
      case 'mp3':
        return 'mp3';
      case 'aac':
        return 'aac';
      case 'pcm':
        return 'pcm';
      default:
        // 尝试从数据头部识别
        if (data.length >= 4) {
          // OggS
          if (data[0] == 0x4F &&
              data[1] == 0x67 &&
              data[2] == 0x67 &&
              data[3] == 0x53) {
            return 'ogg';
          }
          // RIFF (WAV)
          if (data[0] == 0x52 &&
              data[1] == 0x49 &&
              data[2] == 0x46 &&
              data[3] == 0x46) {
            return 'wav';
          }
        }
        return 'dat'; // 默认扩展名
    }
  }
}

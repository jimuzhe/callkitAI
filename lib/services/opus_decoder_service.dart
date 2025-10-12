import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;

/// Opus 音频解码服务
///
/// 用于将原始 Opus 数据包解码成 PCM 音频
/// 优化配置：16kHz 输出，单声道（提高性能）
class OpusDecoderService {
  static final OpusDecoderService instance = OpusDecoderService._();
  OpusDecoderService._();

  SimpleOpusDecoder? _decoder;
  bool _isInitialized = false;

  // 配置参数（与服务器保持一致）
  static const int sampleRate = 16000; // 16kHz （匹配服务器）
  static const int channels = 1; // 单声道
  static const int frameSize = 960; // 16000 * 0.06 = 960 samples (60ms)

  /// 初始化解码器
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ Opus 解码器已初始化，跳过');
      return;
    }

    try {
      // 加载 Opus 原生库
      debugPrint('🔧 加载 Opus 原生库...');
      initOpus(await opus_flutter.load());
      debugPrint('✅ Opus 原生库加载成功');

      // 创建 Opus 解码器
      _decoder = SimpleOpusDecoder(sampleRate: sampleRate, channels: channels);

      _isInitialized = true;
      debugPrint('✅ Opus 解码器初始化成功: ${sampleRate}Hz, $channels 声道');
    } catch (e) {
      debugPrint('❌ Opus 解码器初始化失败: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  /// 解码 Opus 数据包为 PCM（带性能监控）
  ///
  /// [opusData] - 原始 Opus 编码数据
  /// Returns: PCM 音频数据（16-bit signed integers）
  Future<Uint8List> decode(Uint8List opusData) async {
    if (!_isInitialized || _decoder == null) {
      throw StateError('Opus 解码器未初始化，请先调用 initialize()');
    }

    final stopwatch = Stopwatch()..start();
    try {
      // 解码 Opus 数据
      final pcmData = _decoder!.decode(input: opusData);

      if (pcmData.isEmpty) {
        debugPrint('⚠️ Opus 解码返回空数据');
        return Uint8List(0);
      }

      // 转换为 Uint8List
      final result = _convertInt16ListToUint8List(pcmData);
      stopwatch.stop();
      final duration = stopwatch.elapsedMilliseconds;
      // 仅在耗时较长时打印警告，避免频繁日志导致抖动
      if (duration > 50) {
        debugPrint('⚠️ Opus 解码耗时过长: ${duration}ms，可能影响播放流畅度');
      }
      return result;
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ Opus 解码失败: $e (耗时: ${stopwatch.elapsedMilliseconds}ms)');
      rethrow;
    }
  }

  /// 将 Int16 PCM 数据转换为 Uint8List（小端序）
  Uint8List _convertInt16ListToUint8List(List<int> pcmData) {
    final byteData = ByteData(pcmData.length * 2);

    for (int i = 0; i < pcmData.length; i++) {
      byteData.setInt16(i * 2, pcmData[i], Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  /// 将 PCM 数据转换为 WAV 格式
  ///
  /// [pcmData] - PCM 音频数据
  /// [sampleRate] - 采样率（默认 16kHz，匹配服务器）
  /// [channels] - 声道数（默认 1）
  /// [bitsPerSample] - 位深度（默认 16）
  Uint8List convertPcmToWav(
    Uint8List pcmData, {
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final int blockAlign = channels * (bitsPerSample ~/ 8);
    final int dataSize = pcmData.length;
    final int fileSize = 36 + dataSize;

    final ByteData header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, fileSize, Endian.little);

    // WAVE header
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little);

    // 合并 header 和 PCM 数据
    final result = Uint8List(44 + dataSize);
    result.setRange(0, 44, header.buffer.asUint8List());
    result.setRange(44, 44 + dataSize, pcmData);

    debugPrint(
      '📦 PCM 转 WAV: ${pcmData.length} bytes PCM → ${result.length} bytes WAV',
    );

    return result;
  }

  /// 解码 Opus 并转换为 WAV（一步到位）
  Future<Uint8List> decodeToWav(Uint8List opusData) async {
    final pcmData = await decode(opusData);
    if (pcmData.isEmpty) {
      return Uint8List(0);
    }
    return convertPcmToWav(pcmData, sampleRate: sampleRate, channels: channels);
  }

  /// 关闭解码器
  Future<void> dispose() async {
    if (_isInitialized && _decoder != null) {
      try {
        _decoder!.destroy();
        _decoder = null;
        _isInitialized = false;
        debugPrint('🛑 Opus 解码器已关闭');
      } catch (e) {
        debugPrint('⚠️ 关闭 Opus 解码器时出错: $e');
      }
    }
  }

  /// 获取解码器状态
  bool get isInitialized => _isInitialized;
}

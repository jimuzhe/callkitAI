import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;

/// 音频编解码工具类
///
/// 参考 xiaozhi 项目实现,支持 PCM16 与 Opus 的互转
class AudioCodec {
  static AudioCodec? _instance;
  static AudioCodec get instance => _instance ??= AudioCodec._();

  AudioCodec._();

  SimpleOpusEncoder? _encoder;
  SimpleOpusDecoder? _decoder;
  bool _opusInitialized = false;

  Future<void> _ensureOpusLoaded() async {
    if (_opusInitialized) return;
    initOpus(await opus_flutter.load());
    _opusInitialized = true;
  }

  /// PCM16 转 Opus
  ///
  /// [pcmData] PCM16LE 格式的音频数据 (16bit, mono, 16kHz)
  /// [sampleRate] 采样率,默认 16000
  /// [frameDuration] 帧时长(毫秒),默认 60ms
  ///
  /// 返回 Opus 编码后的字节流,失败返回 null
  Future<Uint8List?> pcmToOpus({
    required Uint8List pcmData,
    int sampleRate = 16000,
    int frameDuration = 60,
  }) async {
    try {
      await _ensureOpusLoaded();

      _encoder ??= SimpleOpusEncoder(
        sampleRate: sampleRate,
        channels: 1,
        application: Application.voip,
      );

      final Int16List pcmInt16 = Int16List.fromList(
        List.generate(
          pcmData.length ~/ 2,
          (i) => (pcmData[i * 2]) | (pcmData[i * 2 + 1] << 8),
        ),
      );

      final int samplesPerFrame = (sampleRate * frameDuration) ~/ 1000;

      Uint8List encoded;

      if (pcmInt16.length < samplesPerFrame) {
        final Int16List paddedData = Int16List(samplesPerFrame);
        for (int i = 0; i < pcmInt16.length; i++) {
          paddedData[i] = pcmInt16[i];
        }
        encoded = Uint8List.fromList(_encoder!.encode(input: paddedData));
      } else {
        encoded = Uint8List.fromList(
          _encoder!.encode(input: pcmInt16.sublist(0, samplesPerFrame)),
        );
      }

      return encoded;
    } catch (e, s) {
      debugPrint('PCM 转 Opus 失败: $e\n$s');
      return null;
    }
  }

  /// Opus 转 PCM16
  ///
  /// [opusData] Opus 编码的音频数据
  /// [sampleRate] 采样率,默认 16000
  /// [channels] 声道数,默认 1(单声道)
  ///
  /// 返回 PCM16LE 格式的字节流,失败返回 null
  Future<Uint8List?> opusToPcm({
    required Uint8List opusData,
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    try {
      await _ensureOpusLoaded();

      _decoder ??= SimpleOpusDecoder(
        sampleRate: sampleRate,
        channels: channels,
      );

      final Int16List pcmData = _decoder!.decode(input: opusData);
      final Uint8List pcmBytes = Uint8List(pcmData.length * 2);
      final ByteData bytes = ByteData.view(pcmBytes.buffer);

      for (int i = 0; i < pcmData.length; i++) {
        bytes.setInt16(i * 2, pcmData[i], Endian.little);
      }

      return pcmBytes;
    } catch (e, s) {
      debugPrint('Opus 转 PCM 失败: $e\n$s');
      return null;
    }
  }

  /// AAC(M4A) 转 PCM16
  ///
  /// iOS 平台优选 AAC 编码,需要时可用此方法解码
  Future<Uint8List?> aacToPcm({required Uint8List aacData}) async {
    debugPrint('AAC 解码通常由播放器自动处理');
    return null;
  }
}

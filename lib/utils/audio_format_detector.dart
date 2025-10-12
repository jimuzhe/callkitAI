import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// 音频格式检测工具
class AudioFormatDetector {
  /// 检测音频数据格式
  static AudioFormat detectFormat(Uint8List data) {
    if (data.isEmpty) {
      return AudioFormat.unknown;
    }

    // OGG 容器格式: "OggS" (0x4F 0x67 0x67 0x53)
    if (data.length >= 4 &&
        data[0] == 0x4F &&
        data[1] == 0x67 &&
        data[2] == 0x67 &&
        data[3] == 0x53) {
      return AudioFormat.oggOpus;
    }

    // WAV 格式: "RIFF" (0x52 0x49 0x46 0x46)
    if (data.length >= 4 &&
        data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46) {
      return AudioFormat.wav;
    }

    // MP3 格式: ID3 tag or frame sync
    if (data.length >= 3) {
      // ID3v2 header
      if (data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) {
        return AudioFormat.mp3;
      }
      // MP3 frame sync (0xFF 0xFB or 0xFF 0xFA)
      if (data[0] == 0xFF && (data[1] & 0xE0) == 0xE0) {
        return AudioFormat.mp3;
      }
    }

    // AAC 格式: ADTS header (0xFF 0xF1 or 0xFF 0xF9)
    if (data.length >= 2 &&
        data[0] == 0xFF &&
        (data[1] == 0xF1 || data[1] == 0xF9)) {
      return AudioFormat.aac;
    }

    // OpusHead signature (在 OGG 容器内)
    if (data.length >= 8 &&
        data[0] == 0x4F && // 'O'
        data[1] == 0x70 && // 'p'
        data[2] == 0x75 && // 'u'
        data[3] == 0x73 && // 's'
        data[4] == 0x48 && // 'H'
        data[5] == 0x65 && // 'e'
        data[6] == 0x61 && // 'a'
        data[7] == 0x64) {
      // 'd'
      return AudioFormat.opusHeader;
    }

    // 可能是原始 Opus 数据包（没有明确的魔数）
    // Opus 包通常很小（几十到几百字节）
    if (data.length >= 10 && data.length <= 4000) {
      // 启发式检测：Opus 包的 TOC byte
      final tocByte = data[0];
      // TOC byte 的高5位是配置索引 (0-31)
      final config = (tocByte >> 3) & 0x1F;
      if (config <= 31) {
        return AudioFormat.rawOpus;
      }
    }

    return AudioFormat.unknown;
  }

  /// 获取格式的详细信息
  static String getFormatInfo(Uint8List data) {
    final format = detectFormat(data);
    final hex = data.length >= 8
        ? data
              .sublist(0, 8)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ')
        : data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

    return '''
格式: ${format.name}
大小: ${data.length} bytes
头部: $hex
可播放: ${format.isPlayable ? '✅' : '❌'}
${format.isPlayable ? '' : '需要: ${format.requiresDecoding ? 'Opus解码' : 'OGG容器封装'}'}
''';
  }

  /// 打印音频数据的详细调试信息
  static void debugPrintAudioData(Uint8List data, {String label = '音频数据'}) {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('$label 分析:');
    debugPrint(getFormatInfo(data));
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }
}

/// 音频格式枚举
enum AudioFormat {
  oggOpus('OGG/Opus 容器', true, false),
  wav('WAV', true, false),
  mp3('MP3', true, false),
  aac('AAC', true, false),
  opusHeader('Opus Header', false, true),
  rawOpus('原始 Opus 包', false, true),
  unknown('未知格式', false, false);

  const AudioFormat(this.name, this.isPlayable, this.requiresDecoding);

  final String name;
  final bool isPlayable; // 是否可以直接播放
  final bool requiresDecoding; // 是否需要解码
}

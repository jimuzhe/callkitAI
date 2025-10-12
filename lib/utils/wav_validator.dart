import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// WAV 文件验证工具
class WavValidator {
  /// 验证 WAV 文件格式
  static bool validateWav(Uint8List data) {
    if (data.length < 44) {
      debugPrint('❌ WAV 文件太小: ${data.length} bytes (最少需要 44 bytes)');
      return false;
    }

    try {
      // 检查 RIFF 头
      if (data[0] != 0x52 ||
          data[1] != 0x49 ||
          data[2] != 0x46 ||
          data[3] != 0x46) {
        debugPrint('❌ 缺少 RIFF 头');
        return false;
      }

      // 检查 WAVE 标识
      if (data[8] != 0x57 ||
          data[9] != 0x41 ||
          data[10] != 0x56 ||
          data[11] != 0x45) {
        debugPrint('❌ 缺少 WAVE 标识');
        return false;
      }

      // 检查 fmt 块
      if (data[12] != 0x66 ||
          data[13] != 0x6D ||
          data[14] != 0x74 ||
          data[15] != 0x20) {
        debugPrint('❌ 缺少 fmt 块');
        return false;
      }

      // 读取音频格式
      final audioFormat = ByteData.view(
        data.buffer,
      ).getUint16(20, Endian.little);
      final channels = ByteData.view(data.buffer).getUint16(22, Endian.little);
      final sampleRate = ByteData.view(
        data.buffer,
      ).getUint32(24, Endian.little);
      final byteRate = ByteData.view(data.buffer).getUint32(28, Endian.little);
      final blockAlign = ByteData.view(
        data.buffer,
      ).getUint16(32, Endian.little);
      final bitsPerSample = ByteData.view(
        data.buffer,
      ).getUint16(34, Endian.little);

      // 检查 data 块
      if (data[36] != 0x64 ||
          data[37] != 0x61 ||
          data[38] != 0x74 ||
          data[39] != 0x61) {
        debugPrint('❌ 缺少 data 块');
        return false;
      }

      final dataSize = ByteData.view(data.buffer).getUint32(40, Endian.little);

      debugPrint('✅ WAV 文件格式验证成功:');
      debugPrint('  - 音频格式: $audioFormat (1=PCM)');
      debugPrint('  - 声道数: $channels');
      debugPrint('  - 采样率: $sampleRate Hz');
      debugPrint('  - 字节率: $byteRate bytes/s');
      debugPrint('  - 块对齐: $blockAlign');
      debugPrint('  - 位深度: $bitsPerSample bits');
      debugPrint('  - 数据大小: $dataSize bytes');
      debugPrint('  - 总文件大小: ${data.length} bytes');

      // 验证计算
      final expectedByteRate = sampleRate * channels * (bitsPerSample ~/ 8);
      final expectedBlockAlign = channels * (bitsPerSample ~/ 8);

      if (byteRate != expectedByteRate) {
        debugPrint('⚠️ 字节率不匹配: 期望 $expectedByteRate, 实际 $byteRate');
      }

      if (blockAlign != expectedBlockAlign) {
        debugPrint('⚠️ 块对齐不匹配: 期望 $expectedBlockAlign, 实际 $blockAlign');
      }

      if (audioFormat != 1) {
        debugPrint('⚠️ 非 PCM 格式: $audioFormat');
      }

      // 检查数据完整性
      if (data.length < 44 + dataSize) {
        debugPrint(
          '⚠️ 数据不完整: 期望 ${44 + dataSize} bytes, 实际 ${data.length} bytes',
        );
      }

      return true;
    } catch (e) {
      debugPrint('❌ WAV 验证出错: $e');
      return false;
    }
  }

  /// 打印 WAV 文件的十六进制头部
  static void printWavHeader(Uint8List data, {int length = 44}) {
    if (data.isEmpty) {
      debugPrint('❌ 数据为空');
      return;
    }

    final headerLength = length.clamp(0, data.length);
    final header = data.sublist(0, headerLength);

    debugPrint('📄 WAV 文件头 (前 $headerLength bytes):');

    // 每行显示 16 bytes
    for (int i = 0; i < headerLength; i += 16) {
      final end = (i + 16).clamp(0, headerLength);
      final line = header.sublist(i, end);

      // 十六进制
      final hex = line
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');

      // ASCII (可打印字符)
      final ascii = line
          .map((b) {
            return (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.';
          })
          .join('');

      debugPrint('  ${i.toString().padLeft(4, '0')}: $hex  |$ascii|');
    }
  }

  /// 检查音频数据是否包含有效样本（不是全0）
  static bool hasValidSamples(Uint8List data) {
    if (data.length < 44) {
      return false;
    }

    // 跳过 WAV 头，检查音频数据
    final audioData = data.sublist(44);

    // 检查是否全为0
    int nonZeroCount = 0;
    for (int i = 0; i < audioData.length && i < 1000; i++) {
      if (audioData[i] != 0) {
        nonZeroCount++;
      }
    }

    final hasData = nonZeroCount > 0;
    debugPrint(
      '🔍 音频数据检查: ${hasData ? "包含有效样本" : "全为0（静音）"} (前1000字节中有 $nonZeroCount 个非零值)',
    );

    return hasData;
  }
}

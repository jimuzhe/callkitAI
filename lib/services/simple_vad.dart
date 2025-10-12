import 'dart:math' as math;
import 'dart:typed_data';

/// 极简能量阈值 VAD，用于在移动端快速检测“用户开始说话”。
/// - 输入: 16-bit PCM 单声道/多声道 (小端)
/// - 输出: onVoiceStart 回调（含冷却，避免重复触发）
class SimpleVAD {
  SimpleVAD({
    this.energyThreshold = 900, // 平均绝对幅度阈值，需按设备调优
    this.triggerFrames = 4, // 连续高能帧数达到后触发（约 80~120ms）
    this.cooldown = const Duration(milliseconds: 1200),
  });

  final double energyThreshold;
  final int triggerFrames;
  final Duration cooldown;

  // 可选：启停控制
  bool _enabled = true;
  void setEnabled(bool v) => _enabled = v;

  // 状态
  int _speechCount = 0;
  DateTime? _lastTriggerAt;

  // 回调
  void Function()? onVoiceStart;

  /// 添加一帧 PCM16 数据。
  /// 注意：这里按“数据块”为一帧进行检测，record 插件回调大小可能不同。
  void addPcm16(
    Uint8List pcmBytes, {
    int sampleRate = 16000,
    int channels = 1,
  }) {
    if (!_enabled || pcmBytes.isEmpty) return;

    // 计算平均绝对幅度（Mean Absolute Amplitude）
    final int16 = Int16List.view(pcmBytes.buffer, pcmBytes.offsetInBytes,
        pcmBytes.lengthInBytes ~/ 2);
    if (int16.isEmpty) return;

    double sum = 0;
    for (var v in int16) {
      sum += (v < 0) ? -v.toDouble() : v.toDouble();
    }
    final double meanAbs = sum / int16.length;

    final bool isSpeech = meanAbs >= energyThreshold;

    if (isSpeech) {
      _speechCount++;
      if (_speechCount >= triggerFrames) {
        _maybeTrigger();
        _speechCount = 0; // 触发一次后复位
      }
    } else {
      // 衰减/复位
      _speechCount = math.max(0, _speechCount - 1);
    }
  }

  void _maybeTrigger() {
    final now = DateTime.now();
    if (_lastTriggerAt != null) {
      final dt = now.difference(_lastTriggerAt!);
      if (dt < cooldown) return;
    }
    _lastTriggerAt = now;
    try {
      onVoiceStart?.call();
    } catch (_) {}
  }
}

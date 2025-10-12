import 'package:flutter/foundation.dart';
import 'package:volume_controller/volume_controller.dart';

/// 音量控制服务（用于急中生智模式）
class VolumeService {
  static final VolumeService instance = VolumeService._();
  VolumeService._();

  final VolumeController _volumeController = VolumeController();
  double? _originalVolume;
  
  /// 保存当前音量并设置为最大音量
  Future<void> setMaxVolume() async {
    try {
      // 保存当前音量
      _originalVolume = await _volumeController.getVolume();
      
      // 设置为最大音量（setVolume 返回 void，不需要 await）
      _volumeController.setVolume(1.0);
      
      debugPrint('🔊 音量已设置为最大 (原音量: ${(_originalVolume! * 100).toInt()}%)');
    } catch (e) {
      debugPrint('⚠️ 设置最大音量失败: $e');
    }
  }
  
  /// 恢复原来的音量
  Future<void> restoreVolume() async {
    if (_originalVolume != null) {
      try {
        // setVolume 返回 void，不需要 await
        _volumeController.setVolume(_originalVolume!);
        debugPrint('🔊 音量已恢复到 ${(_originalVolume! * 100).toInt()}%');
        _originalVolume = null;
      } catch (e) {
        debugPrint('⚠️ 恢复音量失败: $e');
      }
    }
  }
  
  /// 获取当前音量
  Future<double> getCurrentVolume() async {
    try {
      return await _volumeController.getVolume();
    } catch (e) {
      debugPrint('⚠️ 获取音量失败: $e');
      return 0.5;
    }
  }
}

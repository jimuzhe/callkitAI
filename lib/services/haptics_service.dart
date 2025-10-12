import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart' as vib;
import 'dart:io' show Platform;

/// 统一触觉反馈服务（专为iOS优化）：
/// - 开关与强度从 SharedPreferences 读取：
///   - vibration_enabled: bool (默认 true)
///   - vibration_intensity: int 0/1/2 (轻/中/强，默认 1)
/// - iOS 使用系统级 HapticFeedback（light/medium/heavy/selection），原生触控反馈
/// - 物理震动仅用于倒计时结束等重要提醒场景
class HapticsService {
  HapticsService._();
  static final HapticsService instance = HapticsService._();

  Future<bool> _enabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('vibration_enabled') ?? true;
  }

  Future<int> _intensity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('vibration_intensity') ?? 1; // 0/1/2
  }

  // 轻微选择反馈（列表/滚轮变更） - 随强度设置调整
  Future<void> selection() async {
    if (!await _enabled()) return;
    final level = await _intensity();
    switch (level) {
      case 0:
        // 轻：更轻微的选择触感
        await HapticFeedback.selectionClick();
        break;
      case 2:
        // 强：更明显的触感
        await HapticFeedback.heavyImpact();
        break;
      case 1:
      default:
        // 中：标准触感
        await HapticFeedback.mediumImpact();
        break;
    }
  }

  // iOS 系统原生滚轮声音（清脆齿轮声）
  // 仅在 iOS 上生效，自动调用 selectionClick 触觉反馈
  // iOS 的 CupertinoPicker 默认就会播放系统声音，但这里显式调用确保一致性
  Future<void> pickerSelection() async {
    if (!await _enabled()) return;
    // 在 iOS 上，selectionClick 会触发系统的选择声音和触觉反馈
    await HapticFeedback.selectionClick();
    final level = await _intensity();
    switch (level) {
      case 0:
        break;
      case 2:
        await HapticFeedback.heavyImpact();
        break;
      case 1:
      default:
        await HapticFeedback.mediumImpact();
        break;
    }
  }

  // 按键反馈（iOS触控反馈）
  Future<void> buttonTap() async {
    if (!await _enabled()) return;
    final level = await _intensity();
    // iOS原生触控反馈
    switch (level) {
      case 0:
        // 轻：最轻微的触感
        await HapticFeedback.selectionClick();
        break;
      case 2:
        // 强：明显的强烈反馈
        await HapticFeedback.heavyImpact();
        break;
      case 1:
      default:
        // 中：标准的按键反馈
        await HapticFeedback.mediumImpact();
        break;
    }
  }

  // 点击/切换（iOS触控反馈）
  Future<void> impact() async {
    if (!await _enabled()) return;
    final level = await _intensity();
    switch (level) {
      case 0:
        // 轻：轻微触感
        await HapticFeedback.selectionClick();
        break;
      case 2:
        // 强：强烈触感
        await HapticFeedback.heavyImpact();
        break;
      case 1:
      default:
        // 中：中等触感
        await HapticFeedback.mediumImpact();
        break;
    }
  }

  // 重要提醒专用：强烈物理震动（仅用于倒计时结束等关键场景）
  Future<void> alertVibration() async {
    if (!await _enabled()) return;
    
    // iOS触控反馈
    await HapticFeedback.heavyImpact();
    
    // 物理震动增强提醒效果
    final hasVibrator = await vib.Vibration.hasVibrator() ?? false;
    if (hasVibrator) {
      await vib.Vibration.vibrate(duration: 500); // 500ms强烈震动
    }
  }

  // 预览指定强度的反馈（iOS触控反馈预览）
  Future<void> previewImpact(int level) async {
    if (!await _enabled()) return;
    switch (level) {
      case 0:
        // 轻：轻微触感
        await HapticFeedback.selectionClick();
        break;
      case 2:
        // 强：明显的强烈反馈
        await HapticFeedback.heavyImpact();
        break;
      case 1:
      default:
        // 中：中等触感
        await HapticFeedback.mediumImpact();
        break;
    }
  }
}

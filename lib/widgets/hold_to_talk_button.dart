import 'package:flutter/material.dart';
import '../services/xiaozhi_service.dart';
import '../services/haptics_service.dart';

/// 长按说话按钮 (参考 xiaozhi 项目的 HoldToTalkWidget)
///
/// 提供对讲模式的交互体验:
/// - 按住说话,松开停止
/// - 上滑取消
/// - 视觉反馈(波纹动画、颜色变化)
class HoldToTalkButton extends StatefulWidget {
  final VoidCallback? onStartTalk;
  final VoidCallback? onStopTalk;
  final VoidCallback? onCancelTalk;

  const HoldToTalkButton({
    super.key,
    this.onStartTalk,
    this.onStopTalk,
    this.onCancelTalk,
  });

  @override
  State<HoldToTalkButton> createState() => HoldToTalkButtonState();
}

class HoldToTalkButtonState extends State<HoldToTalkButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  bool _canCancel = false;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onPressStart(LongPressStartDetails details) async {
    await HapticsService.instance.impact();
    setState(() => _isPressed = true);
    _animController.forward();
    widget.onStartTalk?.call();

    // 对讲模式: 开启监听并启动麦克风
    await XiaozhiService.instance.listenStart(mode: 'manual');
    await XiaozhiService.instance.startMic();
  }

  void _onPressEnd(LongPressEndDetails details) async {
    if (_canCancel) {
      // 上滑取消
      await HapticsService.instance.selection();
      widget.onCancelTalk?.call();
    } else {
      // 正常结束
      await HapticsService.instance.selection();
      widget.onStopTalk?.call();
    }

    // 停止麦克风与监听
    await XiaozhiService.instance.stopMic();
    await XiaozhiService.instance.listenStop();

    setState(() {
      _isPressed = false;
      _canCancel = false;
    });
    _animController.reverse();
  }

  void _onMoveUpdate(LongPressMoveUpdateDetails details) {
    // 判断是否上滑到取消区域 (距离顶部 < 100px)
    final shouldCancel = details.globalPosition.dy < 100;
    if (shouldCancel != _canCancel) {
      setState(() => _canCancel = shouldCancel);
      if (_canCancel) {
        HapticsService.instance.selection();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;

    return Stack(
      alignment: Alignment.center,
      children: [
        // 取消提示区域
        if (_isPressed)
          Positioned(
            top: 40,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: _canCancel ? 60 : 0,
              height: _canCancel ? 60 : 0,
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(30),
              ),
              child: _canCancel
                  ? Icon(Icons.close_rounded, color: errorColor, size: 32)
                  : null,
            ),
          ),

        // 主按钮
        GestureDetector(
          onLongPressStart: _onPressStart,
          onLongPressEnd: _onPressEnd,
          onLongPressMoveUpdate: _onMoveUpdate,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _isPressed ? 100 : 80,
            height: _isPressed ? 100 : 80,
            decoration: BoxDecoration(
              color: _canCancel
                  ? errorColor.withValues(alpha: 0.9)
                  : primaryColor.withValues(alpha: _isPressed ? 0.9 : 0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_canCancel ? errorColor : primaryColor).withValues(
                    alpha: 0.3,
                  ),
                  blurRadius: _isPressed ? 20 : 10,
                  spreadRadius: _isPressed ? 5 : 0,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 波纹动画
                if (_isPressed && !_canCancel)
                  ScaleTransition(
                    scale: _animController,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                // 图标
                Icon(
                  _canCancel ? Icons.close : Icons.mic,
                  color: Colors.white,
                  size: 40,
                ),
              ],
            ),
          ),
        ),

        // 底部提示文字
        if (_isPressed)
          Positioned(
            bottom: 20,
            child: AnimatedOpacity(
              opacity: _canCancel ? 0.6 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Text(
                _canCancel ? '松开取消' : '上滑取消',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

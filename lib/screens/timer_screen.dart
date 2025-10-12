import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/haptics_service.dart';
import '../widgets/metallic_card.dart';
import 'dart:async';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> with WidgetsBindingObserver {
  int _hours = 0;
  int _minutes = 0;
  int _seconds = 0;
  int _remainingSeconds = 0;
  int _totalSeconds = 0;
  Timer? _timer;
  bool _isRunning = false;
  Timer? _vibrationTimer;
  bool _isLandscape = false;
  
  // 滚动控制器
  late FixedExtentScrollController _hoursController;
  late FixedExtentScrollController _minutesController;
  late FixedExtentScrollController _secondsController;

  void _startTimer() {
    if (_hours == 0 && _minutes == 0 && _seconds == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请设置倒计时时间'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    setState(() {
      _totalSeconds = _hours * 3600 + _minutes * 60 + _seconds;
      _remainingSeconds = _totalSeconds;
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _stopTimer();
          _showTimerFinishedDialog();
        }
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _vibrationTimer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = 0;
      _totalSeconds = 0;
    });
  }

  void _showTimerFinishedDialog() async {
    // 启动强烈持续震动
    await _startContinuousVibration();
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('⏰ 时间到！'),
        content: const Text('倒计时已结束'),
        actions: [
          TextButton(
            onPressed: () {
              _vibrationTimer?.cancel();
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
  
  @override
  void initState() {
    super.initState();
    // 初始化滚动控制器
    _hoursController = FixedExtentScrollController(initialItem: _hours);
    _minutesController = FixedExtentScrollController(initialItem: _minutes);
    _secondsController = FixedExtentScrollController(initialItem: _seconds);
    
    WidgetsBinding.instance.addObserver(this);
    // 允许所有方向
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 修复：使用 WidgetsBinding 获取屏幕信息
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      final size = MediaQuery.of(context).size;
      final isLandscape = size.width > size.height;
      
      if (isLandscape != _isLandscape) {
        setState(() {
          _isLandscape = isLandscape;
        });
        
        // 横屏时自动全屏
        if (isLandscape) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );
        }
      }
    });
  }
  
  /// 启动持续强烈震动提醒
  Future<void> _startContinuousVibration() async {
    // 立即震动一次
    await HapticsService.instance.alertVibration();
    
    // 每隔 1 秒震动一次，持续提醒
    _vibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      await HapticsService.instance.alertVibration();
    });
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _vibrationTimer?.cancel();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    
    // 清理时恢复系统 UI 和方向
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 修复：在 build 时检测横屏状态
    final size = MediaQuery.of(context).size;
    final isCurrentlyLandscape = size.width > size.height;
    if (isCurrentlyLandscape != _isLandscape) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isLandscape = isCurrentlyLandscape;
          });
        }
      });
    }
    
    // 横屏时使用全屏专用布局
    if (_isLandscape) {
      return _buildLandscapeUI(isDark);
    }
    
    // 竖屏保持原有布局
    return Scaffold(
      appBar: AppBar(
        title: const Text('倒计时'),
      ),
      body: SafeArea(
        top: !_isLandscape,
        bottom: !_isLandscape,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final circleSize = maxW < 360 ? maxW - 32 : 280.0;
              return Stack(
                children: [
                  SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                  // 顶部计时展示或选择器
                  if (_remainingSeconds > 0)
                    MetallicCard(
                      padding: const EdgeInsets.all(24),
                      child: SizedBox(
                        width: circleSize,
                        height: circleSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: Size.square(circleSize),
                              painter: _TimerRingPainter(
                                progress: _totalSeconds == 0
                                    ? 0
                                    : (_totalSeconds - _remainingSeconds) /
                                          _totalSeconds,
                                isDark: isDark,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MetallicText(
                                  text: _formatTime(_remainingSeconds),
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800,
                                  isLarge: true,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '剩余时间',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    MetallicCard(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                      child: Column(
                        children: [
                          MetallicText(
                            text: '设置倒计时',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 180,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildScrollPicker(
                                    24,
                                    _hours,
                                    _hoursController,
                                    (value) async {
                                      await HapticsService.instance.pickerSelection();
                                      setState(() => _hours = value);
                                    },
                                    '时',
                                  ),
                                ),
                                const _PickerSeparator(),
                                Expanded(
                                  child: _buildScrollPicker(
                                    60,
                                    _minutes,
                                    _minutesController,
                                    (value) async {
                                      await HapticsService.instance.pickerSelection();
                                      setState(() => _minutes = value);
                                    },
                                    '分',
                                  ),
                                ),
                                const _PickerSeparator(),
                                Expanded(
                                  child: _buildScrollPicker(
                                    60,
                                    _seconds,
                                    _secondsController,
                                    (value) async {
                                      await HapticsService.instance.pickerSelection();
                                      setState(() => _seconds = value);
                                    },
                                    '秒',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 36),

                  // 控制按钮
                  if (_remainingSeconds > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isRunning)
                          MetallicButton(
                            onPressed: _pauseTimer,
                            isExtended: true,
                            icon: Icons.pause,
                            child: const Text('暂停'),
                          )
                        else
                          MetallicButton(
                            onPressed: () {
                              // 继续
                              setState(() => _isRunning = true);
                              _timer = Timer.periodic(
                                const Duration(seconds: 1),
                                (_) => setState(() {
                                  if (_remainingSeconds > 0) {
                                    _remainingSeconds--;
                                  } else {
                                    _stopTimer();
                                    _showTimerFinishedDialog();
                                  }
                                }),
                              );
                            },
                            isExtended: true,
                            icon: Icons.play_arrow,
                            child: const Text('继续'),
                          ),
                        const SizedBox(width: 16),
                        MetallicButton(
                          onPressed: _stopTimer,
                          isExtended: true,
                          icon: Icons.stop,
                          child: const Text('停止'),
                        ),
                      ],
                    )
                  else
                    MetallicButton(
                      onPressed: _startTimer,
                      isExtended: true,
                      icon: Icons.play_arrow,
                      child: const Text('开始', style: TextStyle(fontSize: 18)),
                    ),

                  const SizedBox(height: 20),

                  // 快速设置按钮
                  if (_remainingSeconds == 0) ...[
                    MetallicText(
                      text: '快速设置',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildQuickButton('1分钟', 0, 1, 0),
                        _buildQuickButton('5分钟', 0, 5, 0),
                        _buildQuickButton('10分钟', 0, 10, 0),
                        _buildQuickButton('30分钟', 0, 30, 0),
                        _buildQuickButton('1小时', 1, 0, 0),
                      ],
                    ),
                  ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildScrollPicker(
    int itemCount,
    int selectedValue,
    FixedExtentScrollController controller,
    Function(int) onChanged,
    String label,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: CupertinoPicker(
            scrollController: controller,
            itemExtent: 44,
            onSelectedItemChanged: onChanged,
            selectionOverlay: Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            children: List.generate(
              itemCount,
              (index) => Center(
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 22,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 横屏全屏UI - 大号圆环居中，底部控制按钮
  Widget _buildLandscapeUI(bool isDark) {
    return WillPopScope(
      onWillPop: () async {
        return true;
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF3F4F6),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final availableHeight = constraints.maxHeight;

              double circleSize = availableHeight * 0.7;
              circleSize = circleSize.clamp(220, 360);

              final progress = _totalSeconds == 0
                  ? 0.0
                  : (_totalSeconds - _remainingSeconds) / _totalSeconds;

              Widget timerCircle = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: circleSize,
                    height: circleSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: Size.square(circleSize),
                          painter: _TimerRingPainter(
                            progress: progress,
                            isDark: isDark,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: circleSize * 0.78,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _formatTime(_remainingSeconds),
                                  style: TextStyle(
                                    fontSize: circleSize * 0.22,
                                    fontWeight: FontWeight.w900,
                                    color: isDark
                                        ? const Color(0xFFE5E7EB)
                                        : const Color(0xFF111827),
                                    letterSpacing: -1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isRunning ? '倒计时进行中' : '倒计时已暂停',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.grey[400] : Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLandscapeControlButton(
                        icon: _isRunning ? Icons.pause : Icons.play_arrow,
                        label: _isRunning ? '暂停' : '继续',
                        onTap: _isRunning
                            ? _pauseTimer
                            : () {
                                setState(() => _isRunning = true);
                                _timer = Timer.periodic(
                                  const Duration(seconds: 1),
                                  (_) => setState(() {
                                    if (_remainingSeconds > 0) {
                                      _remainingSeconds--;
                                    } else {
                                      _stopTimer();
                                      _showTimerFinishedDialog();
                                    }
                                  }),
                                );
                              },
                        isDark: isDark,
                      ),
                      const SizedBox(width: 20),
                      _buildLandscapeControlButton(
                        icon: Icons.stop,
                        label: '停止',
                        onTap: _stopTimer,
                        isDark: isDark,
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              );

              if (_remainingSeconds <= 0) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 96,
                          color: isDark ? Colors.grey[700] : Colors.grey[400],
                        ),
                        const SizedBox(height: 24),
                        MetallicText(
                          text: '横屏模式下无法设置',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '请旋转设备回竖屏以设置倒计时时间。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (availableWidth < 900) {
                return Center(
                  child: timerCircle,
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: Center(child: timerCircle),
                  ),
                  Container(
                    width: 1,
                    height: availableHeight * 0.7,
                    margin: const EdgeInsets.symmetric(vertical: 32),
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        MetallicText(
                          text: '倒计时进度',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: availableWidth * 0.28,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '总时长',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 4),
                              MetallicText(
                                text: _formatTime(_totalSeconds),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                '已用时间',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 4),
                              MetallicText(
                                text: _formatTime(_totalSeconds - _remainingSeconds),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                '进度',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 10,
                                  backgroundColor: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.08),
                                  valueColor: AlwaysStoppedAnimation(
                                    isDark
                                        ? const Color(0xFF60A5FA)
                                        : const Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                '状态',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isRunning
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFFF59E0B),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isRunning ? '倒计时进行中' : '倒计时已暂停',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.grey[200]
                                          : const Color(0xFF111827),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 横屏控制按钮
  Widget _buildLandscapeControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: () async {
        await HapticsService.instance.impact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDestructive
                ? [
                    const Color(0xFFEF4444),
                    const Color(0xFFDC2626),
                  ]
                : isDark
                    ? [const Color(0xFF6B7280), const Color(0xFF4B5563)]
                    : [const Color(0xFFD1D5DB), const Color(0xFFA8A8A8)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.white.withValues(alpha: isDark ? 0.1 : 0.6),
              offset: const Offset(-2, -2),
              blurRadius: 4,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.3),
              offset: const Offset(2, 2),
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickButton(String label, int hours, int minutes, int seconds) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF6B7280), const Color(0xFF4B5563)]
              : [const Color(0xFFE5E7EB), const Color(0xFFC0C0C0)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.5),
            offset: const Offset(-1, -1),
            blurRadius: 3,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.2),
            offset: const Offset(1, 1),
            blurRadius: 3,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            debugPrint('🔘 快速设置按钮被点击: $label');
            await HapticsService.instance.impact();
            
            // 更新滚动位置
            if (_hoursController.hasClients && hours != _hours) {
              _hoursController.animateToItem(
                hours,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
            if (_minutesController.hasClients && minutes != _minutes) {
              _minutesController.animateToItem(
                minutes,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
            if (_secondsController.hasClients && seconds != _seconds) {
              _secondsController.animateToItem(
                seconds,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
            
            setState(() {
              _hours = hours;
              _minutes = minutes;
              _seconds = seconds;
              debugPrint('✅ 已设置时间: ${hours}小时 ${minutes}分钟 ${seconds}秒');
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: MetallicText(
              text: label,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress; // 0 ~ 1
  final bool isDark;

  _TimerRingPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // 背景环（金属渐变 + 凸起）
    final bgRect = Rect.fromCircle(center: center, radius: radius);
    final bgPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 6.28318,
        colors: isDark
            ? [
                const Color(0xFF4B5563),
                const Color(0xFF6B7280),
                const Color(0xFF4B5563),
              ]
            : [
                const Color(0xFFBFC7CF),
                const Color(0xFFE7EBF0),
                const Color(0xFFBFC7CF),
              ],
      ).createShader(bgRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 2);

    canvas.drawArc(bgRect, 0, 6.28318, false, bgPaint);

    // 进度环
    final angle = (progress.clamp(0.0, 1.0)) * 6.28318;
    if (angle > 0) {
      final progPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -1.5708,
          endAngle: -1.5708 + angle,
          colors: isDark
              ? [const Color(0xFF93C5FD), const Color(0xFF60A5FA)]
              : [const Color(0xFF2563EB), const Color(0xFF60A5FA)],
        ).createShader(bgRect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 12;

      canvas.drawArc(bgRect, -1.5708, angle, false, progPaint);
    }

    // 内层微阴影以增加金属深度
    final innerPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.25 : 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius - 8, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _TimerRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

class _PickerSeparator extends StatelessWidget {
  const _PickerSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Center(
        child: MetallicText(
          text: ':',
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

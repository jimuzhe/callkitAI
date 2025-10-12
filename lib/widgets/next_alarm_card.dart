import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../models/alarm.dart';
import './weather_card.dart';
import '../services/weather_service.dart';
import '../providers/alarm_provider.dart';

class NextAlarmCard extends StatefulWidget {
  final Alarm? nextAlarm;
  final Duration? duration;

  const NextAlarmCard({super.key, this.nextAlarm, this.duration});

  @override
  State<NextAlarmCard> createState() => _NextAlarmCardState();
}

class _NextAlarmCardState extends State<NextAlarmCard> {
  Timer? _timer;
  Timer? _weatherTimer;
  Duration? _currentDuration;
  WeatherNow? _weather;
  bool _isLoadingWeather = false;

  @override
  void initState() {
    super.initState();
    _currentDuration = widget.duration;
    _startTimer();
    _loadWeather();
    // 每30分钟刷新一次天气
    _weatherTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _loadWeather();
    });
  }

  @override
  void didUpdateWidget(NextAlarmCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _currentDuration = widget.duration;
      _startTimer();
    }
  }

  Future<void> _loadWeather() async {
    if (!mounted) return;

    setState(() {
      _isLoadingWeather = true;
    });
    // 先尝试缓存，快速显示
    final cached = WeatherService.instance.getCachedNow();
    if (mounted && cached != null) {
      setState(() {
        _weather = cached;
      });
    }

    final weather = await WeatherService.instance.getNowWeather(
      allowCache: true,
    );

    if (mounted) {
      setState(() {
        _weather = weather;
        _isLoadingWeather = false;
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentDuration == null) return;
      if (_currentDuration!.inSeconds > 0) {
        setState(() {
          _currentDuration = _currentDuration! - const Duration(seconds: 1);
        });
      } else {
        // 倒计时到达，刷新 Provider 以切换到下一个闹钟或天气卡片
        _timer?.cancel();
        setState(() {
          _currentDuration = const Duration(seconds: 0);
        });
        try {
          final provider = context.read<AlarmProvider>();
          // 触发一次重算/刷新（会 notifyListeners，从而让 AlarmScreen 重建）
          provider.loadAlarms();
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _weatherTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nextAlarm == null) {
      // 没有闹钟时显示完整天气卡片
      return const WeatherCard(isFullMode: true);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF4B5563),
                    const Color(0xFF374151),
                    const Color(0xFF3F4753),
                    const Color(0xFF2D3748),
                  ]
                : [
                    const Color(0xFFE8E8E8),
                    const Color(0xFFC0C0C0),
                    const Color(0xFFD4D4D4),
                    const Color(0xFFA8A8A8),
                  ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.8),
              offset: const Offset(-2, -2),
              blurRadius: 6,
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              offset: const Offset(2, 2),
              blurRadius: 6,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.4),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.1),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 160),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧:闹钟信息
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部:标题
                        Row(
                          children: [
                            // 左侧:闹钟图标和标题
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.alarm,
                                    color: Color(0xFF4A5568),
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '下一个闹钟',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: const Color(0xFF2D3748),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      shadows: [
                                        Shadow(
                                          color: Colors.white.withValues(
                                            alpha: 0.8,
                                          ),
                                          offset: const Offset(0, 1),
                                          blurRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 保持标题简洁,不显示天气
                          ],
                        ),
                        const SizedBox(height: 20),
                        // 闹钟时间
                        Text(
                          widget.nextAlarm!.getFormattedTime(),
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? Colors.grey[200]
                                : const Color(0xFF1A202C),
                            height: 1,
                            letterSpacing: -1,
                            shadows: [
                              Shadow(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.white.withValues(alpha: 0.9),
                                offset: const Offset(0, 2),
                                blurRadius: 2,
                              ),
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                offset: const Offset(0, -1),
                                blurRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 闹钟名称
                        Text(
                          widget.nextAlarm!.name,
                          style: TextStyle(
                            fontSize: 20,
                            color: isDark
                                ? Colors.grey[300]
                                : const Color(0xFF2D3748),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                            shadows: [
                              Shadow(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.white.withValues(alpha: 0.7),
                                offset: const Offset(0, 1),
                                blurRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // 倒计时
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF4A5568).withValues(alpha: 0.15),
                                const Color(0xFF2D3748).withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: isDark
                                    ? Colors.grey[400]
                                    : const Color(0xFF4A5568),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _formatCountdown(
                                    _currentDuration ?? widget.duration!,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.grey[300]
                                        : const Color(0xFF2D3748),
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 右侧:天气信息
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 2,
                    child: _weather != null
                        ? _buildWeatherSidebar()
                        : _buildWeatherPlaceholder(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatCountdown(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 24) {
      final days = hours ~/ 24;
      final remainingHours = hours % 24;
      return '$days天 $remainingHours小时后响铃';
    } else if (hours > 0) {
      return '$hours小时 $minutes分钟后响铃';
    } else if (minutes > 0) {
      return '$minutes分钟 $seconds秒后响铃';
    } else {
      return '$seconds秒后响铃';
    }
  }

  // 右侧天气信息栏
  Widget _buildWeatherSidebar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 自适应小屏宽度，避免文字/图标溢出
        final w = constraints.maxWidth;
        // final colGap = 12.0;
        final rowGap = 8.0;
        final iconSize = w < 120 ? 36.0 : (w < 160 ? 44.0 : 56.0);
        final tempSize = w < 120 ? 22.0 : (w < 160 ? 26.0 : 32.0);
        // final colWidth = (w - colGap) / 2; // 预留，如果后续要做两列布局

        Widget infoRow(IconData icon, String text) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isDark ? Colors.grey[400] : const Color(0xFF4A5568),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[300] : const Color(0xFF2D3748),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          );
        }

        // 统一上下间距：在侧栏内部增加对称的垂直内边距
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 单行: 图标 + 温度 + 天气状况
              Row(
                children: [
                  Image.network(
                    _weather!.getIconUrl(),
                    width: iconSize,
                    height: iconSize,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.wb_sunny_outlined,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: iconSize,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_weather!.temp}°',
                    style: TextStyle(
                      fontSize: tempSize,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? Colors.grey[200]
                          : const Color(0xFF1A202C),
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _weather!.text,
                      style: TextStyle(
                        fontSize: w < 140 ? 13 : 16,
                        color: isDark
                            ? Colors.grey[300]
                            : const Color(0xFF4A5568),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 第一行：体感
              SizedBox(
                width: double.infinity,
                child: infoRow(
                  Icons.thermostat_outlined,
                  '体感 ${_weather!.feelsLike}°',
                ),
              ),
              SizedBox(height: rowGap),
              // 第二行：湿度
              SizedBox(
                width: double.infinity,
                child: infoRow(
                  Icons.water_drop_outlined,
                  '湿度 ${_weather!.humidity}%',
                ),
              ),
              SizedBox(height: rowGap),
              // 第三行：风
              SizedBox(
                width: double.infinity,
                child: infoRow(
                  Icons.air,
                  '${_weather!.windDir} ${_weather!.windScale}级',
                ),
              ),
              SizedBox(height: rowGap),
              // 第四行：能见度
              SizedBox(
                width: double.infinity,
                child: infoRow(
                  Icons.visibility_outlined,
                  '能见度 ${_weather!.vis}km',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ...

  // ...

  // 天气占位符(加载中或未配置)
  Widget _buildWeatherPlaceholder() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 根据配置状态调整提示文案
    return FutureBuilder<bool>(
      future: WeatherService.instance.hasValidConfig(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          );
        }
        final hasConfig = snapshot.data == true;
        // 当配置刚变为可用且当前没有天气数据时，自动触发一次加载
        if (hasConfig && !_isLoadingWeather && _weather == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadWeather();
          });
        }
        final title = _isLoadingWeather
            ? '加载中...'
            : (hasConfig ? '获取失败' : '未配置');
        final sub = _isLoadingWeather
            ? null
            : (hasConfig ? '稍后自动重试' : '请在设置中配置和风天气');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoadingWeather)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              )
            else
              Icon(
                hasConfig ? Icons.cloud_off_outlined : Icons.settings_outlined,
                size: 48,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
                fontWeight: FontWeight.w600,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[600] : Colors.grey[500],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

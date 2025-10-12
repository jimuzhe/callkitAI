import 'package:flutter/material.dart';
import 'dart:async';
import '../services/weather_service.dart';
import './metallic_card.dart';

class WeatherCard extends StatefulWidget {
  final bool isFullMode; // 是否为完整模式(无闹钟时显示)

  const WeatherCard({super.key, this.isFullMode = false});

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  WeatherNow? _weather;
  bool _isLoading = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    // 每30分钟自动刷新一次
    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _loadWeather();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    setState(() {
      _isLoading = true;
    });

    final weather = await WeatherService.instance.getNowWeather();

    if (mounted) {
      setState(() {
        _weather = weather;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_weather == null && !_isLoading) {
      if (widget.isFullMode) {
        return Card(
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.3),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 64,
                      color: isDark ? Colors.grey[500] : Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '天气未配置',
                      style: TextStyle(
                        fontSize: 18,
                        color: isDark ? Colors.grey[500] : Colors.grey[400],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '请在设置中配置和风天气 API',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[600] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else {
        return MetallicCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 32,
                color: isDark ? Colors.grey[500] : Colors.grey[400],
              ),
              const SizedBox(height: 8),
              Text(
                '天气未配置',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                ),
              ),
            ],
          ),
        );
      }
    }

    if (_isLoading && _weather == null) {
      if (widget.isFullMode) {
        return Card(
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.3),
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
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        return MetallicCard(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        );
      }
    }

    if (widget.isFullMode) {
      return Card(
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.3),
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
                child: _buildFullModeLayout(isDark),
              ),
            ),
          ),
        ),
      );
    } else {
      return MetallicCard(
        padding: const EdgeInsets.all(16),
        child: _buildCompactModeLayout(isDark),
      );
    }
  }

  // 完整模式布局(无闹钟时)
  Widget _buildFullModeLayout(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 上半部分:图标和温度/天气
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧:天气图标
            SizedBox(
              width: 96,
              height: 96,
              child: Image.network(
                _weather!.getIconUrl(),
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.wb_sunny_outlined,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 80,
                  );
                },
              ),
            ),
            const SizedBox(width: 20),
            // 右侧:温度和天气状况
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 温度和天气在同一行
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      MetallicText(
                        text: '${_weather!.temp}°',
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        isLarge: true,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _weather!.text,
                          style: TextStyle(
                            fontSize: 22,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildSoftDivider(isDark),
        const SizedBox(height: 14),
        // 下半部分:详细信息网格(2x2) + 脚注行
        Column(
          children: [
            // 第一行:体感温度、风力风向
            Row(
              children: [
                Expanded(
                  child: _buildFullInfoItem(
                    Icons.thermostat_outlined,
                    '体感温度',
                    '${_weather!.feelsLike}°',
                    isDark,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildFullInfoItem(
                    Icons.air,
                    '风力风向',
                    '${_weather!.windDir} ${_weather!.windScale}级',
                    isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSoftDivider(isDark),
            const SizedBox(height: 10),
            // 第二行:湿度、能见度
            Row(
              children: [
                Expanded(
                  child: _buildFullInfoItem(
                    Icons.water_drop_outlined,
                    '相对湿度',
                    '${_weather!.humidity}%',
                    isDark,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildFullInfoItem(
                    Icons.visibility_outlined,
                    '能见度',
                    '${_weather!.vis}km',
                    isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '气压 ${_weather!.pressure}hPa · 云量 ${_weather!.cloud}%',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 柔和分隔线
  Widget _buildSoftDivider(bool isDark) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.06),
                ]
              : [
                  const Color(0xFF4A5568).withValues(alpha: 0.06),
                  const Color(0xFF4A5568).withValues(alpha: 0.12),
                  const Color(0xFF4A5568).withValues(alpha: 0.06),
                ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  // 紧凑模式布局(有闹钟时,右侧小卡片)
  Widget _buildCompactModeLayout(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 温度和天气图标
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 天气图标
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF4B5563), const Color(0xFF374151)]
                      : [
                          Colors.white.withValues(alpha: 0.9),
                          Colors.grey.shade200,
                        ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(0),
                child: Image.network(
                  _weather!.getIconUrl(),
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.wb_sunny_outlined,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: 24,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 温度
                  MetallicText(
                    text: '${_weather!.temp}°',
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    isLarge: true,
                  ),
                  const SizedBox(height: 2),
                  // 天气状况
                  Text(
                    _weather!.text,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 体感温度
        _buildInfoRow(
          Icons.thermostat_outlined,
          '体感',
          '${_weather!.feelsLike}°',
          isDark,
        ),
        const SizedBox(height: 6),
        // 风力风向
        _buildInfoRow(
          Icons.air,
          _weather!.windDir,
          '${_weather!.windScale}级',
          isDark,
        ),
      ],
    );
  }

  // 完整模式的信息项(无背景框)
  Widget _buildFullInfoItem(
    IconData icon,
    String label,
    String value,
    bool isDark,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label：$value',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
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

  // 紧凑模式的信息行
  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: isDark ? Colors.grey[500] : Colors.grey[500],
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$label：$value',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
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
}

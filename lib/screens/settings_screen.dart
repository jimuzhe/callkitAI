import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:provider/provider.dart';
// kIsWeb not used in this file
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/haptics_service.dart';
import '../providers/theme_provider.dart';
import '../models/ai_persona.dart';
import '../services/persona_store.dart';
import '../widgets/metallic_card.dart';
import '../services/weather_service.dart';
import '../pages/audio_test_page.dart';
import '../pages/debug_log_page.dart';
import 'log_viewer_screen.dart';
import '../services/audio_service.dart';
// location_service not used here; keep imports minimal
import '../services/xiaozhi_service.dart';
import '../services/notification_service.dart';
import '../services/callkit_service.dart';
import 'persona_manager_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _keepAliveEnabled = false;
  bool _vibrationEnabled = true;
  int _vibrationIntensity = 1; // 0:轻, 1:中, 2:强
  String _weatherApiKey = '';
  String _weatherApiHost = '';
  // ignore: unused_field
  String _weatherLocation = '';
  String _weatherLocationName = '北京';
  bool _panicModeEnabled = false;
  int _panicNotificationCount = 200;
  int _panicNotificationInterval = 3;
  // Xiaozhi settings
  String _xiaozhiOtaUrl = '';
  String _xiaozhiWsUrl = '';
  String _xiaozhiDeviceId = '';
  String _xiaozhiAccessToken = '';
  String _xiaozhiClientId = '';
  String _xiaozhiSerialNumber = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final svc = WeatherService.instance;
    final host = await svc.getApiHost();
    final key = await svc.getApiKey();
    // Xiaozhi
    final xo = await XiaozhiService.instance.getOtaUrl();
    final xw = await XiaozhiService.instance.getWsUrl();
    final xd = await XiaozhiService.instance.getDeviceId();
    final xt = await XiaozhiService.instance.getAccessToken();
    final xc = await XiaozhiService.instance.getClientId();
    final xsn = await XiaozhiService.instance.getSerialNumber();
    final keepAliveEnabled = prefs.getBool('keep_alive_enabled') ?? false;
    setState(() {
      _keepAliveEnabled = keepAliveEnabled;
      _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      _vibrationIntensity = prefs.getInt('vibration_intensity') ?? 1;
      _weatherApiKey = key ?? '';
      _weatherApiHost = host ?? '';
      _weatherLocation = prefs.getString('weather_location') ?? '101010100';
      _weatherLocationName = prefs.getString('weather_location_name') ?? '北京';
      _xiaozhiOtaUrl = xo;
      _xiaozhiWsUrl = xw;
      _xiaozhiDeviceId = xd;
      _xiaozhiAccessToken = xt;
      _xiaozhiClientId = xc;
      _xiaozhiSerialNumber = xsn;
      _panicModeEnabled = prefs.getBool('panic_mode_enabled') ?? false;
      _panicNotificationCount = prefs.getInt('panic_notification_count') ?? 200;
      _panicNotificationInterval =
          prefs.getInt('panic_notification_interval') ?? 3;
    });

    if (keepAliveEnabled) {
      await AudioService.instance.ensureBackgroundKeepAlive();
    } else {
      await AudioService.instance.disableBackgroundKeepAlive();
    }
  }

  String _getVibrationIntensityLabel() {
    switch (_vibrationIntensity) {
      case 0:
        return '轻 - 轻柔触感，按键反馈柔和';
      case 1:
        return '中 - 标准触感，按键反馈适中';
      case 2:
        return '强 - 明显触感，按键反馈增强';
      default:
        return '中 - 标准触感，按键反馈适中';
    }
  }

  Future<void> _showPanicCountDialog(BuildContext context) async {
    final controller = TextEditingController(
      text: _panicNotificationCount.toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('设置连续通知次数'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '输入 1 - 500 之间的整数'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null) {
                  Navigator.of(context).pop();
                  return;
                }
                final num clamped = parsed.clamp(1, 500);
                Navigator.of(context).pop(clamped.toInt());
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('panic_notification_count', result);
      setState(() {
        _panicNotificationCount = result;
      });
      await NotificationService.instance.refreshPanicConfig();
    }
  }

  Future<void> _showPanicIntervalDialog(BuildContext context) async {
    final controller = TextEditingController(
      text: _panicNotificationInterval.toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('设置通知间隔'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '输入 1 - 60 之间的秒数'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null) {
                  Navigator.of(context).pop();
                  return;
                }
                final num clamped = parsed.clamp(1, 60);
                Navigator.of(context).pop(clamped.toInt());
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('panic_notification_interval', result);
      setState(() {
        _panicNotificationInterval = result;
      });
      await NotificationService.instance.refreshPanicConfig();
    }
  }

  // 震动时长已统一由 HapticsService 控制，这里不再需要本地计算

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSection(
            context,
            title: '显示',
            children: [
              _buildMetallicListTile(
                context,
                icon: Icons.brightness_6_outlined,
                title: '主题模式',
                subtitle: _themeModeLabel(
                  context.read<ThemeProvider>().themeMode,
                ),
                onTap: () => _showThemeSelector(context),
              ),
            ],
          ),
          _buildSection(
            context,
            title: '行为',
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      MetallicIconBox(
                        icon: Icons.phone_in_talk_outlined,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MetallicText(
                              text: '自动来电（后台保活）',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '到点无需点通知，直接弹出来电界面',
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _keepAliveEnabled,
                        onChanged: (v) async {
                          await HapticsService.instance.impact();
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('keep_alive_enabled', v);
                          setState(() {
                            _keepAliveEnabled = v;
                          });
                          if (v) {
                            await AudioService.instance
                                .ensureBackgroundKeepAlive();
                          } else {
                            await AudioService.instance
                                .disableBackgroundKeepAlive();
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(v ? '已开启自动来电' : '已关闭自动来电'),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              _buildMetallicListTile(
                context,
                icon: Icons.manage_accounts_outlined,
                title: '管理AI人设库',
                subtitle: '新增/编辑/删除自定义人设',
                onTap: () async {
                  await HapticsService.instance.selection();
                  if (!mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PersonaManagerScreen(),
                    ),
                  );
                  // 可能默认人设被修改，刷新显示
                  _loadSettings();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  '提示：iOS 在应用被系统挂起或锁屏时，不能直接凭本地代码拉起 CallKit。\n'
                  '若需要真正的“来电式”唤醒，请接入 VoIP Push（后台推送）或依赖本地通知兜底后再进入通话。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[400]
                        : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          _buildSection(
            context,
            title: '通知设置',
            children: [
              _buildMetallicListTile(
                context,
                icon: Icons.notifications_outlined,
                title: '通知权限',
                subtitle: '已授权',
                onTap: () {
                  // 跳转到系统设置
                },
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      MetallicIconBox(icon: Icons.vibration_outlined, size: 24),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MetallicText(
                              text: '触觉反馈',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '操作时振动',
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _vibrationEnabled,
                        onChanged: (value) async {
                          await HapticsService.instance.impact();
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('vibration_enabled', value);
                          setState(() {
                            _vibrationEnabled = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (_vibrationEnabled) ...[
                const Divider(height: 1, indent: 56, endIndent: 16),
                _buildMetallicListTile(
                  context,
                  icon: Icons.tune,
                  title: '震动强度',
                  subtitle: _getVibrationIntensityLabel(),
                  onTap: () => _showVibrationIntensitySelector(context),
                ),
              ],
              const Divider(height: 1, indent: 56, endIndent: 16),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      MetallicIconBox(
                        icon: Icons.warning_amber_rounded,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MetallicText(
                              text: '急中生智模式',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '闹钟到点后持续推送通知，直到接听为止',
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _panicModeEnabled,
                        onChanged: (value) async {
                          await HapticsService.instance.impact();
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('panic_mode_enabled', value);
                          setState(() {
                            _panicModeEnabled = value;
                          });
                          await NotificationService.instance
                              .refreshPanicConfig();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (_panicModeEnabled) ...[
                const Divider(height: 1, indent: 56, endIndent: 16),
                _buildMetallicListTile(
                  context,
                  icon: Icons.numbers,
                  title: '连续通知次数',
                  subtitle: '$_panicNotificationCount次',
                  onTap: () => _showPanicCountDialog(context),
                ),
                const Divider(height: 1, indent: 56, endIndent: 16),
                _buildMetallicListTile(
                  context,
                  icon: Icons.timer_outlined,
                  title: '通知间隔',
                  subtitle: '$_panicNotificationInterval秒',
                  onTap: () => _showPanicIntervalDialog(context),
                ),
              ],
            ],
          ),
          _buildSection(
            context,
            title: '权限',
            children: [
              _buildMetallicListTile(
                context,
                icon: Icons.location_on_outlined,
                title: '定位权限',
                subtitle: '用于自动获取城市以显示天气',
                onTap: () async {
                  await HapticsService.instance.selection();
                  final serviceEnabled =
                      await geolocator.Geolocator.isLocationServiceEnabled();
                  if (!serviceEnabled) {
                    await _showLocationPermissionHelp(
                      context,
                      error: '定位服务未开启',
                    );
                    return;
                  }
                  var permission =
                      await geolocator.Geolocator.checkPermission();
                  if (permission == geolocator.LocationPermission.denied) {
                    permission =
                        await geolocator.Geolocator.requestPermission();
                  }
                  if (permission ==
                      geolocator.LocationPermission.deniedForever) {
                    await _showLocationPermissionHelp(context);
                  } else if (permission ==
                      geolocator.LocationPermission.denied) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('定位权限已拒绝')));
                    }
                  } else {
                    // 已授权：尝试获取当前位置并解析为天气 location（city id 或 city name）
                    try {
                      final pos =
                          await geolocator.Geolocator.getCurrentPosition(
                            desiredAccuracy: geolocator.LocationAccuracy.low,
                          );
                      final resolved = await WeatherService.instance
                          .resolveLocation(
                            lat: pos.latitude,
                            lon: pos.longitude,
                          );
                      final name = await WeatherService.instance
                          .getLocationName();
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('weather_location', resolved);
                      await prefs.setString('weather_location_name', name);
                      if (mounted) {
                        setState(() {
                          _weatherLocation = resolved;
                          _weatherLocationName = name.isNotEmpty
                              ? name
                              : _weatherLocationName;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '已根据定位设置城市：${name.isNotEmpty ? name : resolved}',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('获取定位或解析城市失败：$e')),
                        );
                      }
                    }
                  }
                },
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              _buildMetallicListTile(
                context,
                icon: Icons.mic_none_outlined,
                title: '麦克风权限',
                subtitle: '用于通话录音/对讲',
                onTap: () async {
                  await HapticsService.instance.selection();
                  final status = await perm.Permission.microphone.status;
                  if (status.isDenied || status.isRestricted) {
                    await perm.Permission.microphone.request();
                  } else if (status.isPermanentlyDenied) {
                    await perm.openAppSettings();
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('麦克风权限已授权')));
                    }
                  }
                },
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              _buildMetallicListTile(
                context,
                icon: Icons.notifications_active_outlined,
                title: '通知权限',
                subtitle: '用于来电提醒/全屏意图',
                onTap: () async {
                  await HapticsService.instance.selection();
                  final status = await perm.Permission.notification.status;
                  if (status.isDenied || status.isRestricted) {
                    await perm.Permission.notification.request();
                  } else if (status.isPermanentlyDenied) {
                    await perm.openAppSettings();
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('通知权限已授权')));
                    }
                  }
                },
              ),
            ],
          ),
          _buildSection(
            context,
            title: '天气',
            children: [
              _buildMetallicListTile(
                context,
                icon: Icons.dns_outlined,
                title: 'API Host',
                subtitle: _weatherApiHost.isEmpty ? '未配置' : _weatherApiHost,
                onTap: () => _showWeatherApiHostDialog(context),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              _buildMetallicListTile(
                context,
                icon: Icons.key_outlined,
                title: 'API Key',
                subtitle: _weatherApiKey.isEmpty
                    ? '未配置'
                    : _maskApiKey(_weatherApiKey),
                onTap: () => _showWeatherApiKeyDialog(context),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              _buildMetallicListTile(
                context,
                icon: Icons.location_on_outlined,
                title: '城市',
                subtitle: _weatherLocationName,
                onTap: () => _showLocationDialog(context),
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'API配置',
            children: [
              _buildMetallicListTile(
                context,
                icon: Icons.settings_ethernet_outlined,
                title: '小智连接配置',
                subtitle: _buildXiaozhiSubtitle(),
                onTap: () => _showXiaozhiConfigDialog(context),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: '检查激活',
                      icon: const Icon(Icons.verified_user),
                      onPressed: () async {
                        final res = await XiaozhiService.instance
                            .checkActivation();
                        if (!mounted) return;
                        if (res.activated) {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('设备已激活'),
                              content: Text('Device: $_xiaozhiDeviceId'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('知道了'),
                                ),
                              ],
                            ),
                          );
                        } else {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('激活设备'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('验证码：${res.code ?? '——'}'),
                                  const SizedBox(height: 8),
                                  if (res.portalUrl != null)
                                    Text('门户：${res.portalUrl}'),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () async {
                                    // Start activation flow
                                    Navigator.pop(
                                      context,
                                    ); // close current dialog
                                    await _startActivation(context, res);
                                  },
                                  child: const Text('开始激活'),
                                ),
                                if (res.portalUrl != null)
                                  TextButton(
                                    onPressed: () async {
                                      final uri = Uri.parse(res.portalUrl!);
                                      if (await launcher.canLaunchUrl(uri)) {
                                        await launcher.launchUrl(
                                          uri,
                                          mode: launcher
                                              .LaunchMode
                                              .externalApplication,
                                        );
                                      }
                                    },
                                    child: const Text('打开门户'),
                                  ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('关闭'),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                    IconButton(
                      tooltip: '连接',
                      icon: const Icon(Icons.wifi_tethering),
                      onPressed: () async {
                        await XiaozhiService.instance.connect();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已发起连接（WebSocket）')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          _buildSection(
            context,
            title: '调试',
            children: [
              _buildMetallicListTile(
                context,
                icon: Icons.bug_report_outlined,
                title: '实时日志',
                subtitle: '查看应用运行日志（用于诊断连接问题）',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DebugLogPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              _buildMetallicListTile(
                context,
                icon: Icons.speaker_outlined,
                title: '音频测试',
                subtitle: '诊断音频播放问题',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AudioTestPage()),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context,
            title: '关于',
            children: [
              _buildMetallicListTile(
                context,
                icon: Icons.info_outline,
                title: '版本',
                subtitle: '1.0.0',
                trailing: Container(),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              FutureBuilder<String?>(
                future: CallKitService.instance.getVoipPushToken(),
                builder: (context, snap) {
                  final token = snap.data;
                  return _buildMetallicListTile(
                    context,
                    icon: Icons.phone_in_talk_outlined,
                    title: 'iOS VoIP 推送令牌',
                    subtitle: token == null || token.isEmpty
                        ? '仅真机可用，初始化后自动获取'
                        : '${token.substring(0, 10)}...${token.substring(token.length - 10)}',
                    onTap: token == null || token.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: token));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制 VoIP 令牌')),
                              );
                            }
                          },
                  );
                },
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              _buildMetallicListTile(
                context,
                icon: Icons.bug_report_outlined,
                title: '查看日志',
                onTap: () {
                  HapticsService.instance.selection();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LogViewerScreen()),
                  );
                },
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              _buildMetallicListTile(
                context,
                icon: Icons.help_outline,
                title: '帮助文档',
                onTap: () {
                  // TODO: 打开帮助文档
                },
              ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: MetallicText(
            text: title,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        MetallicCard(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildMetallicListTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            MetallicIconBox(icon: icon, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MetallicText(
                    text: title,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[400]
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[400]
                    : Colors.grey[600],
              ),
          ],
        ),
      ),
    );
  }

  void _showVibrationIntensitySelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择震动强度',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildIntensityOption(context, 0, '轻', '轻柔触感，适用于需要安静环境的场景'),
              const Divider(height: 1),
              _buildIntensityOption(context, 1, '中', '标准触感，平衡反馈强度和舒适度'),
              const Divider(height: 1),
              _buildIntensityOption(context, 2, '强', '明显触感，提供更强的操作反馈'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIntensityOption(
    BuildContext context,
    int value,
    String label,
    String description,
  ) {
    final isSelected = _vibrationIntensity == value;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      subtitle: Text(description),
      onTap: () async {
        // 先震动体验一下选择的强度
        await HapticsService.instance.previewImpact(value);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('vibration_intensity', value);
        setState(() {
          _vibrationIntensity = value;
        });

        if (mounted) {
          Navigator.pop(context);
        }
      },
    );
  }

  Future<void> _saveDefaultPersona(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_persona_id', id);
  }

  void _showXiaozhiConfigDialog(BuildContext context) async {
    final otaController = TextEditingController(text: _xiaozhiOtaUrl);
    final wsController = TextEditingController(text: _xiaozhiWsUrl);
    final deviceController = TextEditingController(text: _xiaozhiDeviceId);
    final tokenController = TextEditingController(text: _xiaozhiAccessToken);
    final clientController = TextEditingController(text: _xiaozhiClientId);
    final serialController = TextEditingController(text: _xiaozhiSerialNumber);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('配置小智服务'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: otaController,
                  decoration: const InputDecoration(
                    labelText: 'OTA 地址（激活）',
                    hintText: 'https://.../xiaozhi/ota/',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: wsController,
                  decoration: const InputDecoration(
                    labelText: '实时服务地址 (WS)',
                    hintText: 'wss://.../xiaozhi/v1/',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deviceController,
                  decoration: const InputDecoration(
                    labelText: '设备ID (MAC-like)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenController,
                  decoration: const InputDecoration(
                    labelText: '访问令牌 (Authorization)',
                    hintText: '可留空',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clientController,
                  decoration: const InputDecoration(
                    labelText: 'Client ID (可选)',
                    hintText: '默认自动生成 UUID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: serialController,
                  decoration: const InputDecoration(
                    labelText: '序列号 (serial_number)',
                    hintText: '设备已烧录的序列号',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await XiaozhiService.instance.saveConfig(
                  otaUrl: otaController.text.trim(),
                  wsUrl: wsController.text.trim(),
                  deviceId: deviceController.text.trim(),
                  accessToken: tokenController.text.trim(),
                  clientId: clientController.text.trim(),
                  serialNumber: serialController.text.trim(),
                );
                setState(() {
                  _xiaozhiOtaUrl = otaController.text.trim();
                  _xiaozhiWsUrl = wsController.text.trim();
                  _xiaozhiDeviceId = deviceController.text.trim();
                  _xiaozhiAccessToken = tokenController.text.trim();
                  _xiaozhiClientId = clientController.text.trim();
                  _xiaozhiSerialNumber = serialController.text.trim();
                });
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('小智配置已保存，若已连接请重新连接以生效')),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  String _buildXiaozhiSubtitle() {
    final ws = _xiaozhiWsUrl.isEmpty ? '未配置' : _xiaozhiWsUrl;
    final dev = _xiaozhiDeviceId.isEmpty ? '未生成' : _xiaozhiDeviceId;
    final token = _xiaozhiAccessToken.isEmpty
        ? '无'
        : _maskApiKey(_xiaozhiAccessToken);
    final client = _xiaozhiClientId.isEmpty
        ? '自动'
        : _xiaozhiClientId.substring(0, 8);
    final serial = _xiaozhiSerialNumber.isEmpty
        ? '未录入'
        : _xiaozhiSerialNumber.length <= 8
        ? _xiaozhiSerialNumber
        : '${_xiaozhiSerialNumber.substring(0, 6)}...';
    return 'WS: $ws · 设备: $dev · Token: $token · Client: $client · SN: $serial';
  }

  String _maskApiKey(String key) {
    if (key.length <= 8) return key;
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }

  String _themeModeLabel(ThemeMode mode) {
    if (mode == ThemeMode.light) return '浅色';
    if (mode == ThemeMode.dark) return '深色';
    return '跟随系统';
  }

  void _showThemeSelector(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final current = themeProvider.themeMode;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: const Text('跟随系统'),
                value: ThemeMode.system,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) themeProvider.setThemeMode(v);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ThemeMode>(
                title: const Text('浅色'),
                value: ThemeMode.light,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) themeProvider.setThemeMode(v);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ThemeMode>(
                title: const Text('深色'),
                value: ThemeMode.dark,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) themeProvider.setThemeMode(v);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showLocationPermissionHelp(
    BuildContext context, {
    String? error,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('定位权限帮助'),
        content: Text(error ?? '请在系统设置中允许应用使用定位权限，以便自动获取城市信息。'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await perm.openAppSettings();
              } catch (_) {}
            },
            child: const Text('打开系统设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentName =
        prefs.getString('weather_location_name') ?? _weatherLocationName;
    final nameController = TextEditingController(text: currentName);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置城市'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '城市名称'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await HapticsService.instance.selection();
              final cityNameInput = nameController.text.trim();
              if (cityNameInput.isNotEmpty) {
                // 尝试使用 Geo API 查找 city id 并保存。如果失败，则直接保存城市名作为可读名称
                final ok = await WeatherService.instance
                    .trySetLocationFromCityName(cityNameInput);
                if (ok) {
                  final savedLocation = await WeatherService.instance
                      .getLocation();
                  final name = await WeatherService.instance.getLocationName();
                  if (mounted) {
                    setState(() {
                      _weatherLocation = savedLocation;
                      _weatherLocationName = name.isNotEmpty
                          ? name
                          : cityNameInput;
                    });
                  }
                } else {
                  await prefs.setString('weather_location', cityNameInput);
                  await prefs.setString('weather_location_name', cityNameInput);
                  if (mounted) {
                    setState(() {
                      _weatherLocation = cityNameInput;
                      _weatherLocationName = cityNameInput;
                    });
                  }
                }
              }
              Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存城市')));
      }
    }
  }

  void _showWeatherApiKeyDialog(BuildContext context) {
    final controller = TextEditingController(text: _weatherApiKey);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置和风天气 API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '请输入 API Key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '获取免费 API Key:\n1. 访问 dev.qweather.com\n2. 注册并创建应用\n3. 复制 Web API Key',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await HapticsService.instance.impact();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('weather_api_key', controller.text);
              setState(() {
                _weatherApiKey = controller.text;
              });
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('API Key 已保存')));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showWeatherApiHostDialog(BuildContext context) {
    final controller = TextEditingController(text: _weatherApiHost);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置 API Host'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '例如: m23v59af3y.re.qweatherapi.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '在和风天气控制台中可以找到:\n项目管理 → 我的项目 → API Host',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await HapticsService.instance.impact();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('weather_api_host', controller.text);
              setState(() {
                _weatherApiHost = controller.text;
              });
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('API Host 已保存')));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _startActivation(
    BuildContext context,
    XiaozhiActivationResult res,
  ) async {
    // 尝试提取 challenge
    String? challenge = res.challenge;
    if (challenge == null && res.raw != null) {
      try {
        final raw = res.raw as Map;
        if (raw['challenge'] != null) challenge = raw['challenge'].toString();
        if (challenge == null && raw['message'] != null) {
          final msg = raw['message'].toString();
          // 尝试从 message 中抽取看起来像 challenge 的十六进制串或随机 token
          final m = RegExp(r"[0-9A-Fa-f]{8,}").firstMatch(msg);
          if (m != null) challenge = m.group(0);
        }
      } catch (_) {}
    }

    if (challenge == null || challenge.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('无法获取 challenge'),
          content: const Text('服务器未返回可用的 challenge，无法进行激活。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    int attempt = 0;
    String lastResp = '等待响应...';
    bool detected200k = false;

    // show progress dialog with StatefulBuilder to update UI
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('激活中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('challenge: $challenge'),
                  const SizedBox(height: 8),
                  Text('尝试次数：$attempt'),
                  const SizedBox(height: 8),
                  Text('最后响应：'),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      child: Text(
                        lastResp,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    // 取消：关闭对话框即可（activateWithChallenge 会继续在后台运行，但由于我们不 hold 它在此处，可以考虑未来取消 Token）
                    Navigator.pop(context);
                  },
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      },
    );

    // 调用激活方法并在回调中更新对话框
    final success = await XiaozhiService.instance.activateWithChallenge(
      challenge,
      onAttempt: (a, resp) async {
        attempt = a;
        if (resp != null) {
          try {
            lastResp = resp.toString();
          } catch (_) {
            lastResp = resp.toString();
          }
        } else {
          lastResp = '请求失败或无响应';
        }

        // 如果响应中包含 '200k'，视为激活成功并立即处理
        try {
          final lr = lastResp.toLowerCase();
          if (!detected200k && lr.contains('200k')) {
            detected200k = true;
            // 关闭进度对话框（如果仍然打开）
            try {
              if (context.mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            } catch (_) {}

            // 标记本地已激活并提示用户（均在 mounted 检查下进行）
            await XiaozhiService.instance.setLocalActivated(true);
            if (context.mounted) {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('激活成功'),
                  content: const Text('设备已激活。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            }
            await _loadSettings();
            // 返回以避免重复处理
            return;
          }
        } catch (_) {}

        // 更新对话框 UI
        if (!mounted) return;
        // Rebuild by marking the overlay context
        try {
          (context as Element).markNeedsBuild();
        } catch (_) {}
      },
    );

    // 关闭进度对话框（如果仍然打开）
    try {
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (_) {}

    if (success) {
      await XiaozhiService.instance.setLocalActivated(true);
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('激活成功'),
            content: const Text('设备已激活。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      await _loadSettings();
    } else {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('激活失败'),
            content: const Text('尝试多次未能激活，请稍后重试或查看日志以获得更多信息。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    }
  }
}

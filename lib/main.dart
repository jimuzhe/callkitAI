import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import 'providers/alarm_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'services/callkit_service.dart';
import 'services/audio_service.dart';
import 'services/notification_service.dart';
import 'services/app_log_service.dart';
import 'utils/database_helper.dart';
import 'config/app_environment.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppLogService.instance.attach();

  await _loadEnvironment();

  // 初始化时区数据
  tz.initializeTimeZones();

  // 初始化数据库
  await DatabaseHelper.instance.database;

  // 初始化通知服务
  await NotificationService.instance.initialize();

  // 初始化CallKit服务
  await CallKitService.instance.initialize();

  // 初始化音频服务
  try {
    await AudioService.instance.initialize();
    debugPrint('✅ 音频服务初始化成功');
  } catch (e) {
    debugPrint('❌ 音频服务初始化失败: $e');
  }

  // iOS：预请求麦克风权限，保证来电接通后能立即录音/对话
  try {
    await Permission.microphone.request();
  } catch (_) {}

  // 设置竖屏方向
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

Future<void> _loadEnvironment() async {
  final targetFile = AppEnvironmentConfig.isDev ? '.env.dev' : '.env';
  try {
    await dotenv.load(fileName: targetFile);
  } catch (error) {
    if (AppEnvironmentConfig.isDev) {
      debugPrint('加载 $targetFile 失败: $error, 回退到 .env');
      await dotenv.load(fileName: '.env');
    } else {
      rethrow;
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AlarmProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => GetMaterialApp(
          title: 'AI Call Clock',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF8B92A8),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFE5E7EB),
            appBarTheme: AppBarTheme(
              elevation: 0,
              centerTitle: true,
              backgroundColor: const Color(0xFFD1D5DB),
              foregroundColor: const Color(0xFF1F2937),
              shadowColor: Colors.black.withValues(alpha: 0.2),
            ),
            cardTheme: CardThemeData(
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: const Color(0xFFE5E7EB),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF9CA3AF);
                }
                return const Color(0xFFD1D5DB);
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF6B7280);
                }
                return const Color(0xFFE5E7EB);
              }),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                backgroundColor: const Color(0xFFD1D5DB),
                foregroundColor: const Color(0xFF1F2937),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              elevation: 8,
              backgroundColor: const Color(0xFFC0C0C0),
              foregroundColor: const Color(0xFF1F2937),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6B7280),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF1F2937),
            appBarTheme: AppBarTheme(
              elevation: 0,
              centerTitle: true,
              backgroundColor: const Color(0xFF374151),
              foregroundColor: const Color(0xFFE5E7EB),
              shadowColor: Colors.black.withValues(alpha: 0.5),
            ),
            cardTheme: CardThemeData(
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: const Color(0xFF374151),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.5),
                backgroundColor: const Color(0xFF4B5563),
                foregroundColor: const Color(0xFFE5E7EB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              elevation: 8,
              backgroundColor: const Color(0xFF6B7280),
              foregroundColor: const Color(0xFFE5E7EB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          themeMode: themeProvider.themeMode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

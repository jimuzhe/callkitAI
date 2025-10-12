import 'package:flutter/material.dart';
import './alarm_screen.dart';
import './timer_screen.dart';
import './settings_screen.dart';
import './ai_call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const AlarmScreen(),
    const TimerScreen(),
    const AICallScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final bool hideBottomBar = orientation == Orientation.landscape && _currentIndex == 1;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: hideBottomBar
          ? null
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: Theme.of(context).brightness == Brightness.dark
                      ? [const Color(0xFF374151), const Color(0xFF2D3748)]
                      : [const Color(0xFFD1D5DB), const Color(0xFFC0C0C0)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    offset: const Offset(0, -2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                backgroundColor: Colors.transparent,
                elevation: 0,
                indicatorColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF4B5563).withValues(alpha: 0.5)
                    : const Color(0xFFE5E7EB).withValues(alpha: 0.5),
                onDestinationSelected: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.alarm_outlined),
                    selectedIcon: Icon(Icons.alarm),
                    label: '闹钟',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.timer_outlined),
                    selectedIcon: Icon(Icons.timer),
                    label: '倒计时',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.phone_in_talk_outlined),
                    selectedIcon: Icon(Icons.phone_in_talk),
                    label: 'AI通话',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: '设置',
                  ),
                ],
              ),
            ),
    );
  }

  // 顶部标题已移除，不再需要标题计算方法
}

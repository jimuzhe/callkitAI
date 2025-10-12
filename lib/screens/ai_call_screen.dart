import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/ai_call_manager.dart';
import '../models/ai_call_state.dart';
import '../services/xiaozhi_service.dart';
import '../widgets/metallic_card.dart';
import '../services/haptics_service.dart';
import '../services/audio_service.dart';

class AICallScreen extends StatefulWidget {
  const AICallScreen({super.key});

  @override
  State<AICallScreen> createState() => _AICallScreenState();
}

class _AICallScreenState extends State<AICallScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final FocusNode _turnTextFocus = FocusNode();
  final _scroll = ScrollController();
  late final TabController _tabController;

  // 使用新的AI通话管理器
  final AICallManager _callManager = AICallManager.instance;
  late final StreamSubscription _subSession;
  late final StreamSubscription _subDebug;

  // 消息缓存
  final _msgsRealtimeMap = <String, XiaozhiMessage>{};
  final _msgsTurnMap = <String, XiaozhiMessage>{};
  late final StreamSubscription _subMsg;

  // 本地UI状态
  bool _turnTextMode = true; // 回合对话默认文字输入
  bool _showDebugPanel = false;

  // 当前会话状态
  AICallSession _currentSession = AICallSession.initial();

  // 定时器用于更新时长显示
  Timer? _durationTimer;
  
  // 防抖和节流
  Timer? _sendTextDebounce;
  Timer? _voiceInputDebounce;
  bool _isProcessingCall = false; // 防止重复调用
  DateTime? _lastStateUpdate;
  
  // 消息批处理
  Timer? _messageBatchTimer;
  bool _hasPendingMessages = false;

  @override
  void initState() {
    super.initState();

    // 初始化Tab控制器
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _currentSession.isRealtimeMode ? 0 : 1,
    );

    // 监听会话状态变化 - 优化：使用节流避免过度重建
    _subSession = _callManager.sessionStream.listen((session) {
      if (!mounted) return;
      
      // 节流：限制更新频率（避免高频消息导致卡顿）
      final now = DateTime.now();
      if (_lastStateUpdate != null && 
          now.difference(_lastStateUpdate!).inMilliseconds < 100) {
        // 100ms内只更新一次
        return;
      }
      _lastStateUpdate = now;
      
      setState(() {
        _currentSession = session;
      });

      // 当连接状态改变时，启动或停止定时器
      if (session.isConnected && _durationTimer == null) {
        // 优化：时长更新降频到2秒（减少重建）
        _durationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (mounted && _currentSession.isConnected) {
            setState(() {
              // 触发UI更新以显示实时时长
            });
          }
        });
      } else if (!session.isConnected && _durationTimer != null) {
        _durationTimer?.cancel();
        _durationTimer = null;
      }
    });

    // 监听调试日志 - 优化：仅在调试面板打开时更新
    _subDebug = _callManager.debugLogStream.listen((log) {
      if (!mounted || !_showDebugPanel) return;
      
      // 批量更新日志，避免高频重建
      if (!_hasPendingMessages) {
        _hasPendingMessages = true;
        _messageBatchTimer?.cancel();
        _messageBatchTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted && _showDebugPanel) {
            setState(() {
              _hasPendingMessages = false;
            });
          }
        });
      }
    });

    // 监听小智服务消息 - 优化：异步处理避免阻塞UI
    final svc = XiaozhiService.instance;
    _subMsg = svc.messageStream.listen((m) {
      // 异步处理消息，不阻塞主线程
      Future.microtask(() {
        _callManager.handleXiaozhiMessage(m);
        
        // 更新消息缓存
        if (!mounted) return;
        
        setState(() {
          if (_currentSession.isRealtimeMode) {
            _msgsRealtimeMap[m.id] = m;
          } else {
            _msgsTurnMap[m.id] = m;
          }
        });
        _scrollToBottom();
      });
    });

    // 监听连接状态
    svc.connectionStream.listen((connected) {
      _callManager.handleConnectionChange(connected);
    });

    _addDebugLog('AI通话界面初始化完成');
  }

  void _addDebugLog(String message) {
    // 调试日志现在由AICallManager统一管理
    // 这里只是调用管理器的方法
    // _callManager._addDebugLog(message);
  }

  void _toggleDebugPanel() {
    if (!mounted) return;
    setState(() {
      _showDebugPanel = !_showDebugPanel;
    });
  }

  void _clearDebugLogs() {
    _callManager.clearDebugLogs();
  }

  Future<void> _copyDebugLogs() async {
    if (_callManager.debugLogs.isEmpty) return;
    final joined = _callManager.debugLogs.join('\n');
    await Clipboard.setData(ClipboardData(text: joined));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
  }

  String _summarizeMessage(XiaozhiMessage m) {
    if (m.text.isNotEmpty) {
      if (m.text.length > 40) {
        return '${m.text.substring(0, 40)}…';
      }
      return m.text;
    }
    if (m.emoji != null && m.emoji!.isNotEmpty) {
      return 'emoji ${m.emoji}';
    }
    return '无文本内容';
  }

  Widget _buildDebugPanel(bool isDark) {
    final logs = _callManager.debugLogs.isEmpty
        ? const <String>[]
        : List<String>.from(_callManager.debugLogs.reversed);
    final Color textColor = isDark
        ? Colors.grey.shade200
        : Colors.grey.shade800;
    final Color emptyColor = textColor.withOpacity(0.65);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: MetallicCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report_outlined, size: 18, color: textColor),
                const SizedBox(width: 6),
                Text(
                  '调试日志',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: textColor,
                  onPressed: _callManager.debugLogs.isEmpty
                      ? null
                      : _clearDebugLogs,
                ),
                IconButton(
                  tooltip: '复制全部',
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  color: textColor,
                  onPressed: _callManager.debugLogs.isEmpty
                      ? null
                      : _copyDebugLogs,
                ),
                IconButton(
                  tooltip: '测试音频播放',
                  icon: const Icon(Icons.volume_up_outlined, size: 18),
                  color: Colors.orange[600],
                  onPressed: () async {
                    try {
                      await AudioService.instance.testAudioPlayback();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🎵 音频测试已发送，请检查是否有声音'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ 音频测试失败: $e'),
                          backgroundColor: Colors.red[600],
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        '暂无日志',
                        style: TextStyle(fontSize: 12, color: emptyColor),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final entry = logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            entry,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              fontFamily: 'monospace',
                              color: textColor,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _turnTextFocus.dispose();
    _scroll.dispose();
    _tabController.dispose();
    _subSession.cancel();
    _subDebug.cancel();
    _subMsg.cancel();
    _durationTimer?.cancel();
    _sendTextDebounce?.cancel();
    _voiceInputDebounce?.cancel();
    _messageBatchTimer?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // 使用新的AI通话管理器方法 - 添加防抖和异步锁
  Future<void> _startCall() async {
    if (_isProcessingCall) return; // 防止重复调用
    _isProcessingCall = true;
    
    try {
      final mode = _currentSession.mode == ListeningMode.realtime
          ? AICallMode.realtime
          : AICallMode.turn;
      await _callManager.startCall(mode);
    } finally {
      _isProcessingCall = false;
    }
  }

  Future<void> _endCall() async {
    if (_isProcessingCall) return; // 防止重复调用
    _isProcessingCall = true;
    
    try {
      await _callManager.endCall();
    } finally {
      // 延迟重置锁，确保状态完全更新
      Future.delayed(const Duration(milliseconds: 500), () {
        _isProcessingCall = false;
      });
    }
  }

  // Future<void> _toggleMute() async {
  //   await _callManager.toggleMute();
  // }

  Future<void> _disconnect() async {
    if (_isProcessingCall) return;
    await _endCall(); // 使用统一的 endCall 方法
  }

  Future<void> _switchMode(AICallMode newMode) async {
    await _callManager.switchMode(newMode);

    // 更新Tab控制器
    final targetIndex = newMode == AICallMode.realtime ? 0 : 1;
    if (_tabController.index != targetIndex) {
      _tabController.animateTo(targetIndex);
    }

    if (newMode == AICallMode.realtime) {
      FocusScope.of(context).unfocus();
    } else if (newMode == AICallMode.turn) {
      // 不再自动连接，等待用户输入
      if (_turnTextMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _turnTextFocus.requestFocus();
        });
      }
    }
  }

  Future<void> _toggleMute() async {
    await _callManager.toggleMute();
  }

  // 转换方法：AICallMode -> ListeningMode
  // helper removed: conversion is handled in AICallManager

  void _onTabTapped(int index) {
    final targetMode = index == 0 ? AICallMode.realtime : AICallMode.turn;
    _switchMode(targetMode);
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    // 防抖：避免快速重复发送
    _sendTextDebounce?.cancel();
    _sendTextDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      try {
        await _callManager.sendTextMessage(text);
        if (mounted) {
          _controller.clear();
          FocusScope.of(context).unfocus();
        }
      } catch (e) {
        debugPrint('发送文本失败: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('发送失败: $e')),
          );
        }
      }
    });
  }

  void _toggleTurnInput() {
    setState(() => _turnTextMode = !_turnTextMode);
    if (_turnTextMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _turnTextFocus.requestFocus();
      });
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  /// 构建连接状态显示组件
  Widget _buildConnectionStatus(bool isDark) {
    if (_currentSession.hasError) {
      return Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: Colors.red[600],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _currentSession.errorMessage ?? '连接失败',
              style: TextStyle(
                fontSize: 13,
                color: Colors.red[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              // 重试连接
              try {
                final mode = _currentSession.isRealtimeMode
                    ? AICallMode.realtime
                    : AICallMode.turn;
                await _callManager.startCall(mode);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('重连失败: $e'),
                      backgroundColor: Colors.red[600],
                    ),
                  );
                }
              }
            },
            child: Text(
              '重试',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    }

    if (_currentSession.isRealtimeMode) {
      return Text(
        _currentSession.isConnected
            ? '实时对话已连接 · ${_currentSession.isMuted ? "已静音" : "麦克风开启"} · ${_currentSession.formattedDuration}'
            : '点击下方绿色按钮发起实时对话',
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
      );
    } else {
      return Text(
        _currentSession.isConnected
            ? '回合对话已连接 · ${_currentSession.formattedDuration}'
            : '输入文字或按住语音按钮开始对话', // 更新提示文字
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
      );
    }
  }

  /// 构建回合模式状态显示
  Widget _buildTurnModeStatus(bool isDark) {
    if (_currentSession.hasError) {
      return Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 14,
            color: Colors.orange[600],
          ),
          const SizedBox(width: 4),
          Text(
            '连接失败，请重试',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange[600],
            ),
          ),
        ],
      );
    }
    
    return Text(
      _currentSession.isConnected 
          ? '回合对话通道已建立' 
          : '输入文字或语音即可开始对话',
      style: TextStyle(
        fontSize: 12,
        color: isDark ? Colors.grey[300] : Colors.grey[600],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 当前模式对应的消息缓存 - 转换为列表并按时间排序
    final currentMsgsMap = _currentSession.isRealtimeMode
        ? _msgsRealtimeMap
        : _msgsTurnMap;
    final currentMsgs = currentMsgsMap.values.toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));

    // 取最近一条包含 emoji 的消息（用于电话模式展示）
    String? lastEmoji;
    for (final m in currentMsgs.reversed) {
      if (m.emoji != null && m.emoji!.isNotEmpty) {
        lastEmoji = m.emoji;
        break;
      }
    }
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: MetallicCard(
              // 增大卡片垂直内边距，让指示器（背景）有足够高度覆盖文字
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: TabBar(
                controller: _tabController,
                onTap: _onTabTapped,
                // 禁用点击波纹效果，避免显示方框
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.resolveWith<Color?>((
                  Set<WidgetState> states,
                ) {
                  return states.contains(WidgetState.pressed)
                      ? Colors.transparent
                      : null;
                }),
                indicator: BoxDecoration(
                  // 胶囊型圆角
                  borderRadius: BorderRadius.circular(999),
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.12,
                  ),
                ),
                // 放大文字与点击区域
                labelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                // 增大 tab 区域（标签左右间距）并让指示器覆盖整个 tab
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                // 让指示器在垂直方向有更多余量，从而完整罩住文字
                indicatorPadding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 6,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Theme.of(context).textTheme.bodyLarge?.color,
                unselectedLabelColor: Theme.of(
                  context,
                ).textTheme.bodySmall?.color,
                tabs: const [
                  Tab(text: '实时对话'),
                  Tab(text: '回合对话'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: Icon(
                  _showDebugPanel
                      ? Icons.visibility_off_outlined
                      : Icons.bug_report_outlined,
                ),
                label: Text(_showDebugPanel ? '隐藏调试日志' : '显示调试日志'),
                onPressed: _toggleDebugPanel,
              ),
            ),
          ),
          if (_showDebugPanel) _buildDebugPanel(isDark),
          Expanded(
            child: Column(
              children: [
                if (_currentSession.isRealtimeMode) ...[
                  SizedBox(
                    height: 80,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          isActive: _currentSession.isTalking,
                          isRecording: _currentSession.isRecording,
                          dark: isDark,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_currentSession.isRealtimeMode) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildConnectionStatus(isDark),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: lastEmoji != null
                            ? Text(
                                lastEmoji,
                                key: ValueKey(lastEmoji),
                                style: const TextStyle(fontSize: 72),
                              )
                            : Icon(
                                Icons.mood,
                                key: const ValueKey('realtime_placeholder'),
                                size: 64,
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.25),
                              ),
                      ),
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildConnectionStatus(isDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: currentMsgs.length,
                      itemBuilder: (context, i) {
                        final m = currentMsgs[i];
                        final time = DateFormat('HH:mm:ss').format(m.ts);
                        final hasEmoji =
                            (m.emoji != null && m.emoji!.isNotEmpty);
                        final bubble = Container(
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: m.fromUser
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (hasEmoji)
                                Text(
                                  m.emoji!,
                                  style: const TextStyle(fontSize: 22),
                                ),
                              if (m.text.isNotEmpty) ...[
                                if (hasEmoji) const SizedBox(height: 4),
                                Text(m.text),
                              ],
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: m.fromUser
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [bubble],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _currentSession.isRealtimeMode
                ? (_currentSession.isConnected
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            MetallicCircleButton(
                              icon: _currentSession.isMuted
                                  ? Icons.mic_off
                                  : Icons.mic,
                              active: !_currentSession.isMuted,
                              activeColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              onTap: _currentSession.isConnected
                                  ? _toggleMute
                                  : null,
                              size: 64,
                            ),
                            MetallicCircleButton(
                              icon: Icons.call_end_rounded,
                              active: _currentSession.isConnected,
                              activeColor: const Color(0xFFEF4444),
                              onTap: _currentSession.isConnected
                                  ? _disconnect
                                  : null,
                              size: 72,
                            ),
                          ],
                        )
                      : Center(
                          child: MetallicCircleButton(
                            icon: Icons.call_rounded,
                            active: true,
                            activeColor: const Color(0xFF22C55E),
                            onTap: _startCall,
                            size: 86,
                          ),
                        ))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 回合对话顶部状态显示
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildTurnModeStatus(isDark),
                      ),
                      const SizedBox(height: 12),
                      MetallicCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                _turnTextMode
                                    ? Icons.keyboard_voice_rounded
                                    : Icons.keyboard_rounded,
                              ),
                              onPressed: _toggleTurnInput,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 150),
                                child: _turnTextMode
                                    ? TextField(
                                        key: const ValueKey('turn_text_field'),
                                        controller: _controller,
                                        focusNode: _turnTextFocus,
                                        enabled: true, // 移除连接状态限制，让按需连接自动处理
                                        minLines: 1,
                                        maxLines: 3,
                                        textInputAction: TextInputAction.send,
                                        onSubmitted: (_) => _sendText(),
                                        decoration: InputDecoration(
                                          hintText: '输入消息发送给AI助手',
                                          border: InputBorder.none,
                                        ),
                                      )
                                    : Listener(
                                        key: const ValueKey('turn_voice_input'),
                                        onPointerDown: (_) async {
                                                debugPrint('🎤 语音按钮: 按下');
                                                HapticsService.instance.impact();
                                                
                                                try {
                                                  // 如果AI正在说话，先打断
                                                  if (AudioService.instance.isPlaying) {
                                                    debugPrint('🚨 打断AI说话');
                                                    await AudioService.instance.stopStreamingAndClear();
                                                  }
                                                  
                                                  await _callManager.startVoiceInput();
                                                  debugPrint('✅ 语音输入已启动');
                                                } catch (e) {
                                                  debugPrint('❌ 语音输入启动失败: $e');
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text('语音输入失败')),
                                                    );
                                                  }
                                                }
                                              },
                                        onPointerUp: (_) async {
                                                debugPrint('🛝 语音按钮: 松开');
                                                HapticsService.instance.selection();
                                                
                                                try {
                                                  await _callManager.stopVoiceInput();
                                                  debugPrint('✅ 语音输入已停止');
                                                } catch (e) {
                                                  debugPrint('❌ 语音输入停止失败: $e');
                                                }
                                              },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          curve: Curves.easeOut,
                                          height: 48,
                                          alignment: Alignment.center,
                                          transform: _currentSession.isTalking
                                              ? Matrix4.identity().scaled(0.98)
                                              : Matrix4.identity(),
                                          decoration: BoxDecoration(
                                            color: _currentSession.isTalking
                                                ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.25)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              width: _currentSession.isTalking
                                                  ? 2
                                                  : 1,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(
                                                    alpha: _currentSession.isTalking
                                                        ? 1.0
                                                        : 0.6,
                                                  ),
                                            ),
                                            boxShadow: _currentSession.isTalking
                                                ? [
                                                    BoxShadow(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                          .withValues(
                                                            alpha: 0.3,
                                                          ),
                                                      blurRadius: 8,
                                                      spreadRadius: 2,
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (_currentSession.isTalking)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 8,
                                                      ),
                                                  child: Icon(
                                                    Icons.mic,
                                                    size: 20,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                  ),
                                                ),
                                              Text(
                                                _currentSession.isTalking
                                                    ? '松开结束'
                                                    : '按住说话',
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.color,
                                                  fontWeight:
                                                      _currentSession.isTalking
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            if (_turnTextMode)
                              IconButton(
                                icon: const Icon(Icons.send_rounded),
                                color: Theme.of(context).colorScheme.primary,
                                onPressed: _sendText, // 移除连接状态限制，让按需连接自动处理
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final bool isActive;
  final bool isRecording;
  final bool dark;
  _WaveformPainter({
    required this.isActive,
    required this.isRecording,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // 根据状态设置颜色和动画参数
    if (isRecording) {
      // 录音状态：红色，表示正在输入
      paint.color = const Color(0xFFEF4444);
    } else if (isActive) {
      // 说话状态：绿色，表示正在输出
      paint.color = const Color(0xFF10B981);
    } else {
      // 空闲状态：灰色
      paint.color = dark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937);
    }

    final midY = size.height / 2;
    final baseAmp = size.height * 0.15;
    final activeAmp = isActive || isRecording ? size.height * 0.35 : baseAmp;

    // 添加时间动画效果
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final animationOffset = time * 2.0; // 控制动画速度

    final path = Path();
    const waves = 3.0; // 增加波形数量使更灵动

    for (double x = 0; x <= size.width; x += 1.5) {
      // 更密集的采样
      final t = (x / size.width) * waves * 3.14159 * 2 + animationOffset;

      // 创建更复杂的波形：主波 + 两个谐波
      final mainWave = math.sin(t) * 0.6;
      final harmonic1 = math.sin(t * 2) * 0.3;
      final harmonic2 = math.sin(t * 3) * 0.1;

      // 根据状态调整波形强度
      final intensity = isRecording ? 1.2 : (isActive ? 1.0 : 0.7);
      final y =
          midY + activeAmp * (mainWave + harmonic1 + harmonic2) * intensity;

      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // 如果正在录音，添加额外的视觉效果
    if (isRecording) {
      final pulsePaint = Paint()
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.3);

      // 添加外围脉冲效果
      final pulsePath = Path();
      final pulseAmp = size.height * 0.45;
      for (double x = 0; x <= size.width; x += 2) {
        final t =
            (x / size.width) * waves * 3.14159 * 2 + animationOffset * 1.5;
        final y = midY + pulseAmp * math.sin(t);
        if (x == 0) {
          pulsePath.moveTo(x, y);
        } else {
          pulsePath.lineTo(x, y);
        }
      }
      canvas.drawPath(pulsePath, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.isActive != isActive ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.dark != dark;
  }
}

// 使用 dart:math 的 sin，不需要自定义实现

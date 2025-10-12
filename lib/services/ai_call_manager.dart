import 'dart:async';
import '../models/ai_call_state.dart';
import 'xiaozhi_service.dart';
import 'audio_service.dart';
import 'haptics_service.dart';

// AI通话模式枚举
enum AICallMode {
  realtime, // 实时对话模式
  turn, // 回合对话模式
}

// AI通话管理器，借鉴py-xiaozhi的插件架构和状态管理
class AICallManager {
  static final AICallManager instance = AICallManager._internal();

  final StreamController<AICallSession> _sessionController =
      StreamController<AICallSession>.broadcast();
  final StreamController<String> _debugLogController =
      StreamController<String>.broadcast();

  AICallSession _currentSession = AICallSession.initial();
  Timer? _durationTimer;
  List<String> _debugLogs = [];
  static const int _maxDebugLogs = 200;

  // 音频状态跟踪
  bool _isAudioInitialized = false;
  bool _isMicActive = false;
  bool _aecEnabled = true; // 默认启用回声消除
  
  // 异步锁，防止同时调用 startCall/endCall
  bool _isProcessingCall = false;
  bool _isProcessingVoice = false;
  
  // 连接状态管理
  int _connectionRetryCount = 0;
  static const int _maxRetryCount = 3;
  Timer? _connectionTimeoutTimer;
  bool _isConnecting = false;

  AICallManager._internal();

  // 公共接口
  Stream<AICallSession> get sessionStream => _sessionController.stream;
  Stream<String> get debugLogStream => _debugLogController.stream;
  AICallSession get currentSession => _currentSession;
  List<String> get debugLogs => List.unmodifiable(_debugLogs);

  // 状态管理方法
  Future<void> startCall(AICallMode mode) async {
    // 异步锁：防止重复调用
    if (_isProcessingCall) {
      _addDebugLog('通话处理中，忽略重复调用');
      return;
    }
    _isProcessingCall = true;
    
    try {
      final listeningMode = _callModeToListeningMode(mode);
      _addDebugLog('开始通话，模式: ${_modeToString(listeningMode)}');

      // 更新状态为连接中
      _updateSession(
        _currentSession.copyWith(
          state: AICallState.connecting,
          mode: listeningMode,
          startTime: DateTime.now(),
          isConnected: false,
          errorMessage: null,
        ),
      );
      // 初始化音频服务
      if (!_isAudioInitialized) {
        await AudioService.instance.initialize();
        _isAudioInitialized = true;
        _addDebugLog('音频服务初始化完成');
      }

      // 连接小智服务
      final realtime = listeningMode == ListeningMode.realtime;
      
      // 重要修复：两种模式都需要语音聊天模式来支持AI音频输出
      try {
        await AudioService.instance.enterVoiceChatMode();
        _addDebugLog('音频会话: 切换至语音聊天模式 (${realtime ? "实时" : "回合"})');
      } catch (e) {
        _addDebugLog('音频会话切换语音聊天模式失败: $e');
      }

      await XiaozhiService.instance.connect(realtime: realtime);
      _addDebugLog('小智服务连接成功');

      // 监听在 hello 回包后启动
      final modeStr = _modeToProtocolMode(listeningMode);
      if (listeningMode == ListeningMode.realtime) {
        XiaozhiService.instance.setKeepListening(true);
        _isMicActive = false;
        _addDebugLog('实时模式等待服务器 hello 后启动监听');
      } else if (listeningMode == ListeningMode.autoStop) {
        XiaozhiService.instance.setKeepListening(false);
        await XiaozhiService.instance.listenStart(mode: modeStr);
        _addDebugLog('监听模式启动: $modeStr');
        _isMicActive = false;
      } else {
        XiaozhiService.instance.setKeepListening(false);
        _isMicActive = false;
        _addDebugLog('手动模式已准备，等待用户触发录音');
      }

      // 更新为连接状态
      _updateSession(
        _currentSession.copyWith(
          state: listeningMode == ListeningMode.realtime
              ? AICallState.listening
              : AICallState.manual,
          isConnected: true,
          isMuted: listeningMode != ListeningMode.realtime,
          isTalking: listeningMode == ListeningMode.realtime && _isMicActive,
        ),
      );

      // 启动计时器
      _startDurationTimer();

      // 触觉反馈
      HapticsService.instance.selection();

      _addDebugLog('通话启动完成');
    } catch (e) {
      _addDebugLog('通话启动失败: $e');
      _updateSession(
        _currentSession.copyWith(
          state: AICallState.error,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      _isProcessingCall = false;
    }
  }

  Future<void> endCall() async {
    // 异步锁：防止重复调用
    if (_isProcessingCall) {
      _addDebugLog('通话结束处理中，忽略重复调用');
      return;
    }
    _isProcessingCall = true;
    
    _addDebugLog('结束通话');

    // 停止计时器
    _durationTimer?.cancel();
    _durationTimer = null;

    try {
      // 停止麦克风
      if (_isMicActive) {
        await XiaozhiService.instance.stopMic();
        _isMicActive = false;
        _addDebugLog('麦克风已停止');
      }

      // 停止监听
      XiaozhiService.instance.setKeepListening(false);
      await XiaozhiService.instance.listenStop();
      _addDebugLog('监听已停止');

      // 断开连接
      final shouldRestoreAudio = _currentSession.isRealtimeMode;
      await XiaozhiService.instance.disconnect(
        restoreAudioSession: shouldRestoreAudio,
      );
      _addDebugLog('小智服务已断开');

      // 退出语音聊天音频模式
      try {
        await AudioService.instance.exitVoiceChatMode();
        _addDebugLog('音频会话: 恢复播放模式');
      } catch (e) {
        _addDebugLog('音频会话恢复播放模式失败: $e');
      }

      // 触觉反馈
      HapticsService.instance.impact();
    } catch (e) {
      _addDebugLog('通话结束异常: $e');
    } finally {
      // 重置状态
      _updateSession(AICallSession.initial());
      
      // 延迟释放锁，确保所有清理完成
      Future.delayed(const Duration(milliseconds: 500), () {
        _isProcessingCall = false;
        _addDebugLog('通话资源清理完成');
      });
    }
  }

  Future<void> toggleMute() async {
    if (!_currentSession.isRealtimeMode) {
      _addDebugLog('当前模式不支持静音切换');
      return;
    }

    if (!_currentSession.isConnected) {
      _addDebugLog('静音切换时检测到连接已断开，尝试重新连接');
      final reconnected = await _ensureConnectedForMode(ListeningMode.realtime);
      if (!reconnected) {
        _addDebugLog('静音切换失败: 无法重新建立实时连接');
        return;
      }
    }

    final targetMuted = !_currentSession.isMuted;
    _addDebugLog(targetMuted ? '静音' : '取消静音');

    try {
      if (targetMuted) {
        if (_isMicActive) {
          await XiaozhiService.instance.stopMic();
          _isMicActive = false;
        }
        // 实时模式下保持监听，即使静音也要允许打断
        XiaozhiService.instance.setKeepListening(true);

        _updateSession(
          _currentSession.copyWith(isMuted: true, isTalking: false),
        );
      } else {
        XiaozhiService.instance.setKeepListening(true);
        await XiaozhiService.instance.listenStart(mode: 'realtime');

        final previousSession = _currentSession;
        final resumedSession = _currentSession.copyWith(
          state: AICallState.listening,
          isMuted: false,
          isTalking: true,
        );
        _updateSession(resumedSession);

        final micStarted = await XiaozhiService.instance.startMic();
        if (!micStarted) {
          _isMicActive = false;
          _addDebugLog('麦克风启动失败，保持静音状态');
          _updateSession(
            previousSession.copyWith(isMuted: true, isTalking: false),
          );
          return;
        }

        _isMicActive = true;
      }

      HapticsService.instance.selection();
    } catch (e) {
      _addDebugLog('静音切换失败: $e');
      _updateSession(_currentSession.copyWith(isMuted: true, isTalking: false));
    }
  }

  Future<void> switchMode(AICallMode newMode) async {
    final newListeningMode = _callModeToListeningMode(newMode);
    if (_currentSession.mode == newListeningMode) {
      return; // 如果模式相同，不需要切换
    }

    _addDebugLog(
      '切换模式: ${_modeToString(_currentSession.mode)} -> ${_modeToString(newListeningMode)}',
    );

    // 断开现有连接（如果有）
    if (_currentSession.isConnected) {
      await endCall();
    }

    _isMicActive = false;
    _connectionRetryCount = 0; // 重置重试计数
    
    // 更新到新模式，但不立即连接
    _updateSession(
      AICallSession(
        state: AICallState.idle,
        mode: newListeningMode,
        startTime: null,
        duration: null,
        isConnected: false,
        isMuted: newListeningMode != ListeningMode.realtime,
        isTalking: false,
        isRecording: false,
        lastEmoji: null,
        errorMessage: null,
      ),
    );
    
    // 不再自动连接，等待用户输入时再连接
    _addDebugLog('模式切换完成，等待用户输入以建立连接');
  }

  Future<void> sendTextMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _addDebugLog('准备发送文本消息: ${trimmed.substring(0, trimmed.length > 20 ? 20 : trimmed.length)}...');
    
    // 按需建立连接
    if (!_currentSession.isConnected) {
      _addDebugLog('检测到未连接，开始按需建立连接');
      final connected = await _connectOnDemand(_currentSession.mode);
      if (!connected) {
        _addDebugLog('❌ 按需连接失败，无法发送文本');
        _updateSessionWithError('连接失败，请稍后重试');
        return;
      }
    }

    if (!_currentSession.isRealtimeMode) {
      _addDebugLog(
        '以 listen.detect 方式发送文本: ${trimmed.length > 40 ? "${trimmed.substring(0, 40)}..." : trimmed}',
      );
      try {
        await XiaozhiService.instance.sendWakeWordDetected(trimmed);
        HapticsService.instance.selection();
      } catch (e) {
        _addDebugLog('发送文本失败: $e');
      }
      return;
    }

    _addDebugLog('当前模式不支持直接发送文本');
  }

  Future<void> startVoiceInput() async {
    // 防止快速重复调用
    if (_isProcessingVoice) {
      _addDebugLog('语音输入处理中，忽略重复调用');
      return;
    }
    _isProcessingVoice = true;
    
    _addDebugLog('开始语音输入流程 (模式: ${_currentSession.isRealtimeMode ? "实时" : "回合"})');
    
    // 按需建立连接
    if (!_currentSession.isConnected) {
      _addDebugLog('检测到未连接，开始按需建立语音连接');
      final connected = await _connectOnDemand(_currentSession.mode);
      if (!connected) {
        _addDebugLog('❌ 按需连接失败，无法启动语音输入');
        _updateSessionWithError('连接失败，请稍后重试');
        _isProcessingVoice = false;
        return;
      }
    }


    // 立即更新UI状态，提供即时视觉反馈
    _updateSession(
      _currentSession.copyWith(
        state: _currentSession.isRealtimeMode
            ? AICallState.listening
            : AICallState.manual,
        isTalking: true, // 修复：回合模式按住时也应该显示为正在说话
        isRecording: true,
      ),
    );

    try {
      // 根据模式设置不同的keepListening值
      if (_currentSession.isRealtimeMode) {
        XiaozhiService.instance.setKeepListening(true); // 实时模式保持监听
      } else {
        XiaozhiService.instance.setKeepListening(false); // 回合模式不保持
      }
      
      // 根据模式启动监听
      final mode = _currentSession.isRealtimeMode ? 'realtime' : 'manual';
      await XiaozhiService.instance.listenStart(mode: mode);
      
      final micStarted = await XiaozhiService.instance.startMic();
      _isMicActive = micStarted;

      HapticsService.instance.impact();
      _addDebugLog('语音输入启动${micStarted ? "成功" : "失败"}');
      
      // 如果启动失败，立即更新状态
      if (!micStarted) {
        _updateSession(
          _currentSession.copyWith(
            state: AICallState.idle,
            isTalking: false,
            isRecording: false,
          ),
        );
      }
    } catch (e) {
      _addDebugLog('语音输入启动失败: $e');
      // 如果启动失败，恢复状态
      _updateSession(
        _currentSession.copyWith(
          state: AICallState.idle,
          isTalking: false,
          isRecording: false,
        ),
      );
    } finally {
      _isProcessingVoice = false;
    }
  }

  Future<void> stopVoiceInput() async {
    if (!_currentSession.isConnected) {
      _isProcessingVoice = false; // 重置锁
      return;
    }
    
    // 快速释放锁，允许下一次语音输入
    _isProcessingVoice = false;

    _addDebugLog('停止语音输入 (模式: ${_currentSession.isRealtimeMode ? "实时" : "回合"})');

    try {
      // 停止麦克风
      if (_isMicActive) {
        await XiaozhiService.instance.stopMic();
        _isMicActive = false;
      }
      
      // 根据模式处理keepListening
      if (_currentSession.isRealtimeMode) {
        // 实时模式：保持监听，不关闭麦克风
        XiaozhiService.instance.setKeepListening(true);
        // 更新状态为继续监听
        _updateSession(
          _currentSession.copyWith(
            state: AICallState.listening,
            isTalking: true, // 实时模式保持可说话状态
            isRecording: false,
          ),
        );
      } else {
        // 回合模式：停止监听，恢复手动状态
        XiaozhiService.instance.setKeepListening(false);
        await XiaozhiService.instance.listenStop();
        // 更新状态为手动模式
        _updateSession(
          _currentSession.copyWith(
            state: AICallState.manual,
            isTalking: false, // 回合模式松开后不保持说话状态
            isRecording: false,
          ),
        );
      }

      HapticsService.instance.selection();
      _addDebugLog('语音输入已停止');
    } catch (e) {
      _addDebugLog('语音输入停止失败: $e');
    }
  }

  // 处理来自小智服务的消息和状态变化
  void handleXiaozhiMessage(XiaozhiMessage message) {
    // 更新表情
    if (message.emoji != null && message.emoji!.isNotEmpty) {
      _updateSession(_currentSession.copyWith(lastEmoji: message.emoji));
    }

    // 根据消息类型更新状态
    if (!message.fromUser) {
      // AI消息，可能表示说话状态
      if (message.isComplete) {
        // AI消息完成，如果是实时模式且保持监听，则立即回到监听状态
        if (_currentSession.isRealtimeMode && _aecEnabled) {
          _updateSession(
            _currentSession.copyWith(
              state: AICallState.listening,
              isTalking: true, // 实时模式下保持可说话状态
            ),
          );
          // 确保keep_listening标志正确
          XiaozhiService.instance.setKeepListening(true);
          _addDebugLog('AI说话完成，实时模式继续监听');
        }
      } else {
        // AI正在说话
        _updateSession(
          _currentSession.copyWith(
            state: AICallState.speaking,
            isTalking: false, // AI说话时用户暂停说话
          ),
        );
      }
    }
  }

  void handleConnectionChange(bool connected) {
    _updateSession(
      _currentSession.copyWith(
        isConnected: connected,
        state: connected ? _currentSession.state : AICallState.idle,
        isTalking: connected ? _currentSession.isTalking : false,
        isRecording: connected ? _currentSession.isRecording : false,
      ),
    );

    if (!connected) {
      _durationTimer?.cancel();
      _durationTimer = null;
    }
  }

  // 工具方法
  String _modeToString(ListeningMode mode) {
    switch (mode) {
      case ListeningMode.realtime:
        return '实时对话';
      case ListeningMode.autoStop:
        return '自动停止';
      case ListeningMode.manual:
        return '手动模式';
    }
  }

  String _modeToProtocolMode(ListeningMode mode) {
    switch (mode) {
      case ListeningMode.realtime:
        return 'realtime';
      case ListeningMode.autoStop:
        return 'auto';
      case ListeningMode.manual:
        return 'manual';
    }
  }

  ListeningMode _callModeToListeningMode(AICallMode mode) {
    switch (mode) {
      case AICallMode.realtime:
        return ListeningMode.realtime;
      case AICallMode.turn:
        return ListeningMode.manual;
    }
  }

  /// 按需建立连接 - 新的连接方法，带重试和超时机制
  Future<bool> _connectOnDemand(ListeningMode mode) async {
    if (_isConnecting) {
      _addDebugLog('已有连接正在建立中，等待...');
      // 等待当前连接完成
      var waited = 0;
      while (_isConnecting && waited < 50) { // 最多等待5秒
        await Future.delayed(const Duration(milliseconds: 100));
        waited++;
      }
      return _currentSession.isConnected;
    }

    if (_currentSession.isConnected && _currentSession.mode == mode) {
      _addDebugLog('已建立相同模式的连接，无需重建');
      return true;
    }

    _isConnecting = true;
    _connectionTimeoutTimer?.cancel();
    
    try {
      // 设置连接超时
      _connectionTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (_isConnecting) {
          _addDebugLog('❌ 连接超时，取消连接');
          _isConnecting = false;
        }
      });

      final targetMode = mode == ListeningMode.realtime
          ? AICallMode.realtime
          : AICallMode.turn;

      _addDebugLog('开始按需连接 - 模式: ${_modeToString(mode)}, 重试次数: $_connectionRetryCount');
      
      await startCall(targetMode);
      
      // 检查连接结果
      final success = _currentSession.isConnected && _currentSession.mode == mode;
      
      if (success) {
        _connectionRetryCount = 0; // 重置重试计数
        _addDebugLog('✅ 按需连接成功');
      } else {
        _connectionRetryCount++;
        _addDebugLog('❌ 按需连接失败 (第 $_connectionRetryCount 次)');
        
        // 如果未超过最大重试次数，尝试重连
        if (_connectionRetryCount < _maxRetryCount) {
          _addDebugLog('将在 2 秒后重试连接...');
          await Future.delayed(const Duration(seconds: 2));
          if (!_currentSession.isConnected) {
            return await _connectOnDemand(mode); // 递归重试
          }
        }
      }
      
      return success;
    } catch (e) {
      _addDebugLog('❌ 按需连接异常: $e');
      _connectionRetryCount++;
      return false;
    } finally {
      _isConnecting = false;
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = null;
    }
  }

  /// 保留原有方法以兼容性
  Future<bool> _ensureConnectedForMode(ListeningMode mode) async {
    return await _connectOnDemand(mode);
  }

  void _updateSession(AICallSession newSession) {
    _currentSession = newSession;
    _sessionController.add(newSession);
  }

  void _addDebugLog(String message) {
    final timestamp = DateTime.now();
    final formattedTime =
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';

    final logEntry = '[$formattedTime] $message';

    _debugLogs.add(logEntry);
    if (_debugLogs.length > _maxDebugLogs) {
      _debugLogs.removeRange(0, _debugLogs.length - _maxDebugLogs);
    }

    _debugLogController.add(logEntry);
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final newDuration = _currentSession.elapsedTime;
      _updateSession(_currentSession.copyWith(duration: newDuration));
    });
  }

  void clearDebugLogs() {
    _debugLogs.clear();
    _addDebugLog('调试日志已清空');
  }

  /// 更新会话状态并设置错误信息
  void _updateSessionWithError(String errorMessage) {
    _updateSession(
      _currentSession.copyWith(
        state: AICallState.error,
        errorMessage: errorMessage,
        isConnected: false,
      ),
    );
  }

  /// 清理连接资源
  void _cleanupConnection() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
    _isConnecting = false;
    _connectionRetryCount = 0;
  }

  void dispose() {
    _durationTimer?.cancel();
    _cleanupConnection();
    _sessionController.close();
    _debugLogController.close();
  }
}

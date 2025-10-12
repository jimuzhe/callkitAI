// AI通话状态机，借鉴py-xiaozhi的状态管理
enum AICallState {
  idle,        // 空闲状态
  connecting,  // 连接中
  listening,   // 监听中（实时对话）
  speaking,    // AI说话中
  manual,      // 手动模式（回合对话）
  error,       // 错误状态
}

enum ListeningMode {
  realtime,    // 实时对话模式（带AEC）
  autoStop,    // 自动停止模式
  manual,      // 手动模式
}

class AICallSession {
  final AICallState state;
  final ListeningMode mode;
  final DateTime? startTime;
  final Duration? duration;
  final bool isConnected;
  final bool isMuted;
  final bool isTalking;
  final bool isRecording;
  final String? lastEmoji;
  final String? errorMessage;

  const AICallSession({
    required this.state,
    required this.mode,
    this.startTime,
    this.duration,
    required this.isConnected,
    required this.isMuted,
    this.isTalking = false,
    this.isRecording = false,
    this.lastEmoji,
    this.errorMessage,
  });

  AICallSession copyWith({
    AICallState? state,
    ListeningMode? mode,
    DateTime? startTime,
    Duration? duration,
    bool? isConnected,
    bool? isMuted,
    bool? isTalking,
    bool? isRecording,
    String? lastEmoji,
    String? errorMessage,
  }) {
    return AICallSession(
      state: state ?? this.state,
      mode: mode ?? this.mode,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      isConnected: isConnected ?? this.isConnected,
      isMuted: isMuted ?? this.isMuted,
      isTalking: isTalking ?? this.isTalking,
      isRecording: isRecording ?? this.isRecording,
      lastEmoji: lastEmoji ?? this.lastEmoji,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  factory AICallSession.initial() {
    return AICallSession(
      state: AICallState.idle,
      mode: ListeningMode.realtime,
      isConnected: false,
      isMuted: true,
      isTalking: false,
      isRecording: false,
    );
  }

  // 状态检查方法
  bool get isIdle => state == AICallState.idle;
  bool get isConnecting => state == AICallState.connecting;
  bool get isListening => state == AICallState.listening;
  bool get isSpeaking => state == AICallState.speaking;
  bool get isManual => state == AICallState.manual;
  bool get hasError => state == AICallState.error;

  // 模式检查方法
  bool get isRealtimeMode => mode == ListeningMode.realtime;
  bool get isAutoStopMode => mode == ListeningMode.autoStop;
  bool get isManualMode => mode == ListeningMode.manual;

  // 时间相关方法
  Duration get elapsedTime {
    if (startTime == null) return Duration.zero;
    final now = DateTime.now();
    return now.difference(startTime!);
  }

  String get formattedDuration {
    final duration = this.duration ?? elapsedTime;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
/// 设备状态枚举 - 参考主流语音助手设计
///
/// 简化状态管理，避免多个布尔值导致的状态不一致
enum DeviceState {
  /// 空闲状态：没有录音也没有播放
  idle,

  /// 监听状态：正在录音，等待用户输入
  listening,

  /// 说话状态：AI正在播放语音
  speaking,
}

extension DeviceStateExtension on DeviceState {
  /// 是否允许发送麦克风音频
  bool get shouldSendMicAudio {
    switch (this) {
      case DeviceState.listening:
        return true;
      case DeviceState.speaking:
        // 在 speaking 状态下，只有开启 AEC 且处于实时模式才发送
        // 这个判断会在调用处结合其他标志位进行
        return false;
      case DeviceState.idle:
        return false;
    }
  }

  /// 是否正在播放音频
  bool get isPlaying {
    return this == DeviceState.speaking;
  }

  /// 是否正在监听
  bool get isListening {
    return this == DeviceState.listening;
  }

  String get displayName {
    switch (this) {
      case DeviceState.idle:
        return '空闲';
      case DeviceState.listening:
        return '监听中';
      case DeviceState.speaking:
        return '播放中';
    }
  }
}

/// 音频播放状态 - 用于 AudioService 内部
enum AudioPlayState {
  /// 空闲，没有播放任务
  idle,

  /// 正在播放
  playing,

  /// 已暂停
  paused,

  /// 正在加载
  loading,
}

extension AudioPlayStateExtension on AudioPlayState {
  bool get isIdle => this == AudioPlayState.idle;
  bool get isPlaying => this == AudioPlayState.playing;
  bool get isPaused => this == AudioPlayState.paused;
  bool get isLoading => this == AudioPlayState.loading;
}

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_session/audio_session.dart';

/// PCM流式播放服务
///
/// 使用 flutter_sound 实现真正的PCM流式播放，无需WAV头部
/// 适用于实时语音助手场景
class PCMStreamService {
  static final PCMStreamService instance = PCMStreamService._internal();

  PCMStreamService._internal();

  FlutterSoundPlayer? _player;
  bool _isInitialized = false;
  bool _isStreaming = false;
  bool _isPlaying = false;

  // PCM参数（与服务器保持一致）
  static const int sampleRate = 16000; // 16kHz（匹配服务器）
  static const int numChannels = 1;
  static const int bitDepth = 16;

  // 状态回调
  ValueChanged<bool>? onPlayingStateChanged;
  VoidCallback? onStreamCompleted;

  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;
  bool get isPlaying => _isPlaying;

  /// 初始化播放器
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🎵 PCMStreamService: 初始化开始...');

    try {
      _player = FlutterSoundPlayer();
      await _player!.openPlayer();

      // 配置音频会话
      await _configureAudioSession();

      _isInitialized = true;
      debugPrint('✅ PCMStreamService: 初始化成功');
    } catch (e) {
      debugPrint('❌ PCMStreamService: 初始化失败: $e');
      rethrow;
    }
  }

  /// 配置音频会话（优化版 - 更好的音质，减少电流声）
  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;

      // 优化：使用更高质量的音频设置
      final categoryOptions =
          AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.mixWithOthers; // 允许与其他音频混合

      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: categoryOptions,
          avAudioSessionMode:
              AVAudioSessionMode.voiceChat, // 与通话一致的语音聊天模式，减少模式切换带来的伪影
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
            flags: AndroidAudioFlags.audibilityEnforced, // 增强可听度
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain, // 获取完整音频焦点
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
      debugPrint('✅ PCMStreamService: 音频会话配置成功（高质量模式）');
    } catch (e) {
      debugPrint('⚠️ PCMStreamService: 音频会话配置失败: $e');
      // 即使失败也继续，不阻止初始化
    }
  }

  /// 开始PCM流式播放
  Future<void> startStreaming() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isStreaming) {
      // debugPrint('⚠️ PCMStreamService: 已在流式播放中');
      return; // 静默返回，避免重复日志
    }

    try {
      debugPrint('🎵 PCMStreamService: 开始PCM流式播放');

      // 修复：重置所有状态
      _lastFeedTime = DateTime.now();
      _stuckDetectionCount = 0;
      _isFeeding = false;
      _smoothBuffer.clear();
      _stuckDetectionTimer?.cancel();

      // 优化：增加缓冲区到 128KB，提供更大的缓冲空间
      await _player!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: numChannels,
        sampleRate: sampleRate,
        bufferSize: 131072, // 128KB 缓冲区（更大的缓冲减少卡顿）
        interleaved: true,
      );

      _isStreaming = true;
      _isPlaying = true;
      onPlayingStateChanged?.call(true);

      debugPrint('✅ PCMStreamService: PCM流式播放已启动');
    } catch (e) {
      debugPrint('❌ PCMStreamService: 启动流式播放失败: $e');
      _isStreaming = false;
      _isPlaying = false;
      rethrow;
    }
  }

  // 音频缓冲区 - 立即喂入模式，减少延迟
  Timer? _feedTimer;
  static int _logCounter = 0; // 日志计数器

  // 优化：增大缓冲门槛，减少喂入频率，提高流畅度
  final List<int> _smoothBuffer = [];
  static const int _smoothThreshold = 3840; // 120ms @ 16kHz，更大的缓冲减少卡顿

  // 新增：播放状态监控
  Timer? _healthCheckTimer;
  DateTime? _lastFeedTime;
  int _stuckDetectionCount = 0;
  Timer? _stuckDetectionTimer; // 单个超时检测定时器
  bool _isFeeding = false; // 正在喂入数据的标记
  DateTime? _lastRestartTime; // 上次重启的时间

  /// 喂入PCM数据（优化版 - 增加卡死检测和自动恢复）
  Future<void> feedPCM(Uint8List pcmData) async {
    if (pcmData.isEmpty) {
      debugPrint('⚠️ 收到空PCM数据，跳过');
      return;
    }

    // 启动播放流（如果尚未启动）
    if (!_isStreaming) {
      await startStreaming();
    }

    try {
      // 更新最后喂入时间
      _lastFeedTime = DateTime.now();

      // 防止缓冲区过大导致卡死（增大限制）
      const maxBufferSize = 32000; // 限制缓冲区最大2秒的音频
      if (_smoothBuffer.length > maxBufferSize) {
        debugPrint('⚠️ 缓冲区过大(${_smoothBuffer.length}), 清理旧数据');
        // 只保留最新的一半数据，而不是全部清空
        final keepSize = maxBufferSize ~/ 2;
        _smoothBuffer.removeRange(0, _smoothBuffer.length - keepSize);
      }

      // 添加数据到缓冲区
      _smoothBuffer.addAll(pcmData);

      // 优化：动态调整喂入阈值
      final currentThreshold = _calculateOptimalThreshold();
      if (_smoothBuffer.length >= currentThreshold) {
        final dataToFeed = Uint8List.fromList(_smoothBuffer);

        // 清空缓冲区
        _smoothBuffer.clear();

        // 优化：不跳过数据，而是等待或合并
        // 如果已经有数据在喂入，将新数据保留在缓冲区等待下次处理
        if (_isFeeding) {
          // 不清空缓冲区，让数据留在里面等待下次处理
          // debugPrint('⚠️ 上一批数据尚未喂入完成，数据保留在缓冲区');
          return;
        }

        // 标记开始喂入
        _isFeeding = true;

        // 启动单个超时检测定时器（缩短到1秒）
        _stuckDetectionTimer?.cancel();
        _stuckDetectionTimer = Timer(const Duration(seconds: 1), () {
          if (_isFeeding) {
            debugPrint('🚨 数据喂入超时1秒，强制重置');
            _stuckDetectionCount++;
            _isFeeding = false; // 强制重置状态

            if (_stuckDetectionCount >= 3) {
              debugPrint('🔄 检测到严重卡死，重启播放流');
              _restartStreamingIfStuck();
              _stuckDetectionCount = 0;
            }
          }
        });

        // 同步喂入数据（改为同步，避免并发问题）
        try {
          await _player!.feedUint8FromStream(dataToFeed);
          // 成功完成，重置状态
          _isFeeding = false;
          _stuckDetectionCount = 0;
          _stuckDetectionTimer?.cancel();
        } catch (e) {
          debugPrint('❌ PCM喂入错误: $e');
          _isFeeding = false;
          _stuckDetectionTimer?.cancel();
          await _handleFeedError(e);
        }

        // 减少日志输出频率
        if (kDebugMode) {
          _logCounter++;
          if (_logCounter % 50 == 0) {
            debugPrint(
              '🌀 PCM喂入: ${dataToFeed.length} bytes (阈值: $currentThreshold)',
            );
          }
        }
      }

      // 启动健康检查（如果尚未启动）
      _ensureHealthCheck();
    } catch (e) {
      debugPrint('❌ PCMStreamService: 喂入数据失败: $e');
      await _handleFeedError(e);
    }
  }

  /// 动态计算最优阈值
  int _calculateOptimalThreshold() {
    // 根据缓冲区大小动态调整
    if (_smoothBuffer.length > 16000) {
      // 缓冲区较大时，增大阈值，一次喂入更多数据
      return _smoothThreshold * 2;
    } else if (_stuckDetectionCount > 0) {
      // 如果有卡死迹象，保持正常阈值
      return _smoothThreshold;
    }
    return _smoothThreshold;
  }

  /// 处理喂入错误
  Future<void> _handleFeedError(dynamic error) async {
    debugPrint('🚨 PCM喂入错误，尝试恢复: $error');

    try {
      // 清空缓冲区
      _smoothBuffer.clear();

      // 如果连续错误太多，重启播放流
      _stuckDetectionCount++;
      if (_stuckDetectionCount >= 2) {
        debugPrint('🔄 连续错误，重启播放流');
        await _restartStreamingIfStuck();
      }
    } catch (e) {
      debugPrint('❌ 处理喂入错误时出现异常: $e');
    }
  }

  /// 确保健康检查定时器运行
  void _ensureHealthCheck() {
    if (_healthCheckTimer?.isActive == true) return;

    // 降低检查频率以减少干扰
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _performHealthCheck();
    });
  }

  /// 执行健康检查（优化版 - 降低误报）
  void _performHealthCheck() {
    if (!_isStreaming) {
      _healthCheckTimer?.cancel();
      return;
    }

    final now = DateTime.now();
    final lastFeed = _lastFeedTime;

    // 修复：只在播放期间检查，避免回合对话模式误报
    // 只有当缓冲区有数据或正在喂入时才进行卡死检查
    if (_isFeeding || _smoothBuffer.isNotEmpty) {
      // 播放进行中，检查是否卡死（20秒无新数据）
      if (lastFeed != null && now.difference(lastFeed).inSeconds > 20) {
        debugPrint('🚨 健康检查：播放中超过20秒无数据，可能卡死');
        debugPrint('🔄 检测到数据卡死，重启播放流');
        _restartStreamingIfStuck();
      }
    }
    // 如果缓冲区为空且没有正在喂入，说明是正常的静默期（等待下一轮对话），不打印警告

    // 提高缓冲区清理阈值到更合理的值
    if (_smoothBuffer.length > 32000) {
      // 2秒音频
      debugPrint('🧹 健康检查：清理过大缓冲区 (${_smoothBuffer.length} bytes)');
      _smoothBuffer.clear();
    }
  }

  /// 重启播放流（如果检测到卡死） - 增加防止频繁重启的冷却机制
  Future<void> _restartStreamingIfStuck() async {
    final now = DateTime.now();

    // 检查冷却时间：距离上次重启必须超过3秒
    if (_lastRestartTime != null) {
      final elapsed = now.difference(_lastRestartTime!);
      if (elapsed.inSeconds < 3) {
        debugPrint('💫 冷却中，跳过重启 (距离上次${elapsed.inMilliseconds}ms)');
        return;
      }
    }

    try {
      debugPrint('🔄 重启播放流以恢复播放');
      _lastRestartTime = now; // 记录重启时间

      // 停止当前播放
      await stopStreaming();

      // 较长的延迟确保清理完成
      await Future.delayed(const Duration(milliseconds: 500));

      // 重新启动
      await startStreaming();

      // 重置计数器
      _stuckDetectionCount = 0;
      _lastFeedTime = DateTime.now();

      debugPrint('✅ 播放流重启完成');
    } catch (e) {
      debugPrint('❌ 重启播放流失败: $e');
    }
  }

  /// 喂入WAV数据（自动去除头部）
  Future<void> feedWAV(Uint8List wavData) async {
    try {
      // 检测并去除WAV头部
      Uint8List pcmData;

      if (wavData.length > 44 &&
          wavData[0] == 0x52 && // R
          wavData[1] == 0x49 && // I
          wavData[2] == 0x46 && // F
          wavData[3] == 0x46) {
        // F
        // 有效的WAV文件，跳过44字节头部
        pcmData = wavData.sublist(44);
        debugPrint(
          '🎵 PCMStreamService: 检测到WAV头部，提取PCM数据 ${pcmData.length} 字节',
        );
      } else {
        // 已经是PCM数据
        pcmData = wavData;
        debugPrint('🎵 PCMStreamService: 直接使用PCM数据 ${pcmData.length} 字节');
      }

      await feedPCM(pcmData);
    } catch (e) {
      debugPrint('❌ PCMStreamService: 处理WAV数据失败: $e');
      rethrow;
    }
  }

  /// 预热播放器（提前启动流减少首包延迟）
  Future<void> warmup() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isStreaming) {
      debugPrint('⚠️ PCMStreamService: 已在播放中，无需预热');
      return;
    }

    try {
      debugPrint('🌡️ PCMStreamService: 开始预热...');

      // 喂入一小段静音数据，预热音频管道
      final silentData = Uint8List(1600); // 50ms 静音 @16kHz
      await startStreaming();
      await Future.delayed(const Duration(milliseconds: 10));
      await _player!.feedUint8FromStream(silentData);
      await Future.delayed(const Duration(milliseconds: 100));
      await stopStreaming();

      debugPrint('✅ PCMStreamService: 预热完成');
    } catch (e) {
      debugPrint('⚠️ PCMStreamService: 预热失败: $e');
    }
  }

  /// 停止流式播放（增强版 - 确保彻底清理）
  Future<void> stopStreaming() async {
    if (!_isStreaming) {
      debugPrint('⚠️ PCMStreamService: 已停止或未启动，跳过');
      return;
    }

    try {
      debugPrint('🛝 PCMStreamService: 停止流式播放');

      // 1. 停止所有定时器
      _feedTimer?.cancel();
      _feedTimer = null;
      _healthCheckTimer?.cancel();
      _healthCheckTimer = null;
      _stuckDetectionTimer?.cancel();
      _stuckDetectionTimer = null;

      // 2. 刷新剩余缓冲，避免截断
      if (_smoothBuffer.isNotEmpty) {
        try {
          final remainingData = Uint8List.fromList(_smoothBuffer);
          // 使用超时机制防止刷新时卡死
          await _player!
              .feedUint8FromStream(remainingData)
              .timeout(
                const Duration(milliseconds: 500),
                onTimeout: () {
                  debugPrint('⚠️ 刷新剩余数据超时，放弃');
                  throw TimeoutException(
                    '刷新剩余数据超时',
                    const Duration(milliseconds: 500),
                  );
                },
              );
          debugPrint(
            '🧹 PCMStreamService: 已刷新剩余缓冲 ${remainingData.length} bytes',
          );
        } catch (e) {
          debugPrint('⚠️ PCMStreamService: 刷新剩余数据失败: $e');
        }
      }

      // 3. 清空所有缓冲区
      _smoothBuffer.clear();

      // 4. 等待短时间让最后的数据播完
      await Future.delayed(const Duration(milliseconds: 200));

      // 5. 停止播放器（带超时保护）
      try {
        await _player!.stopPlayer().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint('⚠️ 停止播放器超时，强制继续');
            throw TimeoutException('停止播放器超时', const Duration(seconds: 2));
          },
        );
      } catch (e) {
        debugPrint('⚠️ 停止播放器异常: $e');
      }

      // 6. 重置所有状态
      _isStreaming = false;
      _isPlaying = false;
      _stuckDetectionCount = 0;
      _lastFeedTime = null;
      _isFeeding = false;

      // 7. 触发回调
      try {
        onPlayingStateChanged?.call(false);
        onStreamCompleted?.call();
      } catch (e) {
        debugPrint('⚠️ 回调执行异常: $e');
      }

      debugPrint('✅ PCMStreamService: 流式播放已彻底停止');
    } catch (e) {
      debugPrint('❌ PCMStreamService: 停止播放失败: $e');

      // 即使停止失败也要重置状态，防止永久卡死
      _isStreaming = false;
      _isPlaying = false;
      _stuckDetectionCount = 0;
      _lastFeedTime = null;
      _isFeeding = false;
      _smoothBuffer.clear();

      // 清理定时器
      _feedTimer?.cancel();
      _healthCheckTimer?.cancel();
      _stuckDetectionTimer?.cancel();

      // 仍然触发回调
      try {
        onPlayingStateChanged?.call(false);
      } catch (_) {}
    }
  }

  /// 暂停播放
  Future<void> pause() async {
    if (!_isPlaying) return;

    try {
      await _player!.pausePlayer();
      _isPlaying = false;
      onPlayingStateChanged?.call(false);
      debugPrint('⏸️ PCMStreamService: 已暂停');
    } catch (e) {
      debugPrint('❌ PCMStreamService: 暂停失败: $e');
    }
  }

  /// 恢复播放
  Future<void> resume() async {
    if (_isPlaying) return;

    try {
      await _player!.resumePlayer();
      _isPlaying = true;
      onPlayingStateChanged?.call(true);
      debugPrint('▶️ PCMStreamService: 已恢复');
    } catch (e) {
      debugPrint('❌ PCMStreamService: 恢复失败: $e');
    }
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    try {
      await _player!.setVolume(volume.clamp(0.0, 1.0));
      debugPrint('🔊 PCMStreamService: 音量设置为 $volume');
    } catch (e) {
      debugPrint('❌ PCMStreamService: 设置音量失败: $e');
    }
  }

  /// 清理资源
  Future<void> dispose() async {
    try {
      _feedTimer?.cancel();
      _feedTimer = null;

      if (_isStreaming) {
        await stopStreaming();
      }

      if (_isInitialized) {
        await _player!.closePlayer();
        _player = null;
        _isInitialized = false;
      }

      debugPrint('🗑️ PCMStreamService: 资源已清理');
    } catch (e) {
      debugPrint('❌ PCMStreamService: 清理失败: $e');
    }
  }

  /// 获取当前播放位置（毫秒）
  Future<Duration?> getPosition() async {
    try {
      // 流式播放没有位置概念，返回 null
      return null;
    } catch (e) {
      return null;
    }
  }
}

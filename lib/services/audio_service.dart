import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:synchronized/synchronized.dart';

import '../audio/pcm_stream_player.dart';
import '../utils/wav_validator.dart';
import '../utils/audio_format_detector.dart';
import 'opus_decoder_service.dart';
import 'pcm_stream_service.dart';

enum _AudioMode { playback, voiceChat }

class AudioService {
  static final AudioService instance = AudioService._init();

  final AudioRecorder _recorder = AudioRecorder();
  
  // 独立的短音效播放器（不干扰主播放器）
  final AudioPlayer _sfxPlayer = AudioPlayer();
  DateTime? _lastSfxAt;
  final _playerLock = Lock();
  final _streamLock = Lock();
  final _sessionLock = Lock();

  // Player and state
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _streamPlayer = AudioPlayer(); // 修复：为流式播放使用独立的播放器
  StreamSubscription<PlayerState>? _playerStateSub;

  // Recording stream controller (forward raw PCM frames)
  StreamController<List<int>>? _audioStreamController;

  // Current audio mode (playback by default)
  _AudioMode _currentAudioMode = _AudioMode.playback;

  PCMStreamPlayer? _pcmStreamPlayer;

  bool _isRecording = false;
  bool _isPlaying = false;
  bool _keepAlive = false;
  bool _streamingSessionActive =
      false; // we switched to playback for streaming and are holding it
  bool _restoreToVoiceChatAfterStream =
      false; // restore session after stream completes
  bool _resumeRecordingAfterStream = false;
  
  // 降低调试日志频率，避免主线程阻塞导致的抖动
  int _processLogCounter = 0;

  AudioService._init();

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  Stream<List<int>>? get audioStream => _audioStreamController?.stream;

  bool get hasAudioStreamListener =>
      _audioStreamController?.hasListener ?? false;

  bool get isVoiceChatMode => _currentAudioMode == _AudioMode.voiceChat;

  Future<void> initialize() async {
    // 不在初始化时配置音频会话，等待实际使用时再配置
    // 这样可以避免与后续的语音聊天模式配置冲突
    debugPrint('🎵 AudioService 初始化，等待实际使用时配置音频会话');

    _ensurePcmStreamPlayer();

    // 初始化 Opus 解码器（AI通话必需）
    try {
      await OpusDecoderService.instance.initialize();
      debugPrint('✅ OpusDecoderService 初始化成功');
    } catch (e) {
      debugPrint('❌ OpusDecoderService 初始化失败: $e');
    }

    // Web 平台暂不使用原生 record 插件
    if (kIsWeb) {
      debugPrint('⚠️ Web 平台：原生录音不受支持，请在 iOS/Android 设备运行以使用麦克风功能');
      return;
    }

    // 检查录音权限
    if (!await _recorder.hasPermission()) {
      debugPrint('⚠️ 没有录音权限');
      return;
    }
  }

  // --- Streaming (AI voice) ---
  void _ensurePcmStreamPlayer() {
    if (_pcmStreamPlayer != null) return;
    // 修复：使用独立的流式播放器，避免与普通播放器冲突
    _pcmStreamPlayer = PCMStreamPlayer(
      player: _streamPlayer,
      onPlaybackStateChanged: (playing) {
        _isPlaying = playing;
      },
      onPlaybackCompleted: () async {
        if (_streamingSessionActive) {
          final needRestore = _restoreToVoiceChatAfterStream;
          final shouldResumeRecording = _resumeRecordingAfterStream;
          _streamingSessionActive = false;
          _restoreToVoiceChatAfterStream = false;
          _resumeRecordingAfterStream = false;
          if (needRestore) {
            try {
              await ensureVoiceChatMode();
            } catch (e) {
              debugPrint('⚠️ 恢复语音聊天模式失败: $e');
            }
            if (shouldResumeRecording) {
              try {
                await startRecording();
                debugPrint('🎙️ 实时通话：恢复麦克风录音');
              } catch (e) {
                debugPrint('⚠️ 实时通话：恢复录音失败: $e');
              }
            }
          }
        }
      },
    );
  }

  Future<void> _ensureStreamPlaylist() async {
    _ensurePcmStreamPlayer();
    await _pcmStreamPlayer!.ensureInitialized();

    // 提前激活音频会话，减少首次播放延时
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      debugPrint('✅ 提前激活音频会话成功');
    } catch (e) {
      debugPrint('⚠️ 提前激活音频会话失败: $e');
    }
  }

  // 使用 PCMStreamService 实现真正的流式播放
  Future<void> streamWavFragment(Uint8List wavBytes) async {
    debugPrint('🎵 streamWavFragment: 接收到数据长度 ${wavBytes.length}');

    if (wavBytes.isEmpty) {
      debugPrint('⚠️ 空音频数据，跳过');
      return;
    }

    try {
      if (!_streamingSessionActive) {
        debugPrint('🔊 初始化PCM流播放会话');
        
        if (_keepAlive) {
          await stopBackgroundKeepAlive();
        }
        
        final inVoiceChatMode = _currentAudioMode == _AudioMode.voiceChat;
        debugPrint('🎤 当前音频模式: ${inVoiceChatMode ? "语音聊天" : "播放"}');
        
        _streamingSessionActive = true;
      }

      // 使用 PCMStreamService 直接播放（自动处理WAV头）
      await PCMStreamService.instance.feedWAV(wavBytes);
      debugPrint('✅ PCM数据已喂入流式播放器');
    } catch (e, stackTrace) {
      debugPrint('❌ streamWavFragment 异常: $e');
      debugPrint('📍 堆栈信息: $stackTrace');
    }
  }

  /// 刷新流式播放缓冲（PCM流不需要显式 flush）
  Future<void> flushStreaming() async {
    debugPrint('🧹 flushStreaming: PCM流式播放自动处理');
    // PCMStreamService 自动管理缓冲，不需要显式 flush
  }

  /// 立即停止当前PCM流式播放并清空队列
  Future<void> stopStreamingAndClear() async {
    try {
      debugPrint('🚦 停止PCM流式播放');
      await PCMStreamService.instance.stopStreaming();
    } catch (e) {
      debugPrint('stopStreamingAndClear failed: $e');
    } finally {
      _streamingSessionActive = false;
      _restoreToVoiceChatAfterStream = false;
      _resumeRecordingAfterStream = false;
    }
  }
  
  /// 检查音频播放是否卡死并尝试恢复
  Future<void> checkAndRecoverPlayback() async {
    try {
      final pcmService = PCMStreamService.instance;
      
      // 如果播放器显示正在播放但实际上没有声音输出
      if (pcmService.isPlaying && _streamingSessionActive) {
        debugPrint('🤖 检查播放状态...');
        
        // 如果检测到可能的卡死情况，尝试重启
        // 这里可以添加更精细的检测逻辑
        debugPrint('🔄 尝试重置音频播放状态');
        await stopStreamingAndClear();
        await Future.delayed(const Duration(milliseconds: 300));
        // 自动重启将由后续数据触发
      }
    } catch (e) {
      debugPrint('⚠️ 检查和恢复播放失败: $e');
    }
  }

  /// 喂入PCM数据到流式播放器（优化版 - 减少日志）
  Future<void> _feedPcmToStream(Uint8List pcmData) async {
    try {
      if (!_streamingSessionActive) {
        debugPrint('🔊 初始化PCM流播放会话');
        
        if (_keepAlive) {
          await stopBackgroundKeepAlive();
        }
        
        final inVoiceChatMode = _currentAudioMode == _AudioMode.voiceChat;
        debugPrint('🎤 当前音频模式: ${inVoiceChatMode ? "语音聊天" : "播放"}');
        
        _streamingSessionActive = true;
      }

      // 直接喂入PCM数据，不添加WAV头部
      await PCMStreamService.instance.feedPCM(pcmData);
      
      // 优化：减少日志输出（每100次输出一次）
      if (_processLogCounter % 100 == 0) {
        debugPrint('✅ PCM数据已喂入流式播放器 (${pcmData.length} bytes)');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ _feedPcmToStream 异常: $e');
      debugPrint('📍 堆栈信息: $stackTrace');
    }
  }

  /// 统一的音频处理入口 - 集成了解码逻辑
  ///
  /// 自动识别音频格式并处理：
  /// - Opus: 解码为 PCM 后流式播放
  /// - WAV: 提取PCM数据后流式播放
  /// - 其他格式: 尝试直接播放
  Future<void> processAudioData(
    Uint8List audioData, {
    String? declaredFormat,
  }) async {
    if (audioData.isEmpty) {
      debugPrint('⚠️ 收到空音频数据，跳过');
      return;
    }

    try {
      // 自动检测格式
      final detectedFormat = AudioFormatDetector.detectFormat(audioData);
      final effectiveFormat = declaredFormat ?? detectedFormat.name;

      _processLogCounter++;
      if (_processLogCounter % 15 == 0) {
        debugPrint(
          '🎵 处理音频数据: 长度=${audioData.length}, 声明格式=$declaredFormat, 检测格式=${detectedFormat.name}',
        );
      }

      // 处理 Opus 格式（需要解码）
      if (_isOpusFormat(detectedFormat, declaredFormat)) {
        await _processOpusAudio(audioData);
        return;
      }

      // 处理 WAV 格式（直接流式播放）
      if (_isWavFormat(audioData)) {
        await streamWavFragment(audioData);
        return;
      }

      // 其他格式尝试直接播放
      final ext = _mapFormatToExtension(effectiveFormat);
      if (ext != null) {
        debugPrint('🎵 尝试直接播放格式: $ext');
        await playAudioFromBytes(audioData, ext: ext);
        return;
      }

      // 兜底：尝试作为 WAV 播放
      debugPrint('⚠️ 未知格式，尝试作为 WAV 播放');
      await streamWavFragment(audioData);
    } catch (e, stack) {
      debugPrint('❌ 处理音频数据失败: $e');
      debugPrint('📍 $stack');
    }
  }

  /// 处理 Opus 编码的音频（优化版 - 减少延迟）
  Future<void> _processOpusAudio(Uint8List opusData) async {
    try {
      // 确保 Opus 解码器已初始化
      if (!OpusDecoderService.instance.isInitialized) {
        debugPrint('⚠️ Opus 解码器未初始化，正在初始化...');
        await OpusDecoderService.instance.initialize();
      }

      // 优化：直接解码，不使用 compute（isolate 会增加延迟）
      // Opus 解码非常快，不会阻塞主线程
      final pcmData = await OpusDecoderService.instance.decode(opusData);

      if (pcmData.isEmpty) {
        debugPrint('⚠️ Opus 解码返回空数据');
        return;
      }

      // 减少日志输出（每20次输出一次）
      _processLogCounter++;
      if (_processLogCounter % 20 == 0) {
        debugPrint(
          '✅ Opus 解码: ${opusData.length} -> ${pcmData.length} bytes PCM',
        );
      }

      // 直接喂入PCM数据到流式播放器
      await _feedPcmToStream(pcmData);
    } catch (e) {
      debugPrint('❌ Opus 解码失败: $e');
    }
  }

  /// 判断是否为 Opus 格式
  bool _isOpusFormat(AudioFormat detected, String? declaredFormat) {
    if (declaredFormat != null) {
      final lower = declaredFormat.toLowerCase();
      return lower.contains('opus') || lower == 'ogg';
    }
    return detected == AudioFormat.rawOpus || detected == AudioFormat.oggOpus;
  }

  /// 判断是否为 WAV 格式
  bool _isWavFormat(Uint8List data) {
    if (data.length < 12) return false;
    return data[0] == 0x52 && // R
        data[1] == 0x49 && // I
        data[2] == 0x46 && // F
        data[3] == 0x46 && // F
        data[8] == 0x57 && // W
        data[9] == 0x41 && // A
        data[10] == 0x56 && // V
        data[11] == 0x45; // E
  }

  /// 映射格式到文件扩展名
  String? _mapFormatToExtension(String? format) {
    if (format == null) return null;

    final lower = format.toLowerCase();
    switch (lower) {
      case 'opus':
      case 'ogg':
      case 'oggopus':
        return 'ogg';
      case 'wav':
      case 'pcm':
        return 'wav';
      case 'mp3':
      case 'mpeg':
        return 'mp3';
      case 'aac':
      case 'm4a':
        return 'aac';
      default:
        return null;
    }
  }

  Future<void> startRecording() async {
    try {
      if (_isRecording) return;

      if (kIsWeb) {
        debugPrint('⚠️ startRecording: Web 平台不支持 record.startStream()');
        throw UnsupportedError('Recording is not supported on web');
      }

      _audioStreamController = StreamController<List<int>>.broadcast();

      final tempDir = await getTemporaryDirectory();
      final String fileExt = 'pcm';
      final path =
          '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      );

      // 开始录音并获取流
      final stream = await _recorder.startStream(config);

      _isRecording = true;

      // 转发音频流
      stream.listen(
        (data) {
          _audioStreamController?.add(data);
        },
        onError: (error) {
          debugPrint('录音流错误: $error');
        },
        onDone: () {
          debugPrint('录音流结束');
        },
      );

      debugPrint('开始录音: $path');
    } catch (e) {
      debugPrint('开始录音失败: $e');
      _isRecording = false;
    }
  }

  // 后台保活：以静音循环方式占用音频会话，避免 App 在后台被挂起
  Future<void> startBackgroundKeepAlive() async {
    try {
      if (_keepAlive) return;

      await _ensureSessionForBackground();

      await _player.stop();
      // 临时使用一个极小的音频数据进行保活，避免文件依赖
      final minimalAudioData = _createMinimalAudioData();
      final tempDir = await getTemporaryDirectory();
      final tempFilePath =
          '${tempDir.path}/keepalive_${DateTime.now().millisecondsSinceEpoch}.wav';
      final file = File(tempFilePath);
      await file.writeAsBytes(minimalAudioData, flush: true);

      await _player.setFilePath(tempFilePath);
      await _player.setLoopMode(LoopMode.one);
      final keepAliveVolume = Platform.isIOS ? 0.01 : 0.0;
      await _player.setVolume(keepAliveVolume);
      await _playWithRetry();
      _keepAlive = true;
      debugPrint('启动后台保活（静音循环）');
    } catch (e) {
      debugPrint('启动后台保活失败: $e');
      _keepAlive = false;
    }
  }

  Future<void> stopBackgroundKeepAlive() async {
    try {
      if (!_keepAlive) return;
      await _player.stop();
      await _player.setLoopMode(LoopMode.off);
      await _player.setVolume(1.0);
      await _playerStateSub?.cancel();
      _playerStateSub = null;
      _keepAlive = false;
      debugPrint('停止后台保活');
    } catch (e) {
      debugPrint('停止后台保活失败: $e');
    }
  }

  bool get isBackgroundKeepingAlive => _keepAlive;

  Future<void> ensureBackgroundKeepAlive() async {
    if (_keepAlive) return;
    await startBackgroundKeepAlive();
  }

  Future<void> disableBackgroundKeepAlive() async {
    if (!_keepAlive) return;
    await stopBackgroundKeepAlive();
  }

  Future<void> _ensureSessionForBackground() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      debugPrint('重新激活音频会话失败: $e');
    }
  }

  Future<void> _configurePlaybackSession() async {
    await _sessionLock.synchronized(() async {
      try {
        final session = await AudioSession.instance;
        // 修复：直接重新配置，不先 deactivate，避免 iOS 错误
        await session.configure(const AudioSessionConfiguration.music());
        await session.setActive(true);
        _currentAudioMode = _AudioMode.playback;
        debugPrint('✅ 音频会话已配置为播放模式');
      } catch (e) {
        debugPrint('⚠️ 配置播放会话失败: $e');
        // 即使失败也更新状态，并尝试激活
        _currentAudioMode = _AudioMode.playback;
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}
      }
    });
  }

  Future<void> _configureVoiceChatSession() async {
    await _sessionLock.synchronized(() async {
      try {
        final session = await AudioSession.instance;
        // 修复：直接重新配置，不先 deactivate
        await session.configure(
          AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth,
            avAudioSessionMode: AVAudioSessionMode.voiceChat,
            androidAudioAttributes: const AndroidAudioAttributes(
              contentType: AndroidAudioContentType.speech,
              usage: AndroidAudioUsage.voiceCommunication,
            ),
          ),
        );
        await session.setActive(true);
        _currentAudioMode = _AudioMode.voiceChat;
        debugPrint('🔊 音频会话已配置为语音聊天模式（支持外放/蓝牙）');
      } catch (e) {
        debugPrint('⚠️ 配置语音聊天会话失败: $e');
        _currentAudioMode = _AudioMode.voiceChat;
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}
      }
    });
  }

  Future<T> _withPlaybackMode<T>(Future<T> Function() action) async {
    final bool shouldRestoreVoiceChat =
        _currentAudioMode == _AudioMode.voiceChat;

    // 修复：不停止录音，语音聊天模式支持同时录音和播放
    // 只需确保音频会话激活
    debugPrint(
      '🧭 播放前模式: ${_currentAudioMode.name}, isRecording: $_isRecording',
    );

    // 如果已经在语音聊天模式，只需确保会话激活
    if (shouldRestoreVoiceChat) {
      await _sessionLock.synchronized(() async {
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
          debugPrint('🔊 保持语音聊天模式，确保会话激活');
        } catch (e) {
          debugPrint('⚠️ 激活语音聊天会话失败: $e');
        }
      });
    } else {
      // 如果不在语音聊天模式，需要配置播放模式
      await _sessionLock.synchronized(() async {
        try {
          await _configurePlaybackSession();
          debugPrint('🎵 切换到播放模式');
        } catch (e) {
          debugPrint('⚠️ 配置播放模式失败: $e');
        }
      });
    }

    try {
      return await action();
    } finally {
      debugPrint('🎵 播放操作完成，保持当前音频会话模式');
    }
  }

  Future<void> _playWithRetry({int retries = 2}) async {
    int attempt = 0;
    while (true) {
      try {
        await _player.play();
        return;
      } catch (e) {
        attempt++;
        if (attempt > retries) rethrow;
        await Future.delayed(const Duration(milliseconds: 500));
        await _ensureSessionForBackground();
      }
    }
  }

  Future<void> stopRecording() async {
    try {
      if (!_isRecording) return;

      await _recorder.stop();
      await _audioStreamController?.close();
      _audioStreamController = null;
      _isRecording = false;

      debugPrint('停止录音');
    } catch (e) {
      debugPrint('停止录音失败: $e');
    }
  }

  Future<void> playAudioFromBytes(List<int> audioData, {String? ext}) async {
    await _playerLock.synchronized(() async {
      await _withPlaybackMode(() async {
        try {
          await _player.stop();

          if (_keepAlive) {
            await stopBackgroundKeepAlive();
          }

          final chosenExt = ext ?? _guessExt(audioData);
          final audioBytes = Uint8List.fromList(audioData);

          // 如果是 WAV 格式，验证文件头
          if (chosenExt == 'wav') {
            debugPrint('🔍 验证 WAV 文件格式...');
            WavValidator.printWavHeader(audioBytes);
            final isValid = WavValidator.validateWav(audioBytes);
            final hasData = WavValidator.hasValidSamples(audioBytes);

            if (!isValid) {
              debugPrint('❌ WAV 文件格式无效，尝试播放可能失败');
            }
            if (!hasData) {
              debugPrint('⚠️ WAV 文件似乎是静音数据');
            }
          }

          // 使用内存流播放（所有平台通用，不持久化文件）
          final source = _buildInMemoryAudioSource(
            audioBytes,
            contentType: _contentTypeForExt(chosenExt),
          );

          await _player.setAudioSource(source);
          await _player.setVolume(1.0);
          _isPlaying = true;

          _player.play();

          await _playerStateSub?.cancel();
          _playerStateSub = _player.playerStateStream.listen((state) {
            debugPrint('🎵 播放状态: ${state.processingState}');
            if (state.processingState == ProcessingState.completed) {
              _isPlaying = false;
            }
          });

          debugPrint('✅ 内存流播放 ${chosenExt.toUpperCase()}');
        } catch (e) {
          debugPrint('❌ 播放音频失败: $e');
          _isPlaying = false;
          rethrow;
        }
      });
    });
  }

  String _guessExt(List<int> bytes) {
    if (bytes.length >= 12) {
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x41 &&
          bytes[10] == 0x56 &&
          bytes[11] == 0x45) {
        return 'wav';
      }
      if (bytes[0] == 0x4F &&
          bytes[1] == 0x67 &&
          bytes[2] == 0x67 &&
          bytes[3] == 0x53) {
        return 'ogg';
      }
      if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
        return 'mp3';
      }
      if (bytes[0] == 0x63 &&
          bytes[1] == 0x61 &&
          bytes[2] == 0x66 &&
          bytes[3] == 0x66) {
        return 'caf';
      }
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0) {
      return 'aac';
    }
    return 'wav';
  }

  String _contentTypeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'ogg':
        return 'audio/ogg';
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
        return 'audio/aac';
      case 'caf':
        return 'audio/x-caf';
      case 'wav':
      default:
        return 'audio/wav';
    }
  }

  AudioSource _buildInMemoryAudioSource(
    Uint8List buffer, {
    required String contentType,
  }) {
    return _BytesAudioSource(buffer, contentType: contentType);
  }

  /// 播放短促的 UI 音效（带最小触发间隔，避免滚动时过度触发）
  Future<void> playUiEffectFromAsset(
    String assetPath, {
    double volume = 0.3,
    int minIntervalMs = 120,
  }) async {
    try {
      final now = DateTime.now();
      if (_lastSfxAt != null &&
          now.difference(_lastSfxAt!).inMilliseconds < minIntervalMs) {
        return; // 节流
      }

      // 规范路径并加载资源字节
      String normalizedPath = assetPath.trim();
      normalizedPath = normalizedPath.replaceAll('/ ', '/').replaceAll(' /', '/');
      if (!normalizedPath.startsWith('assets/')) {
        normalizedPath = 'assets/$normalizedPath';
      }

      ByteData bd;
      try {
        bd = await rootBundle.load(normalizedPath);
      } catch (_) {
        // 回退到默认资源
        bd = await rootBundle.load('assets/audio/ringtones/test.wav');
        normalizedPath = 'assets/audio/ringtones/test.wav';
      }

      final bytes = bd.buffer.asUint8List();
      final contentType = normalizedPath.toLowerCase().endsWith('.wav')
          ? 'audio/wav'
          : normalizedPath.toLowerCase().endsWith('.mp3')
              ? 'audio/mpeg'
              : 'application/octet-stream';

      final source = _buildInMemoryAudioSource(bytes, contentType: contentType);

      await _sfxPlayer.stop();
      await _sfxPlayer.setVolume(volume.clamp(0.0, 1.0));
      await _sfxPlayer.setAudioSource(source);
      await _sfxPlayer.play();

      _lastSfxAt = DateTime.now();
    } catch (e) {
      debugPrint('⚠️ 播放UI音效失败: $e');
    }
  }

  Future<void> playAudioFromAsset(String assetPath) async {
    await _playerLock.synchronized(() async {
      await _withPlaybackMode(() async {
        try {
          await _player.stop();

          // 先停止后台保活
          if (_keepAlive) {
            await stopBackgroundKeepAlive();
          }

          await _player.setVolume(1.0);
          debugPrint('🔊 音量已设置为: 1.0');

          // 标准化资源路径：去除多余空白、修正斜杠两侧的空格，并确保以 'assets/' 开头
          String normalizedPath = assetPath.trim();
          normalizedPath = normalizedPath
              .replaceAll('/ ', '/')
              .replaceAll(' /', '/');
          if (!normalizedPath.startsWith('assets/')) {
            normalizedPath = 'assets/$normalizedPath';
          }

          // 验证资源是否存在
          try {
            await rootBundle.load(normalizedPath);
            debugPrint('✅ 资源文件验证成功: $normalizedPath');
          } catch (e) {
            debugPrint('⚠️ 资源不存在，回退到默认铃声: $e');
            normalizedPath = 'assets/audio/ringtones/ringring.wav';
            try {
              await rootBundle.load(normalizedPath);
              debugPrint('✅ 默认铃声验证成功: $normalizedPath');
            } catch (e2) {
              debugPrint('❌ 连默认铃声都不存在: $e2');
              throw Exception('音频资源文件不存在: $assetPath，且默认铃声也不可用');
            }
          }

          debugPrint('📁 资源路径: $normalizedPath');

          // 直接改为以内存流播放，避免资产键差异导致的问题
          final bd = await rootBundle.load(normalizedPath);
          final bytes = bd.buffer.asUint8List();
          if (normalizedPath.toLowerCase().endsWith('.wav')) {
            debugPrint('🔍 资产WAV头信息:');
            WavValidator.printWavHeader(bytes);
            final ok = WavValidator.validateWav(bytes);
            final has = WavValidator.hasValidSamples(bytes);
            debugPrint(
              'WAV校验 => valid: $ok, hasData: $has, size: ${bytes.length}',
            );
          }
          final ext = normalizedPath.toLowerCase().endsWith('.wav')
              ? 'audio/wav'
              : normalizedPath.toLowerCase().endsWith('.mp3')
              ? 'audio/mpeg'
              : 'application/octet-stream';
          final source = _buildInMemoryAudioSource(bytes, contentType: ext);
          await _player.setAudioSource(source);
          debugPrint('✅ 音频源设置完成(内存)');

          _isPlaying = true;
          _player.play();
          debugPrint('▶️ 开始播放资源: $assetPath');

          await _playerStateSub?.cancel();
          _playerStateSub = _player.playerStateStream.listen((state) {
            debugPrint('🎵 播放状态: ${state.processingState}');
            if (state.processingState == ProcessingState.completed) {
              _isPlaying = false;
              debugPrint('✅ 音频播放完成');
            }
          });
        } catch (e, stack) {
          debugPrint('❌ 播放资源失败: $e');
          debugPrint('$stack');
          _isPlaying = false;
          rethrow;
        }
      });
    });
  }

  Future<void> playAudioFromUrl(String url) async {
    await _playerLock.synchronized(() async {
      await _withPlaybackMode(() async {
        try {
          await _player.stop();

          if (_keepAlive) {
            await stopBackgroundKeepAlive();
          }

          await _player.setVolume(1.0);
          debugPrint('🔊 音量已设置为: 1.0');

          await _player.setUrl(url);
          _isPlaying = true;

          _player.play();
          debugPrint('▶️ 开始播放URL: $url');

          await _playerStateSub?.cancel();
          _playerStateSub = _player.playerStateStream.listen((state) {
            debugPrint('🎵 播放状态: ${state.processingState}');
            if (state.processingState == ProcessingState.completed) {
              _isPlaying = false;
              debugPrint('✅ 音频播放完成');
            }
          });
        } catch (e) {
          debugPrint('❌ 播放URL失败: $e');
          _isPlaying = false;
        }
      });
    });
  }

  Future<void> stopPlaying() async {
    try {
      await _player.stop();
      _isPlaying = false;
      debugPrint('停止播放');
    } catch (e) {
      debugPrint('停止播放失败: $e');
    }
  }

  Future<void> pausePlaying() async {
    try {
      await _player.pause();
      debugPrint('暂停播放');
    } catch (e) {
      debugPrint('暂停播放失败: $e');
    }
  }

  Future<void> resumePlaying() async {
    try {
      await _player.play();
      debugPrint('继续播放');
    } catch (e) {
      debugPrint('继续播放失败: $e');
    }
  }

  Future<void> enterVoiceChatMode() async {
    try {
      await _configureVoiceChatSession();
      debugPrint('🎙️ 切换至语音聊天模式');
    } catch (e) {
      debugPrint('❌ 切换语音聊天模式失败: $e');
    }
  }

  Future<void> ensureVoiceChatMode() async {
    if (isVoiceChatMode) return;
    await enterVoiceChatMode();
  }

  Future<void> exitVoiceChatMode() async {
    // 修复：不在这里打印日志，避免重复，_configurePlaybackSession 已有日志
    await _configurePlaybackSession();
  }

  /// 简单的音频测试：使用 PCMStreamService 播放测试音
  Future<void> testAudioPlayback() async {
    try {
      debugPrint('🎵 开始音频播放测试...');

      // 修复：不再切换模式，直接使用 PCMStreamService 播放
      // 这样不会干扰当前的录音会话

      // 生成一个简单的 440Hz 正弦波信号（A4 音）
      const sampleRate = 16000;
      const duration = 0.5; // 0.5 秒
      const frequency = 440.0; // A4 音

      final samples = <int>[];
      for (int i = 0; i < (sampleRate * duration).toInt(); i++) {
        final t = i / sampleRate;
        final sample = (32767 * 0.3 * sin(2 * 3.14159 * frequency * t)).round();
        samples.add(sample & 0xFF); // Low byte
        samples.add((sample >> 8) & 0xFF); // High byte
      }

      // 构造 WAV 文件头
      final dataSize = samples.length;
      final fileSize = 36 + dataSize;

      final wavData = <int>[
        // "RIFF" header
        0x52, 0x49, 0x46, 0x46,
        fileSize & 0xFF,
        (fileSize >> 8) & 0xFF,
        (fileSize >> 16) & 0xFF,
        (fileSize >> 24) & 0xFF,
        // "WAVE" format
        0x57, 0x41, 0x56, 0x45,
        // "fmt " subchunk
        0x66, 0x6D, 0x74, 0x20,
        16, 0, 0, 0, // Subchunk1Size
        1, 0, // AudioFormat (PCM)
        1, 0, // NumChannels (mono)
        sampleRate & 0xFF, (sampleRate >> 8) & 0xFF, 0, 0, // SampleRate
        (sampleRate * 2) & 0xFF,
        ((sampleRate * 2) >> 8) & 0xFF,
        0,
        0, // ByteRate
        2, 0, // BlockAlign
        16, 0, // BitsPerSample
        // "data" subchunk
        0x64, 0x61, 0x74, 0x61,
        dataSize & 0xFF,
        (dataSize >> 8) & 0xFF,
        (dataSize >> 16) & 0xFF,
        (dataSize >> 24) & 0xFF,
        ...samples,
      ];

      // 使用 PCMStreamService 直接播放 PCM 数据
      final pcmData = Uint8List.fromList(samples);
      
      // 初始化 PCMStreamService
      if (!PCMStreamService.instance.isInitialized) {
        await PCMStreamService.instance.initialize();
      }
      
      // 喂入 PCM 数据
      await PCMStreamService.instance.feedPCM(pcmData);
      
      debugPrint('✅ 测试音频已发送到 PCMStreamService');
      
      // 等待 1 秒后停止
      await Future.delayed(const Duration(seconds: 1));
      await PCMStreamService.instance.stopStreaming();
    } catch (e, stackTrace) {
      debugPrint('❌ 音频播放测试失败: $e');
      debugPrint('📍 堆栈: $stackTrace');
    }
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _audioStreamController?.close();
  }

  List<int> _createMinimalAudioData() {
    // 创建一个最小的WAV文件头 + 1秒的静音数据
    const sampleRate = 8000; // 低采样率
    const duration = 1; // 1秒
    const numSamples = sampleRate * duration;
    final samples = List<int>.filled(numSamples * 2, 0); // 16-bit静音

    // WAV文件头
    final dataSize = samples.length;
    final fileSize = 36 + dataSize;

    return [
      // "RIFF"
      0x52, 0x49, 0x46, 0x46,
      // 文件大小 - 8
      fileSize & 0xFF,
      (fileSize >> 8) & 0xFF,
      (fileSize >> 16) & 0xFF,
      (fileSize >> 24) & 0xFF,
      // "WAVE"
      0x57, 0x41, 0x56, 0x45,
      // "fmt "
      0x66, 0x6D, 0x74, 0x20,
      // fmt chunk size (16)
      0x10, 0x00, 0x00, 0x00,
      // Audio format (1 = PCM)
      0x01, 0x00,
      // 声道数 (1 = 单声道)
      0x01, 0x00,
      // 采样率
      sampleRate & 0xFF,
      (sampleRate >> 8) & 0xFF,
      0x00, 0x00,
      // 字节率 (sampleRate * channels * bitsPerSample/8)
      (sampleRate * 2) & 0xFF, ((sampleRate * 2) >> 8) & 0xFF,
      0x00, 0x00,
      // Block align (channels * bitsPerSample/8)
      0x02, 0x00,
      // Bits per sample
      0x10, 0x00,
      // "data"
      0x64, 0x61, 0x74, 0x61,
      // Data size
      dataSize & 0xFF,
      (dataSize >> 8) & 0xFF,
      (dataSize >> 16) & 0xFF,
      (dataSize >> 24) & 0xFF,
      // 静音样本数据
      ...samples,
    ];
  }
}

class _BytesAudioSource extends StreamAudioSource {
  _BytesAudioSource(this.bytes, {required this.contentType});

  final Uint8List bytes;
  final String contentType;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final totalLength = bytes.length;
    final actualStart = (start ?? 0).clamp(0, totalLength);
    final clampedEnd = end == null ? totalLength : end.clamp(0, totalLength);
    final actualEnd = clampedEnd < actualStart ? actualStart : clampedEnd;
    final slice = bytes.sublist(actualStart, actualEnd);
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: slice.length,
      offset: actualStart,
      stream: Stream.value(slice),
      contentType: contentType,
    );
  }
}

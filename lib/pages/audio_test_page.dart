import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import 'dart:math' as math;

class AudioTestPage extends StatefulWidget {
  @override
  State<AudioTestPage> createState() => _AudioTestPageState();
}

class _AudioTestPageState extends State<AudioTestPage> {
  final List<String> _logs = [];
  bool _isPlaying = false;

  void _addLog(String log) {
    setState(() {
      _logs.insert(0, '${DateTime.now().toString().substring(11, 19)} - $log');
    });
    debugPrint(log);
  }

  Future<void> _testLocalAudio() async {
    _addLog('📱 测试本地音频资源文件...');
    try {
      // 直接测试资源文件，不生成临时音频
      _addLog('🎵 开始测试资源文件播放...');

      // 尝试多个可能的路径 - 修正 test.wav 的实际位置
      final assetPaths = [
        'assets/audio/ringtones/test.wav',  // 实际位置
        'assets/audio/ringtones/ringring.wav',  // 备用文件
        'assets/audio/test.wav',  // 旧路径（保留兼容）
        'audio/ringtones/test.wav',
        'audio/test.wav',
      ];

      bool success = false;
      for (final path in assetPaths) {
        try {
          _addLog('🔍 尝试路径: $path');
          await AudioService.instance.playAudioFromAsset(path);
          _addLog('✅ 资源播放成功: $path');
          success = true;
          break;
        } catch (e) {
          _addLog('❌ 路径失败: $path - $e');
        }
      }

      if (!success) {
        _addLog('⚠️ 所有资源路径都失败');
      }
    } catch (e) {
      _addLog('❌ 音频播放失败: $e');
    }
  }

  Future<void> _playSpecificAsset(String assetPath) async {
    _addLog('🎯 尝试播放资源: $assetPath');
    try {
      await AudioService.instance.playAudioFromAsset(assetPath);
      _addLog('✅ 播放成功: $assetPath');
    } catch (e) {
      _addLog('❌ 播放失败: $assetPath - $e');
    }
  }

  Future<void> _testSimpleWav() async {
    _addLog('🎵 测试简单WAV音频...');
    try {
      // 生成一个简单的440Hz正弦波WAV文件（1秒）
      final bytes = _generateSimpleWav();
      _addLog('📦 生成测试音频: ${bytes.length} bytes');
      await AudioService.instance.playAudioFromBytes(bytes, ext: 'wav');
      _addLog('✅ WAV音频播放成功');
    } catch (e) {
      _addLog('❌ WAV音频播放失败: $e');
    }
  }

  Future<void> _testInitialization() async {
    _addLog('🔧 测试音频服务初始化...');
    try {
      await AudioService.instance.initialize();
      _addLog('✅ 音频服务初始化成功');
    } catch (e) {
      _addLog('❌ 音频服务初始化失败: $e');
    }
  }

  Future<void> _checkPlayingState() async {
    final isPlaying = AudioService.instance.isPlaying;
    _addLog('📊 播放状态: ${isPlaying ? "正在播放" : "未播放"}');
    setState(() {
      _isPlaying = isPlaying;
    });
  }

  // 生成一个简单的440Hz正弦波WAV文件
  List<int> _generateSimpleWav() {
    const sampleRate = 16000;
    const duration = 1; // 1秒
    const frequency = 440.0; // A4音符
    const amplitude = 0.3;

    final numSamples = sampleRate * duration;
    final samples = <int>[];

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final value = (amplitude * 32767 * math.sin(2 * math.pi * frequency * t))
          .round();
      // 16-bit PCM, little-endian
      samples.add(value & 0xFF);
      samples.add((value >> 8) & 0xFF);
    }

    // WAV文件头
    final dataSize = samples.length;
    final fileSize = 36 + dataSize;

    final header = <int>[
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
      (sampleRate >> 16) & 0xFF,
      (sampleRate >> 24) & 0xFF,
      // 字节率 (sampleRate * channels * bitsPerSample/8)
      (sampleRate * 2) & 0xFF, ((sampleRate * 2) >> 8) & 0xFF,
      ((sampleRate * 2) >> 16) & 0xFF, ((sampleRate * 2) >> 24) & 0xFF,
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
    ];

    return [...header, ...samples];
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔊 音频测试'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLogs,
            tooltip: '清除日志',
          ),
        ],
      ),
      body: Column(
        children: [
          // 测试按钮区域
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Text(
                          '播放状态: ${_isPlaying ? "🔊 正在播放" : "🔇 未播放"}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _checkPlayingState,
                          icon: const Icon(Icons.refresh),
                          label: const Text('刷新状态'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _testInitialization,
                  icon: const Icon(Icons.settings),
                  label: const Text('1. 测试音频初始化'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _playSpecificAsset('assets/audio/ringtones/test.wav'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('2a. 直接播放 test.wav (正确路径)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _playSpecificAsset('assets/audio/ringtones/ringring.wav'),
                  icon: const Icon(Icons.music_note),
                  label: const Text('2b. 直接播放 ringring.wav (对比测试)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _testLocalAudio,
                  icon: const Icon(Icons.audiotrack),
                  label: const Text('2. 测试所有音频路径'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _testSimpleWav,
                  icon: const Icon(Icons.graphic_eq),
                  label: const Text('3. 测试生成的WAV音频'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                Text('诊断说明', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                const Text(
                  '• 先测试初始化\n'
                  '• 直接播放 test.wav（已修正路径）\n'
                  '• 对比测试 ringring.wav\n'
                  '• 测试所有可能的音频路径\n'
                  '• 最后测试生成的WAV音频',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              color: Colors.black87,
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        '点击上方按钮开始测试\n日志将显示在这里',
                        style: TextStyle(color: Colors.white54),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        Color color = Colors.white;
                        if (log.contains('✅')) {
                          color = Colors.greenAccent;
                        } else if (log.contains('❌')) {
                          color = Colors.redAccent;
                        } else if (log.contains('⚠️')) {
                          color = Colors.orangeAccent;
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            log,
                            style: TextStyle(
                              color: color,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

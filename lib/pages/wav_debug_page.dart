import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/opus_decoder_service.dart';
import '../utils/wav_validator.dart';
import 'dart:math' as math;

class WavDebugPage extends StatefulWidget {
  const WavDebugPage({Key? key}) : super(key: key);

  @override
  State<WavDebugPage> createState() => _WavDebugPageState();
}

class _WavDebugPageState extends State<WavDebugPage> {
  final List<String> _logs = [];

  void _addLog(String log) {
    setState(() {
      _logs.insert(0, '${DateTime.now().toString().substring(11, 19)} - $log');
    });
    debugPrint(log);
  }

  /// 测试1: 播放内置的 WAV 资源文件
  Future<void> _testAssetWav() async {
    _addLog('📱 测试1: 播放资源文件 test.wav');
    try {
      await AudioService.instance.playAudioFromAsset(
        'assets/audio/ringtones/test.wav',
      );
      _addLog('✅ 资源文件播放成功');
    } catch (e) {
      _addLog('❌ 资源文件播放失败: $e');
    }
  }

  /// 测试2: 生成简单的 WAV 并播放（内存方式）
  Future<void> _testGeneratedWavInMemory() async {
    _addLog('🎵 测试2: 生成 WAV 并播放（内存）');
    try {
      final wavData = _generateTestWav(frequency: 440.0, duration: 1);

      _addLog('📦 生成的 WAV 大小: ${wavData.length} bytes');

      // 验证 WAV
      WavValidator.validateWav(wavData);
      WavValidator.hasValidSamples(wavData);

      await AudioService.instance.playAudioFromBytes(wavData, ext: 'wav');
      _addLog('✅ 内存播放成功');
    } catch (e) {
      _addLog('❌ 内存播放失败: $e');
    }
  }

  /// 测试3: 使用不同频率测试 WAV 播放
  Future<void> _testDifferentFrequencies() async {
    _addLog('🎵 测试3: 测试不同频率的 WAV');
    try {
      // 测试 C5 音符 (523.25 Hz)
      final wavData = _generateTestWav(frequency: 523.25, duration: 1);

      _addLog('📦 生成的 WAV 大小: ${wavData.length} bytes (C5音符)');

      // 验证 WAV
      WavValidator.validateWav(wavData);
      WavValidator.hasValidSamples(wavData);

      await AudioService.instance.playAudioFromBytes(wavData, ext: 'wav');
      _addLog('✅ 不同频率测试成功');
    } catch (e) {
      _addLog('❌ 不同频率测试失败: $e');
    }
  }

  /// 测试4: 模拟 Opus 解码后的 WAV 播放
  Future<void> _testOpusDecodedWav() async {
    _addLog('🎧 测试4: 模拟 Opus 解码播放');
    try {
      // 初始化 Opus 解码器
      if (!OpusDecoderService.instance.isInitialized) {
        _addLog('🔧 初始化 Opus 解码器...');
        await OpusDecoderService.instance.initialize();
        _addLog('✅ Opus 解码器初始化成功');
      }

      // 生成测试 PCM 数据（16kHz, 单声道, 16bit）
      final pcmData = _generateTestPcm(frequency: 523.25, duration: 1); // C5 音符

      _addLog('📦 PCM 数据大小: ${pcmData.length} bytes');

      // 使用 Opus 解码器的 WAV 转换
      final wavData = OpusDecoderService.instance.convertPcmToWav(pcmData);

      _addLog('📦 转换后的 WAV 大小: ${wavData.length} bytes');

      // 验证 WAV
      WavValidator.validateWav(wavData);
      WavValidator.hasValidSamples(wavData);

      await AudioService.instance.playAudioFromBytes(wavData, ext: 'wav');
      _addLog('✅ Opus 解码流程测试成功');
    } catch (e) {
      _addLog('❌ Opus 解码流程测试失败: $e');
    }
  }

  /// 测试5: 检查系统音频权限和配置
  Future<void> _testAudioConfig() async {
    _addLog('⚙️ 测试5: 检查音频配置');
    try {
      await AudioService.instance.initialize();
      _addLog('✅ 音频服务初始化成功');

      _addLog(' 播放状态: ${AudioService.instance.isPlaying ? "播放中" : "空闲"}');
    } catch (e) {
      _addLog('❌ 音频配置检查失败: $e');
    }
  }

  /// 生成测试用的 WAV 数据（标准格式）
  Uint8List _generateTestWav({
    required double frequency,
    required int duration,
    int sampleRate = 16000,
  }) {
    final numSamples = sampleRate * duration;
    final samples = <int>[];

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final value = (0.3 * 32767 * math.sin(2 * math.pi * frequency * t))
          .round();
      // 16-bit PCM, little-endian
      samples.add(value & 0xFF);
      samples.add((value >> 8) & 0xFF);
    }

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
      (sampleRate * 2) & 0xFF,
      ((sampleRate * 2) >> 8) & 0xFF,
      ((sampleRate * 2) >> 16) & 0xFF,
      ((sampleRate * 2) >> 24) & 0xFF,
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

    return Uint8List.fromList([...header, ...samples]);
  }

  /// 生成测试用的 PCM 数据（16kHz, 单声道, 16bit）
  Uint8List _generateTestPcm({
    required double frequency,
    required int duration,
    int sampleRate = 16000,
  }) {
    final numSamples = sampleRate * duration;
    final samples = <int>[];

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final value = (0.3 * 32767 * math.sin(2 * math.pi * frequency * t))
          .round();
      // 16-bit PCM, little-endian
      samples.add(value & 0xFF);
      samples.add((value >> 8) & 0xFF);
    }

    return Uint8List.fromList(samples);
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
        title: const Text('🔍 WAV 播放诊断'),
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '🎯 WAV 音频播放完整诊断',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _testAudioConfig,
                  child: const Text('0️⃣ 检查音频配置'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _testAssetWav,
                  child: const Text('1️⃣ 测试资源文件 WAV'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _testGeneratedWavInMemory,
                  child: const Text('2️⃣ 测试生成的 WAV（内存）'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _testDifferentFrequencies,
                  child: const Text('3️⃣ 测试不同频率的 WAV'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _testOpusDecodedWav,
                  child: const Text('4️⃣ 测试 Opus 解码流程'),
                ),
                const Divider(height: 24),
                const Text(
                  '💡 提示：\n'
                  '• 按顺序运行测试，观察每个测试的输出\n'
                  '• 所有测试均使用内存流播放，不会持久化文件',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
                        } else if (log.contains('📦') || log.contains('📁')) {
                          color = Colors.cyanAccent;
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            log,
                            style: TextStyle(
                              color: color,
                              fontFamily: 'monospace',
                              fontSize: 11,
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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'audio_service.dart';
import 'device_state.dart';
import 'xiaozhi_audio_handler.dart';
import 'xiaozhi_protocol.dart';
import 'xiaozhi_dispatcher.dart';
import 'xiaozhi_mic.dart';
import 'pcm_stream_service.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'simple_vad.dart';

class XiaozhiActivationResult {
  final bool activated;
  final String? code;
  final String? portalUrl;
  final String? challenge;
  final Map? raw;

  XiaozhiActivationResult.activated()
    : activated = true,
      code = null,
      portalUrl = null,
      challenge = null,
      raw = null;

  XiaozhiActivationResult.notActivated({
    required this.code,
    this.portalUrl,
    this.challenge,
    this.raw,
  }) : activated = false;
}

class XiaozhiService {
  static final XiaozhiService instance = XiaozhiService._internal();
  // 公益后端默认地址（来自 liu731/xiaozhi 项目）
  // 修改为新的默认地址（按要求）
  static const String _defaultOtaUrl = 'https://api.tenclass.net/xiaozhi/ota/';
  static const String _defaultWsUrl = 'wss://api.tenclass.net/xiaozhi/v1/';

  // 偏好存储 key
  static const _kOtaUrl = 'xiaozhi_ota_url';
  static const _kWsUrl = 'xiaozhi_ws_url';
  static const _kDeviceId = 'xiaozhi_device_id';
  static const _kAccessToken = 'xiaozhi_access_token';
  static const _kClientId = 'xiaozhi_client_id';
  static const _kSerialNumber = 'xiaozhi_serial_number';
  static const _kActivated = 'xiaozhi_activated';

  // 音频参数（与后端约定）
  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _frameDuration = 60; // ms

  // 统一使用 Opus，便于在本地解码为 PCM 并进行流式播放（更稳定，延迟更低）
  String get _preferredAudioFormat {
    return 'opus';
  }

  WebSocketChannel? _ws;
  // higher-level protocol wrapper
  XiaozhiProtocol? _protocol;
  late final Dio _dio = Dio();
  StreamSubscription<List<int>>? _micSub;
  final XiaozhiMic _webMic = XiaozhiMic();

  // 统一的设备状态机
  DeviceState _deviceState = DeviceState.idle;

  // 简化后的状态标志
  bool _isInRealtimeMode = false; // 是否处于实时通话模式
  bool _keepListening = false; // 客户端偏好：在AI说话后是否保持监听

  // VAD（打断）相关
  bool _bargeInEnabled = true;
  DateTime? _bargeInBlockUntil;

  StreamSubscription? _wsSub;
  Timer? _helloTimeoutTimer;
  Timer? _pingTimer; // 心跳定时器
  DateTime? _lastMessageTime; // 最后一次收到消息的时间
  int _reconnectAttempts = 0; // 重连尝试次数
  bool _shouldReconnect = false; // 是否应该自动重连
  Timer? _reconnectTimer; // 重连定时器

  String? _sessionId;
  // connection & message streams
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<XiaozhiMessage> _messageController =
      StreamController<XiaozhiMessage>.broadcast();
  // framing mode
  bool _useJsonAudioFrames = false; // 默认按协议用二进制音频帧，必要时可切换 JSON+base64

  // VAD
  SimpleVAD? _vad;

  // 开发用：计数已发送的音频帧
  // ignore: unused_field
  int _micChunkCount = 0;

  // TTS 文本累积（用于UI显示）
  String _currentTtsText = '';
  String? _currentAiMessageId; // 当前正在流式更新的AI消息ID

  // 简化消息去重
  final Set<String> _sentMessageHashes = <String>{};

  XiaozhiService._internal();

  // region: public getters
  String? get sessionId => _sessionId;
  bool get isConnected => _ws != null;
  bool get isMicActive => _deviceState.isListening;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<XiaozhiMessage> get messageStream => _messageController.stream;

  Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  Future<String> getOtaUrl() async =>
      (await _prefs).getString(_kOtaUrl) ?? _defaultOtaUrl;

  Future<String> getWsUrl() async =>
      (await _prefs).getString(_kWsUrl) ?? _defaultWsUrl;

  Future<String> getDeviceId() async =>
      (await _prefs).getString(_kDeviceId) ?? await _ensureDeviceId();
  Future<String> getAccessToken() async =>
      (await _prefs).getString(_kAccessToken) ?? '';
  Future<String> getClientId() async =>
      (await _prefs).getString(_kClientId) ?? await _ensureClientId();
  Future<String> getSerialNumber() async =>
      (await _prefs).getString(_kSerialNumber) ?? '';

  Future<bool> isLocallyActivated() async =>
      (await _prefs).getBool(_kActivated) ?? false;

  Future<void> setLocalActivated(bool v) async {
    final prefs = await _prefs;
    await prefs.setBool(_kActivated, v);
  }
  // endregion

  // 生成单播 MAC 风格的设备 ID（与参考项目一致）
  String _generateUnicastMac() {
    final rand = Random();
    final macBytes = List<int>.generate(6, (_) => rand.nextInt(256));
    macBytes[0] = (macBytes[0] & 0xFE) | 0x02; // 置为单播/本地位
    return macBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  Future<String> _ensureDeviceId() async {
    final prefs = await _prefs;
    final existing = prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generateUnicastMac();
    await prefs.setString(_kDeviceId, id);
    return id;
  }

  Future<String> _ensureClientId() async {
    final prefs = await _prefs;
    final existing = prefs.getString(_kClientId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_kClientId, id);
    return id;
  }

  // 生成硬件指纹（主机名 + MAC + 机器ID），并返回 SHA256 十六进制字符串
  Future<String> generateHardwareHash() async {
    // 在 Flutter 环境中，无法可靠获取主机名或机器 id，优先使用已保存的 deviceId 和 machine_id
    final identifiers = <String>[];
    try {
      final prefs = await _prefs;
      final mac = prefs.getString(_kDeviceId);
      if (mac != null && mac.isNotEmpty) identifiers.add(mac);
      final machineId = prefs.getString('machine_id');
      if (machineId != null && machineId.isNotEmpty) identifiers.add(machineId);
    } catch (_) {}

    final fingerprintStr = identifiers.join('||');
    final bytes = crypto.sha256.convert(utf8.encode(fingerprintStr)).bytes;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // 从本地（示例：SharedPreferences 的 efuse.json 或生成）获取 HMAC 密钥；若不存在则生成并保存
  Future<String> _getOrCreateHmacKey() async {
    final prefs = await _prefs;
    final existing = prefs.getString('hmac_key');
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = await generateHardwareHash();
    await prefs.setString('hmac_key', generated);
    return generated;
  }

  // 根据硬件信息生成序列号：优先使用 MAC，格式 SN-<MD5_8>-<mac_clean>
  Future<String> _generateSerialNumber() async {
    try {
      final prefs = await _prefs;
      final mac = prefs.getString(_kDeviceId);
      if (mac != null && mac.isNotEmpty) {
        final macClean = mac.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
        final md5 = crypto.md5
            .convert(utf8.encode(macClean))
            .toString()
            .toUpperCase();
        final shortHash = md5.substring(0, 8);
        return 'SN-$shortHash-$macClean';
      }

      // 备用：尝试 machine_id 或 clientId
      final machineId = prefs.getString('machine_id');
      if (machineId != null && machineId.isNotEmpty) {
        final id = machineId
            .replaceAll(RegExp(r'[^0-9A-Za-z]'), '')
            .toUpperCase();
        final md5 = crypto.md5
            .convert(utf8.encode(id))
            .toString()
            .toUpperCase();
        return 'SN-${md5.substring(0, 8)}-${id.substring(0, 12)}';
      }

      final clientId = prefs.getString(_kClientId) ?? '';
      if (clientId.isNotEmpty) {
        final id = clientId
            .replaceAll(RegExp(r'[^0-9A-Za-z]'), '')
            .toUpperCase();
        final md5 = crypto.md5
            .convert(utf8.encode(id))
            .toString()
            .toUpperCase();
        return 'SN-${md5.substring(0, 8)}-${id.substring(0, id.length < 12 ? id.length : 12)}';
      }

      // 最后兜底
      final rand = Random();
      final randomBytes = List<int>.generate(6, (_) => rand.nextInt(256));
      final rndHex = randomBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final md5 = crypto.md5
          .convert(utf8.encode(rndHex))
          .toString()
          .toUpperCase();
      return 'SN-${md5.substring(0, 8)}-$rndHex';
    } catch (_) {
      // 出错时返回一个随机序列号
      final rand = Random();
      final randomBytes = List<int>.generate(6, (_) => rand.nextInt(256));
      final rndHex = randomBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final md5 = crypto.md5
          .convert(utf8.encode(rndHex))
          .toString()
          .toUpperCase();
      return 'SN-${md5.substring(0, 8)}-$rndHex';
    }
  }

  // 计算 HMAC-SHA256 签名，返回十六进制字符串
  Future<String> generateHmacSignature(String challenge) async {
    final key = await _getOrCreateHmacKey();
    final hmac = crypto.Hmac(crypto.sha256, utf8.encode(key));
    final sig = hmac.convert(utf8.encode(challenge));
    return sig.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> saveConfig({
    String? otaUrl,
    String? wsUrl,
    String? deviceId,
    String? accessToken,
    String? clientId,
    String? serialNumber,
  }) async {
    final prefs = await _prefs;
    if (otaUrl != null && otaUrl.isNotEmpty) {
      await prefs.setString(_kOtaUrl, otaUrl);
    }
    if (wsUrl != null && wsUrl.isNotEmpty) {
      await prefs.setString(_kWsUrl, wsUrl);
    }
    if (deviceId != null && deviceId.isNotEmpty) {
      await prefs.setString(_kDeviceId, deviceId);
    }
    if (accessToken != null) {
      await prefs.setString(_kAccessToken, accessToken);
    }
    if (clientId != null && clientId.isNotEmpty) {
      await prefs.setString(_kClientId, clientId);
    }
    if (serialNumber != null && serialNumber.isNotEmpty) {
      await prefs.setString(_kSerialNumber, serialNumber);
    }
  }

  // 调用 OTA 接口，获取激活状态或六位验证码
  Future<XiaozhiActivationResult> checkActivation() async {
    final url = await getOtaUrl();
    final deviceId = await getDeviceId();
    final clientId = await getClientId();
    String serial = await getSerialNumber();
    final localActivated = await isLocallyActivated();
    // 若未配置序列号，自动生成并持久化
    if (serial.isEmpty) {
      serial = await _generateSerialNumber();
      try {
        await saveConfig(serialNumber: serial);
      } catch (_) {}
    }

    // 固定信息（可根据需要改为配置项）
    final boardType = 'bread-compact-wifi';
    final boardName = 'callcall';
    final appVersion = '2.0.0';
    // 本地 IP 这里用占位，也可以改为实际检测逻辑
    final localIp = '127.0.0.1';

    // 使用基于设备信息生成或持久化的 HMAC 密钥
    final elfSha = await _getOrCreateHmacKey();

    final headers = {
      'Device-Id': deviceId,
      'Client-Id': clientId,
      'Content-Type': 'application/json',
      'User-Agent': '$boardType/callcall-$appVersion',
      'Accept-Language': 'zh-CN',
    };
    // 仅在 v2 协议时添加
    if (appVersion.startsWith('2')) {
      headers['Activation-Version'] = appVersion;
    }

    final body = {
      'application': {'version': appVersion, 'elf_sha256': elfSha},
      'board': {
        'type': boardType,
        'name': boardName,
        'ip': localIp,
        'mac': deviceId,
        if (serial.isNotEmpty) 'serial_number': serial,
      },
    };

    final resp = await _dio.post(
      url,
      data: body,
      options: Options(headers: headers),
    );

    // 调试打印：保存请求与响应到 SharedPreferences 以便 UI 查看
    try {
      debugPrint('OTA req url: $url');
      debugPrint('OTA req headers: ${jsonEncode(headers)}');
      debugPrint('OTA req body: ${jsonEncode(body)}');
      debugPrint('OTA resp status: ${resp.statusCode}');
      debugPrint('OTA resp data: ${jsonEncode(resp.data)}');
      final prefs = await _prefs;
      await prefs.setString(
        'last_ota_request',
        jsonEncode({'headers': headers, 'body': body}),
      );
      await prefs.setString('last_ota_response', jsonEncode(resp.data));
    } catch (_) {}

    final data = resp.data;

    // 服务端无 activation（表示已激活）
    if (data is Map && data['activation'] == null) {
      // Case 2: 本地已激活 + 服务端无激活 -> 设备已激活
      if (localActivated) {
        return XiaozhiActivationResult.activated();
      }
      // Case 3: 本地未激活 + 服务端无激活 -> 自动修复本地状态
      await setLocalActivated(true);
      return XiaozhiActivationResult.activated();
    }

    // 服务端返回 activation（需要激活）
    try {
      final activation = (data is Map) ? data['activation'] : null;
      final String code = activation != null && activation['code'] != null
          ? activation['code'].toString()
          : '------';
      final String message = activation != null && activation['message'] != null
          ? activation['message'].toString()
          : '';

      // message 第一行为域名（portal）或可能携带 challenge
      final String domain = message.isNotEmpty
          ? (message.split('\n').first).trim()
          : '';
      final bool useHttps = url.toLowerCase().startsWith('https');
      final String portal = domain.isNotEmpty
          ? '${useHttps ? 'https' : 'http'}://$domain'
          : '';

      // 从 activation 中尝试读取 challenge
      String? challenge;
      if (activation != null && activation['challenge'] != null) {
        challenge = activation['challenge'].toString();
      }

      // 返回包含 activation 数据与 challenge（若有），不在此自动激活
      return XiaozhiActivationResult.notActivated(
        code: code,
        portalUrl: portal.isEmpty ? null : portal,
        challenge: challenge,
        raw: activation is Map ? Map<String, dynamic>.from(activation) : null,
      );
    } catch (e) {
      // 兜底：返回未激活
      await setLocalActivated(false);
      return XiaozhiActivationResult.notActivated(
        code: '------',
        portalUrl: null,
      );
    }
  }

  /// 使用服务器下发的 challenge 发起激活请求，按协议向 {otaUrl}/activate POST
  /// headers: Activation-Version: 2, Device-Id
  /// body: { "Payload": { "serial_number": ..., "challenge": ..., "hmac": ... } }
  /// 重试逻辑：每隔 [interval] 重试一次，最多 [maxAttempts] 次。返回 true 表示成功。
  Future<bool> activateWithChallenge(
    String challenge, {
    int maxAttempts = 60,
    Duration interval = const Duration(seconds: 5),
    void Function(int attempt, Map? response)? onAttempt,
  }) async {
    final otaBase = await getOtaUrl();
    final activateUrl = otaBase.endsWith('/')
        ? '${otaBase}activate'
        : '$otaBase/activate';
    final deviceId = await getDeviceId();
    final clientId = await getClientId();
    String serial = await getSerialNumber();
    if (serial.isEmpty) {
      serial = await _generateSerialNumber();
      try {
        await saveConfig(serialNumber: serial);
      } catch (_) {}
    }

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final hmac = await generateHmacSignature(challenge);
        final payload = {
          'Payload': {
            'algorithm': 'hmac-sha256',
            'serial_number': serial,
            'challenge': challenge,
            'hmac': hmac,
          },
        };
        final headers = {
          'Activation-Version': '2',
          'Device-Id': deviceId,
          'Client-Id': clientId,
          'Content-Type': 'application/json',
          'User-Agent': 'bread-compact-wifi/callcall-2.0.0',
        };

        debugPrint(
          'OTA activate attempt ${attempt + 1}/$maxAttempts -> $activateUrl',
        );
        debugPrint('Headers: ${jsonEncode(headers)}');
        debugPrint('Payload: ${jsonEncode(payload)}');

        final resp = await _dio.post(
          activateUrl,
          data: payload,
          options: Options(headers: headers),
        );

        // 保存最后一次激活响应以便调试
        try {
          final prefs = await _prefs;
          await prefs.setString(
            'last_activation_request',
            jsonEncode({'headers': headers, 'body': payload}),
          );
          await prefs.setString(
            'last_activation_response',
            jsonEncode(resp.data),
          );
        } catch (_) {}

        Map? respMap;
        if (resp.data is Map) {
          respMap = Map<String, dynamic>.from(resp.data as Map);
          // 标准成功字段
          if (respMap['success'] == true) {
            debugPrint('OTA activate succeeded');
            if (onAttempt != null) onAttempt(attempt + 1, respMap);
            return true;
          }

          // 处理后端返回的结构化激活信息，例如 {message: "Device activated", device_id: 868822}
          try {
            final msg = respMap['message']?.toString() ?? '';
            final hasDeviceId = respMap['device_id'] != null;
            if (msg.toLowerCase().contains('device activated') || hasDeviceId) {
              debugPrint(
                'OTA activate: detected device activated via message/device_id',
              );
              if (onAttempt != null) onAttempt(attempt + 1, respMap);
              // 标记本地已激活
              await setLocalActivated(true);
              return true;
            }
          } catch (_) {}
        }
        if (onAttempt != null) onAttempt(attempt + 1, respMap);
      } catch (e) {
        debugPrint('OTA activate attempt failed: $e');
        if (onAttempt != null) onAttempt(attempt + 1, null);
      }

      if (attempt < maxAttempts - 1) {
        await Future.delayed(interval);
      }
    }

    debugPrint('OTA activate exhausted attempts ($maxAttempts)');
    return false;
  }

  // 建立 WebSocket 连接并发送 hello
  Future<void> connect({bool realtime = false}) async {
    debugPrint('🔌 [连接] 开始连接流程 (${realtime ? "实时" : "回合"}模式)');

    // 若已有连接，先断开
    if (_ws != null) {
      debugPrint('🔌 [连接] 检测到已有连接，先断开...');
      await disconnect();
    }

    final wsUrl = await getWsUrl();
    final deviceId = await getDeviceId();
    final clientId = await getClientId();
    final token = await getAccessToken();

    // 调试日志：显示读取到的配置
    debugPrint('📡 [配置] 准备建立连接 (${realtime ? "实时" : "回合"}模式)');
    debugPrint('   WsUrl: $wsUrl');
    debugPrint('   DeviceId: $deviceId');
    debugPrint('   ClientId: $clientId');
    debugPrint('   Token长度: ${token.length}');

    // 验证必要参数
    if (wsUrl.isEmpty) {
      debugPrint('❌ [配置] 错误: WebSocket URL 为空');
      throw Exception('WebSocket URL 未配置');
    }
    if (deviceId.isEmpty) {
      debugPrint('❌ [配置] 错误: DeviceId 为空');
      throw Exception('DeviceId 未配置');
    }
    if (clientId.isEmpty) {
      debugPrint('❌ [配置] 错误: ClientId 为空');
      throw Exception('ClientId 未配置');
    }

    // access token 可选：记录提示但不阻止连接
    if (token.isEmpty) {
      debugPrint('⚠️ [认证] 警告: access token 为空，将不带认证信息连接');
    } else {
      // 掩码显示 token
      final masked = token.length > 10
          ? '${token.substring(0, 6)}****${token.substring(token.length - 4)}'
          : '****';
      debugPrint('   Token: $masked');
    }

    var uri = Uri.parse(wsUrl);
    // 设置内部 realtime 标志，供后续逻辑（例如 TTS 结束后重启麦克风）使用
    _isInRealtimeMode = realtime;
    _resetPendingAiOutput();

    // 若需要 realtime 模式，改用服务端约定的绝对路径 /realtime_chat 并确保必要参数
    Map<String, String> baseQuery = Map<String, String>.from(
      uri.queryParameters,
    );
    if (token.isNotEmpty) {
      baseQuery['access_token'] = token;
    }

    if (realtime) {
      // 保留原始 wsUrl 中的 path（例如 /xiaozhi/v1/），然后拼接 realtime_chat
      final basePath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
      final newPath = '${basePath}realtime_chat';
      uri = uri.replace(path: newPath);
      final qm = Map<String, String>.from(baseQuery);
      qm.putIfAbsent('sample_rate', () => '16000');
      uri = uri.replace(queryParameters: qm);
      debugPrint('🔌 [路径] 实时模式路径: $newPath');
    }

    if (!realtime) {
      uri = uri.replace(queryParameters: baseQuery);
    }

    debugPrint('🔌 [URI] 最终连接地址: $uri');

    // 启用自动重连
    _shouldReconnect = true;
    _reconnectAttempts = 0;

    try {
      // 通过平台适配的连接器设置 Header（IO）或 Query（Web）
      debugPrint('🔌 [WebSocket] 正在建立WebSocket连接...');
      _protocol = XiaozhiProtocol.connect(
        uri: uri,
        accessToken: token,
        protocolVersion: '1',
        deviceId: deviceId,
        clientId: clientId,
      );
      _ws = _protocol!.channel;
      debugPrint('✅ [WebSocket] WebSocket连接已建立');

      // 标记为已连接（WebSocket 无 session_id）
      _connectionController.add(true);
    } catch (e, stackTrace) {
      debugPrint('❌ [WebSocket] 建立WebSocket连接失败: $e');
      debugPrint('📍 [堆栈] $stackTrace');
      _connectionController.add(false);
      throw Exception('WebSocket连接失败: $e');
    }

    // 监听消息 -> 使用分发器处理 incoming messages
    try {
      final dispatcher = XiaozhiDispatcher(_protocol!);

      dispatcher.onHello = (msg) {
        _helloTimeoutTimer?.cancel();
        _helloTimeoutTimer = null;
        if (msg['session_id'] != null) {
          _sessionId = msg['session_id'].toString();
        }
        _connectionController.add(true);
        debugPrint('✅ [Hello] WebSocket 连接成功, session: $_sessionId');

        // 根据当前模式发送会话信息
        try {
          final info = _buildSessionInfo();
          if (info != null) {
            _protocol?.sendSessionInfo(info);
            debugPrint('📤 [SessionInfo] 已发送 session_info');
          }
        } catch (e) {
          debugPrint('❌ [SessionInfo] 发送 session_info 失败: $e');
        }

        // 启动心跳
        _startHeartbeat();
        debugPrint('💓 [心跳] 心跳已启动');

        if (_isInRealtimeMode) {
          Future.microtask(() async {
            try {
              debugPrint('🎤 [实时模式] hello 已确认，开始 listenStart(realtime)');
              await listenStart(mode: 'realtime');
              if (!_keepListening) {
                setKeepListening(true);
              }

              // 关键修复：延迟启动麦克风，确保服务器先处理 listen.start 消息
              debugPrint('⏱️ [实时模式] 等待500ms让服务器处理 listen.start...');
              await Future.delayed(const Duration(milliseconds: 500));

              final micStarted = await startMic();
              debugPrint('🎤 [麦克风] hello 后麦克风启动: ${micStarted ? "成功" : "失败"}');
            } catch (e) {
              debugPrint('❌ [实时模式] hello 回包后启动监听失败: $e');
            }
          });
        }
      };

      // 只使用统一的TTS/LLM处理器，避免重复处理
      dispatcher.onTts = (msg) => _handleTtsMessage(msg);
      dispatcher.onLlm = (msg) => _handleLlmMessage(msg);

      debugPrint('✅ 消息分发器已配置，使用统一处理器');

      // 预热音频系统，减少第一段TTS音频卡顿
      Future.microtask(() async {
        try {
          await AudioService.instance.initialize();
          // 预热 PCM 流播放器，降低首包启动噪声/卡顿
          await PCMStreamService.instance.warmup();
          debugPrint('🌡️ 音频系统预热完成');
        } catch (e) {
          debugPrint('⚠️ 音频系统预热失败: $e');
        }
      });

      // LLM消息已由上面的dispatcher.onLlm统一处理，不需要重复注册

      dispatcher.onStt = (text) {
        _messageController.add(
          XiaozhiMessage(fromUser: true, text: text, ts: DateTime.now()),
        );
      };

      dispatcher.onBinaryAudio = (bytes) {
        try {
          XiaozhiAudioHandler.instance.processBinary(bytes);
        } catch (e, stack) {
          debugPrint('❌ 处理二进制音频异常: $e');
          debugPrint('📍 堆栈: $stack');
        }
      };

      dispatcher.onJson = (msg) async {
        try {
          final handled = await XiaozhiAudioHandler.instance.processJson(msg);
          if (!handled) {
            final fallback = _extractTextFromPayload(msg);
            if (fallback != null && fallback.isNotEmpty) {
              _emitAiMessage(fallback);
            }
          }
        } catch (e, stack) {
          debugPrint('❌ 处理JSON消息异常: $e');
          debugPrint('📍 堆栈: $stack');
          debugPrint('📦 消息内容: ${jsonEncode(msg)}');
        }
      };

      dispatcher.onError = (msg) {
        final errorText = msg['message'] ?? msg['error'];
        if (errorText is String && errorText.isNotEmpty) {
          debugPrint('❌ 服务器错误: $errorText');
          debugPrint('📦 完整错误消息: ${jsonEncode(msg)}');
          // 不要把服务器错误当作AI消息显示
        }
      };

      // keep reference to wsSub for later cancellation (if needed)
      _wsSub = _protocol!.stream.listen(
        (data) {
          // 更新最后消息时间
          _lastMessageTime = DateTime.now();
        },
        onError: (e) {
          debugPrint('❌ WebSocket stream error: $e');
          _connectionController.add(false);
          // 尝试重连
          _scheduleReconnect();
        },
        onDone: () async {
          debugPrint('⚠️ WebSocket stream onDone called');
          _connectionController.add(false);
          // 如果是在实时模式，尝试重连
          if (_shouldReconnect && _isInRealtimeMode) {
            debugPrint('🔄 检测到连接断开，将尝试重连...');
            _scheduleReconnect();
          } else {
            await disconnect();
          }
        },
      );
    } catch (e) {
      debugPrint('Failed to listen to WebSocket stream: $e');
      await disconnect();
      return;
    }

    // Debug: 打印连接相关信息（掩码 token）
    try {
      final maskedToken = token.isNotEmpty
          ? token.replaceAll(RegExp(r'(.{6}).+(.{4})'), r"$1****$2")
          : '<empty>';
      debugPrint(
        'Connecting WS -> uri: $uri, deviceId: $deviceId, clientId: $clientId, token: $maskedToken',
      );
    } catch (_) {}

    // 发送 hello（按协议包含 version 与音频参数）
    final hello = {
      'type': 'hello',
      'version': 1,
      'transport': 'websocket',
      'features': {'mcp': true},
      'audio_params': {
        'format': _preferredAudioFormat,
        'sample_rate': _sampleRate,
        'channels': _channels,
        'frame_duration': _frameDuration,
      },
    };
    try {
      debugPrint('👋 发送 hello 消息: ${jsonEncode(hello)}');
      _protocol?.sendText(jsonEncode(hello));
    } catch (e) {
      debugPrint('发送 hello 消息失败: $e');
    }

    // 启动心跳保活机制
    _startHeartbeat();

    // 设置重连标志
    _shouldReconnect = realtime; // 实时模式启用自动重连
    _reconnectAttempts = 0;
    _lastMessageTime = DateTime.now();

    // 初始化简单VAD用于打断（仅实时模式）
    if (realtime) {
      _initVAD();
    } else {
      _vad = null;
    }
  }

  String? _mapEmotionToEmoji(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    // 常见情绪到 emoji 的简单映射
    if (s.contains('joy') || s.contains('happy') || s.contains('smile')) {
      return '😄';
    }
    if (s.contains('laugh') || s.contains('haha')) {
      return '😆';
    }
    if (s.contains('love') || s.contains('affection')) {
      return '🥰';
    }
    if (s.contains('excite') || s.contains('delight')) {
      return '🤩';
    }
    if (s.contains('calm') || s.contains('relax')) {
      return '😌';
    }
    if (s.contains('neutral')) {
      return '😐';
    }
    if (s.contains('think') || s.contains('ponder')) {
      return '🤔';
    }
    if (s.contains('confus')) {
      return '😕';
    }
    if (s.contains('sad') || s.contains('down')) {
      return '😢';
    }
    if (s.contains('bored') || s.contains('tired')) {
      return '😪';
    }
    if (s.contains('sleep')) {
      return '😴';
    }
    if (s.contains('angry') || s.contains('mad')) {
      return '😠';
    }
    if (s.contains('fear') || s.contains('scared')) {
      return '😨';
    }
    if (s.contains('disgust')) {
      return '🤢';
    }
    if (s.contains('surpris') || s.contains('wow')) {
      return '😮';
    }
    if (s.contains('wink')) {
      return '😉';
    }
    if (s.contains('embarrass') || s.contains('shy')) {
      return '😳';
    }
    return '🙂';
  }

  void _resetPendingAiOutput() {
    _currentTtsText = '';
  }

  void _finalizePendingTtsSentence() {
    // 简化结束处理
    if (_currentTtsText.isNotEmpty) {
      _emitAiMessage(_currentTtsText, isComplete: true);
    }
    _currentTtsText = '';
  }

  void _scheduleRealtimeMicResume() {
    if (!_isInRealtimeMode) {
      debugPrint('⚠️ 不在实时模式，跳过麦克风恢复');
      return;
    }
    if (!_keepListening) {
      debugPrint('⚠️ _keepListening=false，跳过麦克风恢复');
      return;
    }

    debugPrint('🔍 调度麦克风恢复...');
    // 立即尝试重启，不等待延迟
    Future.microtask(() async {
      if (!_isInRealtimeMode || !_keepListening || !isConnected) {
        return;
      }

      // 等待播放结束，避免截断AI最后一句
      const checkInterval = Duration(milliseconds: 120);
      var waited = Duration.zero;
      const maxWait = Duration(seconds: 3);

      while (AudioService.instance.isPlaying &&
          waited < maxWait &&
          _isInRealtimeMode &&
          _keepListening &&
          isConnected) {
        await Future.delayed(checkInterval);
        waited += checkInterval;
      }

      if (AudioService.instance.isPlaying) {
        debugPrint('⚠️ 播放仍未结束，暂不恢复实时监听');
        return;
      }

      debugPrint('🔊 音频播放已结束，开始恢复麦克风');

      try {
        // 确保监听状态正确
        debugPrint('📡 发送 listenStart(realtime)');
        await listenStart(mode: 'realtime');

        debugPrint('🎯 当前设备状态: ${_deviceState.name}');

        if (_deviceState != DeviceState.listening) {
          // 重启麦克风
          debugPrint('🎤 开始重启麦克风...');
          final micStarted = await startMic();
          if (micStarted) {
            debugPrint('✅ 实时模式麦克风重启成功');
          } else {
            debugPrint('⚠️ 实时模式麦克风重启失败，100ms后重试');
            await Future.delayed(const Duration(milliseconds: 100));
            if (_isInRealtimeMode && _keepListening && isConnected) {
              final retry = await startMic();
              if (retry) {
                debugPrint('✅ 实时模式麦克风重启成功（重试）');
              } else {
                debugPrint('❌ 实时模式麦克风重启失败（重试）');
              }
            }
          }
        } else {
          debugPrint('ℹ️ 实时模式：麦克风保持开启，无需重启');
        }
      } catch (e) {
        debugPrint('❌ 实时模式麦克风重启异常: $e');
      }
    });
  }

  /// 控制当AI说话结束后是否保持监听（用于 realtime + AEC 场景）
  void setKeepListening(bool keep) {
    _keepListening = keep;
  }

  /// 控制是否启用打断（默认启用）
  void setBargeInEnabled(bool enabled) {
    _bargeInEnabled = enabled;
  }

  Map<String, dynamic>? _buildSessionInfo() {
    try {
      final info = <String, dynamic>{
        'mode': _isInRealtimeMode ? 'realtime' : 'manual',
        'client': {'platform': 'flutter', 'version': '2.0.0'},
      };
      return info;
    } catch (e) {
      debugPrint('构建 session_info 失败: $e');
      return null;
    }
  }

  void _emitAiMessage(String text, {String? emoji, bool isComplete = false}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final emojiValue = (emoji != null && emoji.isNotEmpty) ? emoji : null;
    final now = DateTime.now();
    final activeId = _currentAiMessageId;

    // 简化去重检查
    if (isComplete) {
      final messageHash = '${trimmed}_${emojiValue ?? ''}';
      if (_sentMessageHashes.contains(messageHash)) {
        return; // 静默跳过重复消息
      }
      _sentMessageHashes.add(messageHash);
      // 限制集合大小
      if (_sentMessageHashes.length > 50) {
        _sentMessageHashes.clear();
      }
    }

    // 流式更新模式：如果有活跃ID，更新现有消息
    if (activeId != null) {
      _messageController.add(
        XiaozhiMessage(
          id: activeId,
          fromUser: false,
          text: trimmed,
          emoji: emojiValue,
          ts: now,
          isComplete: isComplete,
        ),
      );

      if (isComplete) {
        _currentAiMessageId = null;
        debugPrint('✅ 更新完成AI消息: $trimmed');
      } else {
        debugPrint('🔄 流式更新AI消息: $trimmed');
      }
      return;
    }

    // 开始新的流式消息
    if (!isComplete) {
      final streamingMessage = XiaozhiMessage(
        fromUser: false,
        text: trimmed,
        emoji: emojiValue,
        ts: now,
        isComplete: false,
      );
      _currentAiMessageId = streamingMessage.id;
      _messageController.add(streamingMessage);
      debugPrint('🎆 开始新的流式AI消息: $trimmed');
      return;
    }

    // 发送完整消息
    final completeMessage = XiaozhiMessage(
      fromUser: false,
      text: trimmed,
      emoji: emojiValue,
      ts: now,
      isComplete: true,
    );
    _messageController.add(completeMessage);
    debugPrint('🤖 发送完整AI消息: $trimmed');
  }

  /// 简化的 TTS 消息处理
  ///
  /// 核心逻辑：
  /// - start: 切换到 speaking 状态，停止麦克风（非实时模式）
  /// - delta/chunk: 累积文本用于 UI 显示
  /// - end: 切换回 idle/listening，恢复麦克风
  Future<void> _handleTtsMessage(Map msg) async {
    final state = msg['state'] as String? ?? '';
    final textRaw = msg['text'] as String? ?? '';
    final text = textRaw.trim();

    final normalizedState = state.toLowerCase();

    // TTS 开始
    if (normalizedState == 'start') {
      _deviceState = DeviceState.speaking;

      // 非实时模式：停止麦克风
      // 实时模式且开启保持监听：保持麦克风（依赖 AEC）
      final shouldKeepMic = _isInRealtimeMode && _keepListening;
      if (!shouldKeepMic) {
        await _stopMicInternal();
      }

      // 设置打断保护窗口 - 实时模式下大幅缩短以允许更自然的对话
      final protectionMs = _isInRealtimeMode ? 100 : 600; // 实时模式只保护100ms
      _bargeInBlockUntil = DateTime.now().add(
        Duration(milliseconds: protectionMs),
      );
      _currentTtsText = '';
      _currentAiMessageId = null;
      return;
    }

    // TTS 文本更新（用于 UI 显示）
    if (text.isNotEmpty) {
      // 简化的文本累积逻辑
      if (_currentTtsText.isEmpty) {
        _currentTtsText = text;
      } else if (text.length > _currentTtsText.length &&
          text.startsWith(_currentTtsText)) {
        // 新文本是扩展
        _currentTtsText = text;
      } else if (!_currentTtsText.contains(text)) {
        // 追加新内容
        _currentTtsText = '$_currentTtsText $text'.trim();
      }

      // 发送 UI 更新
      if (_currentTtsText.isNotEmpty) {
        _emitAiMessage(_currentTtsText, isComplete: false);
      }
    }

    // TTS 结束
    if (normalizedState == 'end' ||
        normalizedState == 'finished' ||
        normalizedState == 'finish' ||
        normalizedState == 'stop' ||
        normalizedState == 'complete') {
      debugPrint('🎭 TTS结束，状态: $normalizedState');

      // 发送完整文本
      if (_currentTtsText.isNotEmpty) {
        _emitAiMessage(_currentTtsText, isComplete: true);
      }
      _currentTtsText = '';

      // 刷新音频缓冲
      Future.microtask(() async {
        try {
          await AudioService.instance.flushStreaming();
        } catch (_) {}
      });

      // 切换回 idle 状态
      final oldState = _deviceState;
      _deviceState = DeviceState.idle;
      debugPrint('🔄 设备状态: $oldState -> ${_deviceState.name}');

      // 实时模式：恢复麦克风
      debugPrint(
        '🎤 尝试恢复麦克风 (_isInRealtimeMode: $_isInRealtimeMode, _keepListening: $_keepListening)',
      );
      _scheduleRealtimeMicResume();
    }
  }

  void _handleLlmMessage(Map msg) {
    final text = msg['text'] as String? ?? '';
    final state = msg['state'] as String? ?? '';
    final emojiFromServer = msg['emoji'] as String?;
    final emotion = msg['emotion'] as String?;

    // 只在非 speaking 状态下处理 LLM 消息
    if (text.isNotEmpty && _deviceState != DeviceState.speaking) {
      String? emoji;
      if (emojiFromServer != null && emojiFromServer.isNotEmpty) {
        emoji = emojiFromServer;
      } else if (emotion != null) {
        emoji = _mapEmotionToEmoji(emotion);
      }

      final isComplete =
          state == 'end' || state == 'finished' || state == 'complete';
      _emitAiMessage(text, emoji: emoji, isComplete: isComplete);
    }
  }

  // --- VAD / Barge-in ---
  void _initVAD() {
    _vad ??= SimpleVAD(
      // 提高阈值，减少误触发
      energyThreshold: 1600,
      triggerFrames: 8,
      cooldown: const Duration(milliseconds: 1800),
    );
    // Set callback
    _vad!.onVoiceStart = () {
      if (!_bargeInEnabled || !_isInRealtimeMode) return;
      // 在TTS开始后的短暂时间内禁止打断，避免“第一口音”被秒切
      final now = DateTime.now();
      if (_bargeInBlockUntil != null && now.isBefore(_bargeInBlockUntil!)) {
        return;
      }
      // 简化判断：只看设备状态
      if (_deviceState != DeviceState.speaking) return;
      _handleBargeIn();
    };
  }

  void _feedVad(
    Uint8List pcm, {
    required int sampleRate,
    required int channels,
  }) {
    if (!_bargeInEnabled || !_isInRealtimeMode) return;
    final v = _vad;
    if (v == null) return;
    try {
      v.addPcm16(pcm, sampleRate: sampleRate, channels: channels);
    } catch (_) {}
  }

  Future<void> _handleBargeIn() async {
    debugPrint('🛑 检测到用户说话，执行打断（barge-in）');
    try {
      // Notify server to abort current speaking
      _protocol?.sendAbortSpeaking(reason: 'user_interruption');

      // Immediately stop and clear local playback queue
      await AudioService.instance.stopStreamingAndClear();

      // 切换到监听状态
      _deviceState = DeviceState.listening;

      // Ensure listening state
      _keepListening = true;
      if (_deviceState != DeviceState.listening) {
        await startMic();
      }
      try {
        _protocol?.sendStartListening(mode: 'realtime', sessionId: _sessionId);
      } catch (_) {}
    } catch (e) {
      debugPrint('打断流程异常: $e');
    }
  }

  /// 启动心跳保活机制
  void _startHeartbeat() {
    _stopHeartbeat();

    // 每20秒发送一次ping（更频繁的心跳）
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (_protocol == null || _ws == null) {
        timer.cancel();
        return;
      }

      try {
        // 发送ping消息
        final ping = {
          'type': 'ping',
          'timestamp': DateTime.now().toIso8601String(),
        };
        _protocol!.sendText(jsonEncode(ping));
        debugPrint('💓 发送心跳 ping');

        // 检查是否超时45秒没有收到任何消息（缩短超时时间）
        final now = DateTime.now();
        if (_lastMessageTime != null) {
          final elapsed = now.difference(_lastMessageTime!);
          if (elapsed.inSeconds > 45) {
            debugPrint('⚠️ 超时45秒未收到消息，连接可能已断开');
            // 触发重连
            _scheduleReconnect();
            timer.cancel();
          }
        }
      } catch (e) {
        debugPrint('❌ 发送ping失败: $e');
        // ping失败也触发重连检查
        _scheduleReconnect();
        timer.cancel();
      }
    });

    debugPrint('❤️ 心跳保活已启动 (20秒间隔)');
  }

  /// 停止心跳
  void _stopHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// 调度重连
  void _scheduleReconnect() {
    // 防止重复调度
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      debugPrint('🔄 重连定时器已存在，跳过重复调度');
      return;
    }

    // 如果不应该重连，直接返回
    if (!_shouldReconnect) {
      debugPrint('🚫 重连已禁用，跳过重连');
      return;
    }

    _reconnectAttempts++;

    // 优化的指数退避：1秒, 3秒, 5秒, 10秒, 15秒, 最多20秒
    final delays = [1, 3, 5, 10, 15, 20];
    final delayIndex = min(_reconnectAttempts - 1, delays.length - 1);
    final delay = Duration(seconds: delays[delayIndex]);

    debugPrint('🔄 将在 ${delay.inSeconds} 秒后尝试第 $_reconnectAttempts 次重连...');

    _reconnectTimer = Timer(delay, () async {
      if (!_shouldReconnect) {
        debugPrint('🚫 重连已取消');
        return;
      }

      debugPrint('🔄 开始第 $_reconnectAttempts 次重连尝试...');

      try {
        // 先清理旧连接
        await _cleanupConnection();

        // 短暂延迟确保清理完成
        await Future.delayed(const Duration(milliseconds: 500));

        // 重新连接
        await connect(realtime: _isInRealtimeMode);

        // 验证连接是否真正建立
        await Future.delayed(const Duration(milliseconds: 1000));
        if (_ws != null && _sessionId != null) {
          debugPrint('✅ 重连成功！Session ID: $_sessionId');
          _reconnectAttempts = 0;
          _connectionController.add(true);
        } else {
          throw Exception('连接验证失败');
        }
      } catch (e) {
        debugPrint('❌ 第 $_reconnectAttempts 次重连失败: $e');

        // 如果超过6次尝试，放弃重连
        if (_reconnectAttempts >= 6) {
          debugPrint('❌ 已达到最大重连次数(6)，放弃重连');
          _shouldReconnect = false;
          _reconnectAttempts = 0;
          await disconnect();
          _connectionController.add(false);
        } else {
          // 继续尝试
          _scheduleReconnect();
        }
      }
    });
  }

  /// 清理连接资源
  Future<void> _cleanupConnection() async {
    try {
      await _wsSub?.cancel();
      _wsSub = null;
    } catch (_) {}

    try {
      await _ws?.sink.close();
      _ws = null;
    } catch (_) {}

    _protocol = null;
    _sessionId = null;
    debugPrint('🧹 连接资源清理完成');
  }

  Future<void> disconnect({bool restoreAudioSession = false}) async {
    _isInRealtimeMode = false;
    _shouldReconnect = false; // 禁用重连
    _reconnectAttempts = 0;

    // 停止心跳和重连定时器
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _finalizePendingTtsSentence();
    _resetPendingAiOutput();
    _helloTimeoutTimer?.cancel();
    _helloTimeoutTimer = null;
    try {
      await _wsSub?.cancel();
    } catch (_) {}
    _wsSub = null;
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    _sessionId = null;
    _connectionController.add(false);
    await _stopMicInternal();
    _vad = null;
    if (restoreAudioSession) {
      try {
        await AudioService.instance.exitVoiceChatMode();
      } catch (e) {
        debugPrint('⚠️ 断开连接后恢复播放模式失败: $e');
      }
    }
    debugPrint('WebSocket 已断开连接');
  }

  void _sendAudioFrame(Uint8List bytes) {
    if (_protocol == null) {
      // 连接未建立，静默跳过
      if (_micChunkCount == 0) {
        debugPrint('⚠️ _sendAudioFrame: _protocol 为 null');
      }
      return;
    }
    // 只在监听状态发送音频
    if (_deviceState != DeviceState.listening) {
      if (_micChunkCount == 0) {
        debugPrint('⚠️ _sendAudioFrame: 不在监听状态 (${_deviceState.name})');
      }
      return;
    }
    try {
      if (_useJsonAudioFrames) {
        final frame = <String, dynamic>{
          'type': 'audio',
          'data': base64Encode(bytes),
          'timestamp': DateTime.now().toIso8601String(),
        };
        _protocol!.sendText(jsonEncode(frame));
      } else {
        _protocol!.sendAudio(bytes);
      }
      _micChunkCount++;
      // 限制日志频率（每100帧输出一次）
      if (_micChunkCount % 100 == 0) {
        debugPrint('🎤 已发送 $_micChunkCount 帧音频数据');
      }
    } catch (e) {
      debugPrint('🔴 发送音频帧失败: $e');
    }
  }

  // 发送纯文本到后端（改进版：自动保证连接）
  Future<void> sendText(String text) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    // 检查连接状态，如果未连接则自动建立连接
    if (_ws == null || _protocol == null) {
      debugPrint('🔄 sendText: 检测到未连接，尝试建立连接...');

      try {
        // 先本地回显用户消息
        _messageController.add(
          XiaozhiMessage(fromUser: true, text: trimmedText, ts: DateTime.now()),
        );

        // 建立连接（回合模式）
        await connect(realtime: false);

        // 等待连接建立（最多3秒）
        var waited = 0;
        while ((_ws == null || _sessionId == null) && waited < 30) {
          await Future.delayed(const Duration(milliseconds: 100));
          waited++;
        }

        if (_ws == null || _protocol == null) {
          debugPrint('❌ sendText: 连接建立失败');
          _messageController.add(
            XiaozhiMessage(
              fromUser: false,
              text: '连接失败，请稍后重试',
              ts: DateTime.now(),
            ),
          );
          return;
        }

        debugPrint('✅ sendText: 连接建立成功，继续发送消息');
      } catch (e) {
        debugPrint('❌ sendText: 连接异常: $e');
        _messageController.add(
          XiaozhiMessage(fromUser: false, text: '连接异常: $e', ts: DateTime.now()),
        );
        return;
      }
    }

    try {
      // 重置消息状态，避免重复
      _currentAiMessageId = null;
      _sentMessageHashes.clear(); // 清空消息哈希，开始新对话
      _currentTtsText = ''; // 清空当前 TTS 文本

      final msg = <String, dynamic>{
        'type': 'text',
        'text': trimmedText,
        'timestamp': DateTime.now().toIso8601String(),
      };
      if (_sessionId != null && _sessionId!.isNotEmpty) {
        msg['session_id'] = _sessionId;
      }

      _protocol?.sendText(jsonEncode(msg));
      debugPrint('📝 发送文本: $trimmedText');

      // 如果之前没有回显（连接未断开的情况），现在回显
      if (_ws != null) {
        _messageController.add(
          XiaozhiMessage(fromUser: true, text: trimmedText, ts: DateTime.now()),
        );
      }
    } catch (e) {
      debugPrint('sendText 出错: $e');
      _messageController.add(
        XiaozhiMessage(fromUser: false, text: '发送文本出错: $e', ts: DateTime.now()),
      );
    }
  }

  Future<void> sendWakeWordDetected(String text) async {
    if (_protocol == null && _ws == null) {
      debugPrint('⚠️ sendWakeWordDetected: 未连接，无法发送文本');
      return;
    }

    final payload = <String, dynamic>{
      'type': 'listen',
      'state': 'detect',
      'text': text,
    };
    if (_sessionId != null && _sessionId!.isNotEmpty) {
      payload['session_id'] = _sessionId;
    }

    try {
      if (_protocol != null) {
        _protocol!.sendText(jsonEncode(payload));
      } else {
        _ws!.sink.add(jsonEncode(payload));
      }
    } catch (e) {
      debugPrint('sendWakeWordDetected 发送失败: $e');
    }
  }

  // ignore: unused_element
  String? _extractTextFromPayload(Map data) {
    for (final key in ['text', 'message', 'transcript', 'content']) {
      final v = data[key];
      if (v is String) return v;
    }
    return null;
  }

  // region: mic streaming (push-to-talk) – stubbed
  void setUseJsonAudioFrames(bool useJson) {
    _useJsonAudioFrames = useJson;
  }

  Future<bool> startMic() async {
    debugPrint(
      '🎤 startMic 被调用 (isConnected: $isConnected, _protocol: ${_protocol != null})',
    );

    if (!isConnected) {
      debugPrint('❌ startMic: 未连接，跳过');
      _deviceState = DeviceState.idle;
      return false;
    }

    try {
      await _micSub?.cancel();
      _micSub = null;

      if (kIsWeb) {
        await _webMic.start();
        _micSub = _webMic.audioStream().listen((bytes) {
          final u8 = Uint8List.fromList(bytes);
          _feedVad(u8, sampleRate: _sampleRate, channels: _channels);
          _sendAudioFrame(u8);
        });
      } else {
        // 直接开始录音，避免再次调用 initialize() 将会话切回播放模式
        await AudioService.instance.startRecording();
        _micSub = AudioService.instance.audioStream
            ?.map(Uint8List.fromList)
            .listen((u8) {
              _feedVad(u8, sampleRate: _sampleRate, channels: _channels);
              _sendAudioFrame(u8);
            });
      }

      _deviceState = DeviceState.listening;
      debugPrint('✅ startMic: 麦克风启动成功');
      return true;
    } catch (e) {
      debugPrint('❌ startMic failed: $e');
      await _stopMicInternal();
      return false;
    }
  }

  Future<void> stopMic() async {
    await _stopMicInternal();
  }

  Future<void> _stopMicInternal() async {
    try {
      await _micSub?.cancel();
    } catch (_) {}
    _micSub = null;

    if (kIsWeb) {
      try {
        await _webMic.stop();
      } catch (e) {
        debugPrint('stopMic (web) failed: $e');
      }
    } else {
      try {
        await AudioService.instance.stopRecording();
      } catch (e) {
        debugPrint('stopMic (native) failed: $e');
      }
    }

    _deviceState = DeviceState.idle;
  }

  Future<void> listenStart({String mode = 'manual'}) async {
    if (_ws == null) return;
    _isInRealtimeMode = (mode == 'realtime' || mode == 'auto');
    _resetPendingAiOutput();

    final msg = <String, dynamic>{
      'type': 'listen',
      'state': 'start',
      'mode': mode,
    };
    if (_sessionId != null && _sessionId!.isNotEmpty) {
      msg['session_id'] = _sessionId!;
    }

    try {
      _protocol?.sendStartListening(mode: mode, sessionId: _sessionId);
      debugPrint('开始监听 (mode: $mode)');
    } catch (e) {
      debugPrint('发送 listen start 失败: $e');
    }
  }

  Future<void> listenStop() async {
    if (_protocol == null) return;

    _isInRealtimeMode = false;
    _finalizePendingTtsSentence();
    _resetPendingAiOutput();

    final msg = <String, dynamic>{'type': 'listen', 'state': 'stop'};
    if (_sessionId != null && _sessionId!.isNotEmpty) {
      msg['session_id'] = _sessionId!;
    }

    try {
      _protocol?.sendStopListening(sessionId: _sessionId);
      debugPrint('停止监听');
    } catch (e) {
      debugPrint('发送 listen stop 失败: $e');
    }
  }

  // endregion
}

class XiaozhiMessage {
  final String id; // 消息唯一标识符
  final bool fromUser;
  final String text;
  final String? emoji;
  final DateTime ts;
  final bool isComplete; // 标记消息是否完成（用于流式更新）

  XiaozhiMessage({
    String? id,
    required this.fromUser,
    required this.text,
    this.emoji,
    required this.ts,
    this.isComplete = true,
  }) : id = id ?? const Uuid().v4();

  /// 创建更新后的消息副本
  XiaozhiMessage copyWith({String? text, String? emoji, bool? isComplete}) {
    return XiaozhiMessage(
      id: id,
      fromUser: fromUser,
      text: text ?? this.text,
      emoji: emoji ?? this.emoji,
      ts: ts,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

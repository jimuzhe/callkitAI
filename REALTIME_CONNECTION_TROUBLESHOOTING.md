# 实时对话连接问题诊断和解决方案

## 问题描述
点击实时对话连接后一直重连，无法成功建立连接。

## 可能的原因

### 1. 网络配置问题
**症状**: 日志中显示不断重连
**原因**: 
- 小智服务器地址配置不正确
- 网络连接不稳定
- 防火墙阻止WebSocket连接

### 2. 认证问题
**症状**: 连接建立但立即断开
**原因**:
- access_token 未设置或已过期
- device_id 或 client_id 配置错误

### 3. hello 超时
**症状**: 连接建立但没有收到 hello 消息
**原因**:
- 服务器响应超时
- WebSocket消息格式不匹配
- 服务器端错误

## 诊断步骤

### 步骤1: 检查日志
在应用中打开调试面板，查找以下关键日志：

```
📡 准备建立连接 (实时模式)
   WsUrl: wss://...
   DeviceId: ...
   ClientId: ...
   Token长度: ...
```

**检查要点**:
- ✅ WsUrl 是否正确（应该是 `wss://api.tenclass.net/xiaozhi/v1/`）
- ✅ DeviceId 和 ClientId 是否已生成
- ✅ Token 长度（如果需要认证）

### 步骤2: 查看连接日志
```
Connecting WS -> uri: wss://...
WebSocket 连接成功, session: ...
```

**检查要点**:
- ❌ 如果没有"WebSocket 连接成功"，说明无法建立WebSocket连接
- ❌ 如果没有 session ID，说明没有收到 hello 消息

### 步骤3: 查看错误日志
```
❌ WebSocket stream error: ...
❌ 服务器错误: ...
🔄 将在 X 秒后尝试第 N 次重连...
```

**检查要点**:
- 错误信息内容
- 重连次数（超过6次会放弃）

## 解决方案

### 方案1: 检查网络连接

```dart
// 在应用启动时测试网络
1. 打开设置页面
2. 查看 VoIP Push Token 状态
3. 确认网络连接正常
```

### 方案2: 重置服务配置

添加一个重置按钮清除缓存的配置：

```dart
// 在设置页面添加
await SharedPreferences.getInstance().then((prefs) {
  prefs.remove('xiaozhi_device_id');
  prefs.remove('xiaozhi_client_id');
  prefs.remove('xiaozhi_access_token');
});
```

### 方案3: 手动配置服务器地址

如果默认服务器无法访问，可以配置自己的小智服务器：

```dart
// 在设置中添加服务器地址配置
final prefs = await SharedPreferences.getInstance();
await prefs.setString('xiaozhi_ws_url', 'wss://your-server.com/xiaozhi/v1/');
await prefs.setString('xiaozhi_ota_url', 'https://your-server.com/xiaozhi/ota/');
```

### 方案4: 增加连接超时时间

修改 hello 超时时间：

```dart
// 在 xiaozhi_service.dart 的 connect 方法中
// 当前是 10 秒，可以增加到 20 秒
_helloTimeoutTimer = Timer(const Duration(seconds: 20), () { // 改为20秒
  if (_sessionId == null) {
    debugPrint('❌ hello 超时，断开连接');
    disconnect();
  }
});
```

### 方案5: 禁用自动重连（临时诊断）

如果想暂时禁用重连以更清楚地看到错误：

```dart
// 在 xiaozhi_service.dart 中
Future<void> connect({bool realtime = false}) async {
  // 在方法开头添加：
  _shouldReconnect = false; // 临时禁用重连
  _reconnectAttempts = 0;
  
  // ... 其余代码
}
```

## 调试增强

### 添加更详细的连接日志

让我帮你添加更详细的日志来诊断问题：

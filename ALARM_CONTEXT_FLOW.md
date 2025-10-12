# 闹钟上下文信息发送流程

## 📋 概述

已去掉"闹钟目的"推断功能，现在只发送基础的闹钟信息给小智。

## 🔄 完整流程

### 1. CallKit 接听触发
```
用户接听 CallKit 电话
↓
CallKitService._handleCallAccepted()
↓
CallKitService._startAICallInCallKitSession(alarm)
↓
AIService.startConversation(alarm: alarm)
```

### 2. 构建并发送上下文
```dart
// AIService._sendDirectiveText(Alarm alarm)

// 第一步：构建闹钟上下文
final alarmContext = _buildAlarmContext(alarm);

// 生成的内容格式：
【闹钟上下文信息】
当前时间：2025年10月13日 周一 07:30
闹钟名称：早上起床运动
闹钟类型：每天
---
请根据以上信息，以合适的方式与用户对话，帮助用户完成闹钟设定的任务。

// 第二步：获取人设指示词
final persona = await PersonaStore.instance.getByIdMerged(alarm.aiPersonaId);
String directive = persona.systemPrompt + persona.openingLine;

// 第三步：合并上下文和指示词
final fullDirective = '$alarmContext\n\n$directive';

// 第四步：发送给小智
await XiaozhiService.instance.sendText(fullDirective);
```

### 3. XiaozhiService 发送机制

**位置**: `lib/services/xiaozhi_service.dart` → `sendText(String text)` 方法

```dart
Future<void> sendText(String text) async {
  // 1. 检查连接状态
  if (_ws == null || _protocol == null) {
    // 自动建立 WebSocket 连接（回合模式）
    await connect(realtime: false);
  }

  // 2. 构建消息 JSON
  final msg = {
    'type': 'text',
    'text': text,  // 这里包含完整的上下文+指示词
    'timestamp': DateTime.now().toIso8601String(),
    'session_id': _sessionId,
  };

  // 3. 通过 WebSocket 发送 JSON 文本消息
  _protocol?.sendText(jsonEncode(msg));
  
  // 4. 本地回显消息
  _messageController.add(
    XiaozhiMessage(fromUser: true, text: text, ts: DateTime.now())
  );
}
```

### 4. 小智 WebSocket 协议

**WebSocket URL**: `wss://api.tenclass.net/xiaozhi/v1/realtime_chat`

**发送的消息格式**:
```json
{
  "type": "text",
  "text": "【闹钟上下文信息】\n当前时间：2025年10月13日 周一 07:30\n闹钟名称：早上起床运动\n闹钟类型：每天\n---\n请根据以上信息，以合适的方式与用户对话，帮助用户完成闹钟设定的任务。\n\n[人设指示词内容...]",
  "timestamp": "2025-10-13T07:30:00.000Z",
  "session_id": "xxx-xxx-xxx"
}
```

## 📊 数据流图

```
┌─────────────────┐
│   CallKit 接听   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Alarm 对象     │
│  - name         │
│  - hour/minute  │
│  - aiPersonaId  │
│  - repeatDays   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ _buildAlarmContext()
│ 生成上下文文本   │
│  • 当前时间      │
│  • 闹钟名称      │
│  • 闹钟类型      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ PersonaStore    │
│ 获取人设信息     │
│  • systemPrompt │
│  • openingLine  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 合并文本        │
│ context + directive
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ XiaozhiService  │
│ .sendText()     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  WebSocket 发送 │
│  JSON 消息      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   小智 AI 服务  │
│  接收并处理     │
└─────────────────┘
```

## 🎯 发送的内容示例

**场景**: 用户设置了一个"早上起床运动"的闹钟，时间是 7:30，每天重复

**发送给小智的完整文本**:
```
【闹钟上下文信息】
当前时间：2025年10月13日 周一 07:30
闹钟名称：早上起床运动
闹钟类型：每天
---
请根据以上信息，以合适的方式与用户对话，帮助用户完成闹钟设定的任务。

你是一个温柔的AI助手，专门用于帮助用户起床。请用温和但坚定的语气与用户对话。

开场白建议：早上好！新的一天开始了，该起床运动啦~ 准备好了吗？
```

## 🔧 技术细节

### WebSocket 协议层

使用 `XiaozhiProtocol` 类封装 WebSocket 通信：

```dart
class XiaozhiProtocol {
  final WebSocketChannel _channel;
  
  void sendText(String text) {
    _channel.sink.add(text);  // 直接发送文本到 WebSocket
  }
}
```

### 消息类型

小智支持多种消息类型：
- `type: "text"` - 文本消息（用于发送上下文和指示词）
- `type: "audio"` - 音频数据（用于语音对话）
- `type: "ping"` - 心跳消息
- `type: "listen.start"` - 开始监听
- `type: "listen.stop"` - 停止监听

### 连接管理

- **自动重连**: 如果 WebSocket 断开，`sendText()` 会自动重新连接
- **会话保持**: 使用 `session_id` 维持对话上下文
- **超时处理**: 连接等待最多 3 秒，超时返回错误

## 📝 调试日志

发送过程中的关键日志：

```
📋 闹钟上下文: 【闹钟上下文信息】...
📝 已发送闹钟指示词 (包含上下文)
   闹钟: 早上起床运动
   人设: 温柔助手
   时间: 07:30
📝 发送文本: [完整文本内容]
```

## 🎯 小智如何使用这些信息

小智收到消息后会：

1. **解析上下文**: 识别当前时间、闹钟名称、闹钟类型
2. **理解任务**: 知道这是一个闹钟唤醒场景
3. **应用人设**: 使用指定的 AI 人设（系统提示词 + 开场白）
4. **生成回应**: 根据上下文和人设，生成合适的对话内容
5. **语音合成**: 将文本转换为语音（使用人设指定的 voiceId）

## 🔄 与旧版本的区别

### 旧版本（已移除）
```dart
// 根据闹钟名称推断目的
final purpose = _inferAlarmPurpose(alarm.name);
if (purpose != null) {
  context.writeln('闹钟目的：$purpose');  // ❌ 已删除
}
```

### 新版本（当前）
```dart
// 只发送基础信息
context.writeln('【闹钟上下文信息】');
context.writeln('当前时间：$date $time');
context.writeln('闹钟名称：${alarm.name}');
context.writeln('闹钟类型：$repeatDesc');
context.writeln('---');
context.writeln('请根据以上信息，以合适的方式与用户对话，帮助用户完成闹钟设定的任务。');
```

**改动原因**: 简化信息，让小智根据闹钟名称自行理解，而不是预先推断目的。

## ✅ 总结

1. **触发点**: CallKit 接听电话时
2. **发送内容**: 闹钟基础信息（时间、名称、类型）+ AI 人设指示词
3. **发送方式**: WebSocket JSON 文本消息
4. **协议**: `type: "text"` 消息类型
5. **服务端点**: `wss://api.tenclass.net/xiaozhi/v1/realtime_chat`
6. **效果**: 小智了解闹钟背景，提供针对性对话

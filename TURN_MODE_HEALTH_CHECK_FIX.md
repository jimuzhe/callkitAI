# 回合对话模式健康检查误报修复

## 问题描述

在回合对话模式下，连接后等待一段时间（超过20秒）再发消息时，会出现以下错误日志：

```
🚨 健康检查：超过20秒无数据，可能已经结束
🌟 音频播放可能已正常结束
```

这些日志每10秒重复出现，虽然不影响功能，但会误导用户以为播放出了问题。

## 根本原因

1. **健康检查逻辑问题**：PCM 流服务的健康检查定时器会检查距离上次喂入数据（`_lastFeedTime`）的时间
2. **回合对话特性**：在回合对话模式下，每次 AI 说完话后会调用 `stopStreaming()`，等用户说话时再次 `startStreaming()`
3. **误报触发条件**：
   - AI 说完话后 `stopStreaming()` → 健康检查停止
   - 用户等待超过20秒（思考、处理其他事情等）
   - 用户再次说话 → `startStreaming()` → 健康检查重启
   - 健康检查发现 `_lastFeedTime`（上次 AI 说话的时间）距离现在超过20秒 → 误报

## 修复方案

### 1. 重置健康检查时间戳 ✅

在 `startStreaming()` 时重置 `_lastFeedTime` 和 `_stuckDetectionCount`：

```dart
try {
  debugPrint('🎵 PCMStreamService: 开始PCM流式播放');

  // 修复：重置健康检查时间戳，避免误报
  _lastFeedTime = DateTime.now();
  _stuckDetectionCount = 0;

  await _player!.startPlayerFromStream(
    codec: Codec.pcm16,
    numChannels: numChannels,
    sampleRate: sampleRate,
    bufferSize: 65536,
    interleaved: true,
  );
  // ...
}
```

**作用**：每次开始新的播放流时，重置时间戳，让健康检查从当前时间开始计算。

### 2. 优化健康检查逻辑 ✅

只在真正播放期间（有缓冲数据或正在喂入）才检查卡死：

```dart
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
  if (_smoothBuffer.length > 32000) { // 2秒音频
    debugPrint('🧹 健康检查：清理过大缓冲区 (${_smoothBuffer.length} bytes)');
    _smoothBuffer.clear();
  }
}
```

**作用**：
- ✅ 播放进行中（有数据在缓冲区）→ 正常检查卡死情况
- ✅ 静默期（无数据，等待用户输入）→ 不打印警告，避免误报

## 修复文件

- `lib/services/pcm_stream_service.dart`
  - `startStreaming()` - 添加时间戳重置
  - `_performHealthCheck()` - 优化检查逻辑

## 测试建议

### 回合对话模式测试

1. **正常对话流程**
   ```
   用户: "你好"
   AI: 回答...
   [等待3秒]
   用户: "今天天气怎么样"
   AI: 回答...
   ```
   ✅ 预期：无误报警告

2. **长时间等待**
   ```
   用户: "你好"
   AI: 回答...
   [等待30秒]
   用户: "还在吗"
   AI: 回答...
   ```
   ✅ 预期：无误报警告，正常对话

3. **真实卡死场景**
   ```
   用户: "你好"
   [AI开始说话，网络突然中断]
   [缓冲区有数据但20秒内没有新数据]
   ```
   ✅ 预期：检测到卡死，自动重启播放流

## 技术细节

### 健康检查机制

- **检查频率**：每10秒检查一次
- **卡死阈值**：20秒无新数据
- **检查条件**：
  - `_isFeeding == true` 或 `_smoothBuffer.isNotEmpty`（播放进行中）
  - 距离上次喂入数据超过20秒

### 状态管理

- `_lastFeedTime`：上次喂入数据的时间戳
- `_isFeeding`：是否正在喂入数据的标记
- `_smoothBuffer`：音频缓冲区
- `_stuckDetectionCount`：卡死检测计数器

## 预期效果

### 修复前 ❌
```
2025-10-13T09:26:36.629929  🚨 健康检查：超过20秒无数据，可能已经结束
2025-10-13T09:26:36.630211  🌟 音频播放可能已正常结束
2025-10-13T09:26:46.629472  🚨 健康检查：超过20秒无数据，可能已经结束
2025-10-13T09:26:46.629758  🌟 音频播放可能已正常结束
[每10秒重复...]
```

### 修复后 ✅
```
[用户等待30秒后说话]
🎵 PCMStreamService: 开始PCM流式播放
✅ PCMStreamService: PCM流式播放已启动
[正常播放AI回答，无误报警告]
```

## 相关问题

- [x] 回合对话模式长时间等待后健康检查误报
- [x] PCM 流播放重启时时间戳未重置
- [x] 健康检查在静默期仍然打印警告

## 后续优化建议

1. **区分播放模式**：可以为实时模式和回合模式使用不同的健康检查策略
2. **更智能的卡死检测**：结合网络状态、WebSocket 连接状态等多维度判断
3. **用户通知**：真正卡死时可以给用户友好的提示，而不只是日志

---

**修复日期**：2025-10-13
**修复版本**：v1.0.1
**影响范围**：回合对话模式

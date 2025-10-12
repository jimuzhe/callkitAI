# CallKit与小智AI通话集成说明

## 功能概述

现在你的应用已经支持在接听CallKit来电后，直接在**系统通话界面**中与小智进行AI语音对话。

## 工作流程

### 1. 闹钟触发
- 当闹钟时间到达时，应用会通过CallKit显示来电界面
- 来电显示为闹钟名称（例如："早安闹钟"）

### 2. 接听通话
- 用户在系统通话界面点击"接听"按钮
- CallKit通话会话被激活
- 应用保持在系统通话界面（不跳转到应用界面）

### 3. AI对话开始
- 音频会话自动切换到语音聊天模式（VoiceChat）
- AI服务（小智）自动连接并开始对话
- 用户可以在系统通话界面中直接与小智对话

### 4. 对话进行中
- 用户的语音通过麦克风采集并发送给小智
- 小智的回复通过扬声器播放
- 所有音频处理都在CallKit音频会话中进行

### 5. 通话结束
- 当AI对话结束时，CallKit通话自动挂断
- 或用户手动挂断CallKit通话，AI对话也会自动停止
- 音频会话恢复正常，音量恢复到之前的设置

## 技术实现细节

### CallKit配置
```dart
ios: const IOSParams(
  audioSessionMode: 'voiceChat',  // 使用语音聊天模式
  audioSessionActive: true,        // 激活音频会话
  audioSessionPreferredSampleRate: 16000.0,  // 16kHz采样率
  audioSessionPreferredIOBufferDuration: 0.005,  // 低延迟
)
```

### 音频会话管理
1. **接听前**: 默认播放模式
2. **接听后**: 切换到VoiceChat模式（支持全双工通信）
3. **挂断后**: 恢复播放模式

### AI对话集成
- 使用 `AICallManager` 管理AI对话状态
- 使用 `XiaozhiService` 处理与小智服务的WebSocket连接
- 使用 `AudioService` 管理音频录制和播放

## 关键代码位置

### CallKit服务
文件: `lib/services/callkit_service.dart`

主要方法:
- `_handleCallAccepted()`: 处理接听事件
- `_startAICallInCallKitSession()`: 在CallKit会话中启动AI对话
- `_monitorAICallAndEndCallKit()`: 监控AI对话状态
- `_endCallKitSession()`: 结束CallKit通话会话

### AI服务
文件: `lib/services/ai_service.dart`

主要方法:
- `startConversation()`: 启动AI对话
- `stopConversation()`: 停止AI对话

### 音频服务
文件: `lib/services/audio_service.dart`

主要方法:
- `enterVoiceChatMode()`: 进入语音聊天模式
- `exitVoiceChatMode()`: 退出语音聊天模式

## 调试和日志

### 查看日志
在Xcode Console中查找以下标记:
- `📞` CallKit通话事件
- `🤖` AI对话启动
- `🎙️` 音频会话配置
- `✅` 成功操作
- `❌` 错误信息
- `⚠️` 警告信息

### 常见日志示例
```
📞 CallKit通话已接听: uuid-123
🎙️ 配置CallKit音频会话以支持AI对话
✅ 音频会话已切换至语音聊天模式（CallKit兼容）
🤖 开始在CallKit通话界面中与小智对话
✅ AI对话已在CallKit通话界面中启动
🔚 AI对话已结束，自动结束CallKit通话
```

## 注意事项

### 1. 无需VoIP推送
- 此实现**不依赖VoIP推送服务**
- 通过本地通知触发CallKit来电
- 适合没有后端服务器的应用

### 2. 音频权限
- 确保应用已获得麦克风权限
- 在 `Info.plist` 中配置麦克风使用说明

### 3. 后台模式
在Xcode中启用以下Background Modes:
- ✅ Audio, AirPlay, and Picture in Picture
- ✅ Voice over IP（用于CallKit）
- ⚠️ **不需要**实际的VoIP推送证书

### 4. 音量控制
- 接听通话时保持最大音量（便于听清AI语音）
- 挂断通话后恢复原音量
- 可在 `VolumeService` 中调整此行为

### 5. 通话时长
- AI对话会持续到用户挂断或AI主动结束
- 建议设置合理的对话时长限制（1-3分钟）
- 可通过小智的人格设置控制对话长度

## 优化建议

### 1. 降低延迟
```dart
// 在AudioService中预初始化音频会话
await AudioService.instance.initialize();

// 在CallKit来电前预热AI服务
await AIService.instance.prewarmConnection();
```

### 2. 改善用户体验
- 添加震动反馈（接听、挂断等操作）
- 优化AI的开场白（简短、友好）
- 设置合理的超时时间

### 3. 错误处理
- 网络连接失败时的重试机制
- 音频设备不可用时的降级方案
- AI服务异常时的友好提示

## 测试流程

### 1. 基础测试
1. 设置一个1分钟后的闹钟
2. 锁定iPhone屏幕
3. 等待CallKit来电界面弹出
4. 点击"接听"按钮
5. 验证能否听到小智的声音
6. 尝试与小智对话
7. 挂断通话

### 2. 边缘情况测试
- 接听后立即挂断
- 网络断开时接听
- 麦克风权限未授予时接听
- 通话中切换到其他应用
- 通话中来其他电话

### 3. 性能测试
- 连续多次接听/挂断
- 长时间通话（5分钟以上）
- 弱网环境下的表现

## 故障排除

### 问题1: 接听后没有声音
**可能原因**:
- 音频会话未正确配置
- 麦克风权限未授予
- AI服务连接失败

**解决方案**:
```dart
// 检查日志
// 查找 "音频会话已切换至语音聊天模式" 消息
// 查找 "AI对话已在CallKit通话界面中启动" 消息
```

### 问题2: 通话自动挂断
**可能原因**:
- AI对话异常结束
- 网络连接断开
- 音频播放失败

**解决方案**:
- 检查网络连接
- 查看错误日志
- 增加重试机制

### 问题3: CallKit界面不显示
**可能原因**:
- Background Modes未正确配置
- 通知权限未授予
- CallKit初始化失败

**解决方案**:
- 检查Xcode项目设置
- 验证权限状态
- 查看初始化日志

## 未来改进方向

1. **多轮对话支持**: 支持更复杂的对话流程
2. **语音识别优化**: 提高识别准确率
3. **情感分析**: 根据用户情绪调整AI回复
4. **个性化设置**: 允许用户自定义AI人格
5. **通话录音**: 可选的对话录音功能
6. **统计分析**: 记录对话数据用于改进

## 相关文件

- `lib/services/callkit_service.dart` - CallKit集成
- `lib/services/ai_service.dart` - AI服务封装
- `lib/services/ai_call_manager.dart` - AI通话管理
- `lib/services/audio_service.dart` - 音频处理
- `lib/services/xiaozhi_service.dart` - 小智服务
- `lib/models/ai_call_state.dart` - 通话状态定义

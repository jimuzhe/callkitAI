# AI Call Clock - iOS配置说明

## iOS权限配置

### 必需权限
1. **麦克风权限**: 用于语音通话
2. **通知权限**: 用于闹钟提醒
3. **VoIP权限**: 用于CallKit网络电话

### Background Modes
在Xcode中启用以下Background Modes:
- Audio, AirPlay, and Picture in Picture
- Voice over IP
- Background fetch
- Remote notifications
- Background processing

## CallKit配置

### 1. 启用Push Notifications
在Xcode中:
1. 打开项目设置
2. 选择Signing & Capabilities
3. 点击 "+ Capability"
4. 添加 "Push Notifications"

### 2. 配置VoIP推送证书
1. 登录Apple Developer网站
2. 创建VoIP Services Certificate
3. 下载并安装证书到钥匙串
4. 导出.p12文件用于推送服务

## TrollStore安装

### 前提条件
- iOS 14.0 - 16.6.1
- 已安装TrollStore

### 安装步骤
1. 构建IPA文件:
   ```bash
   flutter build ipa --release
   ```

2. 找到IPA文件位置:
   ```
   build/ios/ipa/call_clock.ipa
   ```

3. 通过以下方式安装到TrollStore:
   - AirDrop到iPhone
   - 通过Safari下载
   - 使用USB文件传输

4. 在TrollStore中点击IPA文件安装

### 重要提示
- TrollStore安装的应用拥有完整的后台权限
- 不需要企业证书或开发者账号
- 应用将拥有持久化的后台运行能力

## 调试

### 查看日志
使用Xcode的Console查看应用日志:
1. 连接iPhone到Mac
2. 打开Xcode -> Window -> Devices and Simulators
3. 选择设备,点击 "Open Console"
4. 过滤 "call_clock"

### 测试CallKit
1. 设置一个1分钟后的闹钟
2. 锁定iPhone
3. 等待通话界面弹出
4. 接听测试AI对话功能

## 常见问题

### Q: 通知不触发?
A: 检查通知权限是否授予,尝试重启应用

### Q: CallKit不显示?
A: 确保Info.plist中配置了UIBackgroundModes的voip

### Q: 音频无法播放?
A: 检查麦克风权限,确保audio session正确配置

### Q: 后台被杀死?
A: 使用TrollStore安装可以避免此问题

## 性能优化

### 电池优化
- 仅在闹钟时间前激活VoIP连接
- 使用高效的音频编解码器
- 限制AI对话时长(1-3分钟)

### 内存优化
- 及时释放音频资源
- 使用流式处理音频数据
- 定期清理旧日志

## 安全性

### API密钥保护
- 不要将API密钥硬编码
- 使用环境变量(.env)
- 考虑使用后端代理服务

### 数据加密
- 本地数据库加密
- HTTPS通信
- 敏感数据不缓存

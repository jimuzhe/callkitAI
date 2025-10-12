# 修复服务器错误："Error occurred while processing message"

## 问题诊断

从日志中可以看到服务器在收到音频数据后立即报错：
```
❌ 服务器错误: Error occurred while processing message
📦 完整错误消息: {"type":"error","message":"Error occurred while processing message","session_id":"..."}
```

## 根本原因

你使用的是测试token (`test-token`)，但这个公共服务器可能需要：
1. 有效的access token
2. 设备激活
3. 或者需要使用不同的音频参数

## 解决方案

### 方案1: 获取有效的Access Token（推荐）

你需要先激活设备以获取有效的access token。

#### 步骤1: 在设置页面添加激活功能

我会帮你添加一个激活按钮到设置页面。

#### 步骤2: 激活设备

打开应用设置，点击"激活设备"按钮，会显示二维码或链接，扫码/访问后即可激活。

### 方案2: 使用自己的服务器

如果你有自己的小智服务器，可以：

1. 部署自己的小智服务器（参考：https://github.com/liu731/xiaozhi）
2. 在设置中配置你的服务器地址
3. 不需要access token认证

### 方案3: 临时禁用认证（仅用于调试）

让我修改代码，尝试不发送access token来测试连接。

## 立即修复

让我帮你添加设备激活功能和更好的错误处理。

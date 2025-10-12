# Assets 目录说明

本目录用于存放应用所需的静态资源文件。

## 目录结构

```
assets/
├── images/          # 图片资源
│   ├── logo.png    # 应用Logo
│   ├── avatar/     # AI人设头像
│   │   ├── gentle.png
│   │   ├── energetic.png
│   │   ├── informative.png
│   │   └── humorous.png
│   └── icons/      # 自定义图标
│
└── audio/          # 音频资源(可选)
    ├── ringtones/  # 自定义铃声
    └── effects/    # 音效
```

## 使用说明

### 添加图片资源

1. 将图片文件放入对应目录
2. 确保pubspec.yaml中已声明资源路径:
```yaml
flutter:
  assets:
    - assets/images/
    - assets/audio/
```

3. 在代码中使用:
```dart
Image.asset('assets/images/logo.png')
```

### 推荐图片规格

- **应用Logo**: 512x512 PNG (透明背景)
- **AI头像**: 200x200 PNG (圆形或方形)
- **图标**: 48x48 或 64x64 PNG

### 音频资源(可选)

支持格式:
- MP3
- WAV
- M4A

使用示例:
```dart
AudioPlayer().play('assets/audio/ringtones/morning.mp3');
```

## 注意事项

1. 图片文件名使用小写和下划线
2. 避免使用过大的图片文件
3. 可以使用在线图片压缩工具优化
4. 版权问题:确保您有权使用这些资源

## 默认资源

应用使用Flutter内置图标和Emoji,以下资源为可选:

- AI人设头像:可以使用Emoji替代
- 自定义铃声:可以使用系统铃声
- Logo:可以使用应用名称文字

## 获取免费资源

推荐的免费资源网站:
- **图标**: https://www.flaticon.com
- **插图**: https://undraw.co
- **头像**: https://www.avatarmaker.com
- **音效**: https://freesound.org

## 开发建议

在开发阶段,可以暂时不添加这些资源,使用:
- 文本和Emoji代替图标
- 颜色背景代替图片
- 系统铃声代替自定义音频

待功能完善后再添加美化资源。

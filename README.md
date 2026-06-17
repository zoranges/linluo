# 零落

用时间缝合所有的零落。

零落是一款 Flutter 开发的照片时间水印应用，用来给手机照片添加复古数码管风格的日期水印。它的重点不是做复杂修图，而是把旧照片里的时间轻轻放回画面里。

## 下载

Android 安装包：

[releases/linluo-release.apk](releases/linluo-release.apk)

## 功能

- 从相册选择照片并进入独立编辑页
- 预览真实水印效果
- 复古七段数码管日期水印
- 支持多种日期格式
- 支持水印大小、透明度、颜色样式和位置调整
- 支持琥珀数码、蜜黄胶片、橙红日期、淡金旧照、白色数码等样式
- 默认按原图尺寸导出 PNG
- 导出后保存到手机相册

## 设计方向

零落的界面风格偏轻、透、软，避免传统工具软件的厚重面板。选择图片后，编辑页以照片作为主画布，参数控制以底部工具栏的方式出现，尽量保持画面本身的完整感。

水印风格参考老式数码日期机和胶片相机时间戳，强调：

- 七段数码管结构
- 暖橙黄色调
- 无发光阴影
- 尽量贴近真实数码管拼接

## 本地运行

确保已经安装 Flutter，然后在项目根目录执行：

```bash
flutter pub get
flutter run
```

## 构建 Debug 包

```bash
flutter build apk --debug
```

输出位置：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## 构建 Release 包

Windows 上如果项目路径包含中文，Flutter release AOT 可能会遇到路径编码问题。建议复制到纯英文路径后构建：

```powershell
flutter build apk --release
```

输出位置：

```text
build/app/outputs/flutter-apk/app-release.apk
```

当前仓库中已经包含一个可直接安装的 release 包：

```text
releases/linluo-release.apk
```

## 技术栈

- Flutter
- Dart
- Android MediaStore 保存相册
- 自定义 DSEG7 数码管字体

## 说明

当前版本默认导出原图尺寸 PNG，用于尽量减少二次压缩带来的画质损失。由于水印需要写入图片，导出的图片会重新编码，因此文件大小可能与原图不同。

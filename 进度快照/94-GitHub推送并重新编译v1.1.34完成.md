# 进度快照 94 - GitHub 推送并重新编译 v1.1.34 完成

## 版本信息
- 当前应用版本：`v1.1.34`
- `pubspec.yaml`：`1.1.34+52`
- 当前分支：`main`
- GitHub 远端：`https://github.com/luojiang419/ASR-tools.git`
- 已推送提交：
  - `0b574e3 sync v1.1.34 source`
  - `2057e3a merge origin main after v1.1.34 sync`
- 阶段备份：`backup/v0.44.2`
- 发布目录：`dist/v1.1.34`

## 已完成内容

### 1. 已同步并推送到 GitHub
- 已提交 v1.1.34 同步源码、测试、平台工程、文档和进度快照
- 已保留远端新增历史：
  - `91-v1.1.23macOS版本发布完成.md`
  - `92-v1.1.24自动补齐macOS环境并发布完成.md`
- 本轮同步快照已顺延为：
  - `93-同步v1.1.34源码完成.md`
- 已推送 `main -> origin/main`

### 2. 已合入远端 macOS 发布增强
- 已保留当前 v1.1.34 主线源码
- 已补入远端 macOS runtime 工具：
  - `tool/ensure_macos_environment.py`
- 已升级清洁发布脚本：
  - Windows 发布目录仍支持 `asr_tools.exe`
  - macOS 发布目录支持 `asr_tools.app`
  - 清洁数据库继续写入 `PRAGMA user_version`
  - macOS 发布时可安装 runtime
- `.gitignore` 已补充：
  - `/.toolchain/`
  - `/公钥/`

### 3. 已重新编译最新版 Windows release
- 已执行：
  - `flutter pub get`
  - `flutter build windows --release`
  - `python tool/prepare_clean_release.py dist/v1.1.34`
- 已生成：
  - `dist/v1.1.34/asr_tools.exe`
  - `dist/v1.1.34/flutter_windows.dll`
  - `dist/v1.1.34/sqlite3.dll`
  - `dist/v1.1.34/desktop_drop_plugin.dll`
  - `dist/v1.1.34/window_manager_plugin.dll`
  - `dist/v1.1.34/screen_retriever_windows_plugin.dll`
  - `dist/v1.1.34/dartjni.dll`
  - `dist/v1.1.34/data/config/asr_tools_settings.json`
  - `dist/v1.1.34/data/database/asr_tools.db`
  - `dist/v1.1.34/data/projects`
  - `dist/v1.1.34/data/temp`

### 4. 已清理构建临时缓存
- 已删除：
  - `build/`
  - `windows/flutter/ephemeral/`
  - `macos/Flutter/ephemeral/`
- 已保留：
  - `dist/v1.1.34/`
  - `.dart_tool/`

## 当前修改到哪个模块
- GitHub 推送与远端历史合并
- 发布脚本：
  - `tool/prepare_clean_release.py`
  - `tool/ensure_macos_environment.py`
- 本地忽略规则：
  - `.gitignore`
- FFmpeg 路径兼容：
  - `lib/services/ffmpeg_service.dart`
- 发布产物：
  - `dist/v1.1.34/`

## 具体修改代码前后对比

### 1. `.gitignore`
修改前：
```gitignore
/build/
/coverage/
/backup/
/dist/
/output/
```

修改后：
```gitignore
/build/
/coverage/
/.toolchain/
/backup/
/dist/
/output/

# SSH Keys
/公钥/
```

### 2. `lib/services/ffmpeg_service.dart`
修改前：
```dart
final binDir = p.join(normalized, 'bin');
```

修改后：
```dart
final directFile = File(normalized);
if (directFile.existsSync() &&
    p.basename(normalized) == _ffmpegBinaryName) {
  _ffmpegDir = directFile.parent.path;
  return;
}

final binDir = p.join(normalized, 'bin');
```

### 3. `tool/prepare_clean_release.py`
修改前：
```python
exe_path = release_dir / "asr_tools.exe"
data_dir = release_dir / "data"
```

修改后：
```python
layout = _find_release_layout(release_dir)
if layout is None:
    print(f"未找到发布程序: {release_dir}/asr_tools.exe 或 asr_tools.app")
    return 1
exe_path, data_dir = layout
```

## 验证结果
- `dart analyze lib test`
  - 通过
  - 仍保留 26 条既有 info
- `flutter test`
  - 通过
  - `74 tests passed`
- `flutter build windows --release`
  - 通过
- `python tool/prepare_clean_release.py dist/v1.1.34`
  - 通过
- `dist/v1.1.34/data/database/asr_tools.db`
  - `user_version = 5`
  - `projects = 0`

## 待办清单
- [ ] 用 `dist/v1.1.34/asr_tools.exe` 做真实工程手动验收
- [ ] 重点复测：
  - 窄窗口下导入页四个卡片头部是否稳定换行
  - 清空视频后重新导入视频是否正常
  - 清空音频后重新导入音频是否正常
  - Windows 下选择 ffmpeg.exe 文件路径是否能正常识别同目录 ffprobe.exe

## 下一步
- 直接运行 `dist/v1.1.34/asr_tools.exe` 做真实工程验收。

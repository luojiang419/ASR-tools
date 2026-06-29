# 进度快照 95 - GitHub 发布 v1.1.34 安装包完成

## 版本信息
- 当前应用版本：`v1.1.34`
- `pubspec.yaml`：`1.1.34+52`
- 当前分支：`main`
- GitHub 远端：`https://github.com/luojiang419/ASR-tools.git`
- 发布标签：`v1.1.34`
- Release 地址：`https://github.com/luojiang419/ASR-tools/releases/tag/v1.1.34`
- 阶段备份：`backup/v0.44.3`

## 已完成内容

### 1. 已读取上一轮最新快照
- 已读取：`进度快照/94-GitHub推送并重新编译v1.1.34完成.md`
- 确认上一轮源码已在 `main`，发布目录为 `dist/v1.1.34`

### 2. 已创建本阶段源码备份
- 备份目录：`backup/v0.44.3/source-before-github-release`
- 备份说明：`backup/v0.44.3/GitHub安装包推送前备份说明.md`
- 排除范围：`.git`、`.dart_tool`、`build`、`backup`、`dist`、`.toolchain`、`ephemeral`

### 3. 已重新验证并构建 Windows 发布包
- 已执行：`flutter pub get`
- 已执行：`dart analyze lib test`
- 已执行：`flutter test`
- 已执行：`flutter build windows --release`
- 已刷新发布目录：`dist/v1.1.34`
- 已执行：`python tool/prepare_clean_release.py dist/v1.1.34`

### 4. 已生成 GitHub Release 安装包附件
- 安装包：`dist/asr_tools_v1.1.34_windows_x64.zip`
- 校验文件：`dist/asr_tools_v1.1.34_windows_x64.zip.sha256.txt`
- 安装包大小：`13,623,203 bytes`
- SHA256：`f69bf80968700820f2dd44aa5aacfad29800625afd5fc2b95107a472a1455792`

### 5. 已创建 GitHub Release 并上传附件
- 标签：`v1.1.34`
- Release 地址：`https://github.com/luojiang419/ASR-tools/releases/tag/v1.1.34`
- 已上传：
  - `asr_tools_v1.1.34_windows_x64.zip`
  - `asr_tools_v1.1.34_windows_x64.zip.sha256.txt`

### 6. 已清理临时缓存
- 已删除：`dist/package-staging`
- 已删除：`build`
- 已删除：`windows/flutter/ephemeral`
- 已删除：`macos/Flutter/ephemeral`

## 当前修改到哪个模块
- GitHub 源码推送与 Release 发布流程
- Windows 发布包整理
- 发布校验与进度快照

## 具体修改代码前后对比

### 1. 业务源码
修改前：
```text
当前工作区业务源码与 origin/main 一致。
```

修改后：
```text
未修改业务源码，仅重新构建发布产物并新增本进度快照。
```

### 2. 发布产物
修改前：
```text
dist/v1.1.34 中保留上一轮构建产物。
```

修改后：
```text
已用当前 HEAD 重新执行 Windows release 构建，
并重新生成 dist/v1.1.34 与 asr_tools_v1.1.34_windows_x64.zip。
```

## 验证结果
- `dart analyze lib test`
  - 通过
  - 保留 26 条既有 info 级提示
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
- `dist/asr_tools_v1.1.34_windows_x64.zip`
  - 已确认包含 `asr_tools.exe`、Flutter 运行数据、默认配置和清洁数据库

## 待办清单
- [x] 推送本快照提交到 `origin/main`
- [x] 创建并推送 `v1.1.34` 标签
- [x] 创建 GitHub Release 并上传 zip 与 SHA256 文件
- [x] 清理本轮临时打包目录 `dist/package-staging`

## 下一步
- 从 GitHub Release 页面下载 `asr_tools_v1.1.34_windows_x64.zip` 做真实工程手动验收。

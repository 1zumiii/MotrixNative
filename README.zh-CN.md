# Motrix Native

由独立内置 aria2 引擎驱动的 macOS 原生菜单栏下载工具。

简体中文 | [English](README.md)

## 已实现功能

- 作为菜单栏应用运行，后台状态下不显示 Dock 图标。
- 打开主窗口时显示 Dock 图标，关闭窗口后重新隐藏到菜单栏。
- 所有运行数据保存在 `~/Library/Application Support/Motrix Native`。
- 首次启动时可继承 Motrix 的兼容设置和 `download.session`。
- 内置独立 aria2 二进制与配置，运行时不依赖原版 Motrix。
- 可连接已经运行的兼容 aria2 RPC 服务，也能自动启动和守护内置引擎。
- 菜单栏以清晰的 Retina 环形图标显示任务综合进度，并提供完成与异常状态提醒。
- 提供原生 SwiftUI 任务窗口、筛选、搜索、排序和批量选择。
- 支持 HTTP、FTP、磁力链接和 `.torrent` 文件，可在开始前选择 Torrent 内的具体文件。
- 支持暂停、继续、移除、删除文件、清理完成记录和调整队列优先级。
- 提供任务详情、传输统计、文件、来源、Peer、Tracker 和数据块矩阵视图。
- 提供下载、BitTorrent、RPC、监听端口、通知和登录启动等设置。
- 支持完全关闭做种，并在任务完成后清理无用的 `.aria2` 控制文件。
- 提供按服务器学习的智能并发连接调节，默认从 48 个连接开始探测。
- aria2 日志使用干净的文件输出，并在达到 5 MB 后滚动保留最近 3 份。
- 退出时保存 aria2 会话并请求引擎正常关闭。
- 已提供简体中文和英文界面资源。
- 可在通用设置中选择跟随系统、简体中文或 English，并即时切换界面语言。

## 构建

```sh
cd MotrixNative
xcrun swift build
```

## 打包

```sh
MotrixNative/Scripts/package-app.sh
```

开发版 App 会生成在：

```text
MotrixNative/.build/app/Motrix Native.app
```

## 源码结构

可执行目标位于 `Sources/MotrixNative`，采用面向 MVC 的职责划分：

- `Models`：应用状态和持久化配置。
- `Views`：SwiftUI/AppKit 视图、状态图标和用户确认窗口。
- `Views/MainWindow`：按主界面、设置、任务详情、任务列表和新建任务拆分的页面视图。
- `Controllers`：应用生命周期、窗口、状态栏和任务协调逻辑。
- `Services`：aria2 RPC、进程、日志，以及 macOS 系统服务集成。
- `Utilities`：无状态格式化、Tracker 解析和 `L10n` 本地化入口。
- `main.swift`：程序入口和自检命令。

界面文案统一存放在 `Resources/Localization`，Swift 源码仅使用语义化 key，通过 `L10n` 读取。打包脚本会把简体中文与英文资源一并放入 App Bundle。

## 独立性

打包后的应用包含自身所需的 aria2 引擎、默认配置、图标和语言资源。首次迁移完成后，删除原版 Motrix 不会影响 Motrix Native 的引擎、配置或任务会话。

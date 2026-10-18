# 更新日志

遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号用 `X.Y.Z`；
`flutter/pubspec.yaml` 的 build 号取 `minor*100 + patch`（0.1.1 → 101），
经 RustDesk 的映射后 versionCode = `2000 + build`（101 → 2101），保证只增不减、可覆盖安装。

## [0.1.1] - 2026-10-18

### 修复
- **一键关机此前不生效**：关机改走"终端类型"连接。host 只在登录请求带 `Terminal` 时才启动终端服务（`connection.rs:2200`），旧实现在普通画面会话里发 `OpenTerminal`，被 host 以 `terminal_user_token` 为空直接丢弃 —— 表现为按钮按了没反应。
- **不再弹出终端界面**：改为无界面复用 `TerminalModel` 完成"连接 → 灌命令 → 拆连接"，只留一条 toast。
- 无界面路径现在会带上调用方已有的凭据（卡片里存的共享密码 / 当前会话用过的密码），避免"对端要密码但没地方弹框"导致静默失败；确实没有任何凭据时退回会弹密码框的正常连接，并加了 20 秒超时，绝不留下一个待执行的关机。

### 变更
- 移除会话底部的聊天按钮（它在安卓上同时是语音通话入口）。

## [0.1.0] - 2026-10-17

### 新增
- 首个 TapDesk 版本：只主控端 Android 客户端（`conn-type=outgoing`），Win10 关机入口（设备卡片 / 会话工具栏 / ⋮ 菜单）。
- 独立包名 `com.tapdesk.client`、应用名与图标 TapDesk，可与官方 RustDesk 共存。
- 权限由 12 条精简为 4 条；去掉账号、地址簿、分组、帮助卡片、会话录制。

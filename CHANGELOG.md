# 更新日志

遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号用 `X.Y.Z`；
`flutter/pubspec.yaml` 的 build 号取 `minor*100 + patch`（0.1.1 → 101），
经 RustDesk 的映射后 versionCode = `2000 + build`（101 → 2101），保证只增不减、可覆盖安装。

## [0.1.3] - 2026-10-18

### 修复
- **关机失败不再靠猜**：0.1.2 的"那台电脑可能关闭了终端权限"是按排除法猜的话术。现在无界面会话自己挂一层事件回调，把 host 返回的原文抓出来直接显示（登录错误、要密码、要 Windows 管理员凭据都各有其文），终端开不起来时也读 `TerminalResponse` 里的失败原因。原因：`enable-terminal` 在 1.4.5 的 host 上默认是开的（`Config::get_option("access-mode")` 非 view/full 时走 `option2bool`，空值算 Y），所以"权限被关"不是唯一解释，光靠超时提示没法定位。
- **明确失败立刻收尾**，不再干等满 20 秒 —— 无界面会话没有终端区域能显示错误，干等只会更像"按钮没反应"。
- 用户自己开的终端（terminal id 0）报错不再误判成关机失败。

### 变更
- `Shut down failed` 措辞改为"20 秒内没等到终端响应"（它现在只代表超时无响应），拒绝类原因走新的 `Shut down refused` 并附电脑给出的原文。

### 已知
- 对端是官方 RustDesk 1.4.5 时协议层是通的：`OpenTerminal/TerminalAction/TerminalOpened` 的字段号与 1.5.1 完全一致，`LoginRequest` 里 `Terminal terminal = 16` 也一样；1.4.5 host 也带 `enable-terminal`、`No permission of terminal`、`terminal-service-id` 这套实现。
- 官方 host（含 1.4.5）**没有关机原语**，`Misc{restart_remote_device}` 只会 `system_shutdown::force_reboot()` 重启。所以真关机只能借终端通道跑 `shutdown /s /f /t 0`，这也是必须把拒绝原因显示出来的原因。

## [0.1.2] - 2026-10-18

### 修复
- **要点"关机"不再弹密码框并进终端页**：对等端本机没存过密码时，改为在 TapDesk 自己的对话框里一次性完成"确认 + 输入访问密码"，全程无界面。旧实现会退回 `connect(isTerminal: true)`，既有密码框又会闪出终端界面。
- **会话内关机此前建不起终端连接**：安卓/iOS 上画面会话和终端会话共用同一个 session id（`model.dart` 的 `_constSessionId`），Rust 侧一个 id 只容一个会话，`session_add` 会以 `same session id is found with different conn type?` 直接拒绝。现在从会话页（底部电源键、⋮ 菜单）点关机时先同步关掉画面会话，再建终端连接。
- 终端就绪前的重试不再是 5 次就停，改为在整个 20 秒窗口里每 0.7 秒重试一次，慢连接和刚登录完的窗口不再漏发指令。

### 新增
- **记住访问密码**：勾选后由 Rust 把同一份加盐哈希写进 `PeerConfig`（和上游"记住密码"共用存储，客户端不另存明文），之后对这台电脑就是真·一键。为此新增 `session_remember_password` 桥接（`src/flutter_ffi.rs`），它只把已有的 `remember` 位置位，并要求会话的 peer id 与用户确认的那台一致，避免误写别的会话。
- 失败提示分叉：密码不被接受 → "关机指令未发出：那台电脑不接受这个密码"；密码已通过但终端没起来 → "关机指令未生效：那台电脑可能关闭了终端权限"。

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

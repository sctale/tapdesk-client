# 更新日志

遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号用 `X.Y.Z`；
`flutter/pubspec.yaml` 的 build 号取 `minor*100 + patch`（0.1.1 → 101），
经 RustDesk 的映射后 versionCode = `2000 + build`（101 → 2101），保证只增不减、可覆盖安装。

## [0.1.7] - 2026-10-23

### 变更
- **"显示设置"从底部栏挪进 ⋮ 菜单**：那排按钮一行太挤（关闭 / 显示 / 键盘 / 触摸·鼠标 / 电源 / 锁定 / ⋮），把 📺 那个图标按钮收进 ⋮，底部栏现在是 `✕ · 键盘 · 触摸/鼠标 · 电源 · 锁定 · ⋮`。⋮ 的顺序是 显示设置 ─ 刷新 ─ 插入 Ctrl+Alt+Del。
  这个面板就是手机上调 显示模式 / 画质 / 编解码 / 多屏切换 的唯一入口，所以它是**挪位置**而不是删掉；新文案键 `Display settings`（显示设置）。

## [0.1.6] - 2026-10-23

按"只需要 ①看画面并操作 ②最近列表连接/重命名/移除 ③填自建服务器 ④电源键"这一份需求做的第一轮简化（A 档：纯入口裁剪，不碰协议）。

### 新增
- **底部栏常驻"锁定远程电脑"键**，就在电源键右边，调上游同一个 `bind.sessionLockScreen`。原来这个动作埋在 ⋮ 里，出门在外想锁一下屏幕要走两步。

### 变更
- **设备卡片菜单只剩 连接 / 重命名 / 忘记已存密码 / 收藏 / 移除**：删掉 传输文件、查看摄像头、终端、以管理员身份运行终端、强制始终中继 五项（5 个卡片变体各一份），对应的 builder 一并删掉，不留死代码。终端类入口本来在官方 1.4.5 对端上就起不来，留着只会误导。
- **会话 ⋮ 菜单改成白名单**：只留 `刷新` 与 `插入 Ctrl + Alt + Del`（按 `actionId` 过滤，不改上游 `toolbarControls()` 本身，桌面代码零改动）。请求管理员提权、系统账户密码、发送剪贴板按键、重置画布、备注、TCP 隧道、切换角色、截图、复制指纹、显示/跟随远端光标 等都不再出现。
- **权限再收一条**：manifest 去掉 `RECORD_AUDIO`，`MainService` 的 `foregroundServiceType` 从 `specialUse|mediaProjection|microphone` 收窄为 `specialUse`。手机侧唯一会用麦克风的是聊天/语音通话，而那个入口 0.1.1 就删了；`AudioRecordHandle.createAudioRecorder()` 本来就先 `checkSelfPermission` 再优雅返回 false，所以不会崩。

## [0.1.5] - 2026-10-23

### 变更
- **电源键改走安全序列**：会话底部栏那个电源键现在插入 **Ctrl+Alt+Del**，出现的安全屏幕右下角就是电源按钮，点它选"关机"（锁屏下同样可用）。⋮ 菜单里没有再加一条：上游的"插入 Ctrl + Alt + Del"本来就由 `toolbarControls()` 带出来（对等端是 Windows 且 host 自报 `sasEnabled`，或 Linux 时出现），再加是两行同名菜单。换路子的原因：终端关机要 host 起远程终端，而官方 1.4.5 的 Windows 终端要 `CreateProcessAsUser` 另起 helper 进程 + 受限 DACL 命名管道（`src/server/terminal_helper.rs`），这台对端我们连试三版没能把它跑起来，电脑侧也已确认没有策略/杀软在拦。安全序列只是一条普通按键事件（`ControlKey::CtrlAltDel` → host 的 `is_function_key()` → `send_sas()`），1.4.5 与 1.5.1 都有，走的是和画面操作同一条通道。
- **提示语按对端自报能力分两种**：`sasEnabled` 为真（host 以服务/管理员身份运行）时给出"下一步点哪里"的指引；为假时直接说明系统可能忽略这次按键 —— 这个值是 host 自己声明的，不是我们推断的。
- **设备卡片菜单里的"关机"已移除**：安全序列必须有活动会话才能发，卡片位置发不出去，留着一个必然失败的按钮更糟。终端关机那条路径的代码保留但暂时不接线，等对端版本对齐后换回只需一行。

## [0.1.4] - 2026-10-18

### 变更
- **无界面终端改用 id 0**。proto 里 `terminal_id` 的注释就是 "0 for default terminal"，而官方 1.4.5 对 `service_id` 为空的终端连接只给这一个一次性终端；我们自己挑的 99 换不来任何隔离，只是给跨版本行为多加了一个未知量。
- **超时不再只有一句话**，按实际观察到的阶段分成三种：`Shut down password rejected`（要求记住却没落盘 = 登录没过）、`Shut down not connected`（连 `peer_info` 都没收到 = 连接/验证没成）、`Shut down failed`（登录成了、`OpenTerminal` 也发了但无回音）。后两种附对端版本号，例如"…(RustDesk 1.4.5)"，因为跨版本行为只能靠它对号。
- 时间线全部 `debugPrint`（`[TapDesk]` / `[TerminalModel]` 前缀），插 USB 用 `adb logcat` 就能直接取到证据，不必靠人复述英文提示。

### 环境查证记录（对端 = 这台开发机，官方 RustDesk 1.4.5）
- 服务 `RustDesk` 以 **LocalSystem** 运行（`"C:\Program Files\RustDesk\RustDesk.exe" --service`），控制台用户 `haohao` 在 **session 6 / Active**，所以 1.4.5 的 `is_prelogin()` 与 `handle_installed_user()` 这两条拒绝路径按理应放行。
- Windows build **19045** → ConPTY 可用（1.4.5 的 `portable_pty::win::check_support()` 该过）。
- 配置里没有 `access-mode` 也没有 `enable-terminal`，`permission()` 落到 `option2bool` → 空值算 Y → 默认放行。
- 但 1.4.5 的 Windows 终端不是简单管道：`src/server/terminal_helper.rs` 要 `CreateProcessAsUser` 另起 helper 进程 + `create_named_pipe_server`/`wait_for_pipe_connection` + 受限 DACL。这一步是本机这类"策略拦子进程/命名对象"环境最容易断的地方，而服务侧（LocalSystem）日志在 `systemprofile` 下、普通账户读不到，所以只靠读日志无法定位 —— 本版把可见信息全部推到 toast 与 logcat。

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

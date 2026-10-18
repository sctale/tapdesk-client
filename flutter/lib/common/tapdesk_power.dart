import 'dart:async';

import 'package:flutter/material.dart';

import '../common.dart';
import '../consts.dart';
import '../desktop/pages/terminal_connection_manager.dart';
import '../models/platform_model.dart';
import '../models/terminal_model.dart';

/// TapDesk 扩展：一键关闭远程 Windows 电脑，全程不出现终端界面。
///
/// host 只在登录请求带了 Terminal 时才起终端服务
/// （src/server/connection.rs:2200 `else if self.terminal` -> init_terminal_service），
/// 普通画面会话发 OpenTerminal 会因 terminal_user_token 为空被丢弃。所以关机必须
/// 走终端类型的连接；但终端页只是渲染 xterm，投递命令本身不需要界面，于是这里
/// 无界面地复用 TerminalModel：连上、灌命令、拆连接。
const int kShutdownTerminalId = 99;

/// /f 必须有：锁屏下没人替未保存的程序点"仍要关闭"。
const String kShutdownCommand = 'shutdown /s /f /t 0\r';

/// 从发出 OpenTerminal 到拿到 shell 的等待上限，也是"这次没成"的判定窗口。
const Duration _shutdownWindow = Duration(seconds: 20);

bool peerIsWindows(String platform) => platform == kPeerPlatformWindows;

bool get peerSupportsShutdown => peerIsWindows(gFFI.ffiModel.pi.platform);

class _PendingShutdown {
  final String peerId;

  /// 无界面路径自己建连接，所以要自己拆。
  final VoidCallback close;

  /// 这次是否要求把密码存进 PeerConfig；用来区分"密码不对"和"终端权限被关"。
  final bool expectRemember;

  _PendingShutdown(this.peerId,
      {required this.close, this.expectRemember = false});
}

_PendingShutdown? _pending;

/// 密码 + 是否记住。只在本次内存里存在，落盘由 Rust 写 PeerConfig（存的是加盐哈希，
/// 不是明文），我们不自己存任何一份。
class ShutdownCredential {
  final String password;
  final bool remember;

  ShutdownCredential(this.password, this.remember);
}

/// 设备卡片和会话界面共用：确认一次，然后静默完成。
///
/// [password] / [isSharedPassword] 是调用方手上已有的凭据（卡片上的地址簿共享密码，
/// 或当前会话进来时用过的密码）。对等端本机存过密码时也直接免输。一个都没有时，
/// 让用户在我们自己的对话框里输一次并勾选记住 —— 之后就是真的一键。
///
/// [fromSession] 表示正在看这个对等端的画面。手机端画面会话和终端会话共用同一个
/// session id（model.dart 的 `_constSessionId`），Rust 侧一个 id 只容一个会话，
/// 所以必须先把画面会话关掉，终端连接才建得起来。
Future<void> requestShutdown(BuildContext context, String peerId,
    {String? password,
    bool? isSharedPassword,
    bool fromSession = false}) async {
  if (!context.mounted) {
    return;
  }
  var typed = (password ?? '').isNotEmpty ? password! : '';
  var remember = false;
  final isShared = isSharedPassword == true;
  final hasSaved = await bind.mainPeerHasPassword(id: peerId);
  if (!isShared && typed.isEmpty && !hasSaved) {
    // 确认和密码合并成一个框：本来就要输密码，就不再叠加一次"确定关机？"。
    final cred = await askShutdownPassword(context);
    if (cred == null) {
      return;
    }
    typed = cred.password;
    remember = cred.remember;
  } else {
    if (!await confirmShutdown(context)) {
      return;
    }
  }
  if (fromSession) {
    await leaveLiveSession();
  }
  await startShutdown(
    peerId,
    password: typed.isEmpty ? null : typed,
    isSharedPassword: isShared ? isSharedPassword : null,
    remember: remember,
  );
}

/// 关掉正在显示的画面会话，腾出手机端唯一的 session id。
///
/// `bind.sessionClose` 同步把会话从 Rust 的 SESSIONS 里摘掉（flutter.rs
/// `remove_session_by_session_id`），所以返回后终端连接就能 add 成功；页面退出交给
/// `closeConnection()` 异步做，它后续在 dispose 里再关一次是空操作。
Future<void> leaveLiveSession() async {
  unawaited(bind.sessionClose(sessionId: gFFI.sessionId));
  closeConnection();
  await Future.delayed(const Duration(milliseconds: 300));
}

Future<void> startShutdown(String peerId,
    {String? password, bool? isSharedPassword, bool remember = false}) async {
  if (_pending != null) {
    showToast(translate('Shut down command sent'));
    return;
  }
  final ffi = TerminalConnectionManager.getConnection(
    peerId: peerId,
    password: password,
    isSharedPassword: isSharedPassword,
    forceRelay: null,
    connToken: null,
  );
  // 预置密码走 host 的 preset 分支（client.rs `handle_hash`），那条分支不会把
  // remember 打开，于是这里赶在 peer_info 之前替用户补上，让 Rust 把同一份加盐哈希
  // 写进 PeerConfig。下次点关机就真的一键了。
  if (remember && (password ?? '').isNotEmpty) {
    final saved = await bind.sessionRememberPassword(
        sessionId: ffi.sessionId, id: peerId, remember: true);
    if (!saved) {
      debugPrint('[TapDesk] $peerId: password not remembered');
    }
  }
  // 无界面会话没挂 Overlay，host 的登录错误走上游对话框是弹不出来的（只会
  // Future.error 后静默消失）。这里自己套一层事件回调，把错误原文抓出来。
  final inner = ffi.ffiModel.startEventListener(ffi.sessionId, peerId);
  platformFFI.setEventCallback((evt) async {
    final note = _shutdownNoteFromEvent(evt);
    if (note != null) {
      reportShutdownFailure(peerId, kShutdownTerminalId, note);
    }
    await inner(evt);
  });
  final model = TerminalModel(ffi, kShutdownTerminalId);
  ffi.registerTerminalModel(kShutdownTerminalId, model);
  void close() {
    try {
      ffi.unregisterTerminalModel(kShutdownTerminalId);
      model.dispose();
    } catch (e) {
      debugPrint('[TapDesk] teardown failed: $e');
    }
    TerminalConnectionManager.releaseConnection(peerId);
  }

  _pending = _PendingShutdown(peerId,
      close: close, expectRemember: remember && (password ?? '').isNotEmpty);
  // 登录没完成时 OpenTerminal 会被丢，所以在整个窗口里持续重试；openTerminal 在已
  // 就绪时直接返回，重复调用是安全的。
  final deadline = DateTime.now().add(_shutdownWindow);
  Timer.periodic(const Duration(milliseconds: 700), (t) {
    final target = _pending;
    if (target == null ||
        target.peerId != peerId ||
        DateTime.now().isAfter(deadline)) {
      t.cancel();
      return;
    }
    unawaited(model.openTerminal());
  });
  // 对端要求密码而没带上、密码不对、或它关了终端权限时，永远等不到就绪。必须超时清掉
  // 目标，否则下次对同一台机器开终端会把它莫名关掉。
  Timer(_shutdownWindow, () async {
    final stuck = _pending;
    if (stuck == null || stuck.peerId != peerId) {
      return;
    }
    _pending = null;
    // 要求记住却始终没落盘 = 登录没过去，问题在密码；否则是对端不让用终端。
    var blamedPassword = false;
    if (stuck.expectRemember) {
      blamedPassword = !await bind.mainPeerHasPassword(id: peerId);
    }
    showToast(translate(
        blamedPassword ? 'Shut down password rejected' : 'Shut down failed'));
    stuck.close();
  });
}

/// TerminalModel 报告远端 shell 已就绪时调用；不是本次目标就什么都不做。
Future<void> deliverPendingShutdown(
    String peerId, Future<void> Function(String data) send) async {
  final target = _pending;
  if (target == null || target.peerId != peerId) {
    return;
  }
  _pending = null;
  try {
    await send(kShutdownCommand);
    showToast(translate('Shut down command sent'));
  } catch (e) {
    showToast('${translate('Failed')}: $e');
  }
  // 等指令真的发出去再拆连接，太早关会把命令一起带走。
  Timer(const Duration(seconds: 3), () => target.close());
}

/// 终端连接没建起来就被关闭时清掉目标，避免留下一个待执行的关机。
void clearPendingShutdown(String peerId) {
  final target = _pending;
  if (target != null && target.peerId == peerId) {
    _pending = null;
  }
}

/// host 明确不让关机时说出来并立刻收尾 —— 无界面会话没有终端区域能显示失败原因，
/// 让人干等满 20 秒只会更像"按钮没反应"。
///
/// [terminalId] 用来过滤：用户自己开的终端（id 0）出错不该把关机目标判定为失败。
void reportShutdownFailure(String peerId, int terminalId, String reason) {
  if (terminalId != kShutdownTerminalId) {
    return;
  }
  final target = _pending;
  if (target == null || target.peerId != peerId) {
    return;
  }
  _pending = null;
  final note = reason.trim().isEmpty ? 'Unknown error' : reason.trim();
  debugPrint('[TapDesk] shutdown refused by $peerId: $note');
  showToast('${translate('Shut down refused')}: $note');
  target.close();
}

/// 会话事件里能当作"这次关机被拒"的几条：登录错误原文、要密码、要 Windows 管理员。
String? _shutdownNoteFromEvent(dynamic evt) {
  if (evt is! Map) {
    return null;
  }
  if (evt['name'] != 'msgbox') {
    return null;
  }
  final type = (evt['type'] ?? '').toString();
  final text = (evt['text'] ?? '').toString().trim();
  switch (type) {
    case 'error':
      return text.isEmpty ? 'Login Error' : text;
    case 'input-password':
    case 're-input-password':
      return translate('Password Required');
    case 'terminal-admin-login':
    case 'terminal-admin-login-password':
      return 'terminal needs Windows administrator credentials';
    default:
      return null;
  }
}

Future<bool> confirmShutdown(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(translate('Shut down')),
      content: Text(translate('Shut down this computer?')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(translate('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(translate('Shut down')),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 确认 + 输入访问密码，一个框办完。
///
/// 不用上游那个密码框：它挂在会话自己的 dialogManager 上，而无界面会话没有 Overlay
/// （common.dart `OverlayDialogManager.show` 在 `_overlayKeyState.state` 为空时直接
/// 抛错），而且文案是"验证 RustDesk 密码"，白标包里不该出现。
Future<ShutdownCredential?> askShutdownPassword(BuildContext context) async {
  final controller = TextEditingController();
  var remember = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(translate('Password Required')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate('Shut down needs the access password')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
              decoration: InputDecoration(labelText: translate('Password')),
            ),
            CheckboxListTile(
              contentPadding: const EdgeInsets.all(0),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(translate('Remember password')),
              value: remember,
              onChanged: (v) => setState(() => remember = v ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(translate('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(translate('Shut down')),
          ),
        ],
      ),
    ),
  );
  final password = controller.text.trim();
  controller.dispose();
  if (ok != true || password.isEmpty) {
    return null;
  }
  return ShutdownCredential(password, remember);
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';

/// TapDesk 扩展：一键关闭远程 Windows 电脑。
///
/// 走 host 已有的终端通道（OpenTerminal + TerminalData），所以协议没动、电脑端
/// 也不需要换成我们的构建，官方 RustDesk host 就能用。代价是它依赖 host 的
/// `enable-terminal` 权限——option2bool 对 enable- 前缀把空值当 Y，所以默认是
/// 开的；被显式设成 N 时指令会"本地发送成功、远端静默无效"。
const int kShutdownTerminalId = 99;

/// 只有 Windows 才有 `shutdown` 命令。
bool peerIsWindows(String platform) => platform == kPeerPlatformWindows;

bool get peerSupportsShutdown => peerIsWindows(gFFI.ffiModel.pi.platform);

// 设备卡片上的"关机"只能先建立会话再发指令，所以点卡片时把目标记下来，等会话
// 就绪后由 remote_page 消费。记的是 peer id，连错人不会误发。
String? _pendingShutdownPeerId;

void armShutdown(String peerId) => _pendingShutdownPeerId = peerId;

void clearPendingShutdown() => _pendingShutdownPeerId = null;

bool _consumePendingShutdown(String peerId) {
  if (_pendingShutdownPeerId != peerId) {
    return false;
  }
  _pendingShutdownPeerId = null;
  return true;
}

Future<void> _runShutdownCommand() async {
  final sessionId = gFFI.sessionId;
  await bind
      .sessionOpenTerminal(
        sessionId: sessionId,
        terminalId: kShutdownTerminalId,
        rows: 24,
        cols: 80,
      )
      .timeout(const Duration(seconds: 5));
  // host 收到 OpenTerminal 后异步起 shell，立刻灌输入会被丢掉。
  await Future<void>.delayed(const Duration(milliseconds: 800));
  // /f 是必须的：锁屏下没人替未保存的程序点"仍要关闭"。
  await bind.sessionSendTerminalInput(
    sessionId: sessionId,
    terminalId: kShutdownTerminalId,
    data: 'shutdown /s /f /t 0\r',
  );
}

Future<void> _closeTerminalQuietly() async {
  try {
    await bind
        .sessionCloseTerminal(
      sessionId: gFFI.sessionId,
      terminalId: kShutdownTerminalId,
    )
        .timeout(const Duration(seconds: 2));
  } catch (e) {
    // The peer is going away or never answered; nothing useful to do.
  }
}

Future<void> _sendAndReport() async {
  try {
    await _runShutdownCommand();
    showToast(translate('Shut down command sent'));
  } catch (e) {
    showToast('${translate('Failed')}: $e');
    await _closeTerminalQuietly();
  }
}

/// 关机前的一次确认。设备卡片和会话工具栏共用这一段文案。
Future<bool> confirmShutdown(BuildContext context) async =>
    await _confirmShutdown(context) ?? false;

Future<bool?> _confirmShutdown(BuildContext context) {
  return showDialog<bool>(
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
}

/// 会话内手动触发（工具栏按钮 / 菜单项）：确认后才发。
Future<void> shutdownPeer(BuildContext context) async {
  if (!(await _confirmShutdown(context) ?? false)) {
    return;
  }
  await _sendAndReport();
}

/// 设备卡片触发：那里已经确认过一次，所以这里只等会话就绪就发，不再弹第二次。
///
/// pi.platform 要等登录完成才有值，所以轮询而不是在 initState 里直接判断。
Future<void> maybeRunPendingShutdown(String peerId) async {
  if (_pendingShutdownPeerId != peerId) {
    return;
  }
  final pi = gFFI.ffiModel.pi;
  for (var i = 0; i < 20 && pi.platform.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (!_consumePendingShutdown(peerId) || !peerIsWindows(pi.platform)) {
    clearPendingShutdown();
    return;
  }
  await _sendAndReport();
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';

/// TapDesk 扩展：一键关闭远程 Windows 电脑。
///
/// 走的是 host 已有的终端通道（OpenTerminal / TerminalData），所以协议没动、
/// 电脑端也不需要换成我们的构建，官方 RustDesk host 就能用。代价是它依赖
/// host 的 `enable-terminal` 权限——该权限默认是开的（option2bool 对 enable-
/// 前缀把空值当作 Y），但被对方显式关掉时这条指令会静默无效。
const int kShutdownTerminalId = 99;

/// 只有 Windows 才有 `shutdown` 命令，其它平台不显示这个入口。
bool get peerSupportsShutdown => gFFI.ffiModel.pi.platform == kPeerPlatformWindows;

Future<void> _runShutdownCommand(String command) async {
  final sessionId = gFFI.sessionId;
  // 24x80 足够放下一条命令；真正的终端尺寸由 host 的 PTY 决定。
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
  await bind.sessionSendTerminalInput(
    sessionId: sessionId,
    terminalId: kShutdownTerminalId,
    data: command,
  );
}

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

/// 菜单项回调。`/f` 是必须的：锁屏下没人替未保存的程序点"仍要关闭"。
Future<void> shutdownPeer(BuildContext context) async {
  if (!(await _confirmShutdown(context) ?? false)) {
    return;
  }
  try {
    await _runShutdownCommand('shutdown /s /f /t 0\r');
    showToast(translate('Shut down command sent'));
  } catch (e) {
    showToast('${translate('Failed')}: $e');
    unawaited(
      bind
          .sessionCloseTerminal(
        sessionId: gFFI.sessionId,
        terminalId: kShutdownTerminalId,
      )
          .catchError((_) {}),
    );
  }
}

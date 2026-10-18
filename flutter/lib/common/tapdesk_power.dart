import 'package:flutter/material.dart';

import '../common.dart';
import '../consts.dart';

/// TapDesk 扩展：一键关闭远程 Windows 电脑。
///
/// 关机必须走"终端类型"的连接。host 只在登录请求里带了 Terminal 时才起终端服务
/// （src/server/connection.rs 里 `else if self.terminal` 那支去
/// init_terminal_service），普通画面会话发 OpenTerminal 会因为 terminal_user_token
/// 为空被直接拒掉 —— 表现就是按钮按了没反应。所以这里开的是 isTerminal 连接，
/// 由 TerminalModel 在 shell 起来后把命令灌进去。
const String kShutdownCommand = 'shutdown /s /f /t 0\r';

bool peerIsWindows(String platform) => platform == kPeerPlatformWindows;

bool get peerSupportsShutdown => peerIsWindows(gFFI.ffiModel.pi.platform);

String? _pendingShutdownPeerId;

/// 会话页/设备卡片共用的一次确认 + 终端连接。
Future<void> requestShutdown(BuildContext context, String peerId) async {
  if (!await confirmShutdown(context)) {
    return;
  }
  _pendingShutdownPeerId = peerId;
  connect(context, peerId, isTerminal: true);
}

/// TerminalModel 报告 shell 已就绪时调用；不是本次目标就什么都不做。
Future<void> deliverPendingShutdown(
    String peerId, Future<void> Function(String data) send) async {
  if (_pendingShutdownPeerId != peerId) {
    return;
  }
  _pendingShutdownPeerId = null;
  try {
    await send(kShutdownCommand);
    showToast(translate('Shut down command sent'));
  } catch (e) {
    showToast('${translate('Failed')}: $e');
  }
}

/// 终端页关掉而命令没发出去（权限被拒、连不上）时，绝不能把目标留着，
/// 否则下次对同一台机器开终端会莫名其妙把它关掉。
void clearPendingShutdown(String peerId) {
  if (_pendingShutdownPeerId == peerId) {
    _pendingShutdownPeerId = null;
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

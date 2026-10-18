import 'dart:async';

import 'package:flutter/material.dart';

import '../common.dart';
import '../consts.dart';
import '../desktop/pages/terminal_connection_manager.dart';
import '../models/model.dart';
import '../models/terminal_model.dart';

/// TapDesk 扩展：一键关闭远程 Windows 电脑，全程不出现终端界面。
///
/// host 只在登录请求带了 Terminal 时才起终端服务
/// （src/server/connection.rs:2200 `else if self.terminal` -> init_terminal_service），
/// 普通画面会话发 OpenTerminal 会因 terminal_user_token 为空被丢弃。所以关机必须
/// 走终端类型的连接；但终端页只是渲染 xterm，命令投递本身不需要界面，于是这里
/// 直接复用 TerminalModel 无界面地连上、灌命令、拆连接。
const int kShutdownTerminalId = 99;

/// /f 必须有：锁屏下没人替未保存的程序点"仍要关闭"。
const String kShutdownCommand = 'shutdown /s /f /t 0\r';

bool peerIsWindows(String platform) => platform == kPeerPlatformWindows;

bool get peerSupportsShutdown => peerIsWindows(gFFI.ffiModel.pi.platform);

class _PendingShutdown {
  final String peerId;
  final FFI ffi;
  final TerminalModel model;

  _PendingShutdown(this.peerId, this.ffi, this.model);
}

_PendingShutdown? _pending;

/// 设备卡片和会话界面共用：确认一次，然后静默完成。
Future<void> requestShutdown(BuildContext context, String peerId) async {
  if (!await confirmShutdown(context)) {
    return;
  }
  await startShutdown(peerId);
}

Future<void> startShutdown(String peerId) async {
  if (_pending != null) {
    showToast(translate('Shut down command sent'));
    return;
  }
  final ffi = TerminalConnectionManager.getConnection(
    peerId: peerId,
    password: null,
    isSharedPassword: null,
    forceRelay: null,
    connToken: null,
  );
  ffi.ffiModel.updateEventListener(ffi.sessionId, peerId);
  final model = TerminalModel(ffi, kShutdownTerminalId);
  ffi.registerTerminalModel(kShutdownTerminalId, model);
  _pending = _PendingShutdown(peerId, ffi, model);
  // 刚 start() 时登录还没完成，第一次 OpenTerminal 可能被丢，所以重试几次；
  // openTerminal 内部在已就绪时会直接返回，重复调用是安全的。
  _scheduleOpen(model, 0);
}

void _scheduleOpen(TerminalModel model, int attempt) {
  if (_pending == null || attempt > 4) {
    return;
  }
  Timer(Duration(milliseconds: attempt == 0 ? 300 : 1200), () {
    if (_pending == null) {
      return;
    }
    unawaited(model.openTerminal());
    _scheduleOpen(model, attempt + 1);
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
  // 等指令发出去再拆连接，太早关会把命令一起带走。
  Timer(const Duration(seconds: 3), () => _close(target));
}

void _close(_PendingShutdown target) {
  try {
    target.ffi.unregisterTerminalModel(kShutdownTerminalId);
    target.model.dispose();
  } catch (e) {
    debugPrint('[TapDesk] teardown failed: $e');
  }
  TerminalConnectionManager.releaseConnection(target.peerId);
}

/// 终端连接没建起来（权限被拒、连不上）时绝不能把目标留着，否则下次对同一台
/// 机器开终端会把它莫名其妙关掉。
void clearPendingShutdown(String peerId) {
  final target = _pending;
  if (target != null && target.peerId == peerId) {
    _pending = null;
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

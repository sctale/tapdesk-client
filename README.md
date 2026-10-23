# TapDesk

> **这不是 RustDesk 官方仓库，也不是 RustDesk 本体。**
> TapDesk 是 [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk) **1.5.1** 的一个 fork，只做成 **Android 主控端（controller only）**——用来从手机连自己家的电脑。它**不能接收别人的连接**，没有桌面端、没有 iOS、不含服务端。要被人远程控制，请在电脑上装官方 RustDesk。
>
> A fork of RustDesk 1.5.1 built as an **Android-only controller** for one family. It cannot accept incoming connections; install the official RustDesk on the machine you remote into.

| | |
|---|---|
| 安装 | [Releases](https://github.com/sctale/tapdesk-client/releases) 里的 `TapDesk-v<版本>.apk`（arm64，release 签名） |
| 更新记录 | [CHANGELOG.md](CHANGELOG.md) |
| 上游原版说明 | [docs/README-UPSTREAM.md](docs/README-UPSTREAM.md)（`docs/README-*.md` 那 20 多份也都是上游的翻译文档，不是本项目的） |
| 许可 | AGPLv3（[`LICENCE`](LICENCE)，与上游一致；仓库因此保持 public） |
| 支持 | 私人自用项目：不处理 issue / PR，不承诺与任何版本兼容 |

## 这个 fork 存在的理由

自家与家人用的手机远控：自建 rustdesk-server（NAS）+ 界面尽量精简 + 一个能真的把 Windows 电脑关掉的按键。原版本身已经很好，我们只是要一个"只用来出门在外连自家电脑"的干净 APK。

## 与原版的差别：看得见的部分

- **只主控端**。不是删 UI，而是 custom client 的 hard setting `conn-type=outgoing`：主页面不再挂 ServerPage/ChatPage，设置页里的被控段自动隐藏。`AndroidManifest.xml` 只留 `INTERNET`/`ACCESS_NETWORK_STATE`/`FOREGROUND_SERVICE`/`RECORD_AUDIO` 四条权限，`BootReceiver` 与输入服务不再声明。
- **白标**：`applicationId` = `com.tapdesk.client`（可与官方 App 共存），名称与图标为 TapDesk。注意 Kotlin `namespace` 仍是 `com.carriez.flutter_hbb` —— JNI 和 R 类依赖它，别改。
- **去掉聊天/语音入口**、会话录制行、账号与地址簿、分组、帮助卡片。
- **电源键**：会话底部栏点一下 = 给对端**插入 Ctrl+Alt+Del**，在弹出的 Windows 安全屏幕右下角就是电源按钮，可选关机/重启（锁屏状态也能用）。
- **服务器地址不写进仓库**：在 App 内"设置 → 服务器"手填自建 rustdesk-server；没填时回落公共服务器。

## 与原版的差别：代码在哪

| 位置 | 做了什么 |
|---|---|
| `build-custom/` | 定制打包链：`custom_client.json`（品牌+硬开关）、`gen_custom_client.py`（签名配置）、`vendor_git_deps.py`（离线 pin pub 依赖）、`build_and_install.py`（触发 CI→取产物→装手机）、图标 |
| `.github/workflows/android-client.yml` | 我们自己加的 arm64 Android 构建任务（release 签名产物） |
| `.github/workflows/` | **删掉了 9 个上游 workflow**（要 `contents: write` 或跑 nightly 的那些，在这个仓库里只会失败）；只留 `bridge.yml`（被我们调用）和 `flutter-build.yml`（无触发器，当步骤对照） |
| `src/common.rs` | custom client 校验公钥 `KEY` 换成我们自己的 |
| `flutter/lib/common/tapdesk_power.dart` | 电源键逻辑（安全序列 + 保留但未接线的终端式关机路径） |
| `flutter/lib/brand/`（gitignore） | 构建时生成的签名后品牌配置，不入仓库 |
| `flutter/android/` | 包名、清单、权限、图标 |
| `flutter/pubspec.yaml` | 版本号 + `flutter_icons` |

## 怎么构建（**只能在 GitHub Actions 上，别在 Windows 本机重试**）

日常出包：双击仓库根的 **`TapDesk出包.bat`**，或直接

```bash
py -3 build-custom/build_and_install.py            # 推送 master → 触发构建 → 等完 → 取 release 签名 APK 到仓库根 → adb install
py -3 build-custom/build_and_install.py --no-install          # 只下载不装机
py -3 build-custom/build_and_install.py --run 39901195725     # 复用已完成的构建号
```

需要配好的 Actions secrets：`CUSTOM_CLIENT_SIGN_KEY`、`ANDROID_SIGNING_KEY`、`ANDROID_ALIAS`、`ANDROID_KEY_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD`。
**keystore 和 custom-client 私钥只保存在维护者本机，不在仓库里**——所以你自己构建出来的 APK 签名不同，无法覆盖安装这里的 Release 包。

本机 Windows 构建不了这件事已经实测过两次，死因与构建无关：① 系统策略会拦下由 `cargo.exe`/`dart.exe` 拉起的 MSYS 进程（而 `openssl` 是 `vendored`，必须 perl/make）；② Android 还要 vcpkg 交叉编译 libvpx/aom/opus/libyuv/ffmpeg。热缓存一轮约 20～35 分钟。

工具链 pin：Flutter 3.24.5（附一个 dropdown-menu patch）、Rust 1.75、NDK r28c（28.2.13676358）、cargo-ndk 3.1.2、flutter_rust_bridge 1.80.1、`flutter/build_android_deps.sh arm64-v8a`。

## 改之前先看这几条（都是踩出来的）

1. 安卓/iOS 上**所有会话共用同一个 session id**（`flutter/lib/models/model.dart` 的 `_constSessionId`），Rust 侧一个 id 只容一个连接；画面会话活着时再建"终端类型"的连接会被 `session_add` 拒绝，而且 Dart 忽略了这个返回值，表现是静默失败。
2. 往会话的 ⋮ 菜单加条目之前，先看 `flutter/lib/common/widgets/toolbar.dart` 的 `toolbarControls()`（上游条目就是它带出来的，容易重复），以及 `_getMobileActionMenus()` 这类宿主函数的返回条件——它是"对端是安卓"专用表，给 Windows 对等端返回空表。
3. **APK 里能 grep 到字符串 ≠ 功能走得通**。协议与连接类型这类语义必须回 Rust 侧读调用链确认，我们为此返工过三次。
4. `flutter/lib/generated_bridge.dart` 由 CI 每次从 `src/flutter_ffi.rs` 重新生成，仓库里那份（gitignore）是旧的；新增 bind 后本地 `flutter analyze` 报 `undefined_method` 属预期。本机跑不了 `cargo check`，可以用 `rustfmt --edition 2021 --check <文件>` 当语法解析器。
5. 版本号规则：产品版本 `X.Y.Z` 写在 `flutter/pubspec.yaml`，build 号 = `minor*100 + patch`，经 RustDesk 的映射得到 versionCode = `2000 + build`（0.1.5 → 105 → 2105），只增不减、可覆盖安装。**`Cargo.toml` 里的 1.5.1 是协议版本**，host 用它做功能门控，绝不能跟着改成 0.x。

## 已知做不到 / 还没做

- 对端是官方 RustDesk 1.4.5 时，它的 Windows 远程终端起不来（要 `CreateProcessAsUser` 另起 helper 进程 + 受限 DACL 命名管道，见 `src/server/terminal_helper.rs`），所以"终端里跑 `shutdown`"这条路不可用——电脑侧的策略/杀软/ConPTY 前置条件都已逐项排除。**电源键因此改走安全序列**；对端升到 1.5.1 后终端路径可以一行换回。
- 没有 Wake-on-LAN：电脑关掉之后，手机叫不醒它。
- 不构建 iOS / 桌面端 / 服务端。

## 免责

只用于控制你自己或已明确获得授权的电脑。未经授权的控制与窥探是违法的，本项目不支持也不提供任何被控能力。

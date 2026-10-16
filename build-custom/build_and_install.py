#!/usr/bin/env python3
"""One-shot: build the TapDesk APK on GitHub Actions, pull it back, install it.

Called by  TapDesk出包.bat  (double-click) or directly:
    python3 build-custom/build_and_install.py [--no-push] [--no-install] [--abi <target>]

The APK is built by .github/workflows/android-client.yml because the Rust and
C++ cross toolchain only works on Linux; everything Windows-side happens here.
"""

import argparse
import datetime
import json
import os
import subprocess
import sys
import time

REPO = "sctale/tapdesk-client"
WORKFLOW = "android-client.yml"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "apks")
POLL_SECONDS = 20


def run(args, capture=False, check=True):
    """Run a command in the repo, echoing what it is, and return its stdout."""
    print("  $ " + " ".join(args))
    p = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if check and p.returncode != 0:
        sys.exit("命令失败：%s\n%s%s" % (" ".join(args), p.stdout, p.stderr))
    return (p.stdout or "").strip()


def gh_json(*args):
    return json.loads(run(["gh"] + list(args), check=True) or "null")


def current_run_id():
    rows = gh_json("run", "list", "--repo", REPO, "--workflow", WORKFLOW,
                   "--limit", "1", "--json", "databaseId")
    return rows[0]["databaseId"] if rows else None


def wait_for_run(run_id):
    print("\n构建中：%s" % ("https://github.com/%s/actions/runs/%s" % (REPO, run_id)))
    dots = 0
    while True:
        data = gh_json("run", "view", str(run_id), "--repo", REPO,
                       "--json", "status", "conclusion")
        status = data.get("status")
        if status == "completed":
            return data.get("conclusion")
        dots += 1
        mins = dots * POLL_SECONDS // 60
        print("  进行中... 已等 %d 分 %02d 秒" % (mins, dots * POLL_SECONDS % 60), flush=True)
        time.sleep(POLL_SECONDS)


def report_failure(run_id):
    print("\n构建失败，最后 40 行错误日志：\n")
    p = subprocess.run(["gh", "run", "view", str(run_id), "--repo", REPO, "--log-failed"],
                       cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    lines = [l for l in (p.stdout or "").splitlines() if l.strip()]
    for line in lines[-40:]:
        print("  " + line[-200:])


def _apks():
    return [os.path.join(OUT_DIR, f) for f in os.listdir(OUT_DIR)
            if f.lower().endswith(".apk")]


def download(run_id, abi):
    """Prefer the release-signed artifact; fall back to the plain one.

    Names are tried instead of listed because `gh run view --json artifacts`
    does not exist on every gh version, and the signed artifact packs its file
    as app-release-signed.apk, so the name inside is not predictable either.
    app-release*.apk are only ever download scratch -- fetched files are renamed
    to TapDesk-* -- so clearing them cannot destroy anything worth keeping.
    """
    os.makedirs(OUT_DIR, exist_ok=True)
    chosen = None
    src = None
    for cand in ("apk-%s-signed" % abi, "apk-%s" % abi):
        for f in os.listdir(OUT_DIR):
            if f.startswith("app-release") and f.lower().endswith(".apk"):
                os.remove(os.path.join(OUT_DIR, f))
        p = subprocess.run(["gh", "run", "download", str(run_id), "--repo", REPO,
                            "--name", cand, "--dir", OUT_DIR],
                           cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        fresh = [f for f in _apks() if os.path.basename(f).startswith("app-release")]
        if p.returncode == 0 and fresh:
            chosen, src = cand, max(fresh, key=os.path.getmtime)
            break
    if not chosen or not src:
        sys.exit("这次 run 里没有取到 APK 产物")
    version = read_version()
    stamp = datetime.datetime.now().strftime("%m%d-%H%M")
    dst = os.path.join(OUT_DIR, "TapDesk-%s-%s-%s.apk" % (version, abi.split("-")[0], stamp))
    os.replace(src, dst)
    signed = chosen.endswith("-signed")
    print("\n产物：%s  (%.1f MB, %s)" % (dst, os.path.getsize(dst) / 1048576,
                                    "release 签名" if signed else "debug 签名"))
    return dst


def read_version():
    try:
        with open(os.path.join(ROOT, "Cargo.toml"), encoding="utf-8") as f:
            for line in f:
                if line.startswith("version ="):
                    return line.split('"')[1]
    except OSError:
        pass
    return "unknown"


def adb_path():
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if sdk:
        p = os.path.join(sdk, "platform-tools", "adb.exe")
        if os.path.isfile(p):
            return p
    return "adb"


def install(apk):
    adb = adb_path()
    out = run([adb, "devices"], check=False)
    devices = [l.split("\t")[0] for l in out.splitlines()[1:] if l.strip() and "\tdevice" in l]
    if not devices:
        print("\n没检测到已连接的手机。插上数据线并允许调试后，执行：\n  %s install -r \"%s\"" % (adb, apk))
        return
    print("\n装到 %d 台设备：" % len(devices))
    for d in devices:
        run([adb, "-s", d, "install", "-r", apk])
        print("  已安装到 %s" % d)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-push", action="store_true", help="不推送本地提交，直接构建远端 master")
    ap.add_argument("--no-install", action="store_true", help="只下载 APK，不装手机")
    ap.add_argument("--abi", default="aarch64-linux-android",
                    choices=["aarch64-linux-android", "armv7-linux-androideabi", "x86_64-linux-android"])
    a = ap.parse_args()

    os.chdir(ROOT)
    if not a.no_push:
        ahead = run(["git", "rev-list", "--count", "fork/master..master"], check=False)
        if ahead.isdigit() and int(ahead) > 0:
            print("\n推送 %s 个本地提交" % ahead)
            run(["git", "push", "fork", "master"])
        else:
            print("\n本地与 fork/master 一致，跳过推送")

    before = current_run_id()
    print("\n触发构建 (%s)" % a.abi)
    run(["gh", "workflow", "run", WORKFLOW, "--repo", REPO, "--ref", "master", "-f", "abi=" + a.abi])
    run_id, waited = None, 0
    while waited < 120:
        time.sleep(5)
        waited += 5
        now = current_run_id()
        if now and now != before:
            run_id = now
            break
    if not run_id:
        sys.exit("等不到新的 run，去 Actions 页面看看")

    conclusion = wait_for_run(run_id)
    if conclusion != "success":
        report_failure(run_id)
        sys.exit("\n构建结论：%s" % conclusion)

    apk = download(run_id, a.abi)
    if not a.no_install:
        install(apk)
    print("\n完成。")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\n已取消")

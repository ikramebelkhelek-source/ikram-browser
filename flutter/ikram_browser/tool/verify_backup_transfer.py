"""Native Android configuration transfer. Only run on a CLEAN disposable emulator.

Source and destination run on separate wiped AVDs. Only public JSON documents
cross the boundary; no preferences, WebView directories or app snapshots do.
"""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import secrets
import subprocess
import tarfile
import time
import xml.etree.ElementTree as ET

TOOL = Path(__file__).resolve().parent
PACKAGE = "com.ikram.ikram_browser"
EDITOR = "com.ikram.backupeditor"
EXPORT = "تصدير إعدادات البروفايلات"
IMPORT = "استيراد إعدادات البروفايلات"
CONFIRM = "تأكيد الاستيراد"
PREVIEW = "معاينة الاستيراد"
SOURCE_NAME = "هاتف المصدر — متجر"
SECOND_NAME = "بروكسي تجريبي"


def backup_profiles(source):
    """Independent strict oracle: no browsing/session fields can be exported."""
    value = json.loads(source)
    assert set(value) == {"format", "version", "profiles"}
    assert value["format"] == "ikram-profile-configurations" and value["version"] == 1
    profiles = value["profiles"]
    assert len(profiles) == 2
    assert len({p["id"] for p in profiles}) == len(profiles)
    for profile in profiles:
        assert set(profile) == {"id", "name", "proxy", "proxyNeedsReview"}
    assert profiles[0] == dict(id="1", name=SOURCE_NAME, proxy="", proxyNeedsReview=False)
    assert profiles[1]["name"] == SECOND_NAME
    assert profiles[1]["proxy"] == "socks://192.0.2.42:1080"
    assert profiles[1]["proxyNeedsReview"] is False
    return profiles


def file_hashes(archive):
    with tarfile.open(fileobj=io.BytesIO(archive)) as files:
        return {f.name: hashlib.sha256(files.extractfile(f).read()).hexdigest()
                for f in files if f.isfile()}


def labels(node):
    return (node.get("text", "") + "\n" + node.get("content-desc", "")).splitlines()


class Device:
    def __init__(self, evidence):
        self.evidence = evidence
        self.sequence = 0

    def adb(self, *args, binary=False):
        return subprocess.check_output(["adb", *args], text=not binary, timeout=90)

    def shell(self, *args):
        return self.adb("shell", *args).strip()

    def dump(self):
        self.shell("uiautomator", "dump", "/sdcard/backup-ui.xml")
        source = self.shell("cat", "/sdcard/backup-ui.xml")
        (self.evidence / "latest-ui.xml").write_text(source)
        return ET.fromstring(source)

    def find(self, label=None, *, editable=False, resource=None, timeout=25):
        until = time.monotonic() + timeout
        while True:
            root = self.dump()
            for node in root.iter("node"):
                if ((editable and node.get("class") == "android.widget.EditText")
                    or (label is not None and label in labels(node))
                    or (resource and node.get("resource-id", "").endswith(resource))):
                    bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]",
                                          node.get("bounds", ""))
                    if bounds:
                        left, top, right, bottom = map(int, bounds.groups())
                        if right > left and bottom > top:
                            return node, ((left + right) // 2, (top + bottom) // 2)
            if time.monotonic() > until:
                raise AssertionError(f"Visible control missing: {label or resource or 'editor'}")
            time.sleep(.4)

    def tap(self, label=None, **options):
        node, point = self.find(label, **options)
        assert node.get("enabled") != "false", f"Disabled control: {label}"
        self.shell("input", "tap", *map(str, point))
        time.sleep(.4)

    def back(self):
        self.shell("input", "keyevent", "KEYCODE_BACK")
        time.sleep(.5)

    def launch(self, package=PACKAGE):
        activity = ".MainActivity" if package == PACKAGE else ".BackupEditor"
        self.shell("am", "start", "-W", "-n", f"{package}/{activity}")
        time.sleep(.7)

    def editor(self, text=None):
        self.shell("am", "force-stop", EDITOR)
        args = ["am", "start", "-W", "-n", f"{EDITOR}/.BackupEditor"]
        if text is not None:
            args += ["--es", "syntheticBase64",
                     base64.b64encode(text.encode()).decode()]
        self.shell(*args)
        self.find("EDITOR READY")

    def clipboard(self, text):
        # Writes only synthetic fixture input, via an independent foreground app.
        # Backup transfers instead use the browser Copy button and editor Open.
        self.editor(text)
        self.tap("Copy")
        self.find("COPIED")
        self.launch()

    def paste(self, *, replace=False, label=None):
        self.tap(label, editable=label is None)
        if replace:
            self.shell("input", "keycombination", "113", "29")  # Ctrl+A
        self.shell("input", "keyevent", "279")  # Android PASTE into Flutter's editor
        time.sleep(.5)
        # Hide the IME without dismissing the Flutter dialog.
        if "mInputShown=true" in self.shell("dumpsys", "input_method"):
            self.back()

    def capture(self, name):
        (self.evidence / f"{name}.xml").write_text(ET.tostring(self.dump(), encoding="unicode"))
        (self.evidence / f"{name}.png").write_bytes(self.adb("exec-out", "screencap", "-p", binary=True))

    def profiles(self):
        xml = self.shell("run-as", PACKAGE, "cat",
                         "shared_prefs/FlutterSharedPreferences.xml")
        root = ET.fromstring(xml)
        return json.loads(next(n.text for n in root if n.get("name") == "flutter.ikram_profiles"))

    def webview(self):
        return file_hashes(self.adb("exec-out", "run-as", PACKAGE, "tar", "-cf",
                                   "-", "app_webview", binary=True))

    def unchanged(self, before, webview):
        assert self.profiles() == before, "A non-committing action changed profiles"
        assert self.webview() == webview, "Backup UI changed WebView files"

    def downloads(self):
        # AOSP DocumentsUI, fixed English SYSTEM locale; Flutter remains Arabic.
        # Navigate explicitly rather than trusting the provider's recent folder.
        self.tap("Show roots", timeout=10)
        self.tap("Downloads")

    def save_document(self, name):
        self.downloads()
        self.tap(resource="/file_name")
        self.shell("input", "keycombination", "113", "29")
        self.shell("input", "text", name)
        self.tap("SAVE")

    def open_document(self, name):
        self.downloads()
        self.tap(name)

    def preview(self, *, allowed):
        self.tap(PREVIEW)
        node, _ = self.find(CONFIRM)
        assert (node.get("enabled") == "true") == allowed, "Unexpected import permission"

    def cold_start(self):
        self.shell("am", "force-stop", PACKAGE)
        self.launch()
        self.find(EXPORT)

    def probe(self, phase, token, name):
        pid = self.shell("pidof", PACKAGE).split()[0]
        self.adb("forward", "tcp:9222", f"localabstract:webview_devtools_remote_{pid}")
        until = time.monotonic() + 40
        while True:
            try:
                import urllib.request
                with urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=2) as response:
                    if json.load(response):
                        break
            except (OSError, ValueError):
                pass
            assert time.monotonic() < until, "No native WebView inspector"
            time.sleep(1)
        subprocess.run(["node", str(TOOL / "probe_webview.mjs"), phase, token,
                        str(self.evidence / f"{name}.json")], check=True)

    def open_browser(self, name):
        self.tap(name)
        self.tap("تأكيد")

    def seed_session(self, name, token):
        self.open_browser(name)
        self.probe("seed", token, "session-seed")
        # Dispose the WebView and flush persistent storage before freezing files.
        self.back()
        self.shell("input", "keyevent", "KEYCODE_HOME")
        time.sleep(35)
        self.cold_start()
        self.open_browser(name)
        self.probe("verify", token, "session-before")
        self.back()
        self.shell("input", "keyevent", "KEYCODE_HOME")
        time.sleep(35)
        self.cold_start()
        return self.webview()


def source(device, exchange):
    device.find("بروفايل 1 - شي إن")
    device.clipboard(SOURCE_NAME)
    device.tap("تعديل")
    device.paste(replace=True)
    device.tap("حفظ")
    device.find(SOURCE_NAME)
    device.clipboard(SECOND_NAME)
    device.tap("إضافة بروفايل")
    device.paste(replace=True)
    # Set proxy through the real profile editor, not direct preference writes.
    device.clipboard("socks://192.0.2.42:1080")
    device.paste(label="البروكسي (Android فقط)")
    device.tap("حفظ")
    device.find(SECOND_NAME)
    token = secrets.token_hex(16)
    webview = device.seed_session(SOURCE_NAME, token)
    before = device.profiles()
    device.tap(EXPORT)
    device.tap("حفظ ملف")
    device.back()  # Real ACTION_CREATE_DOCUMENT cancellation.
    device.capture("save-cancelled")
    device.unchanged(before, webview)
    device.tap("نسخ JSON")
    device.editor()
    device.tap("Paste")
    device.tap("Save")
    device.save_document("editor-backup.json")
    device.find("SAVED")
    device.editor()  # Editor process killed: reopen durable file, not memory.
    device.tap("Open")
    device.open_document("editor-backup.json")
    device.find("OPENED")
    device.tap("Copy")
    device.launch()
    device.tap("حفظ ملف")
    device.save_document("browser-backup.json")
    device.capture("export-saved")
    device.tap("إغلاق")
    for name in ("editor-backup.json", "browser-backup.json"):
        device.adb("pull", f"/sdcard/Download/{name}", str(exchange / name))
        text = (exchange / name).read_text()
        assert backup_profiles(text) == before
        assert token not in text
    assert (exchange / "editor-backup.json").read_bytes() == (exchange / "browser-backup.json").read_bytes()
    device.cold_start()
    device.unchanged(before, webview)
    device.open_browser(SOURCE_NAME)
    device.probe("verify", token, "session-after")
    (device.evidence / "webview-hashes.json").write_text(json.dumps(webview, indent=2))


def destination(device, exchange):
    expected = backup_profiles((exchange / "browser-backup.json").read_text())
    for name in ("browser-backup.json", "editor-backup.json"):
        device.adb("push", str(exchange / name), f"/sdcard/Download/{name}")
    token = secrets.token_hex(16)
    webview = device.seed_session("بروفايل 1 - شي إن", token)
    before = device.profiles()
    # Narrow physical display, Arabic Flutter locale/RTL, real Android IME.
    device.shell("wm", "size", "640x1280")
    device.shell("wm", "density", "320")  # 320 dp wide.
    device.cold_start()
    device.tap(IMPORT)
    device.tap("فتح ملف")
    device.back()
    device.unchanged(before, webview)
    device.capture("open-cancelled-rtl")
    device.tap("إلغاء")
    device.clipboard('{"malformed":')
    device.tap(IMPORT)
    device.paste()
    device.preview(allowed=False)
    device.capture("malformed-rtl")
    device.tap("إلغاء")
    device.unchanged(before, webview)
    # Reopened external editor -> system clipboard -> native Flutter paste.
    device.editor()
    device.tap("Open")
    device.open_document("editor-backup.json")
    device.find("OPENED")
    device.tap("Copy")
    device.launch()
    device.tap(IMPORT)
    device.paste()
    device.preview(allowed=False)  # Source ID 1 conflicts with clean default.
    device.capture("default-conflict-rtl")
    device.unchanged(before, webview)
    device.tap("إلغاء")
    device.tap("حذف")
    device.tap("تأكيد")
    assert device.profiles() == []
    assert device.webview() == webview, "Deleting default cleared website data"
    device.tap(IMPORT)
    device.paste()
    device.preview(allowed=True)
    device.capture("paste-preview-rtl")
    device.tap("إلغاء")  # A valid preview MUST NOT commit on cancellation.
    device.unchanged([], webview)
    device.cold_start()
    device.unchanged([], webview)
    # Test the browser's actual ACTION_OPEN_DOCUMENT path independently too.
    device.tap(IMPORT)
    device.tap("فتح ملف")
    device.open_document("browser-backup.json")
    node, _ = device.find(CONFIRM)
    assert node.get("enabled") == "true"
    device.unchanged([], webview)  # Opening and auto-previewing do not commit.
    device.capture("file-preview-rtl")
    device.tap(CONFIRM)
    device.find(SOURCE_NAME)
    assert device.profiles() == expected
    device.tap(IMPORT)
    device.tap("فتح ملف")
    device.open_document("browser-backup.json")
    node, _ = device.find(CONFIRM)
    assert node.get("enabled") == "false", "Repeated import must be rejected"
    device.capture("repeat-rejected-rtl")
    device.tap("إلغاء")
    device.cold_start()
    device.find(SOURCE_NAME)
    device.capture("restored-cold-start-rtl")
    device.unchanged(expected, webview)
    device.open_browser(SOURCE_NAME)
    # Must still see DESTINATION session, never the source session.
    device.probe("verify", token, "destination-session-after")
    (device.evidence / "compared-profiles.json").write_text(json.dumps(expected, ensure_ascii=False, indent=2))
    (device.evidence / "webview-hashes.json").write_text(json.dumps(webview, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["source", "destination"])
    parser.add_argument("apk", type=Path)
    parser.add_argument("editor_apk", type=Path)
    parser.add_argument("--root", type=Path, default=Path("generated-artifacts/backup-transfer"))
    args = parser.parse_args()
    evidence = args.root / args.phase
    evidence.mkdir(parents=True, exist_ok=True)
    exchange = args.root / "exchange"
    exchange.mkdir(exist_ok=True)
    device = Device(evidence)
    result = {"status": "failed", "phase": args.phase}
    try:
        assert device.shell("getprop", "ro.kernel.qemu") == "1", "Refusing personal hardware"
        for package in (PACKAGE, EDITOR):
            installed = device.shell("pm", "list", "packages", package).splitlines()
            assert f"package:{package}" not in installed, "Refusing existing installation"
        device.adb("install", str(args.apk))
        device.adb("install", str(args.editor_apk))
        (evidence / "device.txt").write_text(
            device.shell("getprop", "ro.build.fingerprint") + "\n" +
            device.shell("dumpsys", "webviewupdate"))
        device.adb("logcat", "-c")
        device.launch()
        (source if args.phase == "source" else destination)(device, exchange)
        log = device.adb("logcat", "-d")
        (evidence / "logcat.txt").write_text(log)
        assert not re.search(
            r"A RenderFlex overflowed|EXCEPTION CAUGHT BY|Another exception was thrown:|"
            r"Unhandled Exception:", log), "Flutter layout/runtime error; see logcat"
        result["status"] = "passed"
    except Exception as error:
        result["error"] = str(error)
        try:
            device.capture("failure")
            (evidence / "logcat.txt").write_text(device.adb("logcat", "-d", "-t", "500"))
        except Exception:
            pass
        raise
    finally:
        (evidence / "result.json").write_text(json.dumps(result, indent=2))
        device.adb("forward", "--remove-all")


if __name__ == "__main__":
    main()

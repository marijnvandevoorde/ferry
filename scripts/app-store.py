#!/usr/bin/env python3
"""App Store Connect chores for the Mac app, over the App Store Connect API.

    scripts/app-store.py setup          everything below in order, asking before each step
    scripts/app-store.py status         what the listing still needs before review
    scripts/app-store.py contact        set the App Review contact (asks for name, phone, email)
    scripts/app-store.py screenshots    take the screenshots against the camera emulator and upload them
    scripts/app-store.py developer-id   create the Developer ID certificate and store it as GitHub secrets
    scripts/app-store.py upload-build   turn on App Store uploads and rerun the Mac job of the latest release
    scripts/app-store.py submit         attach the newest build to the version and submit it for review

Reads the API key from ~/.appstoreconnect/config.json ({"keyId", "issuerId", "privateKey": path to the .p8}),
or from ASC_CONFIG. Needs Python's cryptography package; developer-id and upload-build also need gh.
"""
import base64
import hashlib
import json
import os
import pathlib
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "marijnvandevoorde/ferry"
BUNDLE_ID = "io.github.fujiimport.FujiImport"
PREFS = pathlib.Path.home() / "Library/Containers/io.github.fujiimport.FujiImport/Data/Library/Preferences/io.github.fujiimport.FujiImport"
HISTORY = pathlib.Path.home() / "Library/Containers/io.github.fujiimport.FujiImport/Data/Library/Application Support/FujiImport/imported.json"
SCENES = [
    "the gallery, with the emulated camera's photos listed",
    "the gallery with a few photos selected (don't import)",
    "Settings",
    "the connect screen (the script stops the emulator first, so wait until Ferry shows it)",
]

CONFIG = json.loads(pathlib.Path(os.environ.get("ASC_CONFIG", "~/.appstoreconnect/config.json")).expanduser().read_text())


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def token():
    key = serialization.load_pem_private_key(pathlib.Path(CONFIG["privateKey"]).expanduser().read_bytes(), None)
    now = int(time.time())
    header = b64(json.dumps({"alg": "ES256", "kid": CONFIG["keyId"], "typ": "JWT"}).encode())
    claims = b64(json.dumps({"iss": CONFIG["issuerId"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}).encode())
    r, s = utils.decode_dss_signature(key.sign(header + b"." + claims, ec.ECDSA(hashes.SHA256())))
    return (header + b"." + claims + b"." + b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()


def api(path, method="GET", body=None, fail=True):
    url = path if path.startswith("https:") else f"https://api.appstoreconnect.apple.com/v1/{path}"
    request = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        message = f"{method} {path}: {error.code}\n{error.read().decode()[:1000]}"
        if fail:
            sys.exit(message)
        print(message)
        return None


def app_id():
    return api(f"apps?filter[bundleId]={BUNDLE_ID}")["data"][0]["id"]


def editable_version():
    versions = api(f"apps/{app_id()}/appStoreVersions?filter[platform]=MAC_OS"
                   "&filter[appStoreState]=PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED"
                   "&include=appStoreReviewDetail,build,appStoreVersionLocalizations")
    if not versions["data"]:
        sys.exit("no version to edit: create one in App Store Connect")
    return versions["data"][0], versions.get("included", [])


def ask(question):
    return input(f"{question}: ").strip()


def status():
    version, included = editable_version()
    attrs = version["attributes"]
    print(f"Version {attrs['versionString']} ({attrs['appStoreState']})")
    review = next((i for i in included if i["type"] == "appStoreReviewDetails"), None)
    locale = next(i for i in included if i["type"] == "appStoreVersionLocalizations")
    sets = api(f"appStoreVersionLocalizations/{locale['id']}/appScreenshotSets?include=appScreenshots")
    shots = len([i for i in sets.get("included", []) if i["type"] == "appScreenshots"])
    info = api(f"apps/{app_id()}/appInfos?include=appInfoLocalizations")
    privacy = next(i for i in info["included"] if i["type"] == "appInfoLocalizations")["attributes"]["privacyPolicyUrl"]
    builds = api(f"builds?filter[app]={app_id()}&filter[preReleaseVersion.version]={attrs['versionString']}&limit=1")
    checks = [
        ("Build attached", bool(version["relationships"]["build"]["data"]),
         "uploaded, run submit" if builds["data"] else "none uploaded yet: run upload-build"),
        ("Screenshots", shots > 0, "run screenshots"),
        ("App Review contact", bool(review and review["attributes"]["contactEmail"]), "run contact"),
        ("Description", bool(locale["attributes"]["description"]), "fill in App Store Connect"),
        ("Privacy policy URL", bool(privacy), "fill in App Store Connect"),
    ]
    for name, ok, fix in checks:
        print(f"  {'ok ' if ok else 'TODO'} {name}" + ("" if ok else f": {fix}"))
    print("  ?    App Privacy (not in the API): App Store Connect → App Privacy → Data Not Collected → Publish")


def contact():
    version, included = editable_version()
    review = next((i for i in included if i["type"] == "appStoreReviewDetails"), None)
    attrs = {"contactFirstName": ask("First name"), "contactLastName": ask("Last name"),
             "contactPhone": ask("Phone, with country code (+32 ...)"), "contactEmail": ask("Email")}
    if review:
        api(f"appStoreReviewDetails/{review['id']}", "PATCH",
            {"data": {"type": "appStoreReviewDetails", "id": review["id"], "attributes": attrs}})
    else:
        api("appStoreReviewDetails", "POST", {"data": {"type": "appStoreReviewDetails", "attributes": attrs, "relationships": {
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    print("App Review contact set")


def defaults(*args):
    return subprocess.run(["defaults", *args], capture_output=True, text=True).stdout.strip()


def screenshots():
    out = pathlib.Path(tempfile.mkdtemp(prefix="ferry-screenshots-"))
    host, frame_key = defaults("read", str(PREFS), "cameraHost"), "NSWindow Frame main-AppWindow-1"
    frame = defaults("read", str(PREFS), frame_key)
    history = HISTORY.read_bytes() if HISTORY.exists() else None
    print("Building Ferry and starting the camera emulator…")
    subprocess.run(["xcodebuild", "-quiet", "-project", "Ferry.xcodeproj", "-scheme", "Ferry", "-configuration", "Debug",
                    "-derivedDataPath", ".build/xcode", "build"], cwd=ROOT, check=True)
    subprocess.run(["docker", "start", "fujikit-vcam"], capture_output=True)
    subprocess.run(["osascript", "-e", 'quit app "Ferry"'], capture_output=True)
    defaults("write", str(PREFS), "cameraHost", "127.0.0.1")
    defaults("write", str(PREFS), frame_key, "100 100 1280 800 0 0 1800 1130 ")
    subprocess.run(["open", ROOT / ".build/xcode/Build/Products/Debug/Ferry.app"])
    try:
        files = []
        for number, scene in enumerate(SCENES, 1):
            if number == len(SCENES):
                subprocess.run(["docker", "stop", "fujikit-vcam"], capture_output=True)
            input(f"\n{number}/{len(SCENES)}: show {scene}, then press Enter and click the Ferry window.")
            raw = out / f"raw-{number}.png"
            subprocess.run(["screencapture", "-W", "-o", "-x", raw], check=True)
            if not raw.exists():
                print("no capture, skipped")
                continue
            files.append(fit(raw, out / f"ferry-{number}.png"))
    finally:
        subprocess.run(["osascript", "-e", 'quit app "Ferry"'], capture_output=True)
        defaults("write", str(PREFS), "cameraHost", host)
        if frame:
            defaults("write", str(PREFS), frame_key, frame)
        if history is not None:
            HISTORY.write_bytes(history)
        subprocess.run(["docker", "stop", "fujikit-vcam"], capture_output=True)
        print(f"\nRestored Ferry's settings and import history, stopped the emulator. Screenshots: {out}")
    if files and ask("Upload them to App Store Connect, replacing the current ones? [y/N]").lower() == "y":
        upload(files)


def fit(raw, path):
    """Scales a window capture into a 2560×1600 canvas, the size the Mac App Store asks for."""
    size = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", raw], capture_output=True, text=True).stdout
    width, height = (int(line.split()[-1]) for line in size.strip().split("\n")[1:])
    scale = min(2400 / width, 1480 / height)
    subprocess.run(["sips", "-z", str(round(height * scale)), str(round(width * scale)), raw, "--out", path], capture_output=True, check=True)
    subprocess.run(["sips", "-p", "1600", "2560", "--padColor", "E9EDF2", path], capture_output=True, check=True)
    return path


def upload(files):
    _, included = editable_version()
    locale = next(i for i in included if i["type"] == "appStoreVersionLocalizations")
    sets = api(f"appStoreVersionLocalizations/{locale['id']}/appScreenshotSets?include=appScreenshots")
    desktop = next((s for s in sets["data"] if s["attributes"]["screenshotDisplayType"] == "APP_DESKTOP"), None)
    if desktop:
        for shot in desktop["relationships"]["appScreenshots"]["data"] or []:
            api(f"appScreenshots/{shot['id']}", "DELETE")
    else:
        desktop = api("appScreenshotSets", "POST", {"data": {"type": "appScreenshotSets", "attributes": {
            "screenshotDisplayType": "APP_DESKTOP"}, "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": locale["id"]}}}}})["data"]
    for file in files:
        data = pathlib.Path(file).read_bytes()
        shot = api("appScreenshots", "POST", {"data": {"type": "appScreenshots", "attributes": {
            "fileName": pathlib.Path(file).name, "fileSize": len(data)}, "relationships": {"appScreenshotSet": {
                "data": {"type": "appScreenshotSets", "id": desktop["id"]}}}}})["data"]
        for part in shot["attributes"]["uploadOperations"]:
            headers = {h["name"]: h["value"] for h in part["requestHeaders"]}
            chunk = data[part["offset"]:part["offset"] + part["length"]]
            urllib.request.urlopen(urllib.request.Request(part["url"], data=chunk, method=part["method"], headers=headers))
        api(f"appScreenshots/{shot['id']}", "PATCH", {"data": {"type": "appScreenshots", "id": shot["id"], "attributes": {
            "uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(f"uploaded {pathlib.Path(file).name}")


def developer_id():
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        subprocess.run(["/usr/bin/openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", tmp / "key.pem",
                        "-out", tmp / "req.csr", "-subj", "/CN=Ferry Developer ID"], check=True, capture_output=True)
        csr = (tmp / "req.csr").read_text()
        for kind in ["DEVELOPER_ID_APPLICATION_G2", "DEVELOPER_ID_APPLICATION"]:
            created = api("certificates", "POST", {"data": {"type": "certificates", "attributes": {
                "certificateType": kind, "csrContent": csr}}}, fail=False)
            if created:
                break
        else:
            sys.exit("Apple refused: create it in Xcode → Settings → Accounts → Manage Certificates → + → "
                     "Developer ID Application, then export it from Keychain Access (docs/releasing.md)")
        cert = created["data"]
        print(f"created {cert['attributes']['name']}, valid until {cert['attributes']['expirationDate'][:10]}")
        (tmp / "cert.der").write_bytes(base64.b64decode(cert["attributes"]["certificateContent"]))
        subprocess.run(["/usr/bin/openssl", "x509", "-inform", "der", "-in", tmp / "cert.der", "-out", tmp / "cert.pem"], check=True)
        password = secrets.token_urlsafe(24)
        subprocess.run(["/usr/bin/openssl", "pkcs12", "-export", "-inkey", tmp / "key.pem", "-in", tmp / "cert.pem",
                        "-out", tmp / "id.p12", "-passout", "env:P12_PASSWORD"], check=True, env=os.environ | {"P12_PASSWORD": password})
        for name, value in [("DEVELOPER_ID_P12", base64.b64encode((tmp / "id.p12").read_bytes()).decode()),
                            ("DEVELOPER_ID_P12_PASSWORD", password)]:
            subprocess.run(["gh", "secret", "set", name, "-R", REPO], input=value, text=True, check=True)
    print("stored DEVELOPER_ID_P12 and DEVELOPER_ID_P12_PASSWORD; the next release builds the DMG")


def upload_build():
    subprocess.run(["gh", "variable", "set", "APP_STORE_UPLOAD", "-R", REPO, "--body", "true"], check=True)
    run = json.loads(subprocess.run(["gh", "run", "list", "-R", REPO, "--workflow", "release.yml", "--event", "push",
                                     "--limit", "1", "--json", "databaseId,headBranch"], capture_output=True, text=True, check=True).stdout)[0]
    jobs = json.loads(subprocess.run(["gh", "run", "view", str(run["databaseId"]), "-R", REPO, "--json", "jobs"],
                                     capture_output=True, text=True, check=True).stdout)["jobs"]
    mac = next(job for job in jobs if job["name"] == "mac")
    subprocess.run(["gh", "run", "rerun", str(run["databaseId"]), "-R", REPO, "--job", str(mac["databaseId"])], check=True)
    print(f"rerunning the Mac job of {run['headBranch']}: it uploads the build to App Store Connect; "
          "Apple then processes it for 10 to 30 minutes")


def submit():
    version, _ = editable_version()
    number = version["attributes"]["versionString"]
    builds = api(f"builds?filter[app]={app_id()}&filter[preReleaseVersion.version]={number}"
                 "&filter[processingState]=VALID&sort=-uploadedDate&limit=1")["data"]
    if not builds:
        sys.exit(f"no processed build of {number} yet: run upload-build, then wait for Apple's email")
    build = builds[0]
    api(f"appStoreVersions/{version['id']}/relationships/build", "PATCH", {"data": {"type": "builds", "id": build["id"]}})
    print(f"attached build {build['attributes']['version']} to {number}")
    status()
    if ask(f"Submit Ferry {number} for App Review? [y/N]").lower() != "y":
        return
    submission = api("reviewSubmissions", "POST", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "MAC_OS"},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id()}}}}})["data"]
    api("reviewSubmissionItems", "POST", {"data": {"type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    api(f"reviewSubmissions/{submission['id']}", "PATCH", {"data": {"type": "reviewSubmissions", "id": submission["id"],
                                                                     "attributes": {"submitted": True}}})
    print("submitted for review")


def setup():
    for name, step in [("Create the Developer ID certificate", developer_id), ("Upload the build", upload_build),
                       ("Set the App Review contact", contact), ("Take and upload the screenshots", screenshots)]:
        if ask(f"\n{name}? [Y/n]").lower() in ("", "y"):
            try:
                step()
            except SystemExit as stop:
                print(f"{name} failed: {stop}")
    print("\nIn App Store Connect → App Privacy, choose Data Not Collected and Publish. Then, once Apple emails that "
          "the build is processed: scripts/app-store.py submit\n")
    status()


COMMANDS = {"setup": setup, "status": status, "contact": contact, "screenshots": screenshots, "developer-id": developer_id,
            "upload-build": upload_build, "submit": submit}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    os.chdir(ROOT)
    COMMANDS[sys.argv[1]]()

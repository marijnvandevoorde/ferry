#!/usr/bin/env python3
"""Releases Ferry everywhere it ships, so no platform or store is forgotten.

    scripts/release.py 0.2.2           bump, tag, wait for the release build, then update the site and packages
    scripts/release.py 0.2.2 --after   only the steps after the release build (to resume after an interruption)
    scripts/release.py --check         check that every file names the same version (runs in CI)

Needs git and gh, signed in with push access to the repository and the Homebrew tap. See docs/releasing.md.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "marijnvandevoorde/ferry"
TAP = "marijnvandevoorde/homebrew-ferry"
FLATHUB_REPO = "flathub/io.github.marijnvandevoorde.Ferry"

# Every file that names the app version, with the pattern whose group 1 is the version.
VERSION_FILES = {
    "project.yml": r'MARKETING_VERSION: "([^"]+)"',
    "apps/desktop/package.json": r'"version": "([^"]+)"',
    "apps/desktop/src-tauri/tauri.conf.json": r'"version": "([^"]+)"',
    "apps/desktop/src-tauri/Cargo.toml": r'^version = "([^"]+)"',
    "Sources/ferryctl/main.swift": r'let version = "([^"]+)"',
}
# Files updated after the release build, once its downloads exist.
PACKAGE_FILES = {
    "site/site.json": r'"version": "([^"]+)"',
    "packaging/homebrew/ferryctl.rb": r'archive/refs/tags/v([^/"]+)\.tar\.gz',
    "packaging/flathub/io.github.marijnvandevoorde.Ferry.yml": r'releases/download/v([^/]+)/',
}
# What the release build must attach.
ASSETS = ["Ferry-{v}.dmg", "Ferry_{v}_x64-setup.exe", "Ferry_{v}_x64_en-US.msi", "Ferry_{v}_amd64.AppImage",
          "Ferry_{v}_amd64.AppImage.asc", "Ferry_{v}_amd64.deb", "Ferry_{v}_amd64.deb.asc"]


def run(*args, cwd=ROOT, capture=True):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=capture)
    if result.returncode != 0:
        sys.exit(f"failed: {' '.join(args)}\n{result.stderr if capture else ''}")
    return result.stdout.strip() if capture else ""


def step(message):
    print(f"\n==> {message}", flush=True)


def versions(files):
    found = {}
    for path, pattern in files.items():
        match = re.search(pattern, (ROOT / path).read_text(), re.M)
        found[path] = match.group(1) if match else None
    return found


def replace(path, pattern, version):
    file = ROOT / path
    text = file.read_text()
    new = re.sub(pattern, lambda m: m.group(0).replace(m.group(1), version), text, count=1, flags=re.M)
    file.write_text(new)


def sha256(url):
    with urllib.request.urlopen(url) as response:
        return hashlib.sha256(response.read()).hexdigest()


def check():
    found = versions(VERSION_FILES) | versions(PACKAGE_FILES)
    if len(set(found.values())) != 1:
        for path, version in found.items():
            print(f"{version}\t{path}")
        sys.exit("the files above don't all name the same version")
    print(f"all files name {next(iter(found.values()))}")


def clean_main():
    step("Checking the repository")
    if run("git", "branch", "--show-current") != "main":
        sys.exit("release from main")
    if run("git", "status", "--porcelain"):
        sys.exit("commit or stash your changes first")
    run("git", "fetch", "-q", "origin", "main", "--tags")
    if run("git", "rev-parse", "HEAD") != run("git", "rev-parse", "origin/main"):
        sys.exit("main isn't the same as origin/main: pull or push first")


def preflight(version):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        sys.exit("give the version as 1.2.3")
    if run("git", "tag", "-l", f"v{version}"):
        sys.exit(f"v{version} already exists")
    current = versions(VERSION_FILES)["project.yml"]
    if tuple(map(int, version.split("."))) <= tuple(map(int, current.split("."))):
        sys.exit(f"{version} isn't newer than {current}")
    head = run("git", "rev-parse", "HEAD")
    ci = json.loads(run("gh", "run", "list", "-R", REPO, "--workflow", "ci.yml", "--commit", head,
                        "--json", "status,conclusion"))
    if not ci or ci[0]["conclusion"] != "success":
        sys.exit("CI hasn't passed on this commit yet")


def bump_and_tag(version):
    step(f"Setting the version to {version}")
    for path, pattern in VERSION_FILES.items():
        replace(path, pattern, version)
    run("cargo", "update", "-q", "-p", "ferry", "--offline", cwd=ROOT / "apps/desktop/src-tauri")
    run("git", "commit", "-q", "-m", f"Release {version}", *VERSION_FILES, "apps/desktop/src-tauri/Cargo.lock")
    run("git", "push", "-q", "origin", "main")
    step(f"Tagging v{version}")
    run("git", "tag", f"v{version}")
    run("git", "push", "-q", "origin", f"v{version}")


def wait_for(workflow, commit):
    for _ in range(30):
        runs = json.loads(run("gh", "run", "list", "-R", REPO, "--workflow", workflow, "--commit", commit,
                              "--limit", "1", "--json", "databaseId"))
        if runs:
            break
        time.sleep(10)
    else:
        sys.exit(f"the {workflow} workflow didn't start for {commit[:7]}")
    run_id = str(runs[0]["databaseId"])
    print(f"waiting for https://github.com/{REPO}/actions/runs/{run_id}", flush=True)
    if subprocess.run(["gh", "run", "watch", run_id, "-R", REPO, "--exit-status"], cwd=ROOT,
                      capture_output=True).returncode != 0:
        sys.exit(f"the {workflow} workflow failed: gh run view {run_id} -R {REPO} --log-failed")


def check_assets(version):
    step("Checking the release downloads")
    names = run("gh", "release", "view", f"v{version}", "-R", REPO, "--json", "assets", "-q", ".assets[].name")
    missing = [a.format(v=version) for a in ASSETS if a.format(v=version) not in names.split("\n")]
    if missing:
        sys.exit("missing from the release: " + ", ".join(missing))


def update_packages(version):
    step("Updating the site, Homebrew formula and Flathub manifest")
    download = f"https://github.com/{REPO}/releases/download/v{version}"

    site = ROOT / "site/site.json"
    site.write_text(site.read_text().replace(versions(PACKAGE_FILES)["site/site.json"], version))

    formula = ROOT / "packaging/homebrew/ferryctl.rb"
    replace("packaging/homebrew/ferryctl.rb", PACKAGE_FILES["packaging/homebrew/ferryctl.rb"], version)
    tarball = sha256(f"https://github.com/{REPO}/archive/refs/tags/v{version}.tar.gz")
    formula.write_text(re.sub(r'sha256 "[0-9a-f]+"', f'sha256 "{tarball}"', formula.read_text(), count=1))

    manifest = ROOT / "packaging/flathub/io.github.marijnvandevoorde.Ferry.yml"
    deb = sha256(f"{download}/Ferry_{version}_amd64.deb")
    text = re.sub(r"releases/download/v[^/]+/Ferry_[^_]+_amd64\.deb", f"releases/download/v{version}/Ferry_{version}_amd64.deb",
                  manifest.read_text())
    manifest.write_text(re.sub(r"(Ferry_[^_]+_amd64\.deb\n\s+sha256: )[0-9a-f]+", rf"\g<1>{deb}", text))

    metainfo = ROOT / "packaging/flathub/io.github.marijnvandevoorde.Ferry.metainfo.xml"
    text = metainfo.read_text()
    if f'release version="{version}"' not in text:
        today = datetime.date.today().isoformat()
        entry = (f'    <release version="{version}" date="{today}">\n'
                 f'      <url type="details">https://github.com/{REPO}/releases/tag/v{version}</url>\n'
                 f'    </release>\n')
        metainfo.write_text(text.replace("  <releases>\n", "  <releases>\n" + entry, 1))

    check()
    files = [*PACKAGE_FILES, "packaging/flathub/io.github.marijnvandevoorde.Ferry.metainfo.xml"]
    if not run("git", "status", "--porcelain", *files):
        print("already up to date")
        return None
    run("python3", "site/tools/build.py")
    run("git", "commit", "-q", "-m", f"Site and packages: {version}", *files)
    run("git", "push", "-q", "origin", "main")
    print("pushed: this deploys the site")
    return run("git", "rev-parse", "HEAD")


def update_tap(version):
    step(f"Updating the Homebrew tap ({TAP})")
    with tempfile.TemporaryDirectory() as tmp:
        tap = pathlib.Path(tmp) / "tap"
        run("gh", "repo", "clone", TAP, str(tap), "--", "-q")
        (tap / "Formula/ferryctl.rb").write_text((ROOT / "packaging/homebrew/ferryctl.rb").read_text())
        if run("git", "status", "--porcelain", cwd=tap):
            run("git", "commit", "-q", "-am", f"ferryctl {version}", cwd=tap)
            run("git", "push", "-q", cwd=tap)
        else:
            print("already up to date")


def check_site(version, commit):
    step("Checking the live site")
    wait_for("site.yml", commit)
    with urllib.request.urlopen(json.loads((ROOT / "site/site.json").read_text())["origin"]) as response:
        page = response.read().decode()
    if f"Ferry_{version}_" not in page:
        sys.exit("the live site doesn't link the new downloads yet")
    print("the site links the new downloads")


def by_hand(version):
    step("Left to do by hand")
    todo = []
    upload = subprocess.run(["gh", "variable", "get", "APP_STORE_UPLOAD", "-R", REPO], capture_output=True, text=True)
    if upload.stdout.strip() == "true":
        todo.append(f"Mac App Store: build {version} was uploaded. In App Store Connect, add it to a new version "
                    "and submit it for review.")
    else:
        todo.append("Mac App Store: nothing uploaded, APP_STORE_UPLOAD isn't true.")
    if subprocess.run(["gh", "repo", "view", FLATHUB_REPO], capture_output=True).returncode == 0:
        todo.append(f"Flathub: open a PR on {FLATHUB_REPO} with the files in packaging/flathub.")
    else:
        todo.append("Flathub: the app isn't on Flathub yet (submission pending), nothing to update.")
    todo.append("Microsoft Store: not set up yet.")
    for line in todo:
        print(f"- {line}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("version", nargs="?")
    parser.add_argument("--after", action="store_true", help="only the steps after the release build")
    parser.add_argument("--check", action="store_true", help="check that every file names the same version")
    args = parser.parse_args()
    if args.check:
        return check()
    if not args.version:
        parser.error("give the version to release")
    clean_main()
    if not args.after:
        preflight(args.version)
        bump_and_tag(args.version)
    step("Waiting for the release build")
    wait_for("release.yml", run("git", "rev-list", "-n", "1", f"v{args.version}"))
    check_assets(args.version)
    site_commit = update_packages(args.version)
    update_tap(args.version)
    if site_commit and "site/site.json" in run("git", "diff", "--name-only", f"{site_commit}~1", site_commit):
        check_site(args.version, site_commit)
    by_hand(args.version)


if __name__ == "__main__":
    main()

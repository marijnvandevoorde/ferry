// Builds fujictl in release mode and copies it to where Tauri expects its sidecar:
// src-tauri/binaries/fujictl-<target triple>[.exe]
import { execSync } from "node:child_process";
import { copyFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dirname, "..", "..", "..");
const triple = execSync("rustc --print host-tuple").toString().trim();
const ext = process.platform === "win32" ? ".exe" : "";
const staticStdlib = process.platform === "linux" ? " --static-swift-stdlib" : "";

execSync(`swift build -c release --product fujictl${staticStdlib}`, { cwd: root, stdio: "inherit" });
const bin = execSync("swift build -c release --show-bin-path", { cwd: root }).toString().trim();
mkdirSync(join(import.meta.dirname, "..", "src-tauri", "binaries"), { recursive: true });
copyFileSync(join(bin, `fujictl${ext}`), join(import.meta.dirname, "..", "src-tauri", "binaries", `fujictl-${triple}${ext}`));
console.log(`sidecar ready: fujictl-${triple}${ext}`);

// The license notices the bundle ships (docs/licenses.md).
const python = process.platform === "win32" ? "python" : "python3";
execSync(`${python} scripts/third_party_notices.py`, { cwd: root, stdio: "inherit" });

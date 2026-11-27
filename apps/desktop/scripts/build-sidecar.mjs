// Builds ferryctl in release mode and copies it to where Tauri expects its sidecar:
// src-tauri/binaries/ferryctl-<target triple>[.exe]
import { execSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { basename, join } from "node:path";
import { dllImports } from "./pe-imports.mjs";

const root = join(import.meta.dirname, "..", "..", "..");
const binaries = join(import.meta.dirname, "..", "src-tauri", "binaries");
const triple = execSync("rustc --print host-tuple").toString().trim();
const ext = process.platform === "win32" ? ".exe" : "";
const staticStdlib = process.platform === "linux" ? " --static-swift-stdlib" : "";

execSync(`swift build -c release --product ferryctl${staticStdlib}`, { cwd: root, stdio: "inherit" });
const bin = execSync("swift build -c release --show-bin-path", { cwd: root }).toString().trim();
mkdirSync(binaries, { recursive: true });
const sidecar = join(binaries, `ferryctl-${triple}${ext}`);
copyFileSync(join(bin, `ferryctl${ext}`), sidecar);
console.log(`sidecar ready: ferryctl-${triple}${ext}`);

// On Windows ferryctl links the Swift runtime and Foundation as DLLs, which only a Swift install has.
// Copy them, and the Visual C++ runtime they need, to binaries/windows-runtime; tauri.windows.conf.json
// installs them next to ferryctl.exe.
if (process.platform === "win32") {
  const out = join(binaries, "windows-runtime");
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out);
  for (const dll of windowsRuntime(sidecar)) copyFileSync(dll, join(out, basename(dll)));
  console.log(`windows runtime ready: ${readdirSync(out).join(", ")}`);
}

// The license notices the bundle ships (docs/licenses.md).
const python = process.platform === "win32" ? "python" : "python3";
execSync(`${python} scripts/third_party_notices.py`, { cwd: root, stdio: "inherit" });

// Every DLL the executable needs, directly or through another DLL, that doesn't come with Windows.
function windowsRuntime(exe) {
  const path = Object.entries(process.env).find(([key]) => key.toLowerCase() === "path")?.[1] ?? "";
  const swift = path.split(";").find((dir) => dir && existsSync(join(dir, "swiftCore.dll")));
  if (!swift) throw new Error("swiftCore.dll isn't on PATH: is Swift installed?");
  const vc = [visualCppRedist(), join(process.env.SystemRoot ?? "C:\\Windows", "System32")].filter(Boolean);
  const found = new Map();
  const queue = [exe];
  while (queue.length) {
    for (const name of dllImports(queue.pop())) {
      if (found.has(name.toLowerCase())) continue;
      const dirs = /^(vcruntime|msvcp|concrt)140/i.test(name) ? vc : [swift];
      const dir = dirs.find((d) => existsSync(join(d, name)));
      if (!dir) continue; // part of Windows
      found.set(name.toLowerCase(), join(dir, name));
      queue.push(join(dir, name));
    }
  }
  return [...found.values()];
}

// The Visual C++ runtime Visual Studio ships for redistribution, e.g. VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT.
function visualCppRedist() {
  const vswhere = join(process.env["ProgramFiles(x86)"] ?? "", "Microsoft Visual Studio", "Installer", "vswhere.exe");
  if (!existsSync(vswhere)) return null;
  const vs = execSync(`"${vswhere}" -latest -products * -property installationPath`).toString().trim();
  const msvc = join(vs, "VC", "Redist", "MSVC");
  if (!vs || !existsSync(msvc)) return null;
  const arch = process.arch === "arm64" ? "arm64" : "x64";
  for (const version of readdirSync(msvc).filter((v) => /^\d/.test(v)).sort().reverse()) {
    const dir = join(msvc, version, arch);
    const crt = existsSync(dir) && readdirSync(dir).find((d) => /^Microsoft\.VC\d+\.CRT$/.test(d));
    if (crt) return join(dir, crt);
  }
  return null;
}

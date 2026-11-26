// Windows: checks that the ferryctl sidecar starts with only what ships with Ferry, as on a PC without Swift.
//   node scripts/check-sidecar.mjs <folder with ferryctl.exe | Ferry .msi>
// An .msi is unpacked first (an administrative install, which changes nothing on the machine).
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

let dir = process.argv[2];
if (!dir) throw new Error("usage: node scripts/check-sidecar.mjs <folder | .msi>");
if (dir.toLowerCase().endsWith(".msi")) {
  const target = mkdtempSync(join(tmpdir(), "ferry-msi-"));
  const unpack = spawnSync("msiexec", ["/a", resolve(dir), "/qn", `TARGETDIR=${target}`], { stdio: "inherit" });
  if (unpack.status !== 0) throw new Error(`msiexec /a failed (${unpack.status})`);
  dir = find(target, "ferryctl.exe");
  if (!dir) throw new Error(`no ferryctl.exe in ${process.argv[2]}`);
}
const exe = join(dir, "ferryctl.exe");
if (!existsSync(exe)) throw new Error(`no ferryctl.exe in ${dir}`);

// Keep only Windows' own folders on PATH, so the Swift install on this machine can't fill in missing DLLs.
const windows = process.env.SystemRoot ?? "C:\\Windows";
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => key.toLowerCase() !== "path"));
env.Path = `${join(windows, "System32")};${windows}`;
const run = spawnSync(exe, ["--version"], { env, encoding: "utf8" });
if (run.status !== 0) {
  // 0xC0000135: STATUS_DLL_NOT_FOUND
  const why = run.status === 0xc0000135 ? "a DLL it needs isn't installed next to it" : `exit status ${run.status}`;
  console.error(`${exe} doesn't start: ${why}\n${run.stdout ?? ""}${run.stderr ?? ""}`);
  process.exit(1);
}
console.log(`${exe} starts without Swift: ${run.stdout.trim()}`);

function find(folder, file) {
  for (const entry of readdirSync(folder, { withFileTypes: true })) {
    const path = join(folder, entry.name);
    if (entry.isFile() && entry.name.toLowerCase() === file) return folder;
    if (entry.isDirectory()) {
      const found = find(path, file);
      if (found) return found;
    }
  }
  return null;
}

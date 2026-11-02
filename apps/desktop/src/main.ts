import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { join, pictureDir } from "@tauri-apps/api/path";
import { listen } from "@tauri-apps/api/event";
import { disable as disableAutostart, enable as enableAutostart, isEnabled as autostartEnabled } from "@tauri-apps/plugin-autostart";
import { open } from "@tauri-apps/plugin-dialog";
import { open as openPath } from "@tauri-apps/plugin-shell";
import { t, translatePage } from "./i18n";
import { isPermissionGranted, requestPermission, sendNotification } from "@tauri-apps/plugin-notification";

// Events from `fujictl serve` (see Sources/fujictl/Serve.swift).
type Item = { id: string; filename: string; date: string; isVideo: boolean; kind: string; protected: boolean; size: number; imported: boolean };
type ServeEvent =
  | { event: "status"; phase: "searching" | "connecting" | "waitingForApproval" | "connected"; camera?: string; address?: string }
  | { event: "items"; items: Item[] }
  | { event: "thumbnail"; id: string; path: string }
  | { event: "progress"; index: number; total: number; filename: string; fraction: number; bytes: number; totalBytes: number }
  | { event: "imported"; id: string; path: string }
  | { event: "done"; imported: number; failed: string[]; cancelled: boolean }
  | { event: "error"; message: string }
  | { event: "log"; line: string };

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

// Settings live in the webview's storage; they only matter to this computer.
const settings = {
  get folder() { return localStorage.getItem("folder") ?? ""; },
  set folder(v: string) { localStorage.setItem("folder", v); },
  get folders() { return localStorage.getItem("folders") ?? "{yyyy}/{yyyy-MM-dd}"; },
  set folders(v: string) { localStorage.setItem("folders", v); },
  get rename() { return localStorage.getItem("rename") ?? ""; },
  set rename(v: string) { localStorage.setItem("rename", v); },
  get autoImport() { return localStorage.getItem("autoImport") === "true"; },
  set autoImport(v: boolean) { localStorage.setItem("autoImport", String(v)); },
  get skipVideos() { return localStorage.getItem("skipVideos") === "true"; },
  get immichServer() { return localStorage.getItem("immichServer") ?? ""; },
  set immichServer(v: string) { localStorage.setItem("immichServer", v); },
  get immichKey() { return localStorage.getItem("immichKey") ?? ""; },
  set immichKey(v: string) { localStorage.setItem("immichKey", v); },
  get immichAlbum() { return localStorage.getItem("immichAlbum") ?? ""; },
  set immichAlbum(v: string) { localStorage.setItem("immichAlbum", v); },
  set skipVideos(v: boolean) { localStorage.setItem("skipVideos", String(v)); },
};

const state = {
  phase: "searching" as string,
  camera: "",
  items: [] as Item[],
  thumbnails: new Map<string, string>(),
  selection: new Set<string>(),
  importing: false,
  lastError: "",
  importStarted: 0,
};

/** Filters shown in the toolbar; "Import New" imports what they show. */
function matchesFilters(item: Item): boolean {
  const kind = $<HTMLSelectElement>("kind").value;
  return (!kind || item.kind === kind) && ($<HTMLSelectElement>("filter").value !== "protected" || item.protected);
}

function formatBytes(n: number): string {
  const units = ["B", "KB", "MB", "GB"];
  let i = 0;
  while (n >= 1000 && i < units.length - 1) { n /= 1000; i++; }
  return `${n.toFixed(i ? 1 : 0)} ${units[i]}`;
}

const send = (command: Record<string, unknown>) => invoke("send", { command });

function itemsToImport(): Item[] {
  return state.items.filter((i) => !i.imported && !(settings.skipVideos && i.isVideo) && matchesFilters(i));
}

function startImport(ids?: string[]) {
  if (!settings.folder) {
    openSettings();
    showError(t("Choose a folder to import into first."));
    return;
  }
  state.importing = true;
  state.importStarted = Date.now();
  $("show-folder").hidden = true;
  const immich = settings.immichServer && settings.immichKey
    ? { server: settings.immichServer, apiKey: settings.immichKey, album: settings.immichAlbum }
    : undefined;
  send({ cmd: "import", ids, folder: settings.folder, folders: settings.folders, rename: settings.rename, skipVideos: settings.skipVideos, immich });
  render();
}

async function notify(title: string, body: string) {
  if (document.hasFocus()) return;
  let granted = await isPermissionGranted();
  if (!granted) granted = (await requestPermission()) === "granted";
  if (granted) sendNotification({ title, body });
}

function showError(message: string) {
  state.lastError = message;
  const el = $<HTMLParagraphElement>("error");
  el.textContent = message;
  el.hidden = !message;
  if (message && state.phase === "connected") $("status").textContent = message;
}

// MARK: - Events

listen<ServeEvent>("fujictl", ({ payload: e }) => {
  switch (e.event) {
    case "status": {
      const wasConnected = state.phase === "connected";
      state.phase = e.phase;
      if (e.camera) state.camera = e.camera;
      if (e.phase === "connected") showError("");
      if (e.phase === "searching" && wasConnected) {
        state.items = [];
        state.selection.clear();
        state.importing = false;
      }
      $("connect-subtitle").textContent =
        e.phase === "connecting" ? t("Talking to the camera at {address}…", { address: e.address ?? "" }) :
        e.phase === "waitingForApproval" ? t("Press OK on the camera to allow this computer.") :
        t("Looking for the camera on your Wi-Fi network…");
      break;
    }
    case "items": {
      const firstList = state.items.length === 0;
      state.items = e.items.sort((a, b) => b.date.localeCompare(a.date) || b.filename.localeCompare(a.filename));
      const known = new Set(state.items.map((i) => i.id));
      state.selection.forEach((id) => known.has(id) || state.selection.delete(id));
      const fresh = itemsToImport();
      if (firstList && fresh.length > 0) {
        if (settings.autoImport) startImport();
        else notify(state.camera || t("Camera connected"), t("{n} new items to import", { n: fresh.length }, fresh.length));
      }
      break;
    }
    case "thumbnail":
      state.thumbnails.set(e.id, convertFileSrc(e.path));
      break;
    case "progress":
      {
        let text = t("Importing {file} — {index} of {total}", { file: e.filename, index: e.index, total: e.total });
        const seconds = (Date.now() - state.importStarted) / 1000;
        if (seconds > 2 && e.bytes > 0) {
          const speed = e.bytes / seconds;
          const left = Math.max(0, (e.totalBytes - e.bytes) / speed);
          const leftText = left >= 3600 ? `${Math.round(left / 3600)} h` : left >= 60 ? `${Math.round(left / 60)} min` : `${Math.ceil(left)} s`;
          text += " · " + t("{speed}/s · {left} left", { speed: formatBytes(speed), left: leftText });
        }
        $("status").textContent = text;
        $<HTMLProgressElement>("progress").value = e.totalBytes ? e.bytes / e.totalBytes : (e.index - 1 + e.fraction) / Math.max(e.total, 1);
      }
      return; // no full re-render for progress
    case "imported": {
      const item = state.items.find((i) => i.id === e.id);
      if (item) item.imported = true;
      state.selection.delete(e.id);
      break;
    }
    case "done": {
      state.importing = false;
      let summary = t("Imported {n} items", { n: e.imported }, e.imported);
      if (e.cancelled) summary += t(" (stopped)");
      if (e.failed.length) summary += t(". {n} failed: {list}", { n: e.failed.length, list: e.failed.slice(0, 3).join(", ") });
      render();
      $("status").textContent = summary;
      $("show-folder").hidden = e.imported === 0;
      notify(t("Import finished"), summary);
      return;
    }
    case "error":
      state.importing = false;
      showError(e.message);
      break;
    case "log":
      console.debug(e.line);
      return;
  }
  render();
});

// MARK: - Rendering

function render() {
  const connected = state.phase === "connected";
  $("connect").hidden = connected;
  $("gallery").hidden = !connected;
  $("bar").hidden = !connected;
  $("disconnect").hidden = !connected;
  for (const id of ["filter", "kind", "order", "thumb-size"]) $(id).hidden = !connected;
  $("title").textContent = connected ? state.camera || t("Camera") : "Fuji Import";
  const newCount = state.items.filter((i) => !i.imported).length;
  $("subtitle").textContent = connected ? t("{n} items · {m} not imported", { n: state.items.length, m: newCount }) : "";
  $<HTMLButtonElement>("connect-now").disabled = state.phase !== "searching";
  if (!connected) return;

  // Footer
  const toImport = itemsToImport();
  $("progress").hidden = !state.importing;
  $("stop").hidden = !state.importing;
  const selected = $<HTMLButtonElement>("import-selected");
  selected.hidden = state.importing || state.selection.size === 0;
  selected.textContent = t("Import {n} Selected", { n: state.selection.size });
  const importNew = $<HTMLButtonElement>("import-new");
  importNew.hidden = state.importing;
  importNew.disabled = toImport.length === 0;
  importNew.textContent = toImport.length ? t("Import {n} New", { n: toImport.length }) : t("No New Items");
  if (!state.importing && !state.lastError) $("status").textContent = settings.folder ? t("Importing into {folder}", { folder: settings.folder }) : t("No import folder chosen");

  // Gallery, grouped by day
  const filter = $<HTMLSelectElement>("filter").value;
  const oldestFirst = $<HTMLSelectElement>("order").value === "oldest";
  const visible = (filter === "new" ? state.items.filter((i) => !i.imported) : state.items)
    .filter(matchesFilters)
    .slice()
    .sort((a, b) => (oldestFirst ? 1 : -1) * (a.date.localeCompare(b.date) || a.filename.localeCompare(b.filename)));
  const gallery = $("gallery");
  gallery.replaceChildren();
  if (visible.length === 0) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.style.textAlign = "center";
    empty.style.marginTop = "120px";
    empty.textContent = filter === "new" ? t("Everything is imported.") : t("No photos on the card.");
    gallery.append(empty);
    return;
  }
  const days = new Map<string, Item[]>();
  for (const item of visible) {
    const day = item.date ? new Date(item.date).toDateString() : "unknown";
    days.set(day, [...(days.get(day) ?? []), item]);
  }
  for (const [day, items] of days) {
    const header = document.createElement("div");
    header.className = "day";
    const label = document.createElement("span");
    label.textContent = day === "unknown" ? t("Unknown date") : new Date(day).toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long", year: "numeric" });
    const all = items.every((i) => state.selection.has(i.id));
    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.textContent = all ? t("Deselect") : t("Select");
    toggle.onclick = () => {
      items.forEach((i) => (all ? state.selection.delete(i.id) : state.selection.add(i.id)));
      render();
    };
    header.append(label, toggle);

    const grid = document.createElement("div");
    grid.className = "grid";
    for (const item of items) {
      const cell = document.createElement("button");
      cell.type = "button";
      cell.className = "cell" + (item.imported ? " imported" : "") + (state.selection.has(item.id) ? " selected" : "");
      cell.setAttribute("aria-pressed", String(state.selection.has(item.id)));
      cell.setAttribute("aria-label", `${item.isVideo ? t("Video") : t("Photo")} ${item.filename}${item.imported ? t(", imported") : ""}`);
      cell.title = `${item.filename}\n${item.date ? new Date(item.date).toLocaleString() : ""}`;
      const src = state.thumbnails.get(item.id);
      if (src) {
        const img = document.createElement("img");
        img.src = src;
        img.alt = "";
        cell.append(img);
      }
      const name = document.createElement("span");
      name.className = "name";
      name.textContent = item.filename;
      cell.append(name);
      if (item.imported || item.isVideo || item.protected) {
        const badge = document.createElement("span");
        badge.className = "badge";
        badge.textContent = [item.protected ? "🔒" : "", item.imported ? t("Imported") : "", item.isVideo ? t("Video") : ""].filter(Boolean).join(" · ");
        cell.append(badge);
      }
      cell.onclick = () => {
        state.selection.has(item.id) ? state.selection.delete(item.id) : state.selection.add(item.id);
        render();
      };
      grid.append(cell);
    }
    gallery.append(header, grid);
  }
}

// MARK: - Controls

function openSettings() {
  $<HTMLInputElement>("folder").value = settings.folder;
  $<HTMLSelectElement>("folders").value = settings.folders;
  $<HTMLInputElement>("rename").value = settings.rename;
  $<HTMLInputElement>("auto-import").checked = settings.autoImport;
  $<HTMLInputElement>("skip-videos").checked = settings.skipVideos;
  $<HTMLInputElement>("immich-server").value = settings.immichServer;
  $<HTMLInputElement>("immich-key").value = settings.immichKey;
  $<HTMLInputElement>("immich-album").value = settings.immichAlbum;
  autostartEnabled().then((on) => ($<HTMLInputElement>("autostart").checked = on)).catch(() => {});
  $<HTMLDialogElement>("settings").showModal();
}

$("connect-now").onclick = () => {
  showError("");
  send({ cmd: "connect" });
};
$("disconnect").onclick = () => send({ cmd: "disconnect" });
$("filter").onchange = render;
$("kind").onchange = render;
$("order").onchange = render;
$<HTMLInputElement>("thumb-size").value = localStorage.getItem("thumbSize") ?? "160";
const applyThumbSize = () => {
  const size = $<HTMLInputElement>("thumb-size").value;
  document.documentElement.style.setProperty("--thumb", `${size}px`);
  localStorage.setItem("thumbSize", size);
};
$("thumb-size").oninput = applyThumbSize;
applyThumbSize();
$("show-folder").onclick = () => settings.folder && openPath(settings.folder);
$("import-new").onclick = () => startImport();
$("import-selected").onclick = () => startImport([...state.selection]);
$("stop").onclick = () => send({ cmd: "cancel" });
$("settings-button").onclick = openSettings;
function setFolder(folder: string) {
  settings.folder = folder;
  $<HTMLInputElement>("folder").value = folder;
  showError("");
  render();
}
async function chooseFolder(title: string) {
  const folder = await open({ directory: true, title });
  if (typeof folder === "string") setFolder(folder);
}
$("choose-folder").onclick = () => chooseFolder(t("Choose where to put imported photos"));
// Windows Photos/OneDrive (Windows) and Shotwell/GNOME Photos (Linux) index the Pictures folder.
$("preset-pictures").onclick = async () => setFolder(await join(await pictureDir(), "Camera Imports"));
$("preset-watched").onclick = async () => {
  await chooseFolder(t("Choose the folder Lightroom, Photoshop Elements, digiKam or darktable watches"));
  $<HTMLSelectElement>("folders").value = settings.folders = "";
};
$("folders").onchange = (e) => (settings.folders = (e.target as HTMLSelectElement).value);
$("rename").onchange = (e) => (settings.rename = (e.target as HTMLInputElement).value.trim());
$("auto-import").onchange = (e) => (settings.autoImport = (e.target as HTMLInputElement).checked);
$("skip-videos").onchange = (e) => {
  settings.skipVideos = (e.target as HTMLInputElement).checked;
  render();
};
$("immich-server").onchange = (e) => (settings.immichServer = (e.target as HTMLInputElement).value.trim());
$("immich-key").onchange = (e) => (settings.immichKey = (e.target as HTMLInputElement).value.trim());
$("immich-album").onchange = (e) => (settings.immichAlbum = (e.target as HTMLInputElement).value.trim());
$("autostart").onchange = (e) => ((e.target as HTMLInputElement).checked ? enableAutostart() : disableAutostart());
$("settings").addEventListener("close", render);

translatePage();
render();

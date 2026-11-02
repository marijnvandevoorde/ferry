import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { join, pictureDir } from "@tauri-apps/api/path";
import { listen } from "@tauri-apps/api/event";
import { disable as disableAutostart, enable as enableAutostart, isEnabled as autostartEnabled } from "@tauri-apps/plugin-autostart";
import { open } from "@tauri-apps/plugin-dialog";
import { isPermissionGranted, requestPermission, sendNotification } from "@tauri-apps/plugin-notification";

// Events from `fujictl serve` (see Sources/fujictl/Serve.swift).
type Item = { id: string; filename: string; date: string; isVideo: boolean; size: number; imported: boolean };
type ServeEvent =
  | { event: "status"; phase: "searching" | "connecting" | "waitingForApproval" | "connected"; camera?: string; address?: string }
  | { event: "items"; items: Item[] }
  | { event: "thumbnail"; id: string; path: string }
  | { event: "progress"; index: number; total: number; filename: string; fraction: number }
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
};

const send = (command: Record<string, unknown>) => invoke("send", { command });

function itemsToImport(): Item[] {
  return state.items.filter((i) => !i.imported && !(settings.skipVideos && i.isVideo));
}

function startImport(ids?: string[]) {
  if (!settings.folder) {
    openSettings();
    showError("Choose a folder to import into first.");
    return;
  }
  state.importing = true;
  send({ cmd: "import", ids, folder: settings.folder, folders: settings.folders, rename: settings.rename, skipVideos: settings.skipVideos });
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
        e.phase === "connecting" ? `Talking to the camera at ${e.address ?? ""}…` :
        e.phase === "waitingForApproval" ? "Press OK on the camera to allow this computer." :
        "Looking for the camera on your Wi-Fi network…";
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
        else notify(state.camera || "Camera connected", `${fresh.length} new ${fresh.length === 1 ? "item" : "items"} to import`);
      }
      break;
    }
    case "thumbnail":
      state.thumbnails.set(e.id, convertFileSrc(e.path));
      break;
    case "progress":
      $("status").textContent = `Importing ${e.filename} — ${e.index} of ${e.total}`;
      $<HTMLProgressElement>("progress").value = (e.index - 1 + e.fraction) / Math.max(e.total, 1);
      return; // no full re-render for progress
    case "imported": {
      const item = state.items.find((i) => i.id === e.id);
      if (item) item.imported = true;
      state.selection.delete(e.id);
      break;
    }
    case "done": {
      state.importing = false;
      let summary = `Imported ${e.imported} ${e.imported === 1 ? "item" : "items"}`;
      if (e.cancelled) summary += " (stopped)";
      if (e.failed.length) summary += `. ${e.failed.length} failed: ${e.failed.slice(0, 3).join(", ")}`;
      render();
      $("status").textContent = summary;
      notify("Import finished", summary);
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
  $("filter").hidden = !connected;
  $("title").textContent = connected ? state.camera || "Camera" : "Fuji Import";
  const newCount = state.items.filter((i) => !i.imported).length;
  $("subtitle").textContent = connected ? `${state.items.length} items · ${newCount} not imported` : "";
  $<HTMLButtonElement>("connect-now").disabled = state.phase !== "searching";
  if (!connected) return;

  // Footer
  const toImport = itemsToImport();
  $("progress").hidden = !state.importing;
  $("stop").hidden = !state.importing;
  const selected = $<HTMLButtonElement>("import-selected");
  selected.hidden = state.importing || state.selection.size === 0;
  selected.textContent = `Import ${state.selection.size} Selected`;
  const importNew = $<HTMLButtonElement>("import-new");
  importNew.hidden = state.importing;
  importNew.disabled = toImport.length === 0;
  importNew.textContent = toImport.length ? `Import ${toImport.length} New` : "No New Items";
  if (!state.importing && !state.lastError) $("status").textContent = settings.folder ? `Importing into ${settings.folder}` : "No import folder chosen";

  // Gallery, grouped by day
  const filter = $<HTMLSelectElement>("filter").value;
  const visible = filter === "new" ? state.items.filter((i) => !i.imported) : state.items;
  const gallery = $("gallery");
  gallery.replaceChildren();
  if (visible.length === 0) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.style.textAlign = "center";
    empty.style.marginTop = "120px";
    empty.textContent = filter === "new" ? "Everything is imported." : "No photos on the card.";
    gallery.append(empty);
    return;
  }
  const days = new Map<string, Item[]>();
  for (const item of visible) {
    const day = item.date ? new Date(item.date).toDateString() : "Unknown date";
    days.set(day, [...(days.get(day) ?? []), item]);
  }
  for (const [day, items] of days) {
    const header = document.createElement("div");
    header.className = "day";
    const label = document.createElement("span");
    label.textContent = day === "Unknown date" ? day : new Date(day).toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long", year: "numeric" });
    const all = items.every((i) => state.selection.has(i.id));
    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.textContent = all ? "Deselect" : "Select";
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
      cell.setAttribute("aria-label", `${item.isVideo ? "Video" : "Photo"} ${item.filename}${item.imported ? ", imported" : ""}`);
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
      if (item.imported || item.isVideo) {
        const badge = document.createElement("span");
        badge.className = "badge";
        badge.textContent = [item.imported ? "Imported" : "", item.isVideo ? "Video" : ""].filter(Boolean).join(" · ");
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
  autostartEnabled().then((on) => ($<HTMLInputElement>("autostart").checked = on)).catch(() => {});
  $<HTMLDialogElement>("settings").showModal();
}

$("connect-now").onclick = () => {
  showError("");
  send({ cmd: "connect" });
};
$("disconnect").onclick = () => send({ cmd: "disconnect" });
$("filter").onchange = render;
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
$("choose-folder").onclick = () => chooseFolder("Choose where to put imported photos");
// Windows Photos/OneDrive (Windows) and Shotwell/GNOME Photos (Linux) index the Pictures folder.
$("preset-pictures").onclick = async () => setFolder(await join(await pictureDir(), "Camera Imports"));
$("preset-watched").onclick = async () => {
  await chooseFolder("Choose the folder Lightroom, Photoshop Elements, digiKam or darktable watches");
  $<HTMLSelectElement>("folders").value = settings.folders = "";
};
$("folders").onchange = (e) => (settings.folders = (e.target as HTMLSelectElement).value);
$("rename").onchange = (e) => (settings.rename = (e.target as HTMLInputElement).value.trim());
$("auto-import").onchange = (e) => (settings.autoImport = (e.target as HTMLInputElement).checked);
$("skip-videos").onchange = (e) => {
  settings.skipVideos = (e.target as HTMLInputElement).checked;
  render();
};
$("autostart").onchange = (e) => ((e.target as HTMLInputElement).checked ? enableAutostart() : disableAutostart());
$("settings").addEventListener("close", render);

render();

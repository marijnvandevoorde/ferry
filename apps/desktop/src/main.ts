import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { dirname, downloadDir, join, pictureDir } from "@tauri-apps/api/path";
import { listen } from "@tauri-apps/api/event";
import { disable as disableAutostart, enable as enableAutostart, isEnabled as autostartEnabled } from "@tauri-apps/plugin-autostart";
import { open, save } from "@tauri-apps/plugin-dialog";
import { open as openPath } from "@tauri-apps/plugin-shell";
import { lang, t, translatePage } from "./i18n";
import { isPermissionGranted, requestPermission, sendNotification } from "@tauri-apps/plugin-notification";

// Events from `ferryctl serve` (see Sources/ferryctl/Serve.swift).
type Item = { id: string; filename: string; date: string; isVideo: boolean; kind: string; protected: boolean; size: number; imported: boolean };
type ServeEvent =
  | { event: "status"; phase: "searching" | "connecting" | "waitingForApproval" | "connected"; camera?: string; address?: string; autoSave?: boolean; paused?: boolean }
  | { event: "items"; items: Item[]; complete?: boolean; total?: number }
  | { event: "marked"; ids: string[]; imported: boolean }
  | { event: "autosave"; status: "off" | "listening" | "registered" | "error"; camera?: string; message?: string }
  | { event: "thumbnail"; id: string; path: string }
  | { event: "progress"; index: number; total: number; filename: string; fraction: number; bytes: number; totalBytes: number }
  | { event: "imported"; id: string; path: string }
  | { event: "done"; imported: number; failed: string[]; cancelled: boolean }
  | { event: "battery"; percent: number }
  | { event: "diagnostics"; path: string; summary?: string; error?: string }
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
  get disconnectAfterImport() { return localStorage.getItem("disconnectAfterImport") === "true"; },
  set disconnectAfterImport(v: boolean) { localStorage.setItem("disconnectAfterImport", String(v)); },
  get autoSave() { return localStorage.getItem("autoSave") === "true"; },
  set autoSave(v: boolean) { localStorage.setItem("autoSave", String(v)); },
  /** Cameras whose "already copied these?" notice was closed. */
  get backlogNoticeDismissed(): string[] {
    try { return JSON.parse(localStorage.getItem("backlogNoticeDismissed") ?? "[]"); } catch { return []; }
  },
  set backlogNoticeDismissed(v: string[]) { localStorage.setItem("backlogNoticeDismissed", JSON.stringify(v)); },
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
  /** The running import: the ids still to do, or "new" for all new items. */
  batch: null as string[] | "new" | null,
  /** An import the connection dropped in the middle of; it continues after reconnecting. */
  resume: null as string[] | "new" | null,
  /** The card is still being read; `listed` once it has been read completely in this session. */
  listing: false,
  listed: false,
  listTotal: 0,
  /** "Import New" was pressed while the card was still being read: import what turns up after it too. */
  importNewWhenListed: false,
  /** The camera came over the home network (PC AutoSave): import everything new, then let it go. */
  autoSaveSession: false,
  autoSaveStatus: "",
  /** An AutoSave session that didn't import because the card looks copied already (the backlog notice asks). */
  autoSaveHeldBack: false,
  /** The camera's battery in percent, when it reports it. */
  battery: null as number | null,
  address: "",
  /** The last import's summary, and how many it imported. */
  lastSummary: "",
  lastImported: 0,
  /** Ferry let go of the camera after an import: the connect screen shows what was imported. */
  done: null as { summary: string; imported: number; autoSave: boolean } | null,
  /** Not reconnecting by itself until the camera is gone or Connect is pressed. */
  paused: false,
  stepsShown: false,
};

/** A camera full of photos, none of them imported by Ferry: probably copied some other way before. */
function showBacklogNotice(): boolean {
  return state.phase === "connected" && !state.listing && state.items.length >= 30 && !state.items.some((i) => i.imported)
    && !settings.backlogNoticeDismissed.includes(state.camera);
}

function dismissBacklogNotice() {
  settings.backlogNoticeDismissed = [...settings.backlogNoticeDismissed, state.camera];
  render();
}

/** Records items as imported, or not, without copying anything, so "Import New" leaves them out or offers them again. */
function markImported(ids: string[], imported: boolean) {
  send({ cmd: "mark", ids, imported });
}

/** Lets go of the camera after an import and shows the done state. A camera that came over the home network
 * (PC AutoSave) just goes; otherwise Ferry waits for it to go away before looking for cameras again. */
function letGo() {
  state.done = { summary: state.lastSummary || t("Everything is imported."), imported: state.lastImported, autoSave: state.autoSaveSession };
  state.stepsShown = false;
  send(state.autoSaveSession ? { cmd: "disconnect" } : { cmd: "disconnect", untilGone: true });
}

/** Filters shown in the toolbar, for finding and selecting; "Import New" ignores them. */
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
  return state.items.filter((i) => !i.imported && !(settings.skipVideos && i.isVideo));
}

/** What "Import New" imports: every new item, oldest first. */
function importNew() {
  if (state.listing) state.importNewWhenListed = true;
  startImport(itemsToImport().map((i) => i.id).reverse());
}

/** After an import or once the card is read: import what turned up since "Import New" was pressed. */
function continueImportNew() {
  if (!state.importNewWhenListed || state.listing || state.importing) return;
  state.importNewWhenListed = false;
  if (itemsToImport().length > 0) importNew();
}

function startImport(ids?: string[]) {
  if (!settings.folder) {
    openSettings();
    showError(t("Choose a folder to import into first."));
    return;
  }
  state.importing = true;
  state.importStarted = Date.now();
  state.batch = ids ?? "new";
  $("show-folder").hidden = true;
  const immich = settings.immichServer && settings.immichKey
    ? { server: settings.immichServer, apiKey: settings.immichKey, album: settings.immichAlbum }
    : undefined;
  send({ cmd: "import", ids, folder: settings.folder, folders: settings.folders, rename: settings.rename, skipVideos: settings.skipVideos, immich });
  render();
}

async function notify(title: string, body: string, always = false) {
  if (document.hasFocus() && !always) return;
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
  showReportLink();
}

/** After an import or a failure: a link to the site's cameras page, whose report section links to the form. */
function showReportLink() {
  $("report-line").hidden = !state.lastError && !(state.phase === "searching" && state.done);
}

$("report-link").onclick = () => {
  const prefix = ["nl", "fr", "de", "es", "it"].includes(lang) ? `/${lang}` : "";
  openPath(`https://ferry.small-victories.co${prefix}/cameras/#report`);
};

/** Saves what Ferry and the camera said to each other (no photos), to attach to a camera report. */
$("save-diagnostics").onclick = async () => {
  const stamp = new Date().toISOString().slice(0, 16).replace("T", "-").replace(":", "");
  const path = await save({
    title: t("Attach this file to your camera report. It holds what Ferry and the camera said to each other, but no photos."),
    defaultPath: await join(await downloadDir(), `ferry-diagnostics-${stamp}.json`),
    filters: [{ name: "JSON", extensions: ["json"] }],
  }).catch(() => null);
  if (path) send({ cmd: "diagnostics", path });
};

// MARK: - Events

listen<ServeEvent>("ferryctl", ({ payload: e }) => {
  switch (e.event) {
    case "status": {
      const wasConnected = state.phase === "connected";
      state.phase = e.phase;
      if (e.camera) state.camera = e.camera;
      if (e.address) state.address = e.address;
      state.paused = e.paused === true;
      if (e.phase === "connected") {
        showError("");
        state.done = null;
        if (!wasConnected) {
          state.listed = false;
          state.autoSaveSession = e.autoSave === true;
          state.autoSaveHeldBack = false;
        }
      }
      if (e.phase === "searching") {
        state.battery = null;
        state.listing = false;
        state.importNewWhenListed = false;
        state.autoSaveSession = false;
        state.autoSaveHeldBack = false;
      }
      if (e.phase === "searching" && wasConnected) {
        if (state.batch) state.resume = state.batch;
        state.batch = null;
        state.items = [];
        state.selection.clear();
        state.importing = false;
      }
      break;
    }
    case "items": {
      const complete = e.complete ?? true;
      const firstList = complete && !state.listed;
      state.listing = !complete;
      state.listTotal = e.total ?? e.items.length;
      if (complete) state.listed = true;
      state.items = e.items.sort((a, b) => b.date.localeCompare(a.date) || b.filename.localeCompare(a.filename));
      const known = new Set(state.items.map((i) => i.id));
      state.selection.forEach((id) => known.has(id) || state.selection.delete(id));
      const fresh = itemsToImport();
      if (firstList && state.resume) {
        const resume = state.resume;
        state.resume = null;
        const ids = resume === "new" ? undefined : resume.filter((id) => known.has(id));
        if (!ids || ids.length > 0) startImport(ids);
      } else if (firstList && state.autoSaveSession) {
        if (state.importing) state.importNewWhenListed = true;
        else if (fresh.length === 0) send({ cmd: "disconnect" });
        else if (!settings.folder) {
          // Don't let the camera go silently: say why nothing was imported.
          send({ cmd: "disconnect" });
          showError(t("Choose a folder to import into first."));
          notify("PC AutoSave", t("Choose a folder to import into first."), true);
        } else if (showBacklogNotice()) {
          // Most likely copied some other way before: ask instead of importing the whole card.
          state.autoSaveHeldBack = true;
          notify(state.camera || t("Camera connected"), t("Already copied these photos some other way?"));
        } else importNew();
      } else if (firstList && fresh.length > 0 && settings.autoImport) {
        if (state.importing) state.importNewWhenListed = true;
        else importNew();
      } else if (firstList && fresh.length > 0 && !state.importing) {
        notify(state.camera || t("Camera connected"), t("{n} new items to import", { n: fresh.length }, fresh.length));
      } else if (complete) {
        const waiting = state.importNewWhenListed;
        continueImportNew();
        // Nothing new left after the listing: the import is already done.
        if (waiting && !state.importing && settings.disconnectAfterImport && !state.autoSaveSession) letGo();
      }
      break;
    }
    case "marked": {
      const ids = new Set(e.ids);
      for (const item of state.items) if (ids.has(item.id)) item.imported = e.imported;
      if (e.imported) ids.forEach((id) => state.selection.delete(id));
      // An AutoSave session held back for the notice: with nothing left to import, let the camera go.
      if (state.autoSaveHeldBack && !state.importing && itemsToImport().length === 0) send({ cmd: "disconnect" });
      break;
    }
    case "battery":
      state.battery = e.percent;
      break;
    case "autosave":
      state.autoSaveStatus =
        e.status === "listening" ? t("Listening for cameras on this network") :
        e.status === "registered" ? t("Registered with {camera}", { camera: e.camera ?? "" }) :
        e.status === "error" ? e.message ?? "" : "";
      $("autosave-status").textContent = state.autoSaveStatus;
      if (e.status === "registered") {
        notify(t("Camera registered"), t("{camera} can now send photos to this computer.", { camera: e.camera ?? "" }));
      }
      return;
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
      if (Array.isArray(state.batch)) state.batch = state.batch.filter((id) => id !== e.id);
      break;
    }
    case "done": {
      state.importing = false;
      state.batch = null;
      // Cut off by a lost connection: it continues after reconnecting.
      if (state.resume) {
        render();
        return;
      }
      continueImportNew();
      if (state.importing) return;
      // PC AutoSave: the camera sent what it had; let it go. Otherwise optionally let the computer go back to its usual
      // network; the pause keeps it from reconnecting while the camera closes its own.
      let summary = t("Imported {n} items", { n: e.imported }, e.imported);
      if (e.cancelled) summary += t(" (stopped)");
      if (e.failed.length) summary += t(". {n} failed: {list}", { n: e.failed.length, list: e.failed.slice(0, 3).join(", ") });
      state.lastSummary = summary;
      state.lastImported = e.imported;
      if (!state.listing && (state.autoSaveSession || (settings.disconnectAfterImport && !e.cancelled))) letGo();
      render();
      $("status").textContent = summary;
      $("show-folder").hidden = e.imported === 0;
      notify(t("Import finished"), summary);
      return;
    }
    case "diagnostics":
      if (e.error) showError(t("Could not save the diagnostics: {message}", { message: e.error }));
      else dirname(e.path).then((dir) => openPath(dir)).catch(() => {});
      return;
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
  $("title").textContent = connected ? state.camera || t("Camera") : "Ferry";
  const newCount = state.items.filter((i) => !i.imported).length;
  $("subtitle").textContent = connected ? t("{n} items · {m} not imported", { n: state.items.length, m: newCount }) : "";
  $<HTMLButtonElement>("connect-now").disabled = state.phase !== "searching";
  $("backlog-notice").hidden = !showBacklogNotice();
  if (!connected) {
    renderConnect();
    return;
  }

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
  if (!state.importing && !state.lastError && state.listing) {
    $("status").textContent = t("Reading card… {n} of {total}", { n: state.items.length, total: state.listTotal });
  } else if (!state.importing && !state.lastError && state.battery !== null && state.battery < 20) {
    $("status").textContent = t("Camera battery low: {n}%", { n: state.battery });
  } else if (!state.importing && !state.lastError) $("status").textContent = settings.folder ? t("Importing into {folder}", { folder: settings.folder }) : t("No import folder chosen");

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
      cell.oncontextmenu = (e) => {
        e.preventDefault();
        // From the keyboard (menu key, Shift+F10) there's no pointer position: open it at the photo.
        const rect = cell.getBoundingClientRect();
        const fromKeyboard = e.clientX === 0 && e.clientY === 0;
        openMenu(item, fromKeyboard ? rect.left + 8 : e.clientX, fromKeyboard ? rect.top + 8 : e.clientY);
      };
      grid.append(cell);
    }
    gallery.append(header, grid);
  }
}

function renderConnect() {
  const done = state.phase === "searching" ? state.done : null;
  $("connect-title").textContent = done ? done.summary : t("Connect your camera");
  $("connect-subtitle").textContent =
    state.phase === "connecting" ? t("Talking to the camera at {address}…", { address: state.address }) :
    state.phase === "waitingForApproval" ? t("Press OK on the camera to allow this computer.") :
    // Until the camera's address stops answering; a camera that sent its photos over the home network can go any time.
    done && (state.paused || done.autoSave) ? t("You can turn the camera off now.") :
    t("Join the camera's Wi-Fi network and Ferry connects by itself.");
  $("done-actions").hidden = !done || done.imported === 0 || !settings.folder;
  showReportLink();
  $("autosave-waiting").hidden = !settings.autoSave;
  // After an import the steps are folded away: the camera was found, it didn't get lost.
  const stepsHidden = !!done && !state.stepsShown;
  $("steps").hidden = stepsHidden;
  $("fuji-links").hidden = stepsHidden;
  $("show-steps").hidden = !stepsHidden;
  $("autosave-link-group").hidden = settings.autoSave;
}

// MARK: - Context menu

function closeMenu() {
  $("context-menu").hidden = true;
}

/** Right-click on a photo: acts on the whole selection when the photo is part of it. */
function openMenu(item: Item, x: number, y: number) {
  const ids = state.selection.has(item.id) ? [...state.selection] : [item.id];
  const targets = state.items.filter((i) => ids.includes(i.id));
  const menu = $("context-menu");
  const entry = (label: string, action: () => void, disabled = false) => {
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute("role", "menuitem");
    button.textContent = label;
    button.disabled = disabled;
    button.onclick = () => {
      closeMenu();
      action();
    };
    return button;
  };
  const entries: HTMLElement[] = [
    entry(ids.length > 1 ? t("Import {n} Items", { n: ids.length }) : t("Import"), () => startImport(ids), state.importing),
    document.createElement("hr"),
  ];
  if (targets.some((i) => !i.imported)) entries.push(entry(t("Mark as Imported"), () => markImported(ids, true)));
  if (targets.some((i) => i.imported)) entries.push(entry(t("Mark as Not Imported"), () => markImported(ids, false)));
  menu.replaceChildren(...entries);
  menu.hidden = false;
  const { width, height } = menu.getBoundingClientRect();
  menu.style.left = `${Math.max(0, Math.min(x, innerWidth - width - 4))}px`;
  menu.style.top = `${Math.max(0, Math.min(y, innerHeight - height - 4))}px`;
  menu.querySelector<HTMLButtonElement>("button:not(:disabled)")?.focus();
}

document.addEventListener("pointerdown", (e) => {
  if (!$("context-menu").contains(e.target as Node)) closeMenu();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") closeMenu();
});
$("context-menu").addEventListener("keydown", (e) => {
  if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
  e.preventDefault();
  const buttons = [...$("context-menu").querySelectorAll<HTMLButtonElement>("button:not(:disabled)")];
  const i = buttons.indexOf(document.activeElement as HTMLButtonElement);
  buttons[(i + (e.key === "ArrowDown" ? 1 : buttons.length - 1)) % buttons.length]?.focus();
});
window.addEventListener("blur", closeMenu);
document.querySelector("main")!.addEventListener("scroll", closeMenu);

// MARK: - Controls

function openSettings() {
  $<HTMLInputElement>("folder").value = settings.folder;
  $<HTMLSelectElement>("folders").value = settings.folders;
  $<HTMLInputElement>("rename").value = settings.rename;
  $<HTMLInputElement>("auto-import").checked = settings.autoImport;
  $<HTMLInputElement>("disconnect-after").checked = settings.disconnectAfterImport;
  $<HTMLInputElement>("skip-videos").checked = settings.skipVideos;
  $<HTMLInputElement>("autosave").checked = settings.autoSave;
  $("autosave-status").textContent = settings.autoSave ? state.autoSaveStatus : "";
  $<HTMLInputElement>("immich-server").value = settings.immichServer;
  $<HTMLInputElement>("immich-key").value = settings.immichKey;
  $<HTMLInputElement>("immich-album").value = settings.immichAlbum;
  autostartEnabled().then((on) => ($<HTMLInputElement>("autostart").checked = on)).catch(() => {});
  $<HTMLDialogElement>("settings").showModal();
}

$("connect-now").onclick = () => {
  showError("");
  state.done = null;
  render();
  send({ cmd: "connect" });
};
$("show-steps").onclick = () => {
  state.stepsShown = true;
  render();
};
$("done-open-folder").onclick = () => settings.folder && openPath(settings.folder);
$("autosave-link").onclick = () => {
  openSettings();
  $("autosave").focus();
};
$("backlog-mark").onclick = () => markImported(state.items.map((i) => i.id), true);
$("backlog-dismiss").onclick = dismissBacklogNotice;
$("backlog-dismiss").title = t("Dismiss");
$("disconnect").onclick = () => {
  state.resume = null;
  state.batch = null;
  send({ cmd: "disconnect" });
  invoke("bluetooth_disconnect").catch(() => {});
};
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
$("show-log").onclick = () => invoke<string>("log_dir").then((dir) => openPath(dir)).catch((e) => showError(String(e)));
$("import-new").onclick = () => importNew();
$("import-selected").onclick = () => startImport([...state.selection]);
$("stop").onclick = () => {
  state.batch = null;
  state.importNewWhenListed = false;
  send({ cmd: "cancel" });
};
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
$("disconnect-after").onchange = (e) => (settings.disconnectAfterImport = (e.target as HTMLInputElement).checked);
$("skip-videos").onchange = (e) => {
  settings.skipVideos = (e.target as HTMLInputElement).checked;
  render();
};
$("autosave").onchange = (e) => {
  settings.autoSave = (e.target as HTMLInputElement).checked;
  if (!settings.autoSave) state.autoSaveStatus = "";
  $("autosave-status").textContent = "";
  send({ cmd: "autosave", enabled: settings.autoSave });
  // The camera can send photos any time: Ferry has to be running for that.
  if (settings.autoSave) enableAutostart().then(() => ($<HTMLInputElement>("autostart").checked = true)).catch(() => {});
};
if (settings.autoSave) send({ cmd: "autosave", enabled: true });
$("immich-server").onchange = (e) => (settings.immichServer = (e.target as HTMLInputElement).value.trim());
$("immich-key").onchange = (e) => (settings.immichKey = (e.target as HTMLInputElement).value.trim());
$("immich-album").onchange = (e) => (settings.immichAlbum = (e.target as HTMLInputElement).value.trim());
$("autostart").onchange = (e) => ((e.target as HTMLInputElement).checked ? enableAutostart() : disableAutostart());
$("settings").addEventListener("close", render);

// MARK: - Bluetooth
// Newer cameras hand over their Wi-Fi network over Bluetooth (src-tauri/src/bluetooth.rs); the computer joins it
// (wifi.rs) and ferryctl connects as usual.

type BtCamera = { id: string; name: string; pairing: boolean; saved: boolean; nearby: boolean };
type Credentials = { ssid: string; password: string };

/** Bumped whenever the flow restarts or the dialog closes, so late answers from an older run are ignored. */
let btRun = 0;

/** Rust errors are `{ message, detail }`: fixed English text to translate, and what the OS said. */
function btErrorText(e: unknown): string {
  if (e && typeof e === "object" && "message" in e) {
    const { message, detail } = e as { message: string; detail?: string | null };
    return t(message) + (detail ? ` (${detail})` : "");
  }
  return String(e);
}

function btView(view: "scan" | "busy" | "manual", error = "") {
  $("bt-scan").hidden = view !== "scan";
  $("bt-busy").hidden = view !== "busy";
  $("bt-manual").hidden = view !== "manual";
  const el = $("bt-error");
  el.textContent = error;
  el.hidden = !error;
}

function btCameraRow(camera: BtCamera, inDialog: boolean): HTMLLIElement {
  const row = document.createElement("li");
  const name = document.createElement("span");
  name.className = "name";
  name.textContent = camera.name;
  row.append(name);
  if (inDialog && (camera.pairing || !camera.nearby)) {
    const note = document.createElement("span");
    note.className = "muted";
    note.textContent = camera.pairing ? t("Ready to pair") : t("Not nearby");
    row.append(note);
  }
  if (inDialog && camera.saved) {
    const forget = document.createElement("button");
    forget.type = "button";
    forget.textContent = t("Forget");
    forget.onclick = async () => {
      await invoke("bluetooth_forget", { id: camera.id }).catch(() => {});
      row.remove();
      btRenderSaved();
    };
    row.append(forget);
  }
  const go = document.createElement("button");
  go.type = "button";
  go.className = "primary";
  go.textContent = camera.pairing ? t("Pair") : t("Connect");
  go.onclick = () => btConnect(camera);
  row.append(go);
  return row;
}

/** Saved cameras get a one-click Connect on the connect screen. */
async function btRenderSaved() {
  const saved = (await invoke<BtCamera[]>("bluetooth_saved").catch(() => undefined)) ?? [];
  $("bt-saved").replaceChildren(...saved.map((c) => btCameraRow(c, false)));
  $("bt-saved").hidden = saved.length === 0;
}

async function btScan() {
  const run = ++btRun;
  const dialog = $<HTMLDialogElement>("bluetooth");
  if (!dialog.open) dialog.showModal();
  btView("scan");
  const status = $("bt-scan-status");
  const rescan = $<HTMLButtonElement>("bt-rescan");
  status.textContent = t("Looking for cameras in pairing mode…");
  rescan.disabled = true;
  $("bt-cameras").replaceChildren();
  try {
    const cameras = (await invoke<BtCamera[]>("bluetooth_scan")) ?? [];
    if (run !== btRun) return;
    $("bt-cameras").replaceChildren(...cameras.map((c) => btCameraRow(c, true)));
    status.textContent = cameras.some((c) => c.pairing || c.nearby) ? "" : t("No camera found. Make sure it's in pairing mode and close by.");
  } catch (e) {
    if (run !== btRun) return;
    status.textContent = "";
    btView("scan", btErrorText(e));
  } finally {
    if (run === btRun) rescan.disabled = false;
  }
}

async function btConnect(camera: BtCamera) {
  const run = ++btRun;
  const dialog = $<HTMLDialogElement>("bluetooth");
  if (!dialog.open) dialog.showModal();
  btView("busy");
  $("bt-step").textContent = t("Looking for {camera}…", { camera: camera.name });
  let credentials: Credentials;
  try {
    credentials = await invoke<Credentials>("bluetooth_connect", { id: camera.id });
  } catch (e) {
    if (run !== btRun) return;
    $("bt-scan-status").textContent = "";
    $<HTMLButtonElement>("bt-rescan").disabled = false;
    btView("scan", btErrorText(e));
    return;
  }
  btRenderSaved();
  if (run !== btRun) return;
  try {
    await invoke("wifi_join", { ssid: credentials.ssid, password: credentials.password });
  } catch (e) {
    if (run !== btRun) return;
    // Show the network so the user can join it by hand.
    $("bt-ssid").textContent = credentials.ssid;
    $("bt-password").textContent = credentials.password;
    btView("manual", btErrorText(e));
    return;
  }
  if (run !== btRun) return;
  dialog.close();
  btHandOver();
}

/** The computer is on the camera's network: ferryctl takes it from here. */
function btHandOver() {
  showError("");
  send({ cmd: "connect", bluetooth: true });
}

async function copyText(source: string, button: HTMLButtonElement) {
  const text = $(source).textContent ?? "";
  try {
    await navigator.clipboard.writeText(text);
    button.textContent = t("Copied");
    setTimeout(() => (button.textContent = t("Copy")), 1500);
  } catch {
    getSelection()?.selectAllChildren($(source)); // the user can still press Ctrl+C
  }
}

listen<{ step: string; ssid?: string }>("bluetooth", ({ payload: p }) => {
  const text: Record<string, string> = {
    connecting: t("Connecting over Bluetooth…"),
    pairing: t("Pairing with the camera…"),
    wifi: t("Asking the camera to turn on its Wi-Fi…"),
    joining: t("Joining {ssid}…", { ssid: p.ssid ?? "" }),
  };
  if (text[p.step]) $("bt-step").textContent = text[p.step];
});

$("bt-open").onclick = btScan;
$("bt-rescan").onclick = btScan;
$("bt-copy-ssid").onclick = (e) => copyText("bt-ssid", e.currentTarget as HTMLButtonElement);
$("bt-copy-password").onclick = (e) => copyText("bt-password", e.currentTarget as HTMLButtonElement);
$("bt-manual-connect").onclick = () => {
  $<HTMLDialogElement>("bluetooth").close();
  btHandOver();
};
$("bluetooth").addEventListener("close", () => {
  btRun++;
  // Don't leave the password on screen.
  $("bt-password").textContent = "";
});
btRenderSaved();

translatePage();
render();

// Stand-ins for the Tauri APIs, so the desktop UI renders in a plain browser for screenshots.
try { localStorage.setItem("folder", "C:\\Users\\you\\Pictures\\Camera Imports"); } catch {}
let handler: ((e: { payload: unknown }) => void) | undefined;
export const invoke = async () => undefined;
export const convertFileSrc = (p: string) => p;
export const join = async (...p: string[]) => p.join("/");
export const pictureDir = async () => "C:/Users/you/Pictures";
export const listen = async (event: string, h: (e: { payload: unknown }) => void) => {
  if (event !== "ferryctl") return () => {}; // only ferryctl's events are played back
  handler = h;
  const emit = (payload: unknown) => handler!({ payload });
  setTimeout(() => {
    emit({ event: "status", phase: "connected", camera: "X-T20", address: "192.168.0.1" });
    const items = Array.from({ length: 12 }, (_, i) => ({
      id: String(i + 1), filename: `DSCF${1001 + i}.JPG`, date: `2026-10-${[18, 19, 22][Math.floor(i / 4)]}T1${i % 10}:${10 + i}:00`,
      isVideo: false, kind: "jpeg", protected: i % 4 === 0, size: 6_000_000 + i * 150_000, imported: i < 3,
    }));
    emit({ event: "items", items });
    items.forEach((it, i) => emit({ event: "thumbnail", id: it.id, path: `/photos/scene${String(i + 1).padStart(2, "0")}.jpg` }));
    if (location.hash === "#importing")
      emit({ event: "progress", index: 4, total: 9, filename: "DSCF1004.JPG", fraction: 0.4, bytes: 21_000_000, totalBytes: 56_000_000 });
  }, 50);
  return () => {};
};
export const enable = async () => {}, disable = async () => {}, isEnabled = async () => false;
export const open = async () => null;
export const isPermissionGranted = async () => true, requestPermission = async () => "granted", sendNotification = () => {};

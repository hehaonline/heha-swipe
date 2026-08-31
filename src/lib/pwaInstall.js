let deferredInstallPrompt = null;
let installed = false;
const listeners = new Set();
const releaseEnabled = import.meta.env.VITE_ENABLE_HEHA_SWIPE_PWA === "true";

function detectStandalone() {
  if (typeof window === "undefined") return false;
  return Boolean(
    window.matchMedia?.("(display-mode: standalone)")?.matches
    || window.navigator?.standalone === true
  );
}

function notify() {
  const state = getInstallState();
  listeners.forEach((listener) => listener(state));
}

if (typeof window !== "undefined") {
  installed = detectStandalone();

  window.addEventListener("beforeinstallprompt", (event) => {
    if (!releaseEnabled) return;
    event.preventDefault();
    deferredInstallPrompt = event;
    notify();
  });

  window.addEventListener("appinstalled", () => {
    installed = true;
    deferredInstallPrompt = null;
    notify();
  });
}

export function isAppleMobile() {
  if (typeof navigator === "undefined") return false;
  const platform = navigator.userAgent || "";
  const iOS = /iPad|iPhone|iPod/.test(platform);
  const iPadDesktopMode = navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
  return iOS || iPadDesktopMode;
}

export function getInstallState() {
  return {
    enabled: releaseEnabled,
    installed: releaseEnabled && (installed || detectStandalone()),
    canPrompt: releaseEnabled && Boolean(deferredInstallPrompt),
    appleMobile: isAppleMobile(),
  };
}

export function subscribeToInstallState(listener) {
  listeners.add(listener);
  listener(getInstallState());
  return () => listeners.delete(listener);
}

export async function requestSwipeInstall() {
  if (!releaseEnabled) return { outcome: "disabled" };
  if (detectStandalone()) return { outcome: "installed" };
  if (!deferredInstallPrompt) return { outcome: "manual" };

  const prompt = deferredInstallPrompt;
  deferredInstallPrompt = null;
  await prompt.prompt();
  const result = await prompt.userChoice;
  if (result?.outcome === "accepted") installed = true;
  notify();
  return { outcome: result?.outcome || "dismissed" };
}

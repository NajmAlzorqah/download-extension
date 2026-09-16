const HOST = "com.najm.ytdlp";

let port = null;
let connecting = false;
let requestId = 0;
const pendings = new Map();

const state = {
  alive: false,
  ytdlp: false,
  ffmpeg: false,
  status: "idle", // idle | probing | downloading | done | error
  req: null,
  pct: null,
  speed: null,
  eta: null,
  items: [],
  message: null,
  warn: null,
};

function emit(extra) {
  const snapshot = { ...state, ...extra };
  chrome.runtime.sendMessage({ action: "hostEvent", snapshot }).catch(() => {});
}

function ensureConnected() {
  return new Promise((resolve) => {
    if (port) return resolve(port);
    if (connecting) return setTimeout(() => resolve(ensureConnected()), 50);

    connecting = true;
    try {
      port = chrome.runtime.connectNative(HOST);
    } catch (err) {
      connecting = false;
      resolve(null);
      return;
    }

    const drop = () => {
      const wasServing = !!port;
      port = null;
      connecting = false;
      if (wasServing) {
        state.status = "idle";
        emit();
      }
    };

    port.onMessage.addListener((msg) => {
      handleHostMessage(msg);
    });
    port.onDisconnect.addListener(() => {
      drop();
      if (!state.alive) return;
      // Reconnect for the next request; the host survives a dead tab/sw.
      state.alive = false;
      emit();
      const err = chrome.runtime.lastError;
      if (err) console.warn("native host disconnected:", err.message);
    });

    connecting = false;
    resolve(port);
  });
}

function handleHostMessage(msg) {
  if (msg && msg.event && msg.event !== "progress") {
    if (msg.event === "done") {
      state.status = "done";
      state.items = msg.items || [];
      state.pct = 100;
      state.warn = msg.warn || null;
    } else if (msg.event === "error") {
      state.status = "error";
      state.message = msg.message;
      state.warn = null;
    } else if (msg.event === "cancelled") {
      state.status = "done";
      state.message = "Cancelled";
      state.items = msg.items || [];
      state.warn = null;
    } else if (msg.event === "start") {
      state.status = "downloading";
      state.items = [];
      state.message = null;
      state.warn = null;
    } else if (msg.event === "info") {
      state.message = msg.message;
    }
  }

  if (msg && msg.event === "progress") {
    state.pct = msg.pct;
    state.speed = msg.speed;
    state.eta = msg.eta;
  }

  const req = msg && msg.req;
  const pending = req && pendings.get(req);
  if (pending) {
    pendings.delete(req);
    if (pending.type === "ping") {
      state.alive = !!msg.ok;
      state.ytdlp = !!msg.ytdlp;
      state.ffmpeg = !!msg.ffmpeg;
      pending.resolve(msg.ok);
    } else if (pending.type === "probe") {
      state.message = msg.ok ? null : msg.error;
      pending.resolve(msg);
    } else if (pending.type === "theme") {
      pending.resolve(msg);
    }
  }
  emit();
}

function nextReq() {
  return ++requestId;
}

function withNativePort() {
  return ensureConnected().then((p) => {
    if (!p) throw new Error("native host not available");
    return p;
  });
}

// Probe worst case in the host: run_probe(60s) + sleep(2s) + run_probe(60s)
// for a failed-first-try playlist URL, then flat_entries(60s) + first-video
// probe(60s) = up to 242s of subprocess waits in pathological time-out-every
// step. Typical probes take a couple of seconds, and most real runs stay well
// under 120s; 200s bounds a genuinely hung host without a near-miss on
// legitimate slow probes.
const PROBE_TIMEOUT_MS = 200000;
const PING_TIMEOUT_MS = 10000;
const THEME_TIMEOUT_MS = 5000;

// Live Omarchy theme, short-cached so repeated popup opens don't re-spawn
// hyprctl/fc-match on every open.
let themeCache = { at: 0, val: null };
const THEME_TTL_MS = 4000;

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  switch (msg.action) {
    case "ping":
      withNativePort()
        .then((p) => {
          const req = nextReq();
          const timer = setTimeout(() => {
            if (pendings.has(req)) {
              pendings.delete(req);
              sendResponse({ ok: false, error: "ping timed out" });
            }
          }, PING_TIMEOUT_MS);
          pendings.set(req, {
            type: "ping",
            resolve: (ok) => {
              clearTimeout(timer);
              sendResponse({ ok });
            },
          });
          try {
            p.postMessage({ req, action: "ping" });
          } catch (err) {
            clearTimeout(timer);
            pendings.delete(req);
            sendResponse({ ok: false, error: String(err) });
          }
        })
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "getState":
      sendResponse({ state: { ...state } });
      return false;

    case "getTheme":
      if (themeCache.val && Date.now() - themeCache.at < THEME_TTL_MS) {
        sendResponse({ ok: true, theme: themeCache.val });
        return false;
      }
      withNativePort()
        .then((p) => {
          const req = nextReq();
          const timer = setTimeout(() => {
            if (pendings.has(req)) {
              pendings.delete(req);
              sendResponse({ ok: false, error: "theme timed out" });
            }
          }, THEME_TIMEOUT_MS);
          pendings.set(req, {
            type: "theme",
            resolve: (res) => {
              clearTimeout(timer);
              if (res && res.ok && res.theme) {
                themeCache = { at: Date.now(), val: res.theme };
                sendResponse({ ok: true, theme: res.theme });
              } else {
                sendResponse({ ok: false, error: (res && res.error) || "theme unavailable" });
              }
            },
          });
          p.postMessage({ req, action: "theme" });
        })
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "probe":
      withNativePort()
        .then((p) => {
          const req = nextReq();
          state.status = "probing";
          emit();
          const timer = setTimeout(() => {
            if (pendings.has(req)) {
              pendings.delete(req);
              state.status = "idle";
              state.message = null;
              emit();
              sendResponse({ ok: false, error: "probe timed out" });
            }
          }, PROBE_TIMEOUT_MS);
          pendings.set(req, {
            type: "probe",
            resolve: (res) => {
              clearTimeout(timer);
              state.status = "idle";
              emit();
              sendResponse(res);
            },
          });
          p.postMessage({ req, action: "probe", url: msg.url });
        })
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "download":
      withNativePort()
        .then((p) => {
          p.postMessage({ req: nextReq(), action: "download", url: msg.url, selection: msg.selection });
          sendResponse({ ok: true });
        })
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "cancel":
      withNativePort()
        .then((p) => {
          p.postMessage({ req: nextReq(), action: "cancel" });
          sendResponse({ ok: true });
        })
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    default:
      return false;
  }
});
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
  pct: null,
  speed: null,
  eta: null,
  downloaded: null,
  total: null,
  items: [],
  message: null,
  warn: null,
  // Waiting downloads, mirror of the host's `queue` event (active item is
  // tracked by status/pct/items above).
  queue: [],
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
      state.queue = [];
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

// The done/error/cancelled/start/queue transitions all clear the same five
// per-job progress fields before applying their own status; keeping that in one
// helper is what stops the copies from drifting apart.
function resetTo(overrides) {
  state.pct = null;
  state.speed = null;
  state.eta = null;
  state.downloaded = null;
  state.total = null;
  Object.assign(state, overrides);
}

function handleHostMessage(msg) {
  if (msg && msg.event && msg.event !== "progress") {
    if (msg.event === "done") {
      resetTo({ status: "done", items: msg.items || [], pct: 100, warn: msg.warn || null });
    } else if (msg.event === "error") {
      resetTo({ status: "error", message: msg.message, warn: null });
    } else if (msg.event === "cancelled") {
      resetTo({ status: "done", message: "Cancelled", items: msg.items || [], warn: null });
    } else if (msg.event === "start") {
      resetTo({ status: "downloading", items: [], message: null, warn: null });
    } else if (msg.event === "info") {
      state.message = msg.message;
    }
  }

  if (msg && msg.event === "progress") {
    state.pct = msg.pct;
    state.speed = msg.speed;
    state.eta = msg.eta;
    state.downloaded = msg.downloaded;
    state.total = msg.total;
  }

  if (msg && msg.event === "queue") {
    state.queue = msg.queue || [];
    schedulePersist();
    // The host emits the queue with the next item already "downloading" before
    // that worker's own `start` event arrives. If our status is still a
    // terminal state from the previous job — or idle because this queue event
    // beat the very first `start` — reset it so a reopen doesn't flash the
    // old job's "Saved N files" / error on top of the new item.
    const next = (msg.queue[0] || {}).status;
    if (next === "downloading" &&
        (state.status === "done" || state.status === "error" || state.status === "idle")) {
      resetTo({ status: "downloading", items: [], message: null, warn: null });
    }
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
      // A probe finishing while a download runs must not clobber the download's
      // status message (the probe handler below applies the same guard).
      if (state.status !== "downloading") state.message = msg.ok ? null : msg.error;
      pending.resolve(msg);
    } else {
      // theme, getQueue, download, cancel, reorder — resolve the caller with
      // the host's raw reply; they carry their own typed state via events.
      pending.resolve(msg);
    }
  }
  emit();
}

function nextReq() {
  return ++requestId;
}

// One-shot request over the native port. Registers a pending, times it out,
// and resolves with the host's reply (or `{ok:false, error}` on timeout /
// post failure). Per-type state updates still happen in handleHostMessage via
// the registered pending.type before this promise resolves.
function request(p, action, body = {}, timeout = 10000, timeoutError = "request timed out") {
  return new Promise((resolve) => {
    const req = nextReq();
    const timer = setTimeout(() => {
      if (pendings.has(req)) {
        pendings.delete(req);
        resolve({ ok: false, error: timeoutError });
      }
    }, timeout);
    pendings.set(req, {
      type: action,
      resolve: (res) => {
        clearTimeout(timer);
        resolve(res);
      },
    });
    try {
      p.postMessage({ req, action, ...body });
    } catch (err) {
      clearTimeout(timer);
      pendings.delete(req);
      resolve({ ok: false, error: String(err) });
    }
  });
}

function withNativePort() {
  return ensureConnected().then((p) => {
    if (!p) throw new Error("native host not available");
    return p;
  });
}

// ---------------------------------------------------------------------------
// Queue persistence: mirror the host's queue into chrome.storage.local so a
// full browser restart can re-submit the waiting jobs to a fresh host. The
// host stays authoritative while it is alive; storage is only a restart
// snapshot and is never trusted over what the host reports (`getQueue`).
const QUEUE_STORAGE_KEY = "downloadQueue";
let persistTimer = null;

function persistQueueNow() {
  if (state.queue.length) {
    chrome.storage.local.set({ [QUEUE_STORAGE_KEY]: { queue: state.queue } }).catch(() => {});
  } else {
    chrome.storage.local.remove(QUEUE_STORAGE_KEY).catch(() => {});
  }
  if (persistTimer) {
    clearTimeout(persistTimer);
    persistTimer = null;
  }
}

function schedulePersist() {
  if (persistTimer) return;
  persistTimer = setTimeout(() => {
    persistTimer = null;
    persistQueueNow();
  }, 500);
}

function hostQueue() {
  return withNativePort().then((p) => request(p, "getQueue", {}, 5000, "getQueue timed out"));
}

let restoring = false;

async function restoreFromStorage() {
  if (restoring) return;
  restoring = true;
  try {
    const qr = await hostQueue();
    if (!qr.ok) return; // can't confirm host state — don't risk duplicates
    if (qr.queue && qr.queue.length) {
      // The host already owns a running queue (extension reload while a
      // download was in flight): adopt it, drop the stored copy.
      state.queue = qr.queue;
      persistQueueNow();
      return;
    }
    const stored = await chrome.storage.local.get(QUEUE_STORAGE_KEY);
    const saved = (stored[QUEUE_STORAGE_KEY] || {}).queue;
    if (!Array.isArray(saved) || !saved.length) return;
    state.queue = saved;
    for (const item of saved) {
      if (!item || typeof item.url !== "string") continue;
      try {
        const p = await withNativePort();
        p.postMessage({
          req: nextReq(),
          action: "download",
          url: item.url,
          selection: item.selection || {},
        });
      } catch (err) {
        break;
      }
    }
    // Mirror the re-submitted queue back into storage instead of clearing it:
    // the host's own `queue` events (arriving milliseconds after each accepted
    // download) overwrite this copy with the live snapshot. Clearing here would
    // open a window where a browser death right after the restore loses the
    // queue before the next event re-persists it.
    persistQueueNow();
  } finally {
    restoring = false;
  }
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
        .then((p) =>
          request(p, "ping", {}, PING_TIMEOUT_MS, "ping timed out").then((res) => {
            if (res === true) {
              sendResponse({ ok: true, ytdlp: state.ytdlp, ffmpeg: state.ffmpeg });
            } else {
              sendResponse({ ok: false, error: (res && res.error) || "ping failed" });
            }
          })
        )
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "getState":
      sendResponse({ state: { ...state } });
      return false;

    case "getQueue":
      hostQueue()
        .then((res) => {
          if (res && res.ok && res.queue) {
            state.queue = res.queue;
            persistQueueNow();
            sendResponse({ ok: true, queue: state.queue });
          } else {
            sendResponse({ ok: false, error: (res && res.error) || "queue unavailable" });
          }
        })
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "getTheme":
      if (themeCache.val && Date.now() - themeCache.at < THEME_TTL_MS) {
        sendResponse({ ok: true, theme: themeCache.val });
        return false;
      }
      withNativePort()
        .then((p) =>
          request(p, "theme", {}, THEME_TIMEOUT_MS, "theme timed out").then((res) => {
            if (res && res.ok && res.theme) {
              themeCache = { at: Date.now(), val: res.theme };
              sendResponse({ ok: true, theme: res.theme });
            } else {
              sendResponse({ ok: false, error: (res && res.error) || "theme unavailable" });
            }
          })
        )
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "probe":
      withNativePort()
        .then((p) => {
          if (state.status !== "downloading") state.status = "probing";
          emit();
          request(p, "probe", { url: msg.url }, PROBE_TIMEOUT_MS, "probe timed out").then((res) => {
            // Keep an in-flight download's status untouched: probing during a
            // download is allowed (manual Detect), and dropping back to
            // "idle" here would freeze the popup's progress view (same guard
            // as in handleHostMessage).
            const downloading = state.status === "downloading";
            if (!downloading) state.status = "idle";
            if (res && res.ok) {
              if (!downloading) state.message = null;
              emit();
              sendResponse(res);
            } else {
              const err = (res && res.error) || "probe failed";
              if (!downloading) state.message = err;
              emit();
              sendResponse({ ok: false, error: err });
            }
          });
        })
        .catch((err) => {
          if (state.status !== "downloading") {
            state.status = "idle";
            state.message = null;
          }
          emit();
          sendResponse({ ok: false, error: String(err) });
        });
      return true;

    case "download":
      withNativePort()
        .then((p) =>
          request(p, "download", { url: msg.url, selection: msg.selection }).then((res) => {
            if (res && res.ok) sendResponse({ ok: true, queueId: res.queueId });
            else sendResponse({ ok: false, error: (res && res.error) || "download rejected" });
          })
        )
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "cancel":
      withNativePort()
        .then((p) => {
          const body = {};
          if (Number.isInteger(msg.queueId)) body.queueId = msg.queueId;
          return request(p, "cancel", body).then((res) => {
            if (res && res.ok) sendResponse({ ok: true });
            else sendResponse({ ok: false, error: (res && res.error) || "cancel rejected" });
          });
        })
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "reorder":
      if (!Number.isInteger(msg.queueId) || !Number.isInteger(msg.newIndex)) {
        sendResponse({ ok: false, error: "invalid queueId/newIndex" });
        return false;
      }
      withNativePort()
        .then((p) =>
          request(p, "reorder", { queueId: msg.queueId, newIndex: msg.newIndex }).then((res) => {
            if (res && res.ok) sendResponse({ ok: true });
            else sendResponse({ ok: false, error: (res && res.error) || "reorder rejected" });
          })
        )
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    default:
      return false;
  }
});

// After a full browser restart the native host comes up fresh (empty queue):
// re-submit the jobs persisted to chrome.storage.local in their saved order
// (former active item first). Also fires on extension reload, where the host
// may still be running — restoreFromStorage() then adopts the host's queue
// instead of submitting duplicates.
chrome.runtime.onStartup.addListener(() => restoreFromStorage());
chrome.runtime.onInstalled.addListener(() => restoreFromStorage());
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
  title: null,
  pct: null,
  speed: null,
  eta: null,
  items: [],
  message: null,
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
    } else if (msg.event === "error") {
      state.status = "error";
      state.message = msg.message;
    } else if (msg.event === "cancelled") {
      state.status = "done";
      state.message = "Cancelled";
      state.items = msg.items || [];
    } else if (msg.event === "start") {
      state.status = "downloading";
      state.items = [];
      state.message = null;
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
    }
  }
  emit();
}

function nextReq() {
  return ++requestId;
}

function nativeRequest(payload) {
  return ensureConnected().then((p) => {
    if (!p) throw new Error("native host not available");
    const req = nextReq();
    p.postMessage({ req, ...payload });
    return req;
  });
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  switch (msg.action) {
    case "ping":
      nativeRequest({ action: "ping" })
        .then((req) => {
          pendings.set(req, {
            type: "ping",
            resolve: (ok) => {
              sendResponse({ ok });
            },
          });
        })
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "getState":
      sendResponse({ state });
      return false;

    case "probe":
      nativeRequest({ action: "probe", url: msg.url })
        .then((req) => {
          state.status = "probing";
          emit();
          const timer = setTimeout(() => {
            if (pendings.has(req)) {
              pendings.delete(req);
              sendResponse({ ok: false, error: "probe timed out" });
            }
          }, 70000);
          pendings.set(req, {
            type: "probe",
            resolve: (res) => {
              clearTimeout(timer);
              state.status = "idle";
              emit();
              sendResponse(res);
            },
          });
        })
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "download":
      nativeRequest({ action: "download", url: msg.url, selection: msg.selection })
        .then(() => sendResponse({ ok: true }))
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    case "cancel":
      nativeRequest({ action: "cancel" })
        .then(() => sendResponse({ ok: true }))
        .catch((err) => sendResponse({ ok: false, error: String(err) }));
      return true;

    default:
      return false;
  }
});
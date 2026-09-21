// Client.js — socket protocol helpers for najm.downloads.
//
// Mirrors the JSON-lines contract of the shared host daemon
// (host/najm-ytdlp-host in --agent mode). The widget is just another client:
// requests carry a per-originator `req`, replies echo it, and req-less
// `queue`/`progress` events are broadcast to every client. Keep these in sync
// with the host's AGENT_SOCK_* constants and dispatch.

function socketDir(runtimeDir, stateDir) {
  var base = runtimeDir || stateDir || "/tmp"
  return base + "/najm-ytdlp"
}

// Widget prefs live in ~/.local/state/najm-downloads/ (persistent, unlike the
// runtime-dir socket). Mirrors where the host keeps theme state.
function socketPath(runtimeDir, stateDir) {
  return socketDir(runtimeDir, stateDir) + "/agent.sock"
}

// Frame builders. The host JSON-decodes each newline-terminated line.
function line(obj) {
  return JSON.stringify(obj) + "\n"
}

function ping(req) {
  return { action: "ping", req: req }
}

function cancel(req, queueId) {
  if (queueId !== undefined) return { action: "cancel", req: req, queueId: queueId }
  return { action: "cancel", req: req }
}

function reorder(req, queueId, newIndex) {
  return { action: "reorder", req: req, queueId: queueId, newIndex: newIndex }
}

function getQueue(req) {
  return { action: "getQueue", req: req }
}

// Pause/resume the active job (SIGSTOP). The queue broadcast then reports that
// item with status "paused" until resumed. {req, paused:boolean}
function pause(req, paused) {
  return { action: "pause", req: req, paused: paused }
}

// Parse one incoming line. Returns null unless it is a complete JSON object.
function parseLine(raw) {
  try {
    var obj = JSON.parse(raw)
    return (obj && typeof obj === "object") ? obj : null
  } catch (e) {
    return null
  }
}

// --- classification of incoming frames -----------------------------

// The agent echoes {req, ok:true, host, ytdlp, ffmpeg} for a ping.
function isPingReply(obj) {
  return obj && obj.event === undefined &&
         obj.ok === true && typeof obj.ytdlp === "boolean" &&
         typeof obj.ffmpeg === "boolean"
}

// A probe reply is {req, ok, meta, formats, subs, autoSubs, subFormats} —
// distinguishable from a ping reply by the missing ytdlp/ffmpeg booleans.
// A failure reply (probe or otherwise) is {req, ok:false, error}.
function isErrorReply(obj) {
  return obj && obj.event === undefined && obj.ok === false &&
         obj.req !== undefined && typeof obj.error === "string"
}

// A getQueue reply is {req, ok:true, queue:[...]} — same snapshot shape as the
// broadcast, but req-carrying and ok:true.
function isQueueReply(obj) {
  return obj && obj.event === undefined && obj.ok === true &&
         obj.req !== undefined && Array.isArray(obj.queue)
}

// Req-less broadcast snapshots / coarse progress.
function isQueueBroadcast(obj) {
  return obj && obj.event === "queue" && Array.isArray(obj.queue)
}

function isProgressBroadcast(obj) {
  return obj && obj.event === "progress" && typeof obj.queueId === "number"
}

// True while anything in the snapshot is still running. Used by the widget to
// flip its icon to an "active" state.
function queueBusy(queue) {
  for (var i = 0; i < queue.length; i++) {
    if (String(queue[i].status) === "downloading" ||
        String(queue[i].status) === "paused" ||
        String(queue[i].status) === "queued") return true
  }
  return false
}
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Client.js" as Client
import "Formats.js" as Formats

// najm.downloads — shared-queue monitor for the yt-dlp agent daemon.
//
// The browser extension popup owns URL probing and download initiation; this
// widget is a second socket client (host/najm-ytdlp-host --agent) that only
// watches the shared queue: it pings for host liveness, listens for the
// queue/progress broadcasts, and lets you cancel/pause/resume the active job
// or reorder/remove waiting items. If the agent socket is missing it lazy-
// spawns the agent itself, so the icon can go online with no browser running.
//
// First-run: `omarchy plugin add` installs this repo but never runs plugin
// code, so until the bundled install.sh has written its marker the widget
// doubles as the setup pane (install.sh also lives at the repo root and is
// runnable by hand).
Panel {
  id: root
  moduleName: "najm.downloads"
  ipcTarget: "najm.downloads"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Invisible unless something is downloading/queued/paused — OR the browser
  // side hasn't been set up yet (then the slot stays so the setup pane is
  // reachable). The bar collapses the slot to zero width off activeItem.visible.
  // `busy` also treats a recent progress broadcast as activity so a lone
  // active download shows even if its one-shot queue broadcast was missed.
  visible: root.busy || root.setupNeeded
  onVisibleChanged: {
    if (!visible) {
      root.close()
      if (button) button.hideOwnTooltip()
    }
  }

  // --- host-status state (Slice 5 scope) ---------------------------

  property bool hostOnline: false
  property bool hostYtdlp: false
  property bool hostFfmpeg: false
  property string hostOsd: "unknown" // unknown | ok | missing | broken
  property string hostOsdIssue: ""
  property bool hostOmarchyShell: true
  property string hostState: "connecting" // connecting | online | offline
  property var queue: []
  property string hostBinary: ""

  readonly property string statusText:
    hostOnline
      ? "yt-dlp: " + (hostYtdlp ? "present" : "MISSING") + " · ffmpeg: " + (hostFfmpeg ? "present" : "MISSING")
      : hostState === "connecting" ? "connecting…" : "offline"

  // Update-drift warnings: an Omarchy update can leave the progress OSD / shell
  // deps silently absent. Surface one concise line when a dep actually checks
  // out missing (empty when healthy) so the failure is visible, not silent.
  readonly property string osdWarn: {
    if (!hostOnline) return ""
    if (hostOsd === "missing" || hostOsd === "broken") {
      var why = hostOsdIssue === "" ? "" : (" — " + hostOsdIssue)
      return "Progress OSD unavailable" + why + " (downloads fall back to notifications)"
    }
    if (!hostOmarchyShell) return "omarchy-shell missing — OSD/notifications disabled"
    return ""
  }

  // --- first-run browser setup (the widget doubles as installer) ------
  //
  // `omarchy plugin add` clones + validates the manifest but runs no scripts,
  // so the browser extension + native host must be installed by the user:
  // until the bundled install.sh has written its marker to
  // ~/.local/state/najm-downloads/installed.json the widget shows a setup
  // pane that streams that script's output, then flips to the monitor view.
  property bool installed: false
  property var installedProfiles: []
  property bool setupRunning: false
  property int setupExitCode: 0
  property string setupLog: ""
  readonly property bool setupNeeded: !root.installed

  // Marker journal (install.sh records where the browser side is served from
  // and at which commit) + the installed clone's resolved HEAD: together they
  // drive the update self-heal (clone updated -> auto re-run install.sh).
  property string installedFrom: ""
  property string servedGit: ""
  property string cloneHead: ""
  property bool markerKnown: false
  property bool headChecked: false
  property bool healAttempted: false

  readonly property bool managedByPlugin:
    root.installed && root.installedFrom !== "" && root.installedFrom === root.pluginDir
  readonly property bool headStale:
    root.managedByPlugin && root.servedGit !== "" && root.cloneHead !== "" &&
    root.servedGit !== root.cloneHead

  function probeCloneHead() {
    headProcess.running = false
    headProcess.running = true
  }

  // Update self-heal: when the installed clone is what the browsers are served
  // from and its HEAD moved past what the marker recorded, re-run install.sh so
  // the browsers are re-pointed at the released popup on the next restart.
  // Never fires for a marker from another checkout, and never when git/the
  // marker can't be read.
  function maybeAutoHeal() {
    if (root.healAttempted) return
    if (!root.markerKnown || !root.headChecked) return
    if (!root.managedByPlugin) return
    if (root.headStale) {
      root.healAttempted = true
      root.startSetup()
    }
  }

  readonly property string homeDir: String(Quickshell.env("HOME") || "")
  readonly property string pluginDir: root.homeDir + "/.config/omarchy/plugins/najm.downloads"
  readonly property string setupScript: root.pluginDir + "/install.sh"
  readonly property string setupMarker: root.homeDir + "/.local/state/najm-downloads/installed.json"

  function appendSetupLog(line) {
    var s = String(line || "").replace(/\s+$/, "")
    if (s === "") return
    root.setupLog += s + "\n"
  }

  function startSetup() {
    if (root.setupRunning) return
    root.setupLog = ""
    root.setupExitCode = 0
    root.setupRunning = true
    setupProcess.running = true
  }

  // Re-instantiates the marker FileView so it re-reads the file after the
  // installer exits (FileView does not re-emit on an identical path).
  function refreshMarker() {
    markerLoader.active = false
    markerLoader.active = true
  }

  Component {
    id: markerComponent
    FileView {
      id: markerView
      path: root.setupMarker
      printErrors: false
      onLoaded: {
        root.installed = true
        try {
          var m = JSON.parse(markerView.text())
          if (m && Array.isArray(m.profiles)) root.installedProfiles = m.profiles
          root.installedFrom = (m && typeof m.installed_from === "string") ? m.installed_from : ""
          root.servedGit = (m && typeof m.served_git === "string") ? m.served_git : ""
        } catch (e) {}
        root.markerKnown = true
        root.maybeAutoHeal()
      }
      onLoadFailed: {
        root.installed = false
        root.installedFrom = ""
        root.servedGit = ""
        root.markerKnown = true
        root.maybeAutoHeal()
      }
    }
  }

  Loader {
    id: markerLoader
    sourceComponent: markerComponent
    active: true
  }

  Process {
    id: setupProcess
    running: false
    command: [root.setupScript]
    stdout: SplitParser {
      onRead: function(line) { root.appendSetupLog(String(line)) }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.appendSetupLog(String(text || ""))
    }
    onExited: function(exitCode) {
      root.setupRunning = false
      root.setupExitCode = exitCode
      root.refreshMarker()
    }
  }

  // Resolved HEAD of the installed clone (best-effort; unknown when the clone
  // isn't a git checkout). Feeds the update self-heal; also read the marker's
  // journal on the same async path so a race can't skip the check.
  Process {
    id: headProcess
    running: false
    command: ["git", "-C", root.pluginDir, "rev-parse", "HEAD"]
    stdout: SplitParser {
      onRead: function(line) { root.cloneHead = String(line).trim() }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.cloneHead = ""
      root.headChecked = true
      root.maybeAutoHeal()
    }
  }

  // Socket path mirrors the host's AGENT_SOCK_* fallback chain.
  readonly property string socketPath: Client.socketPath(
    String(Quickshell.env("XDG_RUNTIME_DIR") || ""),
    String(Quickshell.env("HOME") || "") + "/.local/state")

  // --- agent discovery + lazy spawn --------------------------------

  readonly property var manifestCandidates: [
    String(Quickshell.env("HOME") || "") + "/.config/chromium/NativeMessagingHosts/com.najm.ytdlp.json",
    String(Quickshell.env("HOME") || "") + "/.config/BraveSoftware/Brave-Origin/NativeMessagingHosts/com.najm.ytdlp.json"
  ]
  property int manifestIndex: 0
  property int lastSpawnAt: 0

  function tryNextManifest() {
    manifestIndex++
  }

  FileView {
    id: hostManifest
    path: root.manifestCandidates[root.manifestIndex] || ""
    printErrors: false
    onLoaded: {
      // The manifest is JSON; the `path` field is the canonical host binary
      // location (same value install.sh writes to either browser).
      try {
        var m = JSON.parse(hostManifest.text())
        if (m && typeof m.path === "string") root.hostBinary = m.path
      } catch (e) {}
    }
    onLoadFailed: root.tryNextManifest()
  }

  // --- socket client -------------------------------------------------

  function startConnect() {
    if (sockLoader.active) return
    sockLoader.active = true
  }

  function stopConnect() {
    sockLoader.active = false
  }

  function onSocketConnected() {
    root.hostState = "connecting"
    root.ping()
    root.refreshQueue()

    retryBackoff = 500
    retryTimer.stop()
    pingTimer.restart()
    pingTimeoutTimer.restart()
    syncTimer.restart()
  }

  function onSocketDisconnected() {
    root.markOffline("disconnected")
    retryTimer.restart()
  }

  function onSocketError(error) {
    // Quickshell's Socket can't retry after an error on the same object, so a
    // fresh Socket is always created (sockLoader re-instantiation).
    root.markOffline("error " + error)
    if (error === 2) {           // ServerNotFoundError → no socket file
      root.spawnAgent()
    }
    retryTimer.restart()
  }

  function markOffline(reason) {
    root.hostOnline = false
    root.hostState = "offline"
    root.queue = []
    root.liveProgress = null
    pingTimer.stop()
    pingTimeoutTimer.stop()
    syncTimer.stop()
  }

  function spawnAgent() {
    if (root.hostBinary === "") return
    var now = Date.now()
    if (now - root.lastSpawnAt < 15000) return
    root.lastSpawnAt = now
    // Array argv, no shell: exactly how the host's own lazy spawn works.
    Quickshell.execDetached([root.hostBinary, "--agent"])
  }

  // --- framing -------------------------------------------------------

  property int reqCounter: 0

  function nextReq() {
    root.reqCounter++
    return root.reqCounter
  }

  function sendFrame(obj) {
    var sock = sockLoader.item
    if (sock && sock.connected) {
      sock.write(Client.line(obj))
      sock.flush()
    }
  }

  function ping() {
    sendFrame(Client.ping(root.nextReq()))
  }

  // --- shared queue (monitor scope) --------------------------------

  // Req of the last getQueue bootstrap (to match its one-shot reply); the
  // widget starts no downloads, so there is no req-routed job stream here.
  property int pendingQueueReq: -1

  // Coarse progress broadcast for whichever item is active (works for popup-
  // started jobs too). Terminal job state is req-routed to the job's owner,
  // so the widget learns of done/error/cancelled purely from the queue
  // snapshot (the active slot empties or the waiters shrink).
  property var liveProgress: null
  property real lastProgressAt: 0
  property string jobMessage: ""
  property string jobWarn: ""
  property string jobLevel: "" // "" | "warn" | "error"

  // Latest queue snapshot (from broadcast or a getQueue reply). The active
  // item stays active while paused (SIGSTOP) — only cannot/queued break it.
  readonly property var activeItem: {
    var q = root.queue || []
    for (var i = 0; i < q.length; i++) {
      var st = String(q[i].status)
      if (st === "downloading" || st === "paused") return q[i]
    }
    return null
  }
  readonly property bool activePaused:
    root.activeItem && String(root.activeItem.status) === "paused"
  readonly property var waitingItems: {
    var q = root.queue || []
    var w = []
    for (var i = 0; i < q.length; i++) {
      if (String(q[i].status) === "queued") w.push(q[i])
    }
    return w
  }

  readonly property var progressActive:
    root.liveProgress && root.activeItem &&
    Number(root.liveProgress.queueId) === Number(root.activeItem.id)
      ? root.liveProgress : null

  // Latest progress, even when the queue snapshot is momentarily stale (a
  // lone active job whose queue broadcast was missed while we were
  // reconnecting): fall back to the raw broadcast.
  readonly property var currentProgress:
    root.progressActive || root.liveProgress

  // Watch window for the lone-progress fallback: long enough to span one
  // getQueue self-heal (syncTimer.interval) so a job whose broadcasts stopped
  // (paused, or a missed queue snapshot while reconnecting) stays visible
  // until the next sync confirms its status. Single source for both the busy
  // window and the sync period so they can't drift apart.
  readonly property int progressWindowMs: 30000

  // Anything in the queue (downloading/paused/queued) OR a progress stream
  // seen within the progressWindowMs window. The window matches syncTimer so a
  // paused job (whose broadcasts have stopped) stays visible until the next
  // getQueue confirms its status.
  readonly property bool busy:
    Client.queueBusy(root.queue) ||
    (root.currentProgress && Date.now() - root.lastProgressAt < root.progressWindowMs)

  // Bar-indicator values (progress % + centered label). The pct stays frozen
  // at its last value while SIGSTOP-paused; a queue-only state has no active
  // item, so the label falls back to the waiting count.
  readonly property real barPct: root.currentProgress && root.currentProgress.pct != null
    ? Math.max(0, Math.min(100, Number(root.currentProgress.pct))) : 0
  readonly property string barLabel: root.activeItem
    ? Math.round(root.barPct) + "%"
    : (root.waitingItems.length ? "Q" + root.waitingItems.length
       : (root.currentProgress ? "\u2026" : ""))

  // Setup-needed overrides: a full-bar "!" badge in the urgent colour so it
  // reads as attention, not progress, while the browser side is missing.
  readonly property real maybeBarPct: root.setupNeeded ? 100 : root.barPct
  readonly property string maybeBarLabel: root.setupNeeded ? "!" : root.barLabel
  readonly property color maybeFill:
    root.setupNeeded ? Color.urgent : (root.activePaused ? Qt.darker(Color.accent, 1.4) : Color.accent)

  // --- label readability over the fill --------------------------------

  // Relative-luminance helpers (WCAG). Used only to pick a readable label
  // color for whichever surface the fill slides under the text on.
  function relLuminance(c) {
    function lin(v) {
      v = Math.max(0, Math.min(1, v))
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  }
  function contrastRatio(a, b) {
    var la = root.relLuminance(a), lb = root.relLuminance(b)
    var lo = Math.min(la, lb), hi = Math.max(la, lb)
    return (hi + 0.05) / (lo + 0.05)
  }
  // Pick whichever theme base color contrasts best against the accent fill
  // (foreground over a dark accent, background over a light one).
  readonly property color accentText:
    root.contrastRatio(Color.accent, Color.foreground) >=
    root.contrastRatio(Color.accent, Color.background)
      ? Color.foreground : Color.background

  // The label is rendered as two clipped copies (see the button): the copy
  // over the filled region uses `accentText`, the copy over the dark track
  // keeps `Color.popups.text`. Clipping the two against the fill rect makes
  // every glyph readable no matter how the fill sits under the text —
  // a single whole-string color flip (the earlier attempt) left the half of
  // the label still over the track unreadable the moment it straddled.

  function cancelActive() {
    sendFrame(Client.cancel(root.nextReq()))
  }

  function removeWaiting(queueId) {
    sendFrame(Client.cancel(root.nextReq(), queueId))
  }

  function moveWaiting(queueId, newIndex) {
    // newIndex is 0-based within the *waiting* subgroup (host contract).
    sendFrame(Client.reorder(root.nextReq(), queueId, newIndex))
  }

  function refreshQueue() {
    root.pendingQueueReq = root.nextReq()
    sendFrame(Client.getQueue(root.pendingQueueReq))
  }

  function applyQueue(q) {
    root.queue = q
    // Drop stale progress when the active item (if any) no longer matches —
    // keeps a finished job's last broadcast from pinning the bar visible.
    var active = null
    for (var i = 0; i < q.length; i++) {
      var st = String(q[i].status)
      if (st === "downloading" || st === "paused") { active = q[i].id; break }
    }
    if (active === null ||
        (root.liveProgress && Number(root.liveProgress.queueId) !== Number(active))) {
      root.liveProgress = null
    }
  }

  function handleLine(raw) {
    var obj = Client.parseLine(raw)
    if (!obj) return

    if (Client.isPingReply(obj)) {
      // Only accept a ping reply whose req matches what we sent.
      root.hostOnline = true
      root.hostYtdlp = obj.ytdlp === true
      root.hostFfmpeg = obj.ffmpeg === true
      root.hostOsd = String(obj.osd || "unknown")
      root.hostOsdIssue = String(obj.osdIssue || "")
      if (obj.deps && typeof obj.deps === "object") {
        root.hostOmarchyShell = String(obj.deps.omarchyShell) !== "false"
      }
      root.hostState = "online"
      pingTimeoutTimer.restart()
      return
    }

    if (Client.isQueueBroadcast(obj)) {
      root.applyQueue(obj.queue)
      return
    }

    if (Client.isProgressBroadcast(obj)) {
      // Coarse progress (works whether this widget or the popup owns the
      // active job). Keyed by queueId so the progress view only binds to the
      // item it belongs to.
      root.liveProgress = obj
      root.lastProgressAt = Date.now()
      return
    }

    // A getQueue reply is the same snapshot as the broadcast; distinguish it
    // by its req (sent from refreshQueue on connect/reopen).
    if (Client.isQueueReply(obj)) {
      if (obj.req === root.pendingQueueReq) root.applyQueue(obj.queue)
      return
    }
  }

  // --- retry / keepalive timers --------------------------------------

  property int retryBackoff: 500

  Timer {
    id: retryTimer
    interval: root.retryBackoff
    onTriggered: {
      retryBackoff = Math.min(8000, retryBackoff * 2)
      root.stopConnect()
      root.startConnect()
    }
  }

  Timer {
    id: pingTimer
    interval: 15000
    repeat: true
    onTriggered: {
      if (root.hostOnline) root.ping()
    }
  }

  Timer {
    id: pingTimeoutTimer
    interval: 6000
    onTriggered: {
      // Connected but the agent stopped answering → drop and reconnect.
      if (!root.hostOnline && sockLoader.item && sockLoader.item.connected) {
        root.stopConnect()
        retryBackoff = 500
        retryTimer.restart()
      }
    }
  }

  // Periodic getQueue so the widget self-heals even if it misses a one-shot
  // queue broadcast (e.g. it was reconnecting when a lone download started):
  // a stale-empty view converges within one interval, a finished job is
  // dropped too. One-shot reply, every progressWindowMs (30s) while connected
  // (coarse progress broadcasts already stream live during a download, so this
  // is purely the self-heal backstop).
  Timer {
    id: syncTimer
    interval: root.progressWindowMs
    repeat: true
    onTriggered: {
      if (root.hostOnline) root.refreshQueue()
    }
  }

  // A fresh Socket per connect attempt (Quickshell cannot reconnect a failed
  // socket object).
  Component {
    id: socketComponent
    Socket {
      id: sock
      path: root.socketPath
      connected: true
      parser: SplitParser {
        splitMarker: "\n"
        onRead: function(data) { root.handleLine(String(data)) }
      }
      onConnectedChanged: {
        if (sock.connected) root.onSocketConnected()
        else root.onSocketDisconnected()
      }
      onError: function(error) { root.onSocketError(error) }
    }
  }

  Loader {
    id: sockLoader
    sourceComponent: socketComponent
    active: false
  }

  // --- button: conditional progress-bar indicator ---------------------

  // A slim progress bar in place of the glyph; the root Panel hides the whole
  // widget when the queue is empty. Left-click opens the popup (the queue/
  // progress view), right-click pings.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : Math.round(Style.space(120))
    fixedHeight: vertical ? Math.round(Style.space(120)) : -1
    tooltipText: root.setupNeeded
      ? "Najm Downloader — setup needed (open for install)"
      : "Downloads · " + root.statusText
    onPressed: function(btn) {
      if (btn === Qt.LeftButton) root.toggle()
      else root.ping()
    }

    Rectangle {
      id: track
      anchors.fill: parent
      anchors.margins: Math.round(Style.space(3))
      radius: Math.min(height / 2, Style.cornerRadius)
      color: Qt.darker(Color.popups.text, 2.4)
    }
    Rectangle {
      z: 1
      x: track.x
      y: button.vertical ? track.y + track.height * (1 - root.maybeBarPct / 100) : track.y
      width: button.vertical ? track.width : track.width * root.maybeBarPct / 100
      height: button.vertical ? track.height * root.maybeBarPct / 100 : track.height
      radius: Math.min(track.height / 2, Style.cornerRadius)
      color: root.maybeFill

      Behavior on width {
        enabled: !button.vertical
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }
      Behavior on height {
        enabled: button.vertical
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }
      Behavior on y {
        enabled: button.vertical
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }
    }
    Text {
      id: barText
      visible: false
      anchors.centerIn: parent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      textFormat: Text.PlainText
      text: root.maybeBarLabel
      color: root.accentText
    }

    // Two clipped copies of `barText` geometry: the part over the accent fill
    // uses a fill-contrasting color, the part over the dark track keeps
    // Color.popups.text. Both are centered like the single label; each clip
    // reveals only its half of the text, so a glyph straddling the boundary
    // still shows each of its pixels in the color that contrasts with the
    // surface underneath.
    Item {
      id: fillLabelClip
      z: 2
      x: track.x
      y: button.vertical
         ? track.y + track.height * (1 - root.maybeBarPct / 100)
         : track.y
      width: button.vertical ? track.width : track.width * root.maybeBarPct / 100
      height: button.vertical ? track.height * root.maybeBarPct / 100 : track.height
      clip: true
      Text {
        // Anchors are parent/sibling-only, so centre on `button` by hand:
        // its centre, expressed in this clip's coordinates.
        x: button.width / 2 - implicitWidth / 2 - parent.x
        y: button.height / 2 - implicitHeight / 2 - parent.y
        font.family: barText.font.family
        font.pixelSize: barText.font.pixelSize
        font.bold: barText.font.bold
        textFormat: Text.PlainText
        text: root.maybeBarLabel
        color: root.accentText
      }
      Behavior on width {
        enabled: !button.vertical
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }
      Behavior on height {
        enabled: button.vertical
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }
      Behavior on y {
        enabled: button.vertical
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }
    }
    Item {
      id: trackLabelClip
      z: 2
      x: button.vertical ? track.x : track.x + track.width * root.maybeBarPct / 100
      y: track.y
      width: button.vertical ? track.width : track.width * (1 - root.maybeBarPct / 100)
      height: button.vertical ? track.height * (1 - root.maybeBarPct / 100) : track.height
      clip: true
      Text {
        x: button.width / 2 - implicitWidth / 2 - parent.x
        y: button.height / 2 - implicitHeight / 2 - parent.y
        font.family: barText.font.family
        font.pixelSize: barText.font.pixelSize
        font.bold: barText.font.bold
        textFormat: Text.PlainText
        text: root.maybeBarLabel
        color: Color.popups.text
      }
      Behavior on width {
        enabled: !button.vertical
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }
      Behavior on height {
        enabled: button.vertical
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }
      Behavior on x {
        enabled: !button.vertical
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(420), Style.space(420))
    contentHeight: popup.fittedContentHeight(body.implicitHeight, Style.space(600))

    // Esc closes the popup. Attached to a focusable Item — PopupWindow is
    // not an Item, so the window itself rejects Keys.
    Item {
      anchors.fill: parent
      activeFocusOnTab: true
      focus: true
      Keys.onEscapePressed: root.close()
    }

    Column {
      id: body
      width: parent.width
      spacing: Style.spacing.md

      // --- header: identity + status --------------------------------
      Text {
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        textFormat: Text.PlainText
        text: "Najm Downloader"
        color: Color.popups.text
      }
      Text {
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
        text: root.statusText
        color: root.hostOnline ? Qt.darker(Color.popups.text, 1.5) : Color.urgent
      }
      // Update-drift warning: an Omarchy update that breaks the progress OSD or
      // the shell deps shows up here instead of failing silently.
      Text {
        width: parent.width
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.osdWarn
        color: Qt.darker(Color.popups.text, 1.5)
        visible: root.osdWarn !== ""
      }

      // --- browser-setup pane (first run) -----------------------------
      Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: root.setupNeeded || root.setupRunning

        Item { width: parent.width; implicitHeight: Style.space(2) }
        Rectangle {
          width: parent.width
          height: 1
          color: Qt.darker(Color.popups.text, 2.2)
        }
        Item { width: parent.width; implicitHeight: Style.space(2) }

        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          textFormat: Text.PlainText
          text: root.setupRunning ? "Installing browser extension…" : "Browser extension not installed"
          color: Color.popups.text
        }
        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: root.setupExitCode !== 0 && root.setupLog !== "" && !root.setupRunning
            ? "Setup finished with an error — the log below shows what happened."
            : "This widget watches the shared download queue; the Najm Downloader " +
              "browser extension (and its yt-dlp native host) drives it. Install the " +
              "extension + host now, then restart the installed browsers so they load it."
          color: Qt.darker(Color.popups.text, 1.5)
        }
        Button {
          id: setupBtn
          width: parent.width
          text: root.setupRunning ? "Installing…"
            : (root.setupExitCode === 0 && root.setupLog !== "" ? "Re-run install" : "Install browser extension")
          enabled: !root.setupRunning
          foreground: Color.popups.text
          fontFamily: Style.font.family
          tooltipText: "Runs: " + root.setupScript
          bordered: true
          onClicked: root.startSetup()
        }
        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          visible: root.setupLog !== ""
          text: root.setupLog
          color: Qt.darker(Color.popups.text, 1.5)
        }
        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          visible: root.installed
          text: "Done. Restart the browsers to load the extension." +
            (root.installedProfiles.length ? "\nConfigured browsers:\n" + root.installedProfiles.join(" · ") : "")
          color: Color.popups.text
        }
      }

      Item { width: parent.width; implicitHeight: Style.space(2) }

      // --- active download (progress view) ----------------------------
      Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: !!root.activeItem

        Item { width: parent.width; implicitHeight: Style.space(2) }
        Rectangle {
          width: parent.width
          height: 1
          color: Qt.darker(Color.popups.text, 2.2)
        }
        Item { width: parent.width; implicitHeight: Style.space(2) }

        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          elide: Text.ElideRight
          text: root.activeItem ? ((root.activeItem.selection && root.activeItem.selection.title) || root.activeItem.url || "Downloading") : ""
          color: Color.popups.text
        }

        // Bar + pct, mirroring the popup progress row. Height 6px, rounded.
        Row {
          width: parent.width
          spacing: Style.spacing.md
          Rectangle {
            width: parent.parent.width - pctLabel.implicitWidth - parent.spacing
            height: 6
            radius: 3
            color: Qt.darker(Color.popups.text, 2.4)
            Rectangle {
              width: parent.width * Math.max(0, Math.min(100, root.progressActive ? root.progressActive.pct || 0 : 0)) / 100
              height: parent.height
              radius: parent.radius
              color: Color.accent
            }
          }
          Text {
            id: pctLabel
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            textFormat: Text.PlainText
            text: (root.progressActive && root.progressActive.pct != null)
              ? Math.round(root.progressActive.pct) + "%" : ""
            color: Color.popups.text
          }
        }

        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          visible: root.progressActive != null
          text: {
            var p = root.progressActive
            if (!p) return ""
            var d = p.downloaded, t = p.total
            if (t != null) {
              return Formats.fmtBytes(d != null ? d : 0) + " / ~" + Formats.fmtBytes(t)
            }
            return d != null ? Formats.fmtBytes(d) + " downloaded" : ""
          }
          color: Qt.darker(Color.popups.text, 1.5)
        }
        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          visible: {
            var p = root.progressActive
            return p != null && (p.speed || p.eta)
          }
          text: {
            var p = root.progressActive
            if (!p) return ""
            var parts = []
            if (p.speed) parts.push("speed " + p.speed)
            if (p.eta) parts.push(p.eta + " left")
            return parts.join(" · ")
          }
          color: Qt.darker(Color.popups.text, 1.5)
        }

        // Control row: cancel the active download, or pause/resume it.
        Row {
          width: parent.width
          spacing: Style.spacing.md

          Button {
            id: cancelBtn
            width: parent.width / 2 - parent.spacing / 2
            text: "Cancel"
            foreground: Color.urgent
            fontFamily: Style.font.family
            tooltipText: "Cancel the current download"
            bordered: true
            onClicked: root.cancelActive()
          }
          Button {
            id: pauseBtn
            width: parent.width / 2 - parent.spacing / 2
            text: root.activePaused ? "Resume" : "Pause"
            foreground: Color.popups.text
            fontFamily: Style.font.family
            tooltipText: root.activePaused ? "Resume the download" : "Pause the download"
            bordered: true
            onClicked: sendFrame(Client.pause(root.nextReq(), !root.activePaused))
          }
        }
      }

      // --- waiting queue ------------------------------------------------
      Column {
        width: parent.width
        spacing: Style.spacing.xs
        visible: root.waitingItems.length > 0

        Item { width: parent.width; implicitHeight: Style.space(2) }
        Rectangle {
          width: parent.width
          height: 1
          color: Qt.darker(Color.popups.text, 2.2)
        }
        Item { width: parent.width; implicitHeight: Style.space(2) }

        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          textFormat: Text.PlainText
          text: "Queue (" + root.waitingItems.length + " waiting)"
          color: Qt.darker(Color.popups.text, 1.5)
        }

        // One row per waiting item: position, title + summary, move/remove.
        Repeater {
          model: root.waitingItems
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: parent.parent.width
            implicitHeight: Math.max(Style.space(28), queueTitle.implicitHeight + queueOpts.implicitHeight + Style.space(8))
            radius: Style.cornerRadius
            color: Qt.darker(Color.popups.text, 3.3)

            Row {
              anchors.fill: parent
              anchors.margins: Style.spacing.sm
              spacing: Style.spacing.md

              Text {
                id: queuePos
                width: Style.space(14)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                textFormat: Text.PlainText
                text: String(index + 1)
                color: Qt.darker(Color.popups.text, 1.8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - queuePos.width - queueBtns.implicitWidth - parent.spacing * 2
                spacing: 0
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: queueTitle
                  width: parent.width
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: {
                    var sel = modelData.selection
                    return (sel && sel.title) || modelData.url || "queued"
                  }
                  color: Color.popups.text
                }
                Text {
                  id: queueOpts
                  width: parent.width
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: Formats.summarizeSelection(modelData.selection) || "queued"
                  color: Qt.darker(Color.popups.text, 1.5)
                }
              }

              Row {
                id: queueBtns
                spacing: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter

                Button {
                  text: "\u2191"
                  enabled: index > 0
                  tooltipText: "Move earlier"
                  foreground: Qt.darker(Color.popups.text, 1.5)
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(3)
                  onClicked: root.moveWaiting(modelData.id, index - 1)
                }
                Button {
                  text: "\u2193"
                  enabled: index < root.waitingItems.length - 1
                  tooltipText: "Move later"
                  foreground: Qt.darker(Color.popups.text, 1.5)
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(3)
                  onClicked: root.moveWaiting(modelData.id, index + 1)
                }
                Button {
                  text: "\u2715"
                  tooltipText: "Remove from queue"
                  foreground: Color.urgent
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(3)
                  onClicked: root.removeWaiting(modelData.id)
                }
              }
            }
          }
        }
      }

      // --- job terminal message (warn/error/done/cancelled) ------------
      Column {
        width: parent.width
        spacing: Style.spacing.xs
        visible: root.jobMessage !== "" || root.jobWarn !== ""

        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          visible: root.jobWarn !== ""
          text: root.jobWarn
          color: Qt.darker(Color.popups.text, 1.5)
        }
        Text {
          width: parent.width
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          visible: root.jobMessage !== ""
          text: root.jobMessage
          color: root.jobLevel === "error" ? Color.urgent : Color.popups.text
        }
      }
    }
  }

  Component.onCompleted: {
    root.startConnect()
    root.probeCloneHead()
  }
}
const DEFAULTS = {
  subsOn: false,
  auto: false,
  langs: "en",
  langsTouched: false,
  subFormat: "srt",
  convertSrt: false,
  embed: false,
  playlist: false,
  chapters: "off", // "off" | "embed" | "split"
  outDir: "~/Videos",
};

function fmtBytes(n) {
  if (n == null || n <= 0) return "";
  if (n >= 1e9) return (n / 1e9).toFixed(2).replace(/0+$/, "").replace(/\.$/, "") + " GB";
  if (n >= 1e6) return Math.round(n / 1e6) + " MB";
  return Math.max(1, Math.round(n / 1e3)) + " KB";
}

function fmtSizeStr(bytes, approx = true) {
  if (bytes == null) return "";
  return (approx ? "~" : "") + fmtBytes(bytes);
}

const SUB_FMT_WHITELIST = ["srt", "vtt", "ttml", "webvtt", "ass", "ssa", "sbv", "lrc"];
const SUB_FMT_LABEL = {
  srt: "SRT", vtt: "VTT", ttml: "TTML", webvtt: "WebVTT",
  ass: "ASS", ssa: "SSA", sbv: "SBV", lrc: "LRC",
};

const el = (id) => document.getElementById(id);

let prefs = { ...DEFAULTS };
let url = "";
let probeData = null;
let playlistTouched = false;

function send(msg) {
  return chrome.runtime.sendMessage(msg).catch((e) => ({ ok: false, error: String(e) }));
}

function checkHost() {
  send({ action: "ping" }).then((r) => {
    el("hostDot").className = "dot " + (r && r.ok ? "on" : "off");
  });
}

function loadPrefs() {
  return chrome.storage.local.get(null).then((s) => {
    for (const k of Object.keys(DEFAULTS)) {
      if (s[k] !== undefined) prefs[k] = s[k];
    }
    el("subsOn").checked = prefs.subsOn;
    el("autoSubs").checked = prefs.auto;
    el("subFormat").value = prefs.subFormat;
    el("subFormat").disabled = true;
    el("convertSrt").checked = prefs.convertSrt;
    el("embed").checked = prefs.embed;
    el("playlist").checked = prefs.playlist;
    el("chapters").value = prefs.chapters;
    el("outDir").textContent = prefs.outDir;
  });
}

function savePrefs() {
  prefs.subsOn = el("subsOn").checked;
  prefs.auto = el("autoSubs").checked;
  if (el("langs").value) prefs.langs = el("langs").value;
  prefs.subFormat = el("subFormat").value;
  prefs.convertSrt = el("convertSrt").checked;
  prefs.embed = el("embed").checked;
  prefs.playlist = el("playlist").checked;
  prefs.chapters = el("chapters").value || "off";
  chrome.storage.local.set(prefs);
}

function plausibleVideoUrl(u) {
  return /^https?:\/\//i.test(u || "");
}

// Last probe result, keyed by the exact URL it was run against. Reopening the
// popup on the same page restores the options instantly instead of re-probing;
// the manual Probe button still always refetches.
const PROBE_CACHE_KEY = "lastProbe";

function saveProbeCache(sourceUrl, data) {
  return chrome.storage.session
    .set({ [PROBE_CACHE_KEY]: { url: sourceUrl, data } })
    .catch(() => {});
}

async function loadProbeCache() {
  try {
    const o = await chrome.storage.session.get(PROBE_CACHE_KEY);
    const entry = o[PROBE_CACHE_KEY];
    return entry && entry.url && entry.data ? entry : null;
  } catch (e) {
    return null;
  }
}

function probe() {
  url = el("url").value.trim();
  setWarn(null);
  if (!plausibleVideoUrl(url)) {
    el("probeArea").hidden = false;
    el("probeErr").hidden = false;
    el("probeErr").textContent = "Enter an http(s) video URL first.";
    return;
  }
  el("probeBtn").disabled = true;
  el("downloadBtn").disabled = true;
  el("probeErr").hidden = true;
  el("meta").textContent = "Probing…";
  el("probeArea").hidden = false;

  send({ action: "probe", url }).then((r) => {
    el("probeBtn").disabled = false;
    if (!r || !r.ok) {
      el("probeErr").hidden = false;
      el("probeErr").textContent = (r && r.error) || "Probe failed";
      el("meta").textContent = "";
      return;
    }
    saveProbeCache(url, r);
    renderProbe(r);
  });
}

function fmtOrder(a, b) {
  if ((a.height || 0) !== (b.height || 0)) return (b.height || 0) - (a.height || 0);
  const aio = a.vcodec && a.vcodec !== "none" ? 0 : 1;
  const bio = b.vcodec && b.vcodec !== "none" ? 0 : 1;
  if (aio !== bio) return aio - bio;
  return String(a.id).localeCompare(String(b.id), undefined, { numeric: true });
}

function codecRank(c) {
  const s = String(c || "").toLowerCase();
  if (s.startsWith("avc")) return 3;      // h264 / mp4: most compatible
  if (s.startsWith("vp09") || s.startsWith("vp9")) return 2;
  if (s.startsWith("av01")) return 1;     // av1: most efficient but least compatible
  return 0;
}

function pickVideo(top) {
  return top.slice().sort((a, b) =>
    ((b.acodec && b.acodec !== "none" ? 100 : 0) + codecRank(b.vcodec)) -
      ((a.acodec && a.acodec !== "none" ? 100 : 0) + codecRank(a.vcodec))
  )[0];
}

function pickAudio(list) {
  const fam = (f) => (String(f.acodec || "").toLowerCase().startsWith("mp4a") ? 0 : 1);
  const num = (f) => parseInt(String(f.id), 10) || 0;
  return list.slice().sort((a, b) => fam(a) - fam(b) || num(b) - num(a))[0];
}

function presetFormats() {
  const presets = [];
  const add = (id, label, opts = {}) =>
    presets.push({ id, label, preset: true, res: opts.res || "best", audioOnly: !!opts.audioOnly });
  add("preset-best", "Best");
  add("preset-2160", "2160p (4K)", { res: "2160" });
  add("preset-1440", "1440p", { res: "1440" });
  add("preset-1080", "1080p", { res: "1080" });
  add("preset-720", "720p", { res: "720" });
  add("preset-480", "480p", { res: "480" });
  add("preset-360", "360p", { res: "360" });
  add("preset-240", "240p", { res: "240" });
  add("preset-144", "144p", { res: "144" });
  add("preset-audio", "Audio only", { audioOnly: true });
  return presets;
}

function bestAudioSize() {
  const a = (probeData.formats || []).filter((x) => !x.vcodec || x.vcodec === "none");
  const best = a.length ? pickAudio(a) : null;
  return best && best.size ? best.size : 0;
}

function renderFormats() {
  const sel = el("formatSelect");
  sel.innerHTML = "";
  const all = probeData.formats || [];
  const formatHint = el("formatHint");

  if (!all.length) {
    if (probeData.meta && probeData.meta.is_playlist) {
      const presets = presetFormats();
      probeData.formats = presets;
      for (const p of presets) {
        const o = document.createElement("option");
        o.value = String(p.id);
        o.textContent = p.label;
        sel.appendChild(o);
      }
      sel.value = "preset-best";
      sel.disabled = false;
      updateSizeEstimate();
      formatHint.hidden = !probeData.meta.sample_error;
      formatHint.textContent = probeData.meta.sample_error
        ? "Couldn't reach the first video to read its resolutions — using presets."
        : "";
      return;
    }
    const o = document.createElement("option");
    o.value = "";
    o.textContent = "No formats reported";
    sel.appendChild(o);
    sel.disabled = true;
    updateSizeEstimate();
    return;
  }

  const byHeight = new Map();
  const audioOnly = [];
  for (const f of all) {
    if (!f.vcodec || f.vcodec === "none") audioOnly.push(f);
    else {
      const h = f.height || 0;
      if (!byHeight.has(h)) byHeight.set(h, []);
      byHeight.get(h).push(f);
    }
  }

  const collapsed = [];
  for (const grp of byHeight.values()) collapsed.push(pickVideo(grp));
  collapsed.sort(fmtOrder); // non-audio first, big → small
  if (audioOnly.length) collapsed.push(pickAudio(audioOnly)); // single best audio-only option

  probeData.formats = collapsed;

  const bonus = bestAudioSize();
  for (const f of collapsed) {
    const o = document.createElement("option");
    o.value = String(f.id);
    o.title = `id ${f.id}`;
    if (!f.vcodec || f.vcodec === "none") {
      o.textContent = "Audio only" + fmtSizeStr(f.size);
    } else {
      let label = f.height ? f.height + "p" : "Video";
      if (f.fps && f.fps > 30) label += " · " + Math.round(f.fps) + "fps";
      let sz = f.size;
      if (sz && (!f.acodec || f.acodec === "none")) sz += bonus;
      label += fmtSizeStr(sz);
      o.textContent = label;
    }
    sel.appendChild(o);
  }
  sel.disabled = false;

  const favored = collapsed.find((f) => f.vcodec && f.vcodec !== "none") || collapsed[0];
  sel.value = String(favored.id);

  formatHint.hidden = !(probeData.meta && probeData.meta.sample);
  formatHint.textContent = probeData.meta && probeData.meta.sample
    ? "Resolutions from the first video in the playlist: " + probeData.meta.sample
    : "";
  updateSizeEstimate();
}

function updateSizeEstimate() {
  const meta = probeData && probeData.meta;
  const row = el("sizeRow");
  const span = el("sizeEst");
  if (!meta || !row || !span) return;
  let bytes = null;
  const fmt = selectedFormat();
  if (fmt && (fmt.audioOnly || fmt.formatId)) {
    const f = (probeData.formats || []).find((x) => String(x.id) === String(fmt.formatId));
    if (f && f.size) {
      bytes = f.size;
      if (!fmt.audioOnly && (!f.acodec || f.acodec === "none")) bytes += bestAudioSize();
    }
  }
  if (bytes == null) {
    row.hidden = true;
    return;
  }
  const count = meta.is_playlist ? (meta.playlist_count || 0) : 1;
  let txt = fmtSizeStr(bytes);
  if (count > 1) txt += " × " + count + " videos";
  span.textContent = txt;
  row.hidden = false;
}

function renderSubFormats() {
  const sel = el("subFormat");
  const offered = (probeData.subFormats || []).filter((x) => SUB_FMT_WHITELIST.includes(x));
  const list = offered.length ? offered : ["srt", "vtt"];
  sel.innerHTML = "";
  for (const c of list) {
    const o = document.createElement("option");
    o.value = c;
    o.textContent = SUB_FMT_LABEL[c] || c.toUpperCase();
    sel.appendChild(o);
  }
  const def = list.includes(prefs.subFormat)
    ? prefs.subFormat
    : list.includes("srt") ? "srt" : list[0];
  sel.value = def;
  prefs.subFormat = sel.value;
  sel.disabled = false;
}

function renderLangs() {
  const sel = el("langs");
  const manual = Object.keys(probeData.subs || {});
  const auto = Object.keys(probeData.autoSubs || {});
  sel.innerHTML = "";

  const withAuto = el("autoSubs").checked;
  const entries = new Map();
  for (const c of manual) entries.set(c, { code: c, autoOnly: false });
  for (const c of auto) {
    if (!entries.has(c)) entries.set(c, { code: c, autoOnly: true });
  }

  const noSubs = entries.size === 0;
  el("subsOn").disabled = noSubs;
  el("langs").disabled = noSubs;
  el("subHint").hidden = !noSubs;
  el("subHint").textContent = noSubs ? "No subtitles are offered by this video" : "";
  if (noSubs) {
    el("subsOpts").style.display = "none";
    return;
  }
  el("subsOpts").style.display = "";

  const isPlaylist = !!(probeData.meta && probeData.meta.is_playlist);
  const langOk = prefs.langs && (prefs.langs === "all" || entries.has(prefs.langs));
  let want;
  if (isPlaylist && prefs.langsTouched && langOk) {
    want = prefs.langs;
  } else if (isPlaylist) {
    want = "all";
  } else {
    want = prefs.langs && !withAuto && !manual.includes(prefs.langs)
      ? (manual.length ? manual[0] : "all")
      : (prefs.langs && entries.has(prefs.langs) ? prefs.langs : (manual.includes("en") ? "en" : [...entries.keys()][0]));
  }
  prefs.langs = want === "all" ? "all" : (entries.has(want) ? want : [...entries.keys()][0]);

  const oAll = document.createElement("option");
  oAll.value = "all";
  oAll.textContent = withAuto ? "All available (subtitles + auto en)" : "All available (subtitles)";
  sel.appendChild(oAll);

  const manualGroup = document.createElement("optgroup");
  manualGroup.label = "Subtitles";
  for (const c of manual) {
    const o = document.createElement("option");
    o.value = c;
    o.textContent = c;
    manualGroup.appendChild(o);
  }
  sel.appendChild(manualGroup);

  if (withAuto && auto.length) {
    const autoGroup = document.createElement("optgroup");
    autoGroup.label = "Auto-generated";
    for (const c of auto) {
      if (entries.get(c).autoOnly) {
        const o = document.createElement("option");
        o.value = c;
        o.textContent = c;
        autoGroup.appendChild(o);
      }
    }
    if (autoGroup.children.length) sel.appendChild(autoGroup);
  }

  sel.value = [...sel.options].some((o) => o.value === prefs.langs) ? prefs.langs : "all";
  renderSubFormats();
}

const CHAPTER_CONTAINERS = ["mp4", "webm", "mkv"];

function chaptersControlState() {
  const meta = probeData && probeData.meta;
  const count = meta ? meta.chapterCount : null;
  const fmt = selectedFormat();
  if (!count || fmt.audioOnly) return { visible: false, enabled: false, reason: "" };
  let ok = true;
  let reason = "";
  const ext = (fmt.formatExt || "").toLowerCase();
  if (fmt.formatId && ext && !CHAPTER_CONTAINERS.includes(ext)) {
    ok = false;
    reason = `Chapters need MKV/MP4/WebM — this format is ${ext || "a container that can't hold them"}.`;
  }
  return { visible: true, enabled: ok, reason };
}

function updateChaptersControl() {
  const wrap = el("chaptersWrap");
  const sel = el("chapters");
  const hint = el("chaptersHint");
  const st = chaptersControlState();
  wrap.hidden = !st.visible;
  if (!st.visible) return;
  sel.disabled = !st.enabled;
  hint.hidden = !st.enabled;
  hint.textContent = st.reason && !st.enabled ? st.reason : "";
  sel.value = prefs.chapters || "off";
  const label = wrap.querySelector(".field-label");
  if (label) label.textContent = `Video sections (${probeData.meta.chapterCount} chapters)`;
}

function renderProbe(r) {
  probeData = r;
  const meta = r.meta || {};
  const tag = [];
  if (meta.is_playlist) tag.push("playlist" + (meta.playlist_count ? ` · ${meta.playlist_count}` : ""));
  if (meta.chapterCount) tag.push(meta.chapterCount + " chapters");
  if (meta.duration) tag.push(Math.round(meta.duration) + "s");
  if (meta.extractor) tag.push(meta.extractor);

  el("meta").innerHTML =
    `<b>${escapeHtml(meta.title || "Untitled")}</b>` +
    (tag.length ? `<span class="tag">${tag.map(escapeHtml).join(" · ")}</span>` : "");

  if (meta.is_playlist) {
    if (!playlistTouched) {
      el("playlist").checked = true;
      prefs.playlist = true;
    }
  } else if (!playlistTouched) {
    el("playlist").checked = false;
    prefs.playlist = false;
  }

  renderFormats();
  updateChaptersControl();
  renderLangs();
  el("opts").hidden = false;
  el("downloadBtn").disabled = false;
  el("meta").style.display = "";
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function selectedFormat() {
  const id = el("formatSelect").value;
  const f = probeData.formats.find((x) => String(x.id) === id);
  if (!f) return { audioOnly: false, formatId: null, formatHasAudio: false, formatExt: null, resolution: null };
  if (f.preset) {
    return {
      audioOnly: f.audioOnly,
      formatId: null,
      formatHasAudio: false,
      formatExt: null,
      resolution: f.res || "best",
    };
  }
  if (!f.vcodec || f.vcodec === "none") {
    return { audioOnly: true, formatId: String(f.id), formatHasAudio: false, formatExt: f.ext || null, resolution: null };
  }
  return {
    audioOnly: false,
    formatId: String(f.id),
    formatHasAudio: !!(f.acodec && f.acodec !== "none"),
    formatExt: f.ext || null,
    resolution: null,
  };
}

function buildSelection() {
  savePrefs();
  const fmt = selectedFormat();
  const meta = probeData && probeData.meta;
  return {
    title: (meta && (meta.sample || meta.title)) || "",
    audioOnly: fmt.audioOnly,
    formatId: fmt.formatId,
    formatHasAudio: !!fmt.formatHasAudio,
    formatExt: fmt.formatExt,
    resolution: fmt.resolution,
    playlist: prefs.playlist,
    chapters: (!el("chaptersWrap").hidden && !el("chapters").disabled) ? prefs.chapters : "off",
    subs: {
      on: prefs.subsOn && !el("subsOn").disabled,
      auto: prefs.auto,
      langs: prefs.langs || "all",
      subFormat: prefs.subFormat,
      convert: prefs.convertSrt ? "srt" : "best",
      embed: prefs.embed,
    },
    outputDir: prefs.outDir,
  };
}

function setProgress(p) {
  const fill = el("barFill");
  fill.style.width = (p ?? 0) + "%";
  el("pct").textContent = p != null ? Math.round(p) + "%" : "";
}

let warnMsg = null;

function setWarn(msg) {
  warnMsg = msg || null;
  el("warn").hidden = !warnMsg;
  el("warn").textContent = warnMsg || "";
}

function onHostEvent(snapshot) {
  if (snapshot.status === "downloading") {
    el("progress").hidden = false;
    el("downloadBtn").hidden = true;
    el("downloadBtn").disabled = true;
    el("cancelBtn").hidden = false;
    setProgress(snapshot.pct ?? 0);
    const d = snapshot.downloaded, t = snapshot.total;
    el("dlSize").textContent = t != null
      ? fmtBytes(d != null ? d : 0) + " / ~" + fmtBytes(t)
      : (d != null ? fmtBytes(d) + " downloaded" : "");
    el("speed").textContent = snapshot.speed ? `speed ${snapshot.speed}` : "";
    el("speed").textContent += snapshot.eta ? ` · ${snapshot.eta} left` : "";
    el("msg").textContent = snapshot.message || "";
  } else if (snapshot.status === "done") {
    el("progress").hidden = true;
    el("dlSize").textContent = "";
    el("downloadBtn").hidden = false;
    el("downloadBtn").disabled = false;
    el("cancelBtn").hidden = true;
    if (snapshot.message === "Cancelled") {
      setWarn(null);
      el("msg").textContent = (snapshot.items || []).length
        ? `Cancelled — ${snapshot.items.length} file(s) saved so far`
        : "Cancelled";
    } else {
      setWarn(snapshot.warn || null);
      el("msg").textContent =
        (snapshot.items || []).length
          ? `Saved ${snapshot.items.length} file(s)`
          : snapshot.message || "Finished";
    }
  } else if (snapshot.status === "error") {
    el("progress").hidden = true;
    el("dlSize").textContent = "";
    el("downloadBtn").hidden = false;
    el("downloadBtn").disabled = false;
    el("cancelBtn").hidden = true;
    setWarn(null);
    el("msg").textContent = "Error: " + (snapshot.message || "unknown");
  }
}

function startDownload() {
  url = el("url").value.trim();
  if (!url) return;
  savePrefs();
  setWarn(null);
  send({ action: "download", url, selection: buildSelection() }).then((r) => {
    if (!r || !r.ok) {
      el("msg").textContent = "Error: " + ((r && r.error) || "could not start");
      el("progress").hidden = false;
    }
  });
}

document.addEventListener("DOMContentLoaded", async () => {
  await loadPrefs();

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  el("subsOpts").hidden = !prefs.subsOn;
  el("opts").hidden = true;
  if (tab && tab.url && tab.url.startsWith("http")) {
    el("url").value = tab.url;
  }

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.action === "hostEvent") onHostEvent(msg.snapshot);
    return false;
  });

  checkHost();

  // Ask for host state first: a download already running (from a previous
  // popup session) must reopen as the live progress view, never a fresh probe
  // that wipes it. A same-URL reopen also restores the cached probe instead of
  // re-fetching and forgetting the options.
  const { state } = await send({ action: "getState" });
  if (state && state.status === "downloading") {
    onHostEvent(state);
    return;
  }

  const target = el("url").value.trim();
  if (!target) return;

  const cached = await loadProbeCache();
  if (cached && cached.url === target) {
    renderProbe(cached.data);
    return;
  }
  probe();
});

el("subsOn").addEventListener("change", (e) => {
  el("subsOpts").hidden = !e.target.checked;
  savePrefs();
});
el("autoSubs").addEventListener("change", () => {
  renderLangs();
  savePrefs();
});
el("langs").addEventListener("change", () => {
  prefs.langs = el("langs").value;
  prefs.langsTouched = true;
  savePrefs();
});
el("formatSelect").addEventListener("change", () => {
  savePrefs();
  updateSizeEstimate();
  updateChaptersControl();
});
el("subFormat").addEventListener("change", () => savePrefs());
el("convertSrt").addEventListener("change", () => savePrefs());
el("embed").addEventListener("change", () => savePrefs());
el("chapters").addEventListener("change", () => savePrefs());
el("playlist").addEventListener("change", () => {
  playlistTouched = true;
  prefs.playlist = el("playlist").checked;
  savePrefs();
});
el("url").addEventListener("keydown", (e) => { if (e.key === "Enter") probe(); });
el("probeBtn").addEventListener("click", probe);
el("downloadBtn").addEventListener("click", startDownload);
el("cancelBtn").addEventListener("click", () => send({ action: "cancel" }));
el("optsLink").addEventListener("click", (e) => {
  e.preventDefault();
  chrome.runtime.openOptionsPage();
});
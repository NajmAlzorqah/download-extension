// Formats.js — pure port of the popup's format/selection logic.
//
// Kept DOM-free so it can be shared by the widget's options popup and unit
// tested under node (later slices also reuse buildSelection/summarize for the
// download request). Mirrors extension/popup.js; update both sides together.
// The widget cannot read chrome.storage, so prefs mirror extension/defaults.js
// (Defaults.js) plus the widget's own persisted copy — see Defaults.js.

var SUB_FMT_WHITELIST = ["srt", "vtt", "ttml", "webvtt", "ass", "ssa", "sbv", "lrc"];
var SUB_FMT_LABEL = {
  srt: "SRT", vtt: "VTT", ttml: "TTML", webvtt: "WebVTT",
  ass: "ASS", ssa: "SSA", sbv: "SBV", lrc: "LRC",
};

function fmtBytes(n) {
  if (n == null || n <= 0) return "";
  if (n >= 1e9) return (n / 1e9).toFixed(2).replace(/0+$/, "").replace(/\.$/, "") + " GB";
  if (n >= 1e6) return Math.round(n / 1e6) + " MB";
  return Math.max(1, Math.round(n / 1e3)) + " KB";
}

function fmtSizeStr(bytes, approx) {
  if (bytes == null) return "";
  return (approx === undefined || approx ? "~" : "") + fmtBytes(bytes);
}

function codecRank(c) {
  var s = String(c || "").toLowerCase();
  if (s.indexOf("avc") === 0) return 3;        // h264 / mp4: most compatible
  if (s.indexOf("vp09") === 0 || s.indexOf("vp9") === 0) return 2;
  if (s.indexOf("av01") === 0) return 1;      // av1: efficient but least compatible
  return 0;
}

function fmtOrder(a, b) {
  if ((a.height || 0) !== (b.height || 0)) return (b.height || 0) - (a.height || 0);
  var aio = a.vcodec && a.vcodec !== "none" ? 0 : 1;
  var bio = b.vcodec && b.vcodec !== "none" ? 0 : 1;
  if (aio !== bio) return aio - bio;
  return String(a.id).localeCompare(String(b.id), undefined, { numeric: true });
}

function pickVideo(top) {
  return top.slice().sort(function (a, b) {
    return ((b.acodec && b.acodec !== "none" ? 100 : 0) + codecRank(b.vcodec)) -
      ((a.acodec && a.acodec !== "none" ? 100 : 0) + codecRank(a.vcodec));
  })[0];
}

function pickAudio(list) {
  var fam = function (f) { return String(f.acodec || "").toLowerCase().indexOf("mp4a") === 0 ? 0 : 1; };
  var num = function (f) { return parseInt(String(f.id), 10) || 0; };
  return list.slice().sort(function (a, b) { return fam(a) - fam(b) || num(b) - num(a); })[0];
}

function presetFormats() {
  var presets = [];
  var add = function (id, label, opts) {
    opts = opts || {};
    presets.push({ id: id, value: id, label: label, preset: true, res: opts.res || "best", audioOnly: !!opts.audioOnly });
  };
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

function bestAudioSize(formats) {
  var a = (formats || []).filter(function (x) { return !x.vcodec || x.vcodec === "none"; });
  var best = a.length ? pickAudio(a) : null;
  return best && best.size ? best.size : 0;
}

function findFormat(formats, id) {
  for (var i = 0; i < (formats || []).length; i++) {
    if (String(formats[i].id) === String(id)) return formats[i]
  }
  return null
}

// Materialize the wire-visible selection for the format the user picked,
// mirroring popup.js selectedFormat(). `formats` must be the collapsed list
// built by collapseFormats() (presets carry preset/res/audioOnly).
function selectedFormat(formats, id) {
  var f = findFormat(formats, id);
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

function summarizeSelection(sel) {
  sel = sel || {};
  var parts = [];
  if (sel.label) {
    parts.push(sel.label);
  } else if (sel.audioOnly) {
    parts.push("Audio");
  } else if (sel.formatId) {
    parts.push(sel.formatId + (sel.formatExt ? " \u00b7 " + sel.formatExt : ""));
  } else if (sel.resolution && sel.resolution !== "best") {
    parts.push(sel.resolution + "p");
  }
  if (sel.playlist) parts.push("Playlist");
  var chapters = sel.chapters;
  if (chapters === "embed") parts.push("chapters embed");
  else if (chapters === "split") parts.push("split chapters");
  var subs = sel.subs;
  if (subs && subs.on) {
    var tag = "subs";
    if (subs.embed) tag += " embed";
    if (subs.auto) tag += " auto";
    parts.push(tag);
  }
  return parts.join(" \u00b7 ");
}

// Short label for the download row, mirroring popup.js formatLabel().
function formatLabel(formats, id) {
  var f = findFormat(formats, id);
  if (!f) return "Best";
  if (f.preset) return f.label;
  if (!f.vcodec || f.vcodec === "none") return "Audio only";
  var label = f.height ? f.height + "p" : "Video";
  if (f.fps && f.fps > 30) label += " " + Math.round(f.fps) + "fps";
  return label;
}

// Build the wire selection for one download, mirroring popup.js
// buildSelection(). `fmt` is the selectedFormat() result for the chosen
// option; `chaptersActive` is chaptersState.visible && chaptersState.enabled.
function buildSelection(probeData, prefs, fmt, chaptersActive, subsDisabled) {
  var meta = probeData && probeData.meta;
  var langs = prefs.langs || "all";
  // Never ship "all" with auto-captions on: the host would then emit
  // `--write-auto-subs` with no `--sub-langs` and fetch every language.
  if (langs === "all" && prefs.auto) {
    langs = defaultAutoTrack(probeData && probeData.subs, probeData && probeData.autoSubs);
  }
  return {
    title: (meta && (meta.sample || meta.title)) || "",
    label: formatLabel(probeData && probeData.formats, fmt && fmt.formatId),
    audioOnly: !!(fmt && fmt.audioOnly),
    formatId: fmt && fmt.formatId,
    formatHasAudio: !!(fmt && fmt.formatHasAudio),
    formatExt: fmt && fmt.formatExt,
    resolution: fmt && fmt.resolution,
    playlist: !!(prefs.playlist),
    chapters: chaptersActive ? (prefs.chapters || "off") : "off",
    subs: {
      on: !!(prefs.subsOn) && !subsDisabled,
      auto: !!(prefs.auto),
      langs: langs,
      subFormat: prefs.subFormat,
      convert: prefs.convertSrt ? "srt" : "best",
      embed: !!(prefs.embed),
    },
    outputDir: prefs.outDir,
  };
}

function formatOptionLabel(f, bonusSize) {
  if (!f.vcodec || f.vcodec === "none") {
    return "Audio only" + fmtSizeStr(f.size);
  }
  var label = f.height ? f.height + "p" : "Video";
  if (f.fps && f.fps > 30) label += " · " + Math.round(f.fps) + "fps";
  var sz = f.size;
  if (sz && (!f.acodec || f.acodec === "none")) sz += bonusSize;
  label += fmtSizeStr(sz);
  return label;
}

// Collapse raw probe formats into the option list the popup builds:
// one best pick per height bucket (video first, then the single best
// audio-only), presets for playlists with no per-video formats, and the
// size estimate bonus. Returns { options, hint, formatOnly }.
function collapseFormats(formats, meta, sizeBonus) {
  var all = formats || [];
  if (!all.length) {
    if (meta && meta.is_playlist) {
      return {
        options: presetFormats(),
        hint: meta.sample_error
          ? "Couldn't reach the first video to read its resolutions — using presets." : "",
        formatOnly: false,
      };
    }
    return { options: [{ id: "", label: "No formats reported" }], hint: "", formatOnly: true };
  }

  var byHeight = [];
  var audioOnly = [];
  for (var i = 0; i < all.length; i++) {
    var f = all[i];
    if (!f.vcodec || f.vcodec === "none") audioOnly.push(f);
    else {
      var h = f.height || 0;
      var bucket = null;
      for (var j = 0; j < byHeight.length; j++) {
        if (byHeight[j].height === h) { bucket = byHeight[j]; break; }
      }
      if (!bucket) { bucket = { height: h, items: [] }; byHeight.push(bucket); }
      bucket.items.push(f);
    }
  }

  var collapsed = [];
  for (var k = 0; k < byHeight.length; k++) collapsed.push(pickVideo(byHeight[k].items));
  collapsed.sort(fmtOrder);
  if (audioOnly.length) collapsed.push(pickAudio(audioOnly));

  var bonus = sizeBonus !== undefined ? sizeBonus : bestAudioSize(all);
  var opts = collapsed.map(function (f) {
    return { id: String(f.id), value: String(f.id), label: formatOptionLabel(f, bonus), format: f };
  });
  return { options: opts, hint: (meta && meta.sample) ? "Resolutions from the first video in the playlist: " + meta.sample : "", formatOnly: false };
}

// --- subtitle language machinery (pure, mirrors popup.js renderLangs) -------

function langEntries(manual, autoSubs) {
  var keys = [];
  var seen = {};
  var pushKey = function (code) {
    if (seen[code]) return;
    seen[code] = true;
    keys.push(code);
  };
  for (var m in (manual || {})) pushKey(m);
  for (var a in (autoSubs || {})) if (!manual || !(a in manual)) pushKey(a);
  return keys; // order: all manual first, then auto-only
}

// Chosen language for a video: playlist → existing pref or "all"; otherwise
// pref when still offered, else the first offered manual track ("en" preferred),
// with "all" honored as an explicit choice when auto is off.
function chooseLangs(prefs, manual, autoSubs, isPlaylist, withAuto) {
  var entries = langEntries(manual, autoSubs);
  if (!entries.length) return "";
  var has = function (c) { return entries.indexOf(c) >= 0; };

  if (isPlaylist && prefs.langsTouched && has(prefs.langs)) return prefs.langs;
  if (isPlaylist) return "all";
  if (prefs.langs === "all") {
    return withAuto ? defaultAutoTrack(manual, autoSubs) : "all";
  }
  if (prefs.langs && !withAuto && !(prefs.langs in manual)) {
    var mk = [];
    for (var m in manual) mk.push(m);
    return mk.length ? mk[0] : "all";
  }
  if (prefs.langs && has(prefs.langs)) return prefs.langs;
  if ("en" in (manual || {})) return "en";
  return entries[0];
}

function defaultAutoTrack(manual, autoSubs) {
  var offered = [];
  var seen = {};
  for (var m in (manual || {})) { offered.push(m); seen[m] = true; }
  for (var a in (autoSubs || {})) if (!seen[a]) offered.push(a);
  return offered.indexOf("en") >= 0 ? "en" : (offered[0] || "all");
}

function subFormatChoice(prefs, offered) {
  var list = (offered || []).filter(function (x) { return SUB_FMT_WHITELIST.indexOf(x) >= 0; });
  if (!list.length) list = ["srt", "vtt"];
  if (list.indexOf(prefs.subFormat) >= 0) return prefs.subFormat;
  return list.indexOf("srt") >= 0 ? "srt" : list[0];
}

// --- chapters (mirrors popup.js chaptersControlState) -----------------------

var CHAPTER_CONTAINERS = ["mp4", "webm", "mkv"];

function chaptersControlState(meta, fmt) {
  var count = meta ? meta.chapterCount : null;
  if (!count || !fmt || fmt.audioOnly) return { visible: false, enabled: false, reason: "" };
  var ext = (fmt.formatExt || "").toLowerCase();
  if (fmt.formatId && ext && CHAPTER_CONTAINERS.indexOf(ext) < 0) {
    return {
      visible: true, enabled: false,
      reason: "Chapters need MKV/MP4/WebM — this format is " + (ext || "a container that can't hold them") + ".",
    };
  }
  return { visible: true, enabled: true, reason: "" };
}

// --- estimated size line (mirrors popup.js updateSizeEstimate) --------------

function estimatedSize(probeData, fmt) {
  if (!probeData || !probeData.meta) return null;
  if (!fmt || !(fmt.audioOnly || fmt.formatId)) return null;
  var f = null;
  var formats = probeData.formats || [];
  for (var i = 0; i < formats.length; i++) {
    if (String(formats[i].id) === String(fmt.formatId)) { f = formats[i]; break; }
  }
  var bytes = null;
  if (f && f.size) {
    bytes = f.size;
    if (!fmt.audioOnly && (!f.acodec || f.acodec === "none")) bytes += bestAudioSize(formats);
  }
  if (bytes == null) return null;
  var count = probeData.meta.is_playlist ? (probeData.meta.playlist_count || 0) : 1;
  var txt = fmtSizeStr(bytes);
  if (count > 1) txt += " × " + count + " videos";
  return txt;
}
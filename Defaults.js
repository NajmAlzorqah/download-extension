// Defaults.js — widget mirror of extension/defaults.js.
//
// The widget cannot read chrome.storage, so these defaults (plus the widget's
// own persisted copy in the agent's state dir) are a SECOND copy of the
// canonical extension defaults. Keep them in sync with extension/defaults.js;
// this is the known defaults-drift surface flagged in the plan.
var DEFAULTS = {
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
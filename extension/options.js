const DEFAULTS = {
  outDir: "~/Videos",
  playlist: false,
  chapters: "off",
  subsOn: false,
  auto: false,
  langs: "en",
  convertSrt: false,
  embed: false,
};

const el = (id) => document.getElementById(id);

async function load() {
  const s = await chrome.storage.local.get(null);
  for (const k of Object.keys(DEFAULTS)) {
    const v = s[k] !== undefined ? s[k] : DEFAULTS[k];
    el(k).value = v;
    if (el(k).type === "checkbox") el(k).checked = v;
  }
}

function save() {
  for (const k of Object.keys(DEFAULTS)) {
    const e = el(k);
    chrome.storage.local.set({ [k]: e.type === "checkbox" ? e.checked : e.value });
  }
}

document.addEventListener("DOMContentLoaded", async () => {
  await load();
});

// options page can't rely on popup's imports; ping via bg
chrome.runtime.sendMessage({ action: "ping" })
  .then((r) => {
    el("hostStatus").textContent = r && r.ok
      ? `native host OK · yt-dlp ${r.ytdlp ? "✓" : "✗"} · ffmpeg ${r.ffmpeg ? "✓" : "✗"}`
      : "native host NOT detected — run install.sh and restart the browser";
  })
  .catch(() => {
    el("hostStatus").textContent = "extension background unavailable";
  });

el("save").addEventListener("click", () => {
  save();
  el("saved").textContent = "Saved";
  setTimeout(() => (el("saved").textContent = ""), 1500);
});

el("reset").addEventListener("click", async () => {
  for (const k of Object.keys(DEFAULTS)) {
    el(k).value = DEFAULTS[k];
    if (el(k).type === "checkbox") el(k).checked = DEFAULTS[k];
  }
  save();
});

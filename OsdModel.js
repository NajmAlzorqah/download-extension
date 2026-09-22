// OsdModel.js — derived from the Omarchy stock `omarchy.osd` panel
// (Copyright (c) David Heinemeier Hansson, MIT License; see CREDITS.md in the
// project root). Additions on the Omarchy base: progress readout next to a
// title message. Distributed under the MIT License.

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// OSD IPC contract version, mirrored from host/najm-ytdlp-host (OSD_IPC_*).
// `open()` in Osd.qml warns on mismatch so a payload-shape change is visible at
// dev time instead of silently misrendering. Keep in sync with the host.
var OSD_IPC_TAG = "nd-osd-1"
var OSD_IPC_VERSION = 1

// The widest glyph `iconFor` can return. The progress OSD sizes its icon
// column to it so the bar keeps its place as the icon changes.
var widestIcon = ""

function iconFor(name, percent) {
  var n = String(name || "").toLowerCase()
  if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return ""
  if (n === "volume-low") return ""
  if (n === "volume-medium") return ""
  if (n === "volume-high" || n === "volume") return ""
  if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return "󰍭"
  if (n === "microphone" || n === "mic") return "󰍬"
  if (n === "keyboard") return "󰌌"
  if (n === "brightness" || n === "display") return "󰍹"
  if (n === "touchpad") return "󰟸"
  if (n === "touch" || n === "touchscreen") return "󰝁"
  if (n === "reboot" || n === "restart") return "󰜉"
  if (n === "shutdown" || n === "power" || n === "poweroff") return "󰐥"
  if (n === "logout" || n === "sign-out" || n === "leave") return "󰍃"
  if (n === "media" || n === "player") return "󰝚"
  if (n === "media-source" || n === "player-source") return "󰝚"
  if (n === "media-play" || n === "player-play") return "󰐊"
  if (n === "media-pause" || n === "player-pause") return "󰏤"
  if (n === "media-next" || n === "player-next") return "󰒭"
  if (n === "media-previous" || n === "player-previous") return "󰒮"
  if (n.length > 0) return name
  if (percent <= 0) return ""
  if (percent <= 33) return ""
  if (percent <= 66) return ""
  return ""
}

function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
  var maxValue = Math.max(1, parseInt(rawMax || "100", 10))
  var parsedValue = parseInt(rawValue || "0", 10)
  // A progress bar is legitimate whenever a value was passed - a message next
  // to it (eg. the video name on a download OSD) stops being a message-only
  // overlay. The readout is the percent column; the message is whatever title
  // the caller supplied, falling back to the readout when there is none, which
  // keeps the plain progress OSD rendering exactly as before.
  var hasProgress = rawValue !== "" && !isNaN(parsedValue)
  var value = hasProgress ? clamp(parsedValue, 0, maxValue) : 0
  var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
  var percentText = hasProgress ? (rawProgressText || percent + "%") : ""
  var parsedDuration = parseInt(rawDuration || "1200", 10)

  return {
    iconKey: String(iconName || "").toLowerCase(),
    maxValue: maxValue,
    hasProgress: hasProgress,
    value: value,
    readout: percentText,
    message: String(rawMessage || (hasProgress ? percentText : "")),
    icon: iconFor(iconName, percent),
    duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    widestIcon: widestIcon,
    iconFor: iconFor,
    stateForShow: stateForShow,
    OSD_IPC_TAG: OSD_IPC_TAG,
    OSD_IPC_VERSION: OSD_IPC_VERSION
  }
}

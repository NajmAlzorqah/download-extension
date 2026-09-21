// Panel kind of the najm.downloads plugin — derived from the Omarchy stock
// `omarchy.osd` panel (Copyright (c) David Heinemeier Hansson, MIT License;
// see NOTICE.md in the project root). Additions on the Omarchy base: the
// stacked title-over-bar download layout (readout column), and the
// click-to-dismiss card. Both this file and OsdModel.js are distributed under
// the MIT License. The IPC target stays "najm.osd" so the host's OSD calls
// are unchanged.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "OsdModel.js" as OsdModel

Item {
  id: root

  property bool opened: false
  property string icon: ""
  property string message: ""
  property string readout: ""
  property string iconKey: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200
  // Set when the user clicks the download OSD: its progress keep-alive updates
  // are swallowed until the download stops refreshing, then it re-arms for the
  // next one. Other (volume/brightness/media) OSDs are never suppressed.
  property bool dismissed: false

  readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0

  // The card is built out of measured columns instead of fixed widths, so it
  // keeps exactly `pad` between border and content on every side whatever
  // glyph or message it carries. Messages grow with their text up to
  // `maxMessageWidth` and elide beyond it.
  readonly property int pad: Style.space(16)
  readonly property int gap: Style.space(16)
  // A glyph next to a message reads airier than it measures: the icon outline
  // and the letterforms both fall away from their ink extremes, so the space
  // between them opens up well past the nominal gap. Text takes two thirds of
  // it; the progress bar's hard edge keeps the full gap.
  readonly property int messageGap: Math.round(root.gap * 2 / 3)
  readonly property int barWidth: Style.space(142)
  readonly property int maxMessageWidth: root.mediaOsd ? Style.space(325) : Style.space(190)

  // Nerd Font glyphs draw well outside their monospace cell, so the icon
  // column is measured by ink rather than by advance width. Progress OSDs pin
  // it to the widest glyph the model can return, so the bar doesn't shift when
  // volume crosses an icon threshold.
  readonly property int iconInkWidth: Math.ceil(iconMetrics.tightBoundingRect.width)
  readonly property int iconWidth: root.hasProgress
    ? Math.max(root.iconInkWidth, Math.ceil(widestIconMetrics.tightBoundingRect.width))
    : root.iconInkWidth
  // A message next to a progress bar (eg. the video name on a download OSD)
  // switches the card to the stacked layout: the icon and message on one line,
  // the bar and readout on the line below. Everything else keeps the single
  // row, where the readout and message are the same percent string.
  readonly property bool stacked: root.hasProgress && root.message !== "" && root.readout !== "" && root.message !== root.readout
  readonly property int vGap: Style.space(12)
  readonly property int barHeight: Math.max(Style.space(6), Style.spacing.sm)
  // Same idea for the readout: it is as wide as the longest percentage so the
  // digits don't jitter between 9% and 100%. Sized on the readout only, never
  // the message - a long title on a stacked OSD must not inflate the percent
  // column.
  readonly property int valueWidth: Math.ceil(Math.max(valueMetrics.advanceWidth, readoutMetrics.advanceWidth))
  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  // Stacked rows are measured so the bar hangs exactly on the readout's line
  // and the card grows to fit it: the title line, then the bar+readout line.
  readonly property int stackRow1Height: Math.max(Style.font.displayLarge, Math.ceil(messageMetrics.height))
  readonly property int stackRow2Height: Math.max(root.barHeight, Math.ceil(readoutMetrics.height))
  // The stacked bar stretches to the card's content width so the readout lands
  // on the right edge, aligned with the title above it.
  readonly property int stackedBarWidth: root.contentWidth - root.gap - root.valueWidth
  readonly property int contentWidth: root.stacked
    ? Math.max(root.iconWidth + root.messageGap + root.messageWidth, root.barWidth + root.gap + root.valueWidth)
    : root.hasProgress
      ? root.iconWidth + root.gap + root.barWidth + root.gap + root.valueWidth
      : (root.message === "" ? root.iconWidth : root.iconWidth + root.messageGap + root.messageWidth)

  function iconFor(name, percent) {
    return OsdModel.iconFor(name, percent)
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration)
    // A dismissed download OSD stays hidden while its progress keeps ticking;
    // swallowing each update pushes the re-arm timer out so it only fires once
    // the download goes quiet (finished, stalled, or cancelled).
    if (root.dismissed && next.hasProgress && next.message !== "" && next.readout !== "" && next.message !== next.readout) {
      dismissLinger.restart()
      return
    }
    // Update before opening so a fresh OSD starts at its new value; only
    // subsequent updates while it remains open animate the progress bar.
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    readout = next.readout
    icon = next.icon
    duration = next.duration
    opened = true
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      var ipc = String(p.ipc || "")
      var iv = parseInt(p.iface_version, 10)
      if (ipc !== OsdModel.OSD_IPC_TAG || iv !== OsdModel.OSD_IPC_VERSION) {
        // Payload-shape drift between the host and this panel — log it so an
        // Omarchy/host update that changes the IPC is visible instead of
        // silently misrendering. Rendering still proceeds (best effort).
        console.warn("najm.osd: ipc mismatch — payload ipc=" + ipc +
                     " iface_version=" + (isNaN(iv) ? "none" : iv) +
                     ", panel wants " + OsdModel.OSD_IPC_TAG + " v" + OsdModel.OSD_IPC_VERSION)
      }
      show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration))
    } catch (e) {}
  }

  function close() { root.dismissed = false; dismissLinger.stop(); root.opened = false }

  // Click on the OSD card: hide it. A download OSD is remembered as dismissed
  // so its next progress tick cannot pop it straight back up; the re-arm timer
  // is (re)started so a dismissal can never get stuck if updates stop.
  function dismiss() {
    if (root.stacked) {
      root.dismissed = true
      dismissLinger.restart()
    }
    root.opened = false
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  // Re-arms dismissal once the download's progress updates go quiet.
  Timer {
    id: dismissLinger
    interval: 5000
    onTriggered: root.dismissed = false
  }

  TextMetrics {
    id: messageMetrics
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Style.font.title
    text: root.message
  }

  TextMetrics {
    id: valueMetrics
    font: messageMetrics.font
    text: "100%"
  }

  TextMetrics {
    id: readoutMetrics
    font: messageMetrics.font
    text: root.readout !== "" ? root.readout : "100%"
  }

  TextMetrics {
    id: iconMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.displayLarge
    text: root.icon
  }

  TextMetrics {
    id: widestIconMetrics
    font: iconMetrics.font
    text: OsdModel.widestIcon
  }

  IpcHandler {
    target: "najm.osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "najm-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Click-through everywhere except the card itself, so the OSD stays
    // dismissible without the invisible full-screen surface eating input.
    // Empty (0x0) while closed, which keeps the desktop clickable.
    mask: Region {
      x: root.opened ? Math.round(card.x) : 0
      y: root.opened ? Math.round(card.y) : 0
      width: root.opened ? Math.round(card.width) : 0
      height: root.opened ? Math.round(card.height) : 0
      radius: root.opened ? Math.round(card.radius) : 0
    }

    BorderSurface {
      id: card
      width: card.borderLeft + root.pad + root.contentWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + (root.stacked ? root.stackRow1Height + root.vGap + root.stackRow2Height : Style.font.displayLarge) + root.pad + card.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(67)
      color: Util.alpha(Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.opened ? 1 : 0

      Row {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.pad
        anchors.rightMargin: card.borderRight + root.pad
        anchors.bottomMargin: card.borderBottom + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: root.hasProgress ? root.gap : root.messageGap
        visible: !root.stacked
        Item {
          width: root.iconWidth
          height: parent.height
          Text {
            textFormat: Text.PlainText
            // Sit the glyph's ink flush in the column, centered when the
            // column is wider than this particular glyph.
            x: Math.round((root.iconWidth - root.iconInkWidth) / 2 - iconMetrics.tightBoundingRect.x)
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font: iconMetrics.font
            color: Color.popups.text
          }
        }
        Rectangle {
          visible: root.hasProgress
          width: root.barWidth
          height: root.barHeight
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(Color.popups.text, 0.45)
          Rectangle {
            height: parent.height
            width: parent.width * (root.hasProgress ? root.value / root.maxValue : 0)
            color: Color.accent

            Behavior on width {
              enabled: root.opened
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
          }
        }
        Text {
          textFormat: Text.PlainText
          visible: root.message !== ""
          width: root.hasProgress ? root.valueWidth : root.messageWidth
          // The readout hugs the card edge so a short percentage doesn't leave
          // a hole in the padding; the slack lands in the gap after the bar.
          horizontalAlignment: root.hasProgress ? Text.AlignRight : Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
          text: root.message
          font: messageMetrics.font
          color: Color.popups.text
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.pad
        anchors.rightMargin: card.borderRight + root.pad
        anchors.bottomMargin: card.borderBottom + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: root.vGap
        visible: root.stacked

        // Name (plus icon) on top, bar and readout below: the download OSD.
        Row {
          spacing: root.messageGap
          Item {
            width: root.iconWidth
            height: Style.font.displayLarge
            Text {
              textFormat: Text.PlainText
              x: Math.round((root.iconWidth - root.iconInkWidth) / 2 - iconMetrics.tightBoundingRect.x)
              anchors.verticalCenter: parent.verticalCenter
              text: root.icon
              font: iconMetrics.font
              color: Color.popups.text
            }
          }
          Text {
            textFormat: Text.PlainText
            width: root.messageWidth
            horizontalAlignment: Text.AlignLeft
            anchors.verticalCenter: parent.verticalCenter
            text: root.message
            font: messageMetrics.font
            color: Color.popups.text
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
        Row {
          spacing: root.gap
          Rectangle {
            width: root.stackedBarWidth
            height: root.barHeight
            anchors.verticalCenter: parent.verticalCenter
            color: Util.alpha(Color.popups.text, 0.45)
            Rectangle {
              height: parent.height
              width: parent.width * (root.value / root.maxValue)
              color: Color.accent

              Behavior on width {
                enabled: root.opened
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            width: root.valueWidth
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            text: root.readout
            font: messageMetrics.font
            color: Color.popups.text
          }
        }
      }
      // Click anywhere on the card to hide it (download progress can sit on
      // screen for a long time); the input region is limited to the card, so
      // this never steals clicks from the desktop elsewhere.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismiss()
      }
    }
  }
}

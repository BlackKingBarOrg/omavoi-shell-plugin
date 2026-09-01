import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The recording HUD: a 28px strip, one notch off the bar's height, so it
// reads as system chrome rather than a dialog. It is kept loaded because it
// has to be on screen the instant the key goes down — mounting it on demand
// would show up as a stutter at the start of every take.
Item {
  id: root

  readonly property int barH: Style.space(28)
  readonly property int meterW: Style.space(94)

  // idle | recording | transcribing | done | rejected
  property string phase: "idle"
  property string doneText: ""
  property bool doneFlagged: false
  property int doneChanges: 0
  property string rejectedWhy: ""

  readonly property bool open: phase !== "idle"
  readonly property bool quiet: link.level > 0 && link.level < 0.02

  readonly property color edge: {
    if (phase === "done") return quiet ? Color.foreground : "#9ece6a"
    if (phase === "rejected") return Color.muted
    if (quiet && phase === "recording") return "#e0af68"
    return Color.accent
  }

  IpcLink { id: link }

  Connections {
    target: link
    function onStateChanged() {
      if (link.state === "recording") { root.phase = "recording"; dwell.stop() }
      else if (link.state === "transcribing") root.phase = "transcribing"
      else if (link.state === "idle" || link.state === "stopped") {
        // A finished take sends its result just before going idle, and that
        // result owns the screen until the dwell timer says otherwise. Only
        // clear a take that never produced one — a cancel, or a daemon that
        // went away mid-recording.
        if (root.phase === "recording" || root.phase === "transcribing") {
          root.phase = "idle"
          dwell.stop()
        }
      }
    }
    function onTakeFinished(text, rejected, changes, warnings) {
      root.doneChanges = changes
      root.doneFlagged = (warnings && warnings.length > 0)
      if (rejected) {
        root.phase = "rejected"
        root.rejectedWhy = rejected
      } else {
        root.phase = "done"
        root.doneText = text
      }
      dwell.interval = root._dwellFor()
      dwell.restart()
    }
  }

  // "changed" is the default: a dwell you always pay for turns into noise the
  // moment you dictate two sentences in a row, but a silent correction you
  // never saw is worse. So it lingers only when there was something to see.
  function _dwellFor() {
    if (phase === "rejected") return 1600
    if (doneFlagged || doneChanges > 0) return 1400
    return 350
  }

  Timer { id: dwell; onTriggered: root.phase = "idle" }

  IpcHandler {
    target: "omavoi-hud"
    function state(): string { return root.phase }
    function ping(): string { return "ok" }
  }

  PanelWindow {
    id: panel
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omavoi-hud"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual only: never take a click away from the window being dictated into.
    mask: Region {}

    Rectangle {
      id: strip
      height: root.barH
      width: content.implicitWidth + Style.space(16)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.gapsOut
      color: Color.popups.background
      radius: Style.cornerRadius
      border.width: 1
      border.color: root.edge
      opacity: root.open ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 110 } }
      Behavior on width { NumberAnimation { duration: 90 } }

      Row {
        id: content
        anchors.centerIn: parent
        spacing: Style.space(8)

        // Status dot, or a tick / cross once the take is over.
        Text {
          anchors.verticalCenter: parent.verticalCenter
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: root.edge
          text: {
            if (root.phase === "recording") return "󰑊"
            if (root.phase === "transcribing") return "󰑫"
            if (root.phase === "done") return "󰄬"
            return "󰅖"
          }
        }

        // Live meter. The three dim bars on the left stand for the pre-roll —
        // audio captured before the key went down. No label: you learn what
        // they are by watching, and the explanation lives in the console.
        Row {
          visible: root.phase === "recording" || root.phase === "transcribing"
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Repeater {
            model: 24
            Rectangle {
              width: 2
              height: {
                if (index < 3) return 3 + (index % 2) * 3
                if (root.phase === "transcribing") return 2
                var reach = Math.max(0, Math.min(1, link.level * 6))
                var pos = (index - 3) / 20
                var env = Math.sin(pos * Math.PI * 3.1 + link.seconds * 5) * 0.5 + 0.5
                return Math.max(2, Math.round(2 + reach * env * 10))
              }
              radius: 0
              color: index < 3 ? Color.muted
                   : (root.phase === "transcribing" ? Qt.darker(Color.muted, 1.4) : root.edge)
              anchors.verticalCenter: parent.verticalCenter
              Behavior on height { NumberAnimation { duration: 60 } }
            }
          }
        }

        // The text that was actually typed, so you get to see it before it goes.
        Text {
          visible: root.phase === "done" || root.phase === "rejected"
          anchors.verticalCenter: parent.verticalCenter
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.phase === "done" ? Color.foreground : Color.muted
          elide: Text.ElideRight
          width: Math.min(implicitWidth, Style.space(420))
          text: root.phase === "done" ? root.doneText : "no speech"
        }

        // How many rules touched the text. Which ones is a console question;
        // here it only has to register that something changed.
        Text {
          visible: root.phase === "done" && root.doneChanges > 0
          anchors.verticalCenter: parent.verticalCenter
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.accent
          text: "·" + root.doneChanges
        }

        Text {
          visible: root.phase === "rejected"
          anchors.verticalCenter: parent.verticalCenter
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
          elide: Text.ElideRight
          width: Math.min(implicitWidth, Style.space(260))
          text: root.rejectedWhy
        }

        Text {
          visible: root.phase === "recording"
          anchors.verticalCenter: parent.verticalCenter
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.foreground
          text: {
            var t = Math.floor(link.seconds)
            return Math.floor(t / 60) + ":" + (t % 60 < 10 ? "0" : "") + (t % 60)
          }
        }
      }
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The bar module, and — before anything else is installed — the only way in.
// So it appears on a bare plugin install rather than hiding, and it does so
// in the accent colour rather than red: there is something to do, nothing is
// broken.
BarWidget {
  id: root
  moduleName: "ai.bkblab.omavoi"

  property bool setupReady: true
  property int setupDone: 0
  property int setupTotal: 5

  readonly property bool recording: link.state === "recording"
  readonly property bool working: link.state === "transcribing"
  readonly property bool missing: link.state === "stopped"
  readonly property bool needsSetup: !setupReady && !recording && !working

  implicitWidth: reading.visible ? reading.implicitWidth : button.implicitWidth
  implicitHeight: button.implicitHeight

  function _clock(s) {
    var t = Math.max(0, Math.floor(s))
    return Math.floor(t / 60) + ":" + (t % 60 < 10 ? "0" : "") + (t % 60)
  }

  IpcLink { id: link }

  // Setup state is asked for, not pushed: it changes only when the user acts,
  // and a 15 s check costs nothing next to a subscription that would have to
  // stay meaningful for the whole session.
  Process {
    id: probe
    command: ["omavoi", "setup", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var r = JSON.parse(text)
          root.setupReady = !!r.ready
          root.setupDone = r.done || 0
          root.setupTotal = r.total || 5
        } catch (e) {
          root.setupReady = false
        }
      }
    }
  }

  Timer {
    interval: 15000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!root.recording && !root.working) probe.running = true
  }

  Connections {
    target: link
    function onStateChanged() { if (link.state === "idle") probe.running = true }
  }

  // Two buttons rather than one, because they measure differently.
  // BarIconButton reserves a fixed icon slot and centres a glyph optically in
  // it; anything wider than the glyph spills over its neighbour. So the states
  // that carry a reading use WidgetButton, which is sized by its text — the
  // same component the clock uses.
  WidgetButton {
    id: reading
    visible: root.recording || (root.needsSetup && !root.missing)
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.bodySmall
    text: root.recording
          ? "󰑊  " + root._clock(link.seconds)
          : "󰇚  " + root.setupDone + "/" + root.setupTotal
    active: root.recording
    tooltipText: root.recording
                 ? "Recording · release the key to transcribe"
                 : "Omavoi — setup unfinished"
    onPressed: function (b) { root.handle(b) }
  }

  BarIconButton {
    id: button
    visible: !reading.visible
    anchors.fill: parent
    bar: root.bar
    text: {
      if (root.working) return "󰑫"
      if (root.missing) return "󰇚"
      return "󰍬"
    }
    // `active` is the bar's own attention colour, which this theme already
    // reserves for recording modules.
    active: root.recording
    tooltipText: {
      if (root.missing) return "Omavoi — not installed yet. Click to set it up."
      if (root.recording) return "Recording · release the key to transcribe"
      if (root.working) return "Transcribing…"
      if (root.needsSetup)
        return "Omavoi — setup unfinished (" + root.setupDone + "/" + root.setupTotal + ")"
      return link.backend || "Omavoi — ready"
    }
    onPressed: function (b) { root.handle(b) }
  }

  function handle(b) {
    if (b === Qt.RightButton && root.setupReady) {
      // Start or stop a take by hand. The hotkey normally does this inside
      // the daemon; this is for when the key is not set up yet.
      link.send("record")
    } else {
      root.bar.run("omarchy-shell shell toggle ai.bkblab.omavoi")
    }
  }
}

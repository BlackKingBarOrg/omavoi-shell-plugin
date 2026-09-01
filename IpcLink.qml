import QtQuick
import Quickshell
import Quickshell.Io

// One subscription to the omavoi daemon.
//
// State is pushed, never polled: the HUD has to appear on the same frame the
// key goes down, and a 100 ms poll would be visible. Commands go the other
// way as short-lived `omavoi` invocations rather than back down this socket,
// because the daemon closes a request connection after answering and this
// one has to stay open.
Item {
  id: link

  readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omavoi.sock"

  // "stopped" means nothing is listening — usually the daemon is restarting.
  property string state: "stopped"
  property bool alive: false
  property real level: 0
  property real seconds: 0
  property string mode: ""
  property string backend: ""
  property string hotkey: ""

  property string lastText: ""
  property string lastRejected: ""
  property int lastChanges: 0
  property var lastWarnings: []

  signal takeFinished(string text, string rejected, int changes, var warnings)

  function send(cmd) {
    runner.command = ["omavoi", cmd]
    runner.running = true
  }

  Process { id: runner }

  // The socket is rebuilt rather than reconnected. `connected` is a binding
  // that the first disconnect breaks, and assigning to it afterwards does not
  // reliably dial again — which is how the HUD ended up silently deaf after a
  // daemon restart. Destroying the object and making a new one has no such
  // ambiguity.
  Loader {
    id: holder
    active: true
    sourceComponent: Component {
      Socket {
        path: link.socketPath
        connected: true
        parser: SplitParser {
          onRead: function (line) { link._digest(line) }
        }
        onConnectionStateChanged: {
          link.alive = connected
          if (connected) {
            write(JSON.stringify({ cmd: "subscribe" }) + "\n")
          } else {
            link.state = "stopped"
            link.level = 0
            retry.restart()
          }
        }
      }
    }
  }

  // Rebuild on a cadence while there is nothing listening. The daemon may
  // simply not be installed yet, so this stays quiet and slow rather than
  // hammering a socket that will not exist for hours.
  Timer {
    id: retry
    interval: 3000
    repeat: true
    running: !link.alive
    onTriggered: {
      holder.active = false
      holder.active = true
    }
  }

  function _digest(line) {
    if (!line) return
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }

    if (msg.event === "state") {
      link.state = msg.state || "idle"
      if (msg.mode) link.mode = msg.mode
      if (link.state !== "recording") link.level = 0
      return
    }
    if (msg.event === "level") {
      link.level = msg.level || 0
      link.seconds = msg.seconds || 0
      return
    }
    if (msg.event === "result") {
      link.lastText = msg.text || ""
      link.lastRejected = msg.rejected || ""
      link.lastChanges = msg.changes || 0
      link.lastWarnings = msg.warnings || []
      link.takeFinished(link.lastText, link.lastRejected,
                        link.lastChanges, link.lastWarnings)
      return
    }
    // The first line after subscribing is a full status snapshot.
    if (msg.state !== undefined) {
      link.state = msg.state
      link.backend = msg.backend || ""
      if (msg.hotkey) link.hotkey = msg.hotkey.key || ""
    }
  }
}

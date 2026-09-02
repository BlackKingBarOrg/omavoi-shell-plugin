import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A list of commands, run one after another, printed before any of them runs.
//
// Shared by the first-run screen and the update screen because the delicate
// parts are not the commands: a cancelled password dialog is a decision and
// not a fault, stderr from a step that succeeded is noise rather than
// evidence, and a pacman 404 means a stale database rather than a broken
// mirror. One copy of that, or the second copy is the one that gets it wrong.
//
// `steps` is [{ key, label, argv, root? }]. Root steps are marked as asking
// for a password, and there should be exactly one: polkit reports pacman as
// auth_admin rather than auth_admin_keep, so every call prompts again.
ColumnLayout {
  id: root

  property var strings: null
  property var steps: []
  property bool showPlan: true

  // -1 idle, 0..n-1 running that step, n done.
  property int at: -1
  property string failure: ""
  property var log: ({})

  readonly property bool running: at >= 0 && at < steps.length
  readonly property bool done: steps.length > 0 && at >= steps.length

  signal finished()

  function t(k) { return root.strings ? root.strings.t(k) : k }
  function tf(k, a) { return root.strings ? root.strings.tf(k, a) : k }

  function begin() {
    if (!root.steps || root.steps.length === 0) return
    root.failure = ""
    root.log = ({})
    root.at = 0
    runner.start()
  }

  function reset() {
    root.at = -1
    root.failure = ""
    root.log = ({})
  }

  function note(key, text) {
    var next = ({})
    for (var k in root.log) next[k] = root.log[k]
    next[key] = text
    root.log = next
  }

  spacing: Style.space(3)

  Process {
    id: runner
    function start() {
      if (root.at < 0 || root.at >= root.steps.length) return
      runner.held = ""
      runner.command = root.steps[root.at].argv
      runner.running = true
    }
    // Held rather than published: pacman writes a warning per mirror it had
    // to skip, and a step that then succeeds was showing those warnings on
    // screen as though something had gone wrong.
    property string held: ""
    stderr: StdioCollector {
      onStreamFinished: runner.held = text.trim()
    }
    onExited: function (code, status) {
      var step = root.steps[root.at]
      if (code !== 0) {
        if (runner.held !== "") root.note(step.key, runner.held)
        var out = runner.held.toLowerCase()
        var stale = out.indexOf("404") >= 0
                    || out.indexOf("failed retrieving file") >= 0
                    || out.indexOf("target not found") >= 0
        // 126/127 out of pkexec is a cancelled or refused password dialog.
        root.failure = (step.root && (code === 126 || code === 127))
                       ? root.t("first.cancelled")
                       : (step.root && stale)
                         ? root.t("first.pacman404")
                         : root.tf("first.failed", step.label)
        root.at = -1
        return
      }
      root.at = root.at + 1
      if (root.at < root.steps.length) runner.start()
      else root.finished()
    }
  }

  Text {
    visible: root.showPlan && !root.done && root.steps.length > 0
    text: root.t("first.willrun")
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
    color: Color.muted
  }

  Repeater {
    model: root.showPlan && !root.done ? root.steps : []
    RowLayout {
      readonly property var step: modelData
      readonly property int idx: index
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text {
        Layout.preferredWidth: Style.space(16)
        text: root.at > idx ? "✓" : (root.at === idx ? "▶" : "")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: root.at > idx ? "#9ece6a" : Color.accent
      }
      Text {
        Layout.preferredWidth: Style.space(150)
        text: step.label
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: root.at >= idx ? Color.foreground : Color.muted
      }
      Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: "$ " + step.argv.join(" ")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Qt.darker(Color.muted, 1.15)
      }
      Text {
        visible: step.root === true
        text: root.t("first.needspassword")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: "#e0af68"
      }
    }
  }

  // Whatever the failing step said, verbatim — it is usually the answer.
  Repeater {
    model: Object.keys(root.log)
    Text {
      Layout.fillWidth: true
      Layout.topMargin: Style.space(4)
      wrapMode: Text.Wrap
      text: root.log[modelData]
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Qt.darker(Color.muted, 1.1)
    }
  }
}

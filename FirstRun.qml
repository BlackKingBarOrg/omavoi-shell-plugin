import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The first-run screen. Two questions, then one button.
//
// This has to work with nothing installed but itself: no daemon, no config
// file, no model. So the language list and the model list are held here rather
// than read from the daemon, and the two answers live in memory until there is
// an `omavoi config` to write them to.
//
// The one thing it cannot do without help is install packages. Omarchy runs a
// polkit agent inside the shell, so `pkexec` raises a password dialog drawn by
// the desktop itself. polkit reports this action as auth_admin rather than
// auth_admin_keep, which means every pkexec call prompts again — hence exactly
// one call, with every package in it.
Flickable {
  id: root

  property var strings: null
  property bool daemonPresent: false
  // Weights another tool already put on this machine. Reused, never moved.
  property string foundWeights: ""

  readonly property int pad: Style.space(24)

  signal finished()

  function t(k) { return root.strings ? root.strings.t(k) : k }
  function tf(k, a) { return root.strings ? root.strings.tf(k, a) : k }

  // -- the two answers ----------------------------------------------------
  property string lang: ""
  property string model: ""

  readonly property var modelChoices: {
    var out = []
    if (root.foundWeights !== "")
      out.push({ key: "reuse", size: "", note: root.t("first.reuse") })
    out.push({ key: "ggml:large-v3", size: "3.0G", note: root.t("first.m.large") })
    out.push({ key: "ggml:large-v3-turbo-q5_0", size: "0.6G", note: root.t("first.m.turbo") })
    return out
  }

  // -- the plan ------------------------------------------------------------
  //
  // Ordered so the daemon starts exactly once, at the end, with a model
  // already chosen — otherwise its first start exits 78 and the screen would
  // have to explain a failure it caused itself.
  readonly property string repo: "git+https://github.com/BlackKingBarOrg/omavoi"
  readonly property var packages: ["uv", "whisper-cpp", "ggml-cpu", "ggml-vulkan", "xdotool"]

  readonly property var steps: {
    var chosen = (root.model === "reuse") ? "ggml:large-v3" : root.model
    var plan = [
      { key: "packages", root: true,
        label: root.t("first.step.packages"),
        argv: ["pkexec", "/usr/bin/pacman", "-S", "--needed", "--noconfirm"].concat(root.packages) },
      { key: "daemon", root: false,
        label: root.t("first.step.daemon"),
        argv: ["uv", "tool", "install", root.repo] },
      { key: "language", root: false,
        label: root.t("first.step.language"),
        argv: ["omavoi", "config", "set", "ui.language", root.lang] }
    ]
    if (root.model !== "reuse")
      plan.push({ key: "weights", root: false, download: true,
                  label: root.t("first.step.weights"),
                  argv: ["omavoi", "model", "pull", chosen] })
    plan.push({ key: "use", root: false,
                label: root.t("first.step.use"),
                argv: ["omavoi", "model", "use", chosen] })
    plan.push({ key: "mode", root: false,
                label: root.t("first.step.mode"),
                argv: ["omavoi", "mode", "use", "default"] })
    plan.push({ key: "service", root: false,
                label: root.t("first.step.service"),
                argv: [Quickshell.env("HOME") + "/.config/omarchy/plugins/ai.bkblab.omavoi/install.sh"] })
    return plan
  }

  // -1 idle, 0..n-1 running that step, n done
  property int at: -1
  property string failure: ""
  property var log: ({})
  readonly property bool running: at >= 0 && at < steps.length
  readonly property bool done: at >= steps.length

  function begin() {
    if (root.lang === "" || root.model === "") return
    root.failure = ""
    root.log = ({})
    root.at = 0
    runner.start()
  }

  function note(key, text) {
    var next = ({})
    for (var k in root.log) next[k] = root.log[k]
    next[key] = text
    root.log = next
  }

  contentHeight: col.implicitHeight + pad * 2
  clip: true

  Process {
    id: runner
    function start() {
      if (root.at < 0 || root.at >= root.steps.length) return
      var step = root.steps[root.at]
      runner.command = step.argv
      runner.running = true
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.note(root.steps[root.at].key, text.trim())
    }
    onExited: function (code, status) {
      var step = root.steps[root.at]
      if (code !== 0) {
        // 126/127 from pkexec is a cancelled or refused password dialog, which
        // is a decision rather than a fault.
        root.failure = (step.root && (code === 126 || code === 127))
                       ? root.t("first.cancelled")
                       : root.tf("first.failed", step.label)
        root.at = -1
        return
      }
      root.at = root.at + 1
      if (root.at < root.steps.length) runner.start()
      else root.finished()
    }
  }

  ColumnLayout {
    id: col
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    spacing: Style.space(16)

    Text {
      text: root.t("first.title")
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      color: Color.foreground
    }
    Text {
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: root.t("first.blurb")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.muted
    }

    // ---- 1. language ----
    ColumnLayout {
      Layout.fillWidth: true
      Layout.topMargin: Style.space(6)
      spacing: Style.space(6)
      visible: !root.running && !root.done
      Text {
        text: "1  " + root.t("first.pick.language")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        color: root.lang === "" ? Color.accent : Color.muted
      }
      Flow {
        Layout.fillWidth: true
        spacing: Style.space(6)
        Repeater {
          model: root.strings ? root.strings.languages : []
          OmChip {
            readonly property var entry: modelData
            label: entry.name
            on: root.lang === entry.code
            onClicked: root.lang = entry.code
          }
        }
      }
    }

    // ---- 2. model ----
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)
      visible: !root.running && !root.done
      Text {
        text: "2  " + root.t("first.pick.model")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        color: (root.lang !== "" && root.model === "") ? Color.accent : Color.muted
      }
      Repeater {
        model: root.modelChoices
        RowLayout {
          readonly property var choice: modelData
          Layout.fillWidth: true
          spacing: Style.space(10)
          OmChip {
            label: choice.key === "reuse" ? root.t("first.reuse.label") : choice.key
            on: root.model === choice.key
            onClicked: root.model = choice.key
          }
          Text {
            visible: choice.size !== ""
            text: choice.size
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
          }
          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: choice.note
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Qt.darker(Color.muted, 1.1)
          }
        }
      }
    }

    // ---- 3. the commands, shown before anything runs ----
    ColumnLayout {
      Layout.fillWidth: true
      Layout.topMargin: Style.space(6)
      spacing: Style.space(3)
      visible: !root.done && root.lang !== "" && root.model !== ""
      Text {
        text: "3  " + root.t("first.willrun")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        color: Color.muted
      }
      Repeater {
        model: root.steps
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
    }

    // ---- the button, the failure, the end ----
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Style.space(10)
      spacing: Style.space(10)
      Button {
        visible: !root.running && !root.done
        enabled: root.lang !== "" && root.model !== ""
        text: root.failure === "" ? root.t("first.install") : root.t("first.retry")
        onClicked: root.begin()
      }
      Text {
        visible: root.running
        text: root.running
              ? root.tf("first.working", root.steps[root.at].label)
              : ""
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: Color.accent
      }
      Text {
        visible: root.failure !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.failure
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Color.urgent
      }
      Text {
        visible: root.done
        text: root.t("first.done")
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: "#9ece6a"
      }
      Item { Layout.fillWidth: true }
    }

    // Whatever the failing step said, verbatim — it is usually the answer.
    Repeater {
      model: Object.keys(root.log)
      Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.log[modelData]
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Qt.darker(Color.muted, 1.1)
      }
    }
  }
}

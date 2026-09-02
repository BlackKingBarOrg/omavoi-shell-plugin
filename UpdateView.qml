import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Upgrading, in the same shape as installing: the commands are printed, one
// button runs them, and nothing here needs a terminal.
//
// It exists because the honest command for the daemon is not the obvious one.
// `uv tool upgrade omavoi` reports "Nothing to upgrade" against a git source
// even when the branch has moved — measured, pinned to an old commit — so the
// route is a reinstall from the URL. Nobody should have to know that.
ColumnLayout {
  id: root

  property var strings: null
  // Steps the daemon says are still missing and need root — a package added
  // by a version you are upgrading *to* is invisible to the version you have.
  property var setupReport: ({ steps: [] })

  signal command(string cmd)
  signal finished()

  function t(k) { return root.strings ? root.strings.t(k) : k }
  function tf(k, a) { return root.strings ? root.strings.tf(k, a) : k }

  readonly property string repo: "git+https://github.com/BlackKingBarOrg/omavoi"
  readonly property string pluginId: "ai.bkblab.omavoi"

  // -- is there anything to do? -------------------------------------------
  //
  // Asked of the clone rather than of a version file: the plugin is a git
  // checkout, so the question is whether origin has moved past it.
  property int behind: -1
  property string pluginError: ""
  Process {
    id: probeBehind
    command: ["sh", "-c",
              "d=\"$HOME/.config/omarchy/plugins/ai.bkblab.omavoi\"; " +
              "git -C \"$d\" fetch --quiet origin 2>/dev/null; " +
              "git -C \"$d\" rev-list --count HEAD..@{upstream} 2>/dev/null || echo -1"]
    stdout: StdioCollector {
      onStreamFinished: root.behind = parseInt(text.trim(), 10)
    }
  }
  // Local edits stop a fast-forward, and hand-copied files are exactly how a
  // developer's machine ends up unable to update itself.
  property bool pluginDirty: false
  Process {
    id: probeDirty
    command: ["sh", "-c",
              "test -n \"$(git -C \"$HOME/.config/omarchy/plugins/ai.bkblab.omavoi\" " +
              "status --porcelain 2>/dev/null)\""]
    onExited: function (code, status) { root.pluginDirty = code === 0 }
  }

  function refresh() {
    probeBehind.running = true
    probeDirty.running = true
  }
  Component.onCompleted: refresh()

  readonly property var rootSteps: {
    var out = []
    var steps = (root.setupReport && root.setupReport.steps) || []
    for (var i = 0; i < steps.length; i++) {
      var s = steps[i]
      if (!s.done && s.needs_root && String(s.command || "").indexOf("pacman") >= 0)
        out.push(s)
    }
    return out
  }

  readonly property var steps: {
    var plan = [
      { key: "plugin", label: root.t("up.step.plugin"),
        argv: ["omarchy", "plugin", "update", root.pluginId, "--yes"] },
      { key: "daemon", label: root.t("up.step.daemon"),
        // Not `uv tool upgrade`: against a git source it does nothing and
        // says so in a way that reads like success.
        argv: ["uv", "tool", "install", "--reinstall", root.repo] }
    ]
    // Whatever the newer daemon then asks for, in one prompt.
    if (root.rootSteps.length > 0) {
      var pkgs = []
      for (var i = 0; i < root.rootSteps.length; i++) {
        var parts = String(root.rootSteps[i].command).split(/\s+/)
        for (var j = 0; j < parts.length; j++)
          if (parts[j] !== "" && parts[j][0] !== "-"
              && parts[j] !== "sudo" && parts[j] !== "pacman")
            pkgs.push(parts[j])
      }
      if (pkgs.length > 0)
        plan.push({ key: "packages", root: true, label: root.t("first.step.packages"),
                    argv: ["pkexec", "/usr/bin/pacman", "-S", "--needed",
                           "--noconfirm"].concat(pkgs) })
    }
    plan.push({ key: "restart", label: root.t("up.step.restart"),
                argv: ["systemctl", "--user", "restart", "omavoid"] })
    return plan
  }

  spacing: Style.space(8)

  Text {
    text: root.t("up.title")
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
    color: Color.muted
  }

  Text {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    text: root.behind > 0 ? root.tf("up.behind", root.behind)
          : root.behind === 0 ? root.t("up.current")
          : root.t("up.unknown")
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    color: root.behind > 0 ? "#e0af68" : Color.foreground
  }

  // Said before the button, because the button cannot fix it and the message
  // pacman gives for it explains nothing.
  Text {
    visible: root.pluginDirty
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    text: root.t("up.dirty")
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: Color.urgent
  }

  StepRunner {
    id: plan
    Layout.fillWidth: true
    strings: root.strings
    steps: root.steps
    onFinished: {
      root.refresh()
      root.finished()
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(10)
    Button {
      visible: !plan.running
      enabled: !root.pluginDirty
      text: plan.done ? root.t("up.again")
            : plan.failure !== "" ? root.t("first.retry")
            : root.t("up.run")
      onClicked: { plan.reset(); plan.begin() }
    }
    Text {
      visible: plan.running
      // `at` is -1 while idle, and steps[-1] is undefined.
      text: plan.at >= 0 && plan.at < root.steps.length
            ? root.tf("first.working", root.steps[plan.at].label) : ""
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      color: Color.accent
    }
    Text {
      visible: plan.done
      text: root.t("up.done")
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      color: "#9ece6a"
    }
    Text {
      visible: plan.failure !== ""
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: plan.failure
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.urgent
    }
    Item { Layout.fillWidth: true }
  }
}

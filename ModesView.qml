import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A mode is a chain of models, so it is edited as one: the speech step and
// what it is told, the deterministic rules, then zero or more LLM passes each
// with its own prompt, then how the text gets into the window.
//
// Everything here writes through the omavoi command, so the console and the
// terminal cannot drift apart — the config file is the single record.
Item {
  id: root
  property var payload: ({ modes: [], active: "", llm: [] })
  property string selected: ""
  readonly property int pad: Style.space(18)

  property var strings: null
  // The mode a click just refused to enter, so the reason appears next to the
  // mode rather than only in a log the user will never open.
  property string blocked: ""

  signal command(string cmd)
  signal commandArgs(var argv)

  // `strings` is null for the instant between creation and the Loader setting
  // it, so the key stands in until then rather than a blank.
  function t(k) { return root.strings ? root.strings.t(k) : k }
  function tf(k, a) { return root.strings ? root.strings.tf(k, a) : k }

  readonly property var modes: payload.modes || []
  readonly property var switching: payload.switching || ({ by_window: false, mode: "default" })
  readonly property bool byWindow: switching.by_window === true
  readonly property var llms: payload.llm || []
  readonly property string current: {
    for (var i = 0; i < modes.length; i++) if (modes[i].name === selected) return selected
    return payload.active || (modes.length ? modes[0].name : "")
  }
  readonly property var mode: {
    for (var i = 0; i < modes.length; i++) if (modes[i].name === current) return modes[i]
    return null
  }

  function chainOf(m) {
    var names = ["speech"]
    var steps = (m && m.steps) || []
    for (var i = 0; i < steps.length; i++) names.push(steps[i].llm)
    return names.join(" → ")
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0

    // ===================== list =====================
    Rectangle {
      Layout.preferredWidth: Style.space(280)
      Layout.fillHeight: true
      color: Qt.darker(Color.popups.background, 1.05)

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ListView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: root.modes
          delegate: Rectangle {
            readonly property var m: modelData
            width: ListView.view.width
            height: entry.implicitHeight + Style.space(18)
            color: m.name === root.current
                   ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
                   : "transparent"

            Rectangle {
              width: 2; height: parent.height
              color: m.name === root.current ? Color.accent : "transparent"
            }

            ColumnLayout {
              id: entry
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(13)
              anchors.rightMargin: Style.space(11)
              spacing: 2

              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: m.name
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Color.foreground
                }
                Item { Layout.fillWidth: true }
                Text {
                  visible: m.active === true
                  text: root.t("modes.here")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.accent
                }
              }
              Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.chainOf(m)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: (m.steps || []).length ? Color.accent : Color.muted
              }
              Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: (m.match || []).join(", ") || root.t("modes.fallback")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Qt.darker(Color.muted, 1.1)
              }
              // A mode that cannot load its model is not a mode you can be in.
              Text {
                visible: m.vram_known === true && m.fits === false
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.tf("modes.wontfit", (m.needs_mb / 1024).toFixed(1) + "G")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.urgent
              }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              // Clicking a mode uses it, not merely opens it for editing.
              // Selecting-without-switching is what a list of modes looks
              // like it does least, and switching is instant and reversible.
              // With window matching on there is nothing to switch, so a
              // click only selects.
              onClicked: {
                // Selecting always works — you need to open a mode to fix the
                // step that does not fit. Only entering it is refused, and the
                // CLI refuses the same switch for the same reason.
                root.selected = m.name
                if (m.vram_known === true && m.fits === false) {
                  root.blocked = m.name
                  return
                }
                root.blocked = ""
                if (!root.byWindow && (root.switching.mode || "default") !== m.name)
                  root.commandArgs(["omavoi", "mode", "use", m.name])
              }
            }
          }
        }

        // -- new mode --
        RowLayout {
          Layout.fillWidth: true
          Layout.margins: Style.space(11)
          spacing: Style.space(7)
          TextField {
            id: newName
            Layout.fillWidth: true
            placeholderText: root.t("modes.newname")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            onAccepted: makeMode.click()
          }
          Button {
            id: makeMode
            text: "+"
            function click() {
              var name = newName.text.trim()
              if (!name) return
              // Copied from the current mode: a new mode that starts empty
              // has no rules and silently behaves unlike every other one.
              root.commandArgs(["omavoi", "mode", "new", name, root.current])
              root.selected = name
              newName.text = ""
            }
            onClicked: click()
          }
        }
      }
    }

    Rectangle {
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
    }

    // ===================== detail =====================
    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentHeight: detail.implicitHeight + root.pad * 2
      visible: root.mode !== null

      ColumnLayout {
        id: detail
        x: root.pad
        y: root.pad
        width: parent.width - root.pad * 2
        spacing: Style.space(14)

        // How the mode gets picked at all. Without this the trigger chips below
        // are a lie: they are configured, but nothing reads them.
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: pick.implicitHeight + Style.space(18)
          color: root.byWindow
                 ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.07)
                 : "transparent"
          border.width: 1
          border.color: root.byWindow
                        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.6)
                        : Qt.rgba(Color.foreground.r, Color.foreground.g,
                                  Color.foreground.b, 0.25)
          radius: Style.cornerRadius

          RowLayout {
            id: pick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(12)
            spacing: Style.space(12)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2
              Text {
                text: root.byWindow
                      ? root.t("modes.followwin")
                      : root.t("modes.everytake") + (root.switching.mode || "default")
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Color.foreground
              }
              Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.byWindow ? root.t("modes.longestwins")
                                    : root.t("modes.matchoff")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.muted
              }
            }

            OmChip {
              label: root.byWindow ? root.t("modes.following") : root.t("modes.fixed")
              on: root.byWindow
              onClicked: root.commandArgs(
                ["omavoi", "mode", "auto", root.byWindow ? "off" : "on"])
            }

          }
        }

        // -- header --
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          Text {
            text: root.current
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            color: Color.foreground
          }
          Text {
            visible: root.blocked !== "" && root.blocked === root.current
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.t("modes.blocked")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.urgent
          }
          Text {
            visible: root.mode && root.mode.active === true
            text: root.t("modes.activehere")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.accent
          }
          Item { Layout.fillWidth: true }
          Button {
            visible: root.current !== "default"
            text: root.t("modes.delete")
            onClicked: root.commandArgs(["omavoi", "mode", "rm", root.current])
          }
        }

        // -- triggers --
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          opacity: root.byWindow ? 1 : 0.5
          RowLayout {
            spacing: Style.space(8)
            Text {
              text: root.t("modes.opens")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Color.muted
            }
            Text {
              visible: !root.byWindow
              text: root.t("modes.notinuse")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.muted, 1.1)
            }
          }
          Flow {
            Layout.fillWidth: true
            spacing: Style.space(6)
            Repeater {
              model: (root.mode && root.mode.match) || []
              OmChip {
                readonly property string token: modelData
                label: token + "  ×"
                on: true
                onClicked: root.commandArgs(["omavoi", "mode", "unmatch", root.current, token])
              }
            }
            Text {
              visible: !((root.mode && root.mode.match) || []).length
              text: root.t("modes.nothing")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(7)
            TextField {
              id: newMatch
              Layout.preferredWidth: Style.space(280)
              placeholderText: root.t("modes.classph")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              onAccepted: addMatch.click()
            }
            Button {
              id: addMatch
              text: root.t("modes.add")
              function click() {
                var t = newMatch.text.trim()
                if (!t) return
                root.commandArgs(["omavoi", "mode", "match", root.current, t])
                newMatch.text = ""
              }
              onClicked: click()
            }
            Text {
              Layout.fillWidth: true
              wrapMode: Text.Wrap
              text: root.t("modes.matchhint")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.muted, 1.1)
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true; Layout.preferredHeight: 1
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
        }

        // -- 1 speech --
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(7)
          RowLayout {
            spacing: Style.space(9)
            Text {
              text: root.t("modes.s1")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Color.accent
            }
            Text {
              text: root.t("modes.speechsub")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(9)
            Text {
              Layout.preferredWidth: Style.space(96)
              text: root.t("modes.language")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
            TextField {
              Layout.preferredWidth: Style.space(120)
              text: (root.mode && root.mode.language) || ""
              placeholderText: root.t("modes.langauto")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              onEditingFinished: if (root.mode && text !== (root.mode.language || ""))
                root.commandArgs(["omavoi", "mode", "set", root.current, "language", text])
            }
            Text {
              Layout.fillWidth: true
              text: root.t("modes.langhint")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.muted, 1.1)
            }
          }
          Text {
            text: root.t("modes.decoderhint")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
          }
          OmTextArea {
            Layout.fillWidth: true
            minLines: 2
            key: root.current
            text: (root.mode && root.mode.prompt) || ""
            placeholder: root.t("modes.promptph")
            onCommitted: function (v) {
              root.commandArgs(["omavoi", "mode", "set", root.current, "prompt", v])
            }
          }
        }

        // -- 2 rules --
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(7)
          RowLayout {
            spacing: Style.space(9)
            Text {
              text: root.t("modes.s2")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Color.foreground
            }
            Text {
              text: root.t("modes.rulessub")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }
          Flow {
            Layout.fillWidth: true
            spacing: Style.space(6)
            Repeater {
              model: [
                { k: "hallucinations", label: root.t("modes.r.hallucinations") },
                { k: "fillers", label: root.t("modes.r.fillers") },
                { k: "dictionary", label: root.t("modes.r.dictionary") },
                { k: "names", label: root.t("modes.r.names") },
                { k: "cjk_spacing", label: root.t("modes.r.cjk") }
              ]
              OmChip {
                readonly property var rule: modelData
                label: rule.label
                on: root.mode && root.mode.rules ? root.mode.rules[rule.k] !== false : true
                onClicked: root.command(
                  "omavoi config set modes." + root.current + ".rules." + rule.k
                  + " " + (on ? "false" : "true"))
              }
            }
            Rectangle {
              width: 1; height: Style.space(18)
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
            }
            OmChip {
              label: root.t("modes.keeppunct")
              on: !(root.mode && root.mode.rules
                    && root.mode.rules.punctuation === "strip")
              onClicked: root.command(
                "omavoi config set modes." + root.current + ".rules.punctuation "
                + (on ? "strip" : "keep"))
            }
          }
        }

        // -- 3 llm steps --
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(7)
          RowLayout {
            spacing: Style.space(9)
            Text {
              text: root.t("modes.s3")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: ((root.mode && root.mode.steps) || []).length ? Color.accent : Color.muted
            }
            Text {
              text: root.t("modes.llmsub")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }

          Repeater {
            model: (root.mode && root.mode.steps) || []
            Rectangle {
              readonly property var step: modelData
              readonly property int idx: index
              Layout.fillWidth: true
              implicitHeight: stepBody.implicitHeight + Style.space(18)
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.55)
              radius: Style.cornerRadius

              ColumnLayout {
                id: stepBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                spacing: Style.space(6)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(7)
                  Text {
                    text: root.t("modes.step") + (idx + 1)
                          + root.t("modes.stepsuffix")
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.muted
                  }
                  Repeater {
                    model: root.llms
                    OmChip {
                      readonly property string llmName: modelData
                      label: llmName
                      on: llmName === step.llm
                      onClicked: if (!on) root.commandArgs(
                        ["omavoi", "mode", "step", root.current, "llm",
                         String(idx), llmName])
                    }
                  }
                  Item { Layout.fillWidth: true }
                  Button {
                    text: root.t("modes.remove")
                    onClicked: root.commandArgs(
                      ["omavoi", "mode", "step", root.current, "rm", String(idx)])
                  }
                }

                OmTextArea {
                  Layout.fillWidth: true
                  minLines: 3
                  key: root.current + "#" + idx
                  text: step.prompt || ""
                  placeholder: root.t("modes.stepph")
                  onCommitted: function (v) {
                    root.commandArgs(["omavoi", "mode", "step", root.current,
                                      "prompt", String(idx), v])
                  }
                }
              }
            }
          }

          Text {
            visible: !((root.mode && root.mode.steps) || []).length
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.t("modes.nostep")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Qt.darker(Color.muted, 1.1)
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(7)
            Text {
              text: root.t("modes.addstep")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
            Repeater {
              model: root.llms
              OmChip {
                readonly property string llmName: modelData
                label: llmName
                on: false
                // No prompt here: the command fills its default, so the text
                // lives in one place instead of drifting between the two.
                onClicked: root.commandArgs(
                  ["omavoi", "mode", "step", root.current, "add", llmName])
              }
            }
            Text {
              visible: !root.llms.length
              text: root.t("modes.nollm")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
            Item { Layout.fillWidth: true }
          }
        }

        // -- 4 inject --
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(7)
          RowLayout {
            spacing: Style.space(9)
            Text {
              text: root.t("modes.s4")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Color.foreground
            }
            Repeater {
              model: ["auto", "wtype", "clipboard"]
              OmChip {
                readonly property string how: modelData
                // wtype is a program name, so it is not translated.
                label: how === "wtype" ? how : root.t("modes.inject." + how)
                on: ((root.mode && root.mode.inject) || "auto") === how
                onClicked: if (!on) root.commandArgs(
                  ["omavoi", "mode", "set", root.current, "inject", how])
              }
            }
            Item { Layout.fillWidth: true }
          }
          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.t("modes.injecthint")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Qt.darker(Color.muted, 1.1)
          }
        }
      }
    }
  }
}

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// What is left once Modes took the contextual choices and Models took the
// weights: the physical and the global. A key, a microphone, an overlay, and
// what stays on disk.
Flickable {
  id: root
  property var cfg: ({})
  property var setupReport: ({ steps: [] })
  property int pad: Style.space(22)
  property var strings: null

  signal command(string cmd)

  // `strings` is null for the instant between creation and the Loader setting
  // it, so the key stands in until then rather than a blank.
  function t(k) { return root.strings ? root.strings.t(k) : k }
  function tf(k, a) { return root.strings ? root.strings.tf(k, a) : k }

  function get(path, fallback) {
    var node = root.cfg
    var parts = path.split(".")
    for (var i = 0; i < parts.length; i++) {
      if (!node || node[parts[i]] === undefined) return fallback
      node = node[parts[i]]
    }
    return node
  }

  contentHeight: col.implicitHeight + pad * 2
  clip: true

  ColumnLayout {
    id: col
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    spacing: Style.space(18)

    // ---- hotkey ----------------------------------------------------
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text {
        text: root.t("set.hotkey")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        color: Color.muted
      }
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.preferredWidth: Style.space(160)
          text: root.t("set.key")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.muted
        }
        Text {
          text: root.get("hotkey.key", "?")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.foreground
        }
      }
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.preferredWidth: Style.space(160)
          text: root.t("set.behaviour")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.muted
        }
        ButtonGroup {
          options: [{ value: "push_to_talk", label: root.t("set.ptt") },
                    { value: "toggle", label: root.t("set.toggle") }]
          value: root.get("hotkey.mode", "push_to_talk")
          onChanged: function (v) { root.command("omavoi config set hotkey.mode " + v) }
        }
      }
      Text {
        Layout.maximumWidth: Style.space(760)
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.t("set.hotkeynote")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Qt.darker(Color.muted, 1.15)
      }
    }

    // ---- audio -----------------------------------------------------
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text {
        text: root.t("set.audio")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        color: Color.muted
      }
      Repeater {
        model: [
          { k: "audio.preroll_seconds", label: root.t("set.preroll"), unit: "s",
            why: root.t("set.prerollwhy") },
          { k: "audio.tail_seconds", label: root.t("set.tail"), unit: "s", why: "" },
          { k: "audio.warn_rms_dbfs", label: root.t("set.warnbelow"), unit: " dBFS", why: "" },
          { k: "audio.max_seconds", label: root.t("set.maxtake"), unit: "s", why: "" }
        ]
        ColumnLayout {
          readonly property var row: modelData
          Layout.fillWidth: true
          spacing: Style.space(2)
          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.preferredWidth: Style.space(160)
              text: row.label
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: Color.muted
            }
            Text {
              text: root.get(row.k, "?") + row.unit
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: Color.foreground
            }
          }
          Text {
            visible: row.why !== ""
            Layout.maximumWidth: Style.space(760)
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: row.why
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Qt.darker(Color.muted, 1.15)
          }
        }
      }
    }

    // ---- hud -------------------------------------------------------
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text {
        text: root.t("set.hud")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        color: Color.muted
      }
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.preferredWidth: Style.space(160)
          text: root.t("set.keepup")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.muted
        }
        ButtonGroup {
          options: [{ value: "always", label: root.t("set.dwell.always") },
                    { value: "changed", label: root.t("set.dwell.changed") },
                    { value: "never", label: root.t("set.dwell.never") }]
          value: root.get("ui.hud_dwell", "changed")
          onChanged: function (v) { root.command("omavoi config set ui.hud_dwell " + v) }
        }
      }
      Text {
        Layout.maximumWidth: Style.space(760)
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.t("set.hudnote")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Qt.darker(Color.muted, 1.15)
      }
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.preferredWidth: Style.space(160)
          text: root.t("set.notifications")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.muted
        }
        OmChip {
          label: root.get("ui.notify", true) === true ? root.t("set.on")
                                                       : root.t("set.off")
          on: root.get("ui.notify", true) === true
          onClicked: root.command(
            "omavoi config set ui.notify " + (on ? "false" : "true"))
        }
      }
    }

    // ---- history and privacy ---------------------------------------
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text {
        text: root.t("set.history")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        color: Color.muted
      }
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.preferredWidth: Style.space(160)
          text: root.t("set.keepaudio")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.muted
        }
        Text {
          text: root.get("history.keep_audio", 0) + root.t("set.takes")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.foreground
        }
      }
      Text {
        Layout.maximumWidth: Style.space(760)
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.t("set.historynote")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Qt.darker(Color.muted, 1.15)
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(6)
        implicitHeight: privacy.implicitHeight + Style.space(20)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(Color.muted.r, Color.muted.g, Color.muted.b, 0.6)

        ColumnLayout {
          id: privacy
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(10)
          spacing: Style.space(4)
          Text {
            text: root.t("set.neverleaves")
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: "#9ece6a"
          }
          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.t("set.privacynote")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
          }
        }
      }
    }

    RowLayout {
      Layout.topMargin: Style.space(6)
      spacing: Style.space(8)
      Button { text: root.t("set.editconfig"); onClicked: root.command("omavoi config path") }
      Button {
        text: root.t("set.restart")
        onClicked: root.command("systemctl --user restart omavoid")
      }
      Text {
        Layout.fillWidth: true
        text: root.t("set.configpath")
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Color.muted
      }
    }
  }
}

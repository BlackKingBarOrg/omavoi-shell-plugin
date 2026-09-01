import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Two kinds of entry, because they solve different problems. A rule needs you
// to know what the model got wrong. A name does not — and for CJK you never
// will, since the manglings are an open set of homophones — so a name is
// written once, correctly, and matched by sound.
Flickable {
  id: root
  property var rules: []
  property var names: []
  property string seed: ""
  property int budget: 224
  property int pad: Style.space(22)
  property string sub: "rules"
  property var strings: null

  signal command(string cmd)

  // `strings` is null for the instant between creation and the Loader setting
  // it, so the key stands in until then rather than a blank.
  function t(k) { return root.strings ? root.strings.t(k) : k }
  function tf(k, a) { return root.strings ? root.strings.tf(k, a) : k }

  contentHeight: col.implicitHeight + pad * 2
  clip: true

  ColumnLayout {
    id: col
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    spacing: Style.space(12)

    ButtonGroup {
      options: [{ value: "rules", label: root.t("dict.rules") },
                { value: "names", label: root.t("dict.names") }]
      value: root.sub
      onChanged: function (v) { root.sub = v }
    }

    // ---- rules -----------------------------------------------------
    Text {
      visible: root.sub === "rules"
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: root.t("dict.blurb")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.muted
    }
    Repeater {
      model: root.sub === "rules" ? root.rules : []
      RowLayout {
        readonly property var r: modelData
        Layout.fillWidth: true
        spacing: Style.space(10)
        Text {
          Layout.preferredWidth: Style.space(180)
          text: r.heard
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.foreground
        }
        Text {
          text: "→"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
        Text {
          Layout.preferredWidth: Style.space(180)
          text: r.meant
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.foreground
        }
        Text {
          Layout.fillWidth: true
          visible: r.shadowed_by !== ""
          text: root.t("dict.shadowed") + "\"" + r.shadowed_by + "\""
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: "#e0af68"
        }
        Item { Layout.fillWidth: r.shadowed_by === "" }
        Button {
          text: root.t("dict.remove")
          onClicked: root.command("omavoi dict rm " + JSON.stringify(r.heard))
        }
      }
    }

    // ---- names -----------------------------------------------------
    Text {
      visible: root.sub === "names"
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: root.t("dict.namesblurb")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.muted
    }
    Repeater {
      model: root.sub === "names" ? root.names : []
      RowLayout {
        readonly property var n: modelData
        Layout.fillWidth: true
        spacing: Style.space(10)
        Text {
          Layout.preferredWidth: Style.space(150)
          text: n.name
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.foreground
        }
        Text {
          Layout.preferredWidth: Style.space(170)
          text: n.key
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
        Text {
          Layout.preferredWidth: Style.space(80)
          text: n.match
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
        Text {
          Layout.preferredWidth: Style.space(110)
          text: n.enabled ? root.t("dict.matching") : root.t("dict.seedonly")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: n.enabled ? "#9ece6a" : Color.muted
        }
        Item { Layout.fillWidth: true }
        Button {
          text: root.t("dict.remove")
          onClicked: root.command("omavoi names rm " + JSON.stringify(n.name))
        }
      }
    }
    RowLayout {
      visible: root.sub === "names"
      Layout.topMargin: Style.space(8)
      spacing: Style.space(10)
      Button { text: root.t("dict.dryrun"); onClicked: root.command("omavoi names dryrun") }
      Button {
        text: root.t("dict.enable")
        onClicked: root.command("omavoi names enable")
      }
      Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.t("dict.prompt") + (root.seed || root.t("dict.none"))
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Color.muted
      }
    }

    Text {
      Layout.topMargin: Style.space(12)
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: root.sub === "rules" ? root.t("dict.addrule") : root.t("dict.addnames")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.muted
    }
  }
}

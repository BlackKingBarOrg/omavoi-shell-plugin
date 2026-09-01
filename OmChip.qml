import QtQuick
import qs.Commons

// A compact on/off tag. Deliberately not qs.Ui's Toggle: that one is a
// full-width settings row with a label and a description, and a row of five
// of them is a wall of empty boxes. A rule flag is a word you switch, so it
// is drawn as one.
Rectangle {
  id: root
  property string label: ""
  property bool on: false
  property bool enabled: true
  signal clicked()

  implicitWidth: text.implicitWidth + Style.space(16)
  implicitHeight: text.implicitHeight + Style.space(6)

  color: on ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, hover.containsMouse ? 0.26 : 0.16)
            : (hover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g,
                                             Color.foreground.b, 0.06) : "transparent")
  border.width: 1
  border.color: on ? Color.accent
                   : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.28)
  radius: Style.cornerRadius
  opacity: root.enabled ? 1 : 0.45

  Text {
    id: text
    anchors.centerIn: parent
    text: root.label
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: root.on ? Color.foreground : Color.muted
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.enabled) root.clicked()
  }
}

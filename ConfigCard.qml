import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One card, both columns.
//
// The speech engines and the LLM configurations are the same kind of thing —
// pick a route, see whether it is up, see what it costs — and they had two
// layouts. The speech card laid name and detail side by side on one line; the
// LLM card stacked them in a ColumnLayout and was therefore always two lines,
// whatever the text length. That, and not the wording, is why the two model
// tables started at different heights: three two-line cards are taller than
// three one-line cards, and the tables below them inherited the difference.
//
// The two-line shape wins because the LLM cards have five things to say and
// squeezing them onto one line elides the explanation. The speech column has
// spare room underneath, so it costs nothing there.
//
// Six slots, and both columns fill all six:
//
//                 speech                        LLM
//   selected      the chosen engine             a configuration in use
//   running       the engine actually up        a server actually up
//   name          本地 · Vulkan                 系统 agent
//   secondary     whisper.cpp                   claude
//   detail        ggml weights, which GPUs      what this route is
//   status        running                       running / not started / no key
//   note          package size                  which modes use it
Rectangle {
  id: card

  property bool selected: false
  property bool running: false
  property string name: ""
  property string secondary: ""
  property string detail: ""
  // Status and note carry their own colour: the LLM side distinguishes four
  // states (unset, no key, running, cold) and a set of booleans here would
  // have flattened one of them.
  property string status: ""
  property color statusColor: Color.muted
  property string note: ""
  property color noteColor: Color.muted
  // Whether clicking the card is the way to choose it. The speech engines are
  // a single choice; the LLM configurations coexist, so there is nothing to
  // choose and nothing to click.
  property bool selectable: false
  property string actionLabel: ""
  property bool actionOn: false

  signal chosen()
  signal action()

  Layout.fillWidth: true
  implicitHeight: body.implicitHeight + Style.space(16)
  color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.07)
                  : "transparent"
  border.width: 1
  border.color: selected ? Qt.rgba(Color.accent.r, Color.accent.g,
                                   Color.accent.b, 0.6)
                         : Qt.rgba(Color.foreground.r, Color.foreground.g,
                                   Color.foreground.b, 0.2)
  radius: Style.cornerRadius

  RowLayout {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(11)
    anchors.rightMargin: Style.space(11)
    spacing: Style.space(10)

    // The dot is the choice; the ▶ beside it is whether the choice is what is
    // actually up. They coincide most of the time, and the times they do not
    // are the ones worth seeing.
    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      visible: card.selectable
      width: Style.space(9); height: width
      radius: width / 2
      color: card.selected ? Color.accent : "transparent"
      border.width: 1
      border.color: card.selected ? Color.accent : Color.muted
    }
    Text {
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredWidth: Style.space(12)
      text: card.running ? "▶" : ""
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.accent
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 1
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Text {
          text: card.name
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.foreground
        }
        Text {
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: card.secondary
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }
      Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: card.detail
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Qt.darker(Color.muted, 1.15)
      }
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredWidth: Style.space(84)
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: card.status
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: card.statusColor
    }
    Text {
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredWidth: Style.space(96)
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: card.note
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: card.noteColor
    }
    OmChip {
      Layout.alignment: Qt.AlignVCenter
      visible: card.actionLabel !== ""
      label: card.actionLabel
      on: card.actionOn
      onClicked: card.action()
    }
  }

  MouseArea {
    anchors.fill: parent
    visible: card.selectable
    enabled: card.selectable
    cursorShape: Qt.PointingHandCursor
    onClicked: if (!card.selected) card.chosen()
  }
}

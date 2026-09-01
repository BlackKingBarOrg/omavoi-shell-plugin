import QtQuick
import QtQuick.Controls
import qs.Commons

// A themed multi-line field. qs.Ui's TextField is single-line, and a decoder
// hint or an LLM prompt is several sentences with deliberate line breaks.
//
// Edits commit when the field loses focus rather than on every keystroke:
// each commit rewrites config.toml and makes the daemon re-read it, and doing
// that per character would be absurd.
Rectangle {
  id: root
  property string text: ""
  property string placeholder: ""
  property int minLines: 2
  // Changing this reloads the field from `text`. Typing breaks the binding on
  // area.text, so without it switching modes would leave the previous mode's
  // prompt on screen — editable, and about to be saved to the wrong place.
  property string key: ""
  signal committed(string value)

  readonly property bool dirty: area.text !== root.text

  onKeyChanged: area.text = root.text
  onTextChanged: if (!root.dirty || !area.activeFocus) area.text = root.text

  implicitHeight: Math.max(area.implicitHeight + Style.space(10),
                           Style.font.body * 1.7 * minLines + Style.space(10))
                  + (root.dirty ? Style.space(26) : 0)
  color: Qt.darker(Color.popups.background, 1.06)
  border.width: 1
  border.color: area.activeFocus ? Color.accent
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b,
                        root.dirty ? 0.55 : 0.22)
  radius: Style.cornerRadius

  function commit() {
    if (root.dirty) root.committed(area.text)
  }

  TextArea {
    id: area
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(5)
    height: parent.height - Style.space(10) - (root.dirty ? Style.space(26) : 0)
    text: root.text
    placeholderText: root.placeholder
    wrapMode: TextArea.Wrap
    selectByMouse: true
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: Color.foreground
    placeholderTextColor: Color.muted
    background: null
    Keys.onPressed: function (e) {
      if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
          && (e.modifiers & Qt.ControlModifier)) {
        root.commit()
        e.accepted = true
      }
    }
  }

  // An explicit Save, not a commit on focus loss. Losing focus is not an
  // intent: clicking away, closing the panel or tabbing all read the same,
  // and a prompt saved because you looked elsewhere is worse than one you
  // have to press a button for.
  Row {
    visible: root.dirty
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(5)
    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "unsaved"
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.urgent
    }
    OmChip {
      label: "Revert"
      on: false
      onClicked: area.text = root.text
    }
    OmChip {
      label: "Save  ⌃⏎"
      on: true
      onClicked: root.commit()
    }
  }
}

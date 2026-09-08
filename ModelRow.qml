import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One row, both families.
//
// A speech entry and an LLM entry carry the same fifteen fields and mean the
// same things by them — key, size, note, tags, downloaded, ours, running,
// active, fits, needed_mb. The only reason the two tables looked different is
// that the row was written twice, and then drifted: the name column was 178
// on one side and 150 on the other, the action column 180 and 240, the
// won't-fit warning appeared only for LLMs, the on-disk label only for
// speech, and the recommended highlight only for speech. None of that was a
// decision.
//
// So it is written once. `useCommand` is the single real difference: choosing
// a speech model writes the speech model, choosing LLM weights writes them
// into the local configuration.
RowLayout {
  id: row

  property var m: ({})
  property var strings: null
  // Keys with a download in flight, so the button can become a word.
  property var pulling: ({})
  property string useCommand: ""

  signal command(string cmd)

  function t(k) { return row.strings ? row.strings.t(k) : k }

  Layout.fillWidth: true
  spacing: Style.space(10)

  Text {
    Layout.preferredWidth: Style.space(12)
    // ▶ is loaded right now, ● is chosen but not loaded, ○ is merely on
    // disk. The glyph carries that distinction, so the colour does not have
    // to — the speech table used to paint ● in the urgent colour, which is
    // right for a speech model that was asked for and did not load and wrong
    // for LLM weights, which are cold until a take reaches them.
    text: m.running ? "▶" : (m.active ? "●" : (m.downloaded ? "○" : ""))
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: (m.running || m.active) ? Color.accent : Color.muted
  }
  Text {
    Layout.preferredWidth: Style.space(178)
    text: m.key
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    color: Color.foreground
  }
  Text {
    Layout.preferredWidth: Style.space(46)
    horizontalAlignment: Text.AlignRight
    text: (m.size_mb / 1024).toFixed(1) + "G"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: Color.muted
  }
  // Won't-fit is worth saying before the download, not after — and never
  // about the model that is loaded right now, whose own weights are most of
  // what the free-VRAM figure is missing.
  Text {
    visible: m.fits === false && m.running !== true
    text: row.t("models.needs") + " " + (m.needed_mb / 1024).toFixed(1) + "G"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: Color.urgent
  }
  Text {
    Layout.fillWidth: true
    Layout.minimumWidth: Style.space(40)
    elide: Text.ElideRight
    text: m.note
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: (m.tags || []).indexOf("recommended") >= 0 ? Color.foreground
                                                      : Color.muted
  }
  RowLayout {
    Layout.preferredWidth: Style.space(180)
    spacing: Style.space(7)
    Item { Layout.fillWidth: true }
    Text {
      visible: m.running === true
      text: row.t("models.running")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.accent
    }
    // Found where another tool put it, and used where it lies rather than
    // downloaded again. True of either family.
    Text {
      visible: m.downloaded && !m.ours && m.running !== true
      text: row.t("models.ondisk")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.muted
    }
    Text {
      visible: !m.downloaded && row.pulling[m.key] === true
      text: row.t("models.downloading")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.accent
    }
    Button {
      visible: !m.downloaded && row.pulling[m.key] !== true
      text: row.t("models.download")
      onClicked: row.command("omavoi model pull " + m.key)
    }
    Button {
      visible: m.downloaded && !m.active && row.useCommand !== ""
      text: row.t("models.use")
      onClicked: row.command(row.useCommand)
    }
    // Never the weights something is pointing at, and never the ones a
    // server has open.
    Button {
      visible: m.downloaded && m.ours && !m.active && m.running !== true
      text: row.t("models.remove")
      onClicked: row.command("omavoi model rm " + m.key)
    }
  }
}

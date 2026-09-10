import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui

// A URL, a key and a model id — for either family's remote endpoint.
//
// Everything else that used to be on screen here — key_env, key_name,
// timeout, temperature — is machinery, and putting it up made a mechanism
// look like a decision. It lives in the config file for anyone who needs it.
//
// Written once because the speech side had none of this at all: the console
// offered a "remote API" engine card for speech and there was nowhere to put
// the URL, so the engine could be selected and never configured. Building a
// second copy of the LLM panel is how the two would have drifted the way the
// rows and the cards did.
//
// `providers` is the one asymmetry, and it is a real one: the speech backend
// ships presets (openai, groq, siliconflow, deepinfra, local) that fill the
// URL, the model and the key's environment variable from one word. The LLM
// side has no presets, so it passes an empty list and the row disappears.
ColumnLayout {
  id: fields

  property var strings: null
  // What `omavoi config set` writes under: "llm.api" or "speech.api".
  property string prefix: ""
  // What `omavoi secrets set` stores the key as.
  property string secretName: ""
  // What answers "does this endpoint work", as argv.
  property var checkArgv: []

  property string baseUrl: ""
  property string model: ""
  property bool hasKey: false
  // The value that applies when the field is left empty, shown as the
  // placeholder so a preset is visible rather than magic.
  property string defaultBaseUrl: ""
  property string defaultModel: ""
  property var providers: []
  property string provider: ""

  signal command(string cmd)

  function t(k) { return fields.strings ? fields.strings.t(k) : k }

  spacing: Style.space(5)

  property string keyNote: ""
  property string checkNote: ""
  property bool checkOk: false
  property var checkModels: []

  // The key goes over stdin, never in a command line: a value in argv is
  // readable from /proc by every process running as this user for as long as
  // the command lives.
  Process {
    id: keyWriter
    command: ["omavoi", "secrets", "set", fields.secretName]
    stdinEnabled: true
    property string pending: ""
    function send(value) {
      keyWriter.pending = value
      fields.keyNote = ""
      keyWriter.running = true
    }
    onStarted: {
      // Written once the pipe exists, then closed so the reader sees EOF.
      keyWriter.write(keyWriter.pending)
      keyWriter.pending = ""
      keyWriter.stdinEnabled = false
    }
    onExited: function (code, status) {
      fields.keyNote = code === 0 ? fields.t("models.f.key.saved")
                                  : fields.t("models.f.key.failed")
      keyField.text = ""
      fields.command("omavoi config show --json")
    }
  }

  Process {
    id: checker
    command: fields.checkArgv
    stdout: StdioCollector {
      onStreamFinished: {
        var r = ({})
        try { r = JSON.parse(text) } catch (e) { r = ({ ok: false, error: text }) }
        fields.checkOk = r.ok === true
        fields.checkModels = r.ok === true ? (r.models || []) : []
        fields.checkNote = r.ok === true
          ? fields.t("models.f.testok") + (r.models ? "  " + r.models.length : "")
          : String(r.error || fields.t("models.f.testfail"))
      }
    }
  }

  // -- provider, when there are presets to pick from ------------------------
  RowLayout {
    visible: (fields.providers || []).length > 0
    Layout.fillWidth: true
    spacing: Style.space(9)
    Text {
      Layout.preferredWidth: Style.space(52)
      text: fields.t("models.f.provider")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.muted
    }
    Flow {
      Layout.fillWidth: true
      spacing: Style.space(6)
      Repeater {
        model: fields.providers
        OmChip {
          readonly property string pid: modelData
          label: pid
          on: pid === fields.provider
          onClicked: if (!on) fields.command(
            "omavoi config set " + fields.prefix + ".provider " + pid)
        }
      }
    }
  }

  // -- url and model --------------------------------------------------------
  Repeater {
    model: [
      { key: "url", label: fields.t("models.f.url") },
      { key: "model", label: fields.t("models.f.model") }
    ]
    RowLayout {
      readonly property var f: modelData
      readonly property string now: f.key === "url" ? fields.baseUrl : fields.model
      Layout.fillWidth: true
      spacing: Style.space(9)
      Text {
        Layout.preferredWidth: Style.space(52)
        text: f.label
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Color.muted
      }
      TextField {
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(320)
        text: now
        placeholderText: f.key === "url" ? fields.defaultBaseUrl
                                         : fields.defaultModel
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        onEditingFinished: {
          if (text === now) return
          fields.command("omavoi config set " + fields.prefix + "."
                         + (f.key === "url" ? "base_url" : "model")
                         + " " + JSON.stringify(text))
        }
      }
    }
  }

  // -- the key --------------------------------------------------------------
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(9)
    Text {
      Layout.preferredWidth: Style.space(52)
      text: fields.t("models.f.key")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.muted
    }
    TextField {
      id: keyField
      Layout.fillWidth: true
      Layout.maximumWidth: Style.space(320)
      echoMode: TextInput.Password
      placeholderText: fields.t("models.f.key.place")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      onAccepted: if (text !== "") keyWriter.send(text)
    }
    Button {
      enabled: keyField.text !== ""
      text: fields.t("models.f.key.save")
      onClicked: keyWriter.send(keyField.text)
    }
    Text {
      Layout.fillWidth: true
      elide: Text.ElideRight
      text: fields.keyNote !== "" ? fields.keyNote
            : (fields.hasKey ? fields.t("models.f.key.have") : "")
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: fields.keyNote === "" ? Color.muted : Color.accent
    }
  }

  // -- does it answer? ------------------------------------------------------
  RowLayout {
    Layout.fillWidth: true
    Layout.topMargin: Style.space(3)
    spacing: Style.space(9)
    Button {
      enabled: (fields.checkArgv || []).length > 0
      text: fields.t("models.f.test")
      onClicked: { fields.checkNote = fields.t("models.f.testing"); checker.running = true }
    }
    Text {
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: fields.checkNote
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: fields.checkOk ? "#9ece6a" : Color.urgent
    }
  }

  // Offered rather than typed: the check already returned the list, and a
  // model id from memory is the commonest thing to get wrong.
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(6)
    visible: fields.checkModels.length > 0
    Repeater {
      model: fields.checkModels
      OmChip {
        readonly property string mid: modelData
        label: mid
        on: mid === fields.model
        onClicked: fields.command("omavoi config set " + fields.prefix
                                  + ".model " + JSON.stringify(mid))
      }
    }
  }
}

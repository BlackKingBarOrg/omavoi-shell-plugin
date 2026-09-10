import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui

// Two model families side by side, because they are not the same kind of
// thing. Exactly one speech engine runs; any number of LLMs can be defined,
// since different modes reach for different ones. Their costs differ too —
// a speech model is VRAM and RTF, an LLM is latency and, if remote, a key.
Item {
  id: root
  property var payload: ({ models: [], llm: [], vram: ({}), active: "", backend: "", root: "" })
  property var pulling: ({})
  readonly property int pad: Style.space(20)
  property var strings: null

  signal command(string cmd)

  // `strings` is null for the instant between creation and the Loader setting
  // it, so the key stands in until then rather than a blank.
  function t(k) { return root.strings ? root.strings.t(k) : k }
  function tf(k, a) { return root.strings ? root.strings.tf(k, a) : k }

  readonly property bool ggml: payload.backend === "local-whispercpp"
  // A gguf LLM is also fmt=ggml, so the format alone put chat models in the
  // speech table — with a Use button that would have written one into
  // speech.model. The two families split on `kind`.
  readonly property var speechModels: (payload.models || []).filter(function (m) {
    return m.kind === "speech" && (root.ggml ? m.fmt === "ggml" : m.fmt === "ct2")
  })
  readonly property var llmModels: (payload.models || []).filter(function (m) {
    return m.kind === "llm"
  })
  // The entries a downloadable LLM can be pointed at. Removing "Use" from
  // these rows was right in one way — a mode names an entry, not a model —
  // and wrong in another: you could download gemma and have no way to make
  // anything use it.
  readonly property var localLlms: (payload.llm || []).filter(function (l) {
    return l.backend === "llama-local" || l.backend === "llama.cpp"
  })
  // What the daemon has actually loaded. The config only says what was asked
  // for, and the two differ from the moment of an edit until a restart.
  readonly property var engines: payload.engines || ({})
  readonly property var speechNow: engines.speech || ({})
  // Servers resident on this machine right now. The cards below already say
  // which configurations are usable; what they cannot say is what is actually
  // loaded and holding memory, which is the whole of what the speech column's
  // matching line is for.
  readonly property var llmResident: (engines.llm || []).filter(function (l) {
    return l.live === true && (l.pid || 0) > 0
  })
  readonly property bool daemonUp: payload.daemon === true
  readonly property bool speechLive: root.speechNow.live === true
  readonly property bool stale: root.daemonUp && root.speechLive
      && (String(root.speechNow.model || "") !== String(root.payload.active || "")
          || String(root.speechNow.backend || "") !== String(root.payload.backend || ""))

  // The theme gives accent, urgent and muted, and in most omarchy themes
  // accent equals foreground — not enough to tell two model families apart.
  // These are the two colours this console already uses for local-and-good
  // and for attention, so the bar stays in the same vocabulary as the badges.
  readonly property color speechColor: "#9ece6a"
  readonly property color llmColor: "#e0af68"
  readonly property color otherColor: Qt.rgba(Color.foreground.r, Color.foreground.g,
                                              Color.foreground.b, 0.28)

  readonly property var vramSegments: (payload.vram && payload.vram.segments) || []
  // An integrated GPU has no pool of its own -- the daemon reports system RAM
  // and says so, and the two readings need different words for the same bar.
  readonly property bool unifiedMem: ((payload.vram || {}).unified === true)
  function segColor(kind) {
    if (kind === "speech") return root.speechColor
    if (kind === "llm") return root.llmColor
    return root.otherColor
  }
  function segLabel(kind) {
    if (kind === "speech") return root.t("models.seg.speech")
    if (kind === "llm") return root.t("models.llm")
    return root.t("models.seg.other")
  }

  // The fields are a detour, not the page: three rows say what is configured,
  // and only the one you are changing needs to be open.
  // The remote speech endpoint. It had no payload at all, so the console
  // offered a "remote API" engine card with nothing behind it — the engine
  // could be selected and never configured.
  readonly property var speechApi: payload.speech_api || ({})
  readonly property bool speechApiBlank: {
    var a = root.speechApi
    if (a.provider === undefined) return false
    // A provider preset supplies the URL, so blank means neither is there.
    return (String(a.base_url || "") === ""
            && String(a.default_base_url || "") === "")
           || a.has_key !== true
  }
  property var speechApiOpen: null
  readonly property bool editingSpeechApi: root.speechApiOpen !== null
                                           ? root.speechApiOpen === true
                                           : root.speechApiBlank

  // The endpoint panel starts open while there is nothing in it.
  //
  // It was collapsed behind an Edit button always, which was right for an
  // endpoint already set up — and wrong for one that has never been touched,
  // where a button nobody has a reason to press is indistinguishable from
  // there being no way to do it at all. So: open until it is configured,
  // closed once it is, and whatever the user clicks wins over both.
  property var apiOpen: null
  readonly property bool apiBlank: {
    var a = root.entryNamed("api")
    return a ? (String(a.base_url || "") === "" || a.has_key !== true) : false
  }
  readonly property bool editingApi: root.apiOpen !== null ? root.apiOpen === true
                                                          : root.apiBlank

  // The configured entry behind one of the three kinds, or null when the
  // config has none — an older config may predate them.
  function entryNamed(key) {
    var l = payload.llm || []
    for (var i = 0; i < l.length; i++)
      if (String(l[i].name) === String(key)) return l[i]
    return null
  }

  // "127.0.0.1:43593" reads better in a strip than the whole URL.
  function hostport(url) {
    var u = String(url || "")
    if (u === "") return ""
    return u.replace(/^[a-z]+:\/\//, "")
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 0

      // ================= SPEECH =================
      Flickable {
        Layout.fillHeight: true
        // Even halves. 58/42 made sense while each side had its own row and
        // card code sized to its own content; sharing both components makes
        // an uneven split the last thing left that does not match.
        Layout.preferredWidth: Math.round(root.width * 0.5)
        clip: true
        contentHeight: speech.implicitHeight + root.pad * 2

        ColumnLayout {
          id: speech
          x: root.pad
          y: root.pad
          width: parent.width - root.pad * 2
          spacing: Style.space(9)

          RowLayout {
            spacing: Style.space(9)
            Text {
              text: root.t("models.speech")
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.letterSpacing: 2
              color: Color.foreground
            }
            Text {
              text: root.t("models.speechsub")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }

          // -- what is loaded right now --
          //
          // The whole page below this is the config: which engine is selected,
          // which weights are on disk. None of it answers "and what is running",
          // which is the question you have while dictation is behaving oddly.
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Text {
              text: root.t("models.now")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Color.muted
            }
            Text {
              visible: !root.daemonUp
              Layout.fillWidth: true
              text: root.t("models.nodaemon")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.urgent
            }
            Text {
              visible: root.daemonUp
              text: root.speechLive
                    ? (root.speechNow.engine + "  " + root.speechNow.model
                       + "  [" + root.speechNow.device + "]")
                    : root.t("models.notloaded")
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: root.speechLive ? Color.foreground : Color.urgent
            }
            Text {
              visible: root.daemonUp && root.speechLive && root.speechNow.url
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: root.hostport(root.speechNow.url)
                    + (root.speechNow.pid ? "  pid " + root.speechNow.pid : "")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.muted, 1.1)
            }
            Item { Layout.fillWidth: true }
          }

          // -- engines, single choice --
          Repeater {
            model: [
              { id: "local-whispercpp", name: root.t("models.e.vulkan"),
                detail: root.t("models.e.vulkan.sub"),
                note: root.t("models.e.vulkan.note") },
              { id: "local-whisper", name: root.t("models.e.cuda"),
                detail: root.t("models.e.cuda.sub"),
                note: root.t("models.e.cuda.note") },
              { id: "api", name: root.t("models.e.api"),
                detail: root.t("models.e.api.sub"),
                note: root.t("models.e.api.note") }
            ]
            ConfigCard {
              readonly property var eng: modelData
              readonly property bool up: root.daemonUp && root.speechLive
                                         && String(root.speechNow.backend || "") === eng.id
              selectable: true
              selected: root.payload.backend === eng.id
              running: up
              name: eng.name
              // The weights, not the engine: the detail line below already
              // opens with "whisper.cpp", and naming it here put it twice in
              // one card. The LLM cards had the same duplication with
              // llama.cpp, and both follow one rule now — the model when
              // there is one, the engine only when there is not.
              secondary: up ? String(root.speechNow.model || root.speechNow.engine || "")
                            : ""
              detail: eng.detail
              // Selected and not up is a fault here, unlike an LLM server,
              // which is cold until a take reaches it.
              status: up ? root.t("models.running")
                      : (root.payload.backend === eng.id && root.daemonUp
                         ? root.t("models.notloaded") : "")
              statusColor: up ? Color.accent : Color.urgent
              note: eng.note
              noteColor: eng.id === "api" ? Color.urgent : Color.muted
              onChosen: root.command("omavoi config set speech.backend " + eng.id)
            }
          }

          // -- the daemon has not caught up --
          Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(4)
            visible: root.stale
            implicitHeight: staleRow.implicitHeight + Style.space(16)
            color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.09)
            border.width: 1
            border.color: Color.urgent
            radius: Style.cornerRadius
            RowLayout {
              id: staleRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(11)
              spacing: Style.space(10)
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                  text: root.t("models.stale")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Color.foreground
                }
                Text {
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  text: root.t("models.loaded") + root.speechNow.model + "   ·   "
                      + root.t("models.configured") + root.payload.active
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                }
              }
              Button {
                text: root.t("models.restart")
                onClicked: root.command("systemctl --user restart omavoid")
              }
            }
          }

          // ---- the remote endpoint, when speech is the one going out ------
          RowLayout {
            Layout.topMargin: Style.space(6)
            Layout.fillWidth: true
            spacing: Style.space(9)
            Text {
              text: root.t("models.speechapi")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Color.muted
            }
            Text {
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: root.t("models.speechapi.sub")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.muted, 1.15)
            }
            OmChip {
              label: root.editingSpeechApi ? root.t("models.f.close")
                                           : root.t("models.f.edit")
              on: root.editingSpeechApi
              onClicked: root.speechApiOpen = !root.editingSpeechApi
            }
          }

          EndpointFields {
            Layout.fillWidth: true
            Layout.leftMargin: Style.space(22)
            visible: root.editingSpeechApi && root.speechApi.provider !== undefined
            strings: root.strings
            prefix: "speech.api"
            // Its own name, so a speech key and an LLM key can differ.
            secretName: "speech-api"
            checkArgv: ["omavoi", "speech", "check", "--json"]
            baseUrl: String(root.speechApi.base_url || "")
            model: String(root.speechApi.model || "")
            hasKey: root.speechApi.has_key === true
            // The preset's values as placeholders: what applies when the field is
            // left empty, rather than something that happens invisibly.
            defaultBaseUrl: String(root.speechApi.default_base_url || "")
            defaultModel: String(root.speechApi.default_model || "")
            providers: root.speechApi.providers || []
            provider: String(root.speechApi.provider || "")
            onCommand: function (c) { root.command(c) }
          }

          // -- models --
          RowLayout {
            Layout.topMargin: Style.space(8)
            Layout.fillWidth: true
            Text {
              text: root.t("models.list") + (root.ggml ? "ggml" : "ct2")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Color.muted
            }
            Item { Layout.fillWidth: true }
            // The table below is the local engine's weights. With the remote
            // engine selected it is still true and no longer relevant, and
            // saying so is cheaper than a user wondering why "use" changed
            // nothing they could hear.
            Text {
              visible: root.payload.backend === "api"
              Layout.maximumWidth: Style.space(300)
              wrapMode: Text.Wrap
              text: root.t("models.speechapi.cat")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: "#e0af68"
            }
            Text {
              visible: root.payload.backend !== "api"
              text: root.t("models.formathint")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }

          Repeater {
            model: root.speechModels
            ModelRow {
              m: modelData
              strings: root.strings
              pulling: root.pulling
              useCommand: "omavoi model use " + modelData.key
              onCommand: function (c) { root.command(c) }
            }
          }

          Text {
            Layout.topMargin: Style.space(6)
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.tf("models.outside", root.payload.root || root.t("models.ourstore"))
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Qt.darker(Color.muted, 1.1)
          }
        }
      }

      Rectangle {
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
      }

      // ================= LLM =================
      Flickable {
        Layout.fillHeight: true
        Layout.fillWidth: true
        clip: true
        contentHeight: llm.implicitHeight + root.pad * 2

        ColumnLayout {
          id: llm
          x: root.pad
          y: root.pad
          width: parent.width - root.pad * 2
          spacing: Style.space(9)

          RowLayout {
            spacing: Style.space(9)
            Text {
              text: root.t("models.llm")
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.letterSpacing: 2
              color: Color.foreground
            }
            Text {
              text: root.t("models.llmsub")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }

          // The speech column has had this line all along and this one had
          // nothing, which was most of why the two halves did not look alike.
          // Not urgent when it is empty, unlike speech: an LLM server is cold
          // until a take reaches it, and that is the resting state rather
          // than a fault.
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Text {
              text: root.t("models.now")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Color.muted
            }
            Text {
              visible: !root.daemonUp
              Layout.fillWidth: true
              text: root.t("models.nodaemon")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.urgent
            }
            Text {
              visible: root.daemonUp && root.llmResident.length === 0
              Layout.fillWidth: true
              text: root.t("models.llmnone")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.muted, 1.1)
            }
            Repeater {
              model: root.daemonUp ? root.llmResident : []
              RowLayout {
                readonly property var l: modelData
                spacing: Style.space(8)
                Text {
                  text: l.engine + (l.model ? "  " + String(l.model).replace("llm:", "") : "")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Color.foreground
                }
                Text {
                  text: root.hostport(l.url) + "  pid " + l.pid
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.muted, 1.1)
                }
              }
            }
            Item { Layout.fillWidth: true }
          }

          // Three kinds, one row each, in the same shape as the speech engines
        // above — an LLM step is one of these, and nothing else. It was an
        // open-ended list of named entries, which put an implementation detail
        // on screen as a configuration surface and read as a mess with four of
        // them. Which weights the local one runs is a per-step choice now, so
        // one row still serves modes that want different models.
        Repeater {
          model: [
            { key: "agent", name: root.t("models.k.agent"),
              detail: root.t("models.k.agent.sub") },
            { key: "local", name: root.t("models.k.local"),
              detail: root.t("models.k.local.sub") },
            { key: "api", name: root.t("models.k.api"),
              detail: root.t("models.k.api.sub") }
          ]
          ConfigCard {
            readonly property var kind: modelData
            readonly property var l: root.entryNamed(kind.key)
            readonly property bool inUse: l && (l.used_by || []).length > 0
            selectable: false
            selected: inUse
            running: !!(l && l.live_running === true)
            name: kind.name
            // What it is actually set to: the weights, or the agent's own
            // name when it has no model of ours. Not both — the detail line
            // below already names llama.cpp.
            secondary: l ? (l.model ? String(l.model).replace("llm:", "")
                                    : String(l.live_engine || l.backend || ""))
                         : ""
            detail: kind.detail
            status: !l ? root.t("models.k.unset")
                    : l.live_problem ? root.t("models.nokey")
                    : l.live_running === true ? root.t("models.running")
                    : (l.remote ? root.t("models.ready") : root.t("models.coldshort"))
            statusColor: !l ? Qt.darker(Color.muted, 1.2)
                         : l.live_problem ? Color.urgent
                         : l.live_running === true ? Color.accent
                         : Qt.darker(Color.muted, 1.1)
            note: (l && (l.used_by || []).length) ? (l.used_by || []).join(", ") : "—"
            noteColor: inUse ? Color.accent : Qt.darker(Color.muted, 1.2)
            actionLabel: kind.key === "api"
                         ? (root.editingApi ? root.t("models.f.close")
                                            : root.t("models.f.edit"))
                         : ""
            actionOn: root.editingApi
            onAction: root.apiOpen = !root.editingApi
          }
        }

        // ---- the three things a remote endpoint needs -----------------------
        EndpointFields {
          Layout.fillWidth: true
          Layout.leftMargin: Style.space(22)
          visible: root.editingApi && root.entryNamed("api") !== null
          strings: root.strings
          prefix: "llm.api"
          secretName: "openai"
          checkArgv: ["omavoi", "llm", "check", "api", "--json"]
          baseUrl: {
            var e = root.entryNamed("api"); return e ? String(e.base_url || "") : ""
          }
          model: {
            var e = root.entryNamed("api"); return e ? String(e.model || "") : ""
          }
          hasKey: {
            var e = root.entryNamed("api"); return !!(e && e.has_key)
          }
          defaultBaseUrl: "https://api.openai.com/v1"
          defaultModel: "gpt-4o-mini"
          // No presets on this side, so the provider row stays away.
          providers: []
          onCommand: function (c) { root.command(c) }
        }

          // -- the LLM catalogue --
          //
          // These live under LLM, not in the speech table above, because they
          // are the other family's weights — same gguf container, different
          // job. Use points the local configuration at them, which is the
          // global switch; a mode's step can still pin different weights for
          // itself in the Modes tab.
          RowLayout {
            Layout.topMargin: Style.space(10)
            Layout.fillWidth: true
            Text {
              text: root.t("models.list") + "gguf"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Color.muted
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.t("models.llmcathint")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }

          Repeater {
            model: root.llmModels
            ModelRow {
              m: modelData
              strings: root.strings
              pulling: root.pulling
              // The one real difference: LLM weights are chosen by pointing
              // the local configuration at them.
              useCommand: "omavoi config set llm." + (root.localLlms.length ? root.localLlms[0].name : "local") + ".model " + modelData.key
              onCommand: function (c) { root.command(c) }
            }
          }

        // The one thing worth shouting about: a remote entry with no key
          // cannot work, and nothing else on the row says why.
          Repeater {
            model: (root.payload.llm || []).filter(function (l) { return !!l.live_problem })
            Text {
              Layout.fillWidth: true
              wrapMode: Text.Wrap
              text: modelData.name + ": " + modelData.live_problem
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.urgent
            }
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.t("models.endpointnote")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Qt.darker(Color.muted, 1.1)
          }

      }
    }
  }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Qt.rgba(Color.foreground.r, Color.foreground.g,
                     Color.foreground.b, 0.18)
    }

    // ---- the machine's memory, under both families -------------------
    //
    // It sat inside the LLM column, which said it belonged to the LLM. It
    // is a fact about the card, and both families draw on it — the bar has
    // a segment for each.
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: footerCol.implicitHeight + Style.space(26)
      color: Qt.darker(Color.popups.background, 1.06)
      visible: (root.payload.vram || {}).total_mb !== undefined

      ColumnLayout {
        id: footerCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.topMargin: Style.space(13)
        Layout.fillWidth: true
        spacing: Style.space(5)

        Text {
          text: root.t(root.unifiedMem ? "models.shared" : "models.vram")
                + ((root.payload.vram || {}).name || "")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
          color: Color.muted
        }
        Rectangle {
          id: vramTrack
          Layout.fillWidth: true
          implicitHeight: Style.space(14)
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)

          readonly property int totalMb: ((root.payload.vram || {}).total_mb || 0)

          // Stacked left to right in the order the segments arrive, so the
          // two families keep the same place every time you look.
          Row {
            anchors.fill: parent
            spacing: 0
            Repeater {
              model: root.vramSegments
              Rectangle {
                readonly property var seg: modelData
                visible: seg.used_mb > 0
                width: vramTrack.totalMb > 0
                       ? vramTrack.width * Math.max(0, Math.min(1,
                           seg.used_mb / vramTrack.totalMb))
                       : 0
                height: vramTrack.height
                color: root.segColor(seg.kind)
                opacity: seg.kind === "other" ? 1.0 : 0.8
              }
            }
          }

          // Fallback for a daemon too old to send segments: the single fill
          // this replaced, rather than an empty track.
          Rectangle {
            visible: root.vramSegments.length === 0
            width: vramTrack.totalMb > 0
                   ? vramTrack.width * Math.max(0, Math.min(1,
                       ((root.payload.vram || {}).used_mb || 0) / vramTrack.totalMb))
                   : 0
            height: parent.height
            color: Color.accent
            opacity: 0.65
          }
        }

        // -- legend --
        //
        // A two-colour bar with no key is a puzzle, and which colour is
        // which is exactly the thing being asked.
        Flow {
          Layout.fillWidth: true
          spacing: Style.space(14)
          visible: root.vramSegments.length > 0
          Repeater {
            model: root.vramSegments
            Row {
              readonly property var seg: modelData
              visible: seg.used_mb > 0
              spacing: Style.space(5)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(9); height: Style.space(9)
                radius: Style.space(2)
                color: root.segColor(seg.kind)
                opacity: seg.kind === "other" ? 1.0 : 0.8
              }
              Text {
                text: root.segLabel(seg.kind) + "  "
                      + (seg.used_mb / 1024).toFixed(1) + " GB"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.foreground
              }
              Text {
                text: seg.label
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Qt.darker(Color.muted, 1.1)
              }
            }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          Text {
            text: root.t("models.vramsub")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
          }
          Item { Layout.fillWidth: true }
          Text {
            text: (((root.payload.vram || {}).used_mb || 0) / 1024).toFixed(1) + " / "
                  + (((root.payload.vram || {}).total_mb || 0) / 1024).toFixed(1) + " GB"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.foreground
          }
        }
        Text {
          Layout.fillWidth: true
          wrapMode: Text.Wrap
          text: root.t(root.unifiedMem ? "models.sharednote" : "models.vramnote")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Qt.darker(Color.muted, 1.1)
        }
      }
    }
  }
}

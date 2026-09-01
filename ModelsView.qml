import QtQuick
import QtQuick.Layouts
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
  // What the daemon has actually loaded. The config only says what was asked
  // for, and the two differ from the moment of an edit until a restart.
  readonly property var engines: payload.engines || ({})
  readonly property var speechNow: engines.speech || ({})
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

  // "127.0.0.1:43593" reads better in a strip than the whole URL.
  function hostport(url) {
    var u = String(url || "")
    if (u === "") return ""
    return u.replace(/^[a-z]+:\/\//, "")
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0

    // ================= SPEECH =================
    Flickable {
      Layout.fillHeight: true
      Layout.preferredWidth: Math.round(root.width * 0.58)
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
          Rectangle {
            readonly property var eng: modelData
            readonly property bool on: root.payload.backend === eng.id
            Layout.fillWidth: true
            implicitHeight: engRow.implicitHeight + Style.space(16)
            color: on ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.08) : "transparent"
            border.width: 1
            border.color: on ? Color.accent
                             : Qt.rgba(Color.foreground.r, Color.foreground.g,
                                       Color.foreground.b, 0.2)
            radius: Style.cornerRadius

            RowLayout {
              id: engRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(11)
              anchors.rightMargin: Style.space(11)
              spacing: Style.space(10)

              Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: Style.space(9); height: width
                radius: width / 2
                color: on ? Color.accent : "transparent"
                border.width: 1
                border.color: on ? Color.accent : Color.muted
              }
              Text {
                // The dot to the left is the selection; this says whether the
                // selection is what is actually up.
                visible: root.daemonUp && root.speechLive
                         && String(root.speechNow.backend || "") === eng.id
                text: "▶"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.accent
              }
              Text {
                Layout.preferredWidth: Style.space(112)
                text: eng.name
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Color.foreground
              }
              Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: eng.detail
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.muted
              }
              Text {
                text: eng.note
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: eng.id === "api" ? Color.urgent : Color.muted
              }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (!on) root.command("omavoi config set speech.backend " + eng.id)
            }
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
          Text {
            text: root.t("models.formathint")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
          }
        }

        Repeater {
          model: root.speechModels
          RowLayout {
            readonly property var m: modelData
            Layout.fillWidth: true
            spacing: Style.space(10)

            Text {
              Layout.preferredWidth: Style.space(12)
              // ▶ is loaded right now, ● is selected but not loaded, ○ is
              // merely on disk. The first two coincide most of the time; when
              // they do not, that is the thing worth seeing.
              text: m.running ? "▶" : (m.active ? "●" : (m.downloaded ? "○" : ""))
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: m.running ? Color.accent
                               : (m.active ? Color.urgent : Color.muted)
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
            Text {
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: m.note
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: m.tags.indexOf("recommended") >= 0 ? Color.foreground : Color.muted
            }
            RowLayout {
              Layout.preferredWidth: Style.space(180)
              spacing: Style.space(7)
              Item { Layout.fillWidth: true }
              Text {
                visible: m.running === true
                text: root.t("models.running")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.accent
              }
              Text {
                visible: m.downloaded && !m.ours && m.running !== true
                text: root.t("models.ondisk")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.muted
              }
              Text {
                visible: !m.downloaded && root.pulling[m.key] === true
                text: root.t("models.downloading")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.accent
              }
              Button {
                visible: !m.downloaded && root.pulling[m.key] !== true
                text: root.t("models.download")
                onClicked: root.command("omavoi model pull " + m.key)
              }
              Button {
                visible: m.downloaded && !m.active
                text: root.t("models.use")
                onClicked: root.command("omavoi model use " + m.key)
              }
              Button {
                visible: m.downloaded && m.ours && !m.active
                text: root.t("models.remove")
                onClicked: root.command("omavoi model rm " + m.key)
              }
            }
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

        Repeater {
          model: root.payload.llm || []
          Rectangle {
            readonly property var l: modelData
            readonly property bool inUse: (l.used_by || []).length > 0
            Layout.fillWidth: true
            implicitHeight: llmBody.implicitHeight + Style.space(18)
            color: inUse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.06)
                         : "transparent"
            border.width: 1
            border.color: inUse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.7)
                                : Qt.rgba(Color.foreground.r, Color.foreground.g,
                                          Color.foreground.b, 0.2)
            radius: Style.cornerRadius

            ColumnLayout {
              id: llmBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(11)
              spacing: Style.space(4)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)
                Text {
                  visible: root.daemonUp && l.live_running === true && !l.remote
                  text: "▶"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.accent
                }
                Text {
                  text: l.name
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Color.foreground
                }
                Text {
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  text: l.model
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                }
                // Whether using it sends your words off the machine is the
                // one fact worth a badge.
                Text {
                  text: l.remote ? root.t("models.remote") : root.t("models.local")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: l.remote ? Color.urgent : Color.accent
                }
                // Cold is the resting state for a managed server — it starts
                // on the first take that names it — so this is not a warning.
                Text {
                  visible: root.daemonUp
                  text: l.live_running
                        ? (l.remote ? root.t("models.ready") : root.t("models.running"))
                        : (l.remote ? "" : root.t("models.cold"))
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: l.live_running ? Color.accent : Qt.darker(Color.muted, 1.1)
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)
                Text {
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  text: {
                    var bits = [l.backend]
                    if (l.base_url) bits.push(l.base_url)
                    if (l.key_env) bits.push(l.key_env + " " + l.key)
                    return bits.join("  ·  ")
                  }
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                }
                Text {
                  visible: l.live_running === true && l.live_url && !l.remote
                  text: root.hostport(l.live_url)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.muted, 1.1)
                }
                Text {
                  visible: l.key_env && !l.has_key
                  text: root.t("models.nokey")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.urgent
                }
              }

              Text {
                Layout.fillWidth: true
                text: (l.used_by || []).length
                      ? root.t("models.usedby") + (l.used_by || []).join(", ")
                      : root.t("models.unused")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: (l.used_by || []).length ? Color.accent : Qt.darker(Color.muted, 1.1)
              }
            }
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

        // -- the LLM catalogue --
        //
        // These live under LLM, not in the speech table above: they are both
        // gguf, but "use this one" means a mode's step names it, never a
        // global switch, so there is deliberately no Use button here.
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
          RowLayout {
            readonly property var m: modelData
            Layout.fillWidth: true
            spacing: Style.space(10)

            Text {
              Layout.preferredWidth: Style.space(12)
              text: m.running ? "▶" : (m.downloaded ? "○" : "")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: m.running ? Color.accent : Color.muted
            }
            Text {
              Layout.preferredWidth: Style.space(150)
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
            // Won't-fit is worth saying before the download, not after — and
            // never about the model that is loaded right now, whose own
            // weights are most of what the free-VRAM figure is missing.
            Text {
              visible: m.fits === false && m.running !== true
              text: root.t("models.needs") + " "
                    + (m.needed_mb / 1024).toFixed(1) + "G"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.urgent
            }
            Text {
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: m.note
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
            RowLayout {
              Layout.preferredWidth: Style.space(130)
              spacing: Style.space(7)
              Item { Layout.fillWidth: true }
              Text {
                visible: m.running === true
                text: root.t("models.running")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.accent
              }
              Text {
                visible: !m.downloaded && root.pulling[m.key] === true
                text: root.t("models.downloading")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.accent
              }
              Button {
                visible: !m.downloaded && root.pulling[m.key] !== true
                text: root.t("models.download")
                onClicked: root.command("omavoi model pull " + m.key)
              }
              Button {
                visible: m.downloaded && m.ours && m.running !== true
                text: root.t("models.remove")
                onClicked: root.command("omavoi model rm " + m.key)
              }
            }
          }
        }

        // -- VRAM --
        ColumnLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(12)
          visible: (root.payload.vram || {}).total_mb !== undefined
          spacing: Style.space(5)

          Text {
            text: root.t("models.vram") + ((root.payload.vram || {}).name || "")
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
            text: root.t("models.vramnote")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Qt.darker(Color.muted, 1.1)
          }
        }
      }
    }
  }
}

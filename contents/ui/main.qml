import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    readonly property string version: "1.1.0"

    preferredRepresentation: fullRepresentation

    // -- Bundled script paths
    readonly property string codeDir: Qt.resolvedUrl("../code/").toString().replace("file://", "")
    readonly property string sinkScript:  "/bin/sh " + codeDir + "audiohud-sink.sh"
    readonly property string codecScript: "/bin/sh " + codeDir + "audiohud-codec.sh"

    // -- State
    property string dacName:    "—"
    property string codecName:  "—"
    property string sampleRate: "—"
    property string bitDepth:   "—"
    property bool   isMuted:    false
    property int    volume:     0
    property var    streams:    []
    property bool   bitPerfect: false
    property bool   pipewireOk: true   // false when data goes stale

    // -- Stale data watchdog
    property int staleTicks: 0
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            root.staleTicks++
            if (root.staleTicks > 3) root.pipewireOk = false
        }
    }

    // -- Data sources

    Plasma5Support.DataSource {
        id: sinkSource
        engine: "executable"
        connectedSources: [root.sinkScript]
        interval: 3000
        onNewData: function(source, data) {
            var out = data["stdout"] || ""
            if (out.trim() !== "") {
                root.staleTicks = 0
                root.pipewireOk = true
                parseSinkData(out)
            }
        }
    }

    Plasma5Support.DataSource {
        id: streamsSource
        engine: "executable"
        connectedSources: ["pactl list sink-inputs"]
        interval: 2000
        onNewData: function(source, data) {
            parseStreams(data["stdout"] || "")
            checkBitPerfect()
        }
    }

    Plasma5Support.DataSource {
        id: codecSource
        engine: "executable"
        connectedSources: [root.codecScript]
        interval: 60000
        onNewData: function(source, data) {
            var line = (data["stdout"] || "").trim()
            if (line.startsWith("Codec:"))
                root.codecName = line.replace("Codec:", "").trim()
        }
    }

    // -- Parsers

    function parseSinkData(raw) {
        if (!raw) return

        // Prefer node.nick (e.g. "Headphones", "Speaker") over hardware desc
        var nickMatch = raw.match(/node\.nick\s*=\s*"([^"]+)"/)
        var descMatch = raw.match(/Description:\s*(.+)/)
        if (nickMatch)
            root.dacName = nickMatch[1].trim()
        else if (descMatch)
            root.dacName = cleanDeviceName(descMatch[1])

        var specMatch = raw.match(/Sample Specification:\s*(\S+)\s+\S+\s+(\d+)Hz/)
        if (specMatch) {
            var bdMatch = specMatch[1].toLowerCase().match(/\d+/)
            root.bitDepth   = bdMatch ? bdMatch[0] : "?"
            root.sampleRate = specMatch[2]
        }

        var muteMatch = raw.match(/Mute:\s*(\S+)/)
        if (muteMatch) root.isMuted = (muteMatch[1].trim() === "yes")

        var volMatch = raw.match(/Volume:.*?(\d+)%/)
        if (volMatch) root.volume = parseInt(volMatch[1])

        checkBitPerfect()
    }

    function parseStreams(raw) {
        if (!raw) return
        var result = []
        var blocks = raw.split(/\nSink Input #/)
        for (var i = 0; i < blocks.length; i++) {
            var block = blocks[i]
            var appMatch    = block.match(/application\.name\s*=\s*"([^"]+)"/)
            var formatMatch = block.match(/Sample Specification:\s*(\S+)\s+\S+\s+(\d+)Hz/)
            if (!appMatch) continue
            var fmt = "?", rate = "?", depth = "?"
            if (formatMatch) {
                var bd = formatMatch[1].toLowerCase().match(/\d+/)
                depth = bd ? bd[0] : "?"
                fmt   = depth + "-bit"
                rate  = formatMatch[2]
            }
            result.push({ app: appMatch[1], fmt: fmt, rate: rate, depth: depth })
        }
        root.streams = result.slice(0, 3)
    }

    function checkBitPerfect() {
        if (root.streams.length === 0) { root.bitPerfect = false; return }
        var perfect = true
        for (var i = 0; i < root.streams.length; i++) {
            var s = root.streams[i]
            if (s.rate !== root.sampleRate || s.depth !== root.bitDepth) {
                perfect = false; break
            }
        }
        root.bitPerfect = perfect
    }

    function cleanDeviceName(raw) {
        var s = raw.trim()
        if (s.match(/High Definition Audio Controller/i)) {
            if (s.match(/HDMI/i)) return "Intel HDA (HDMI)"
            return "Intel HDA"
        }
        var slash = s.indexOf(" / ")
        if (slash > 0) s = s.substring(0, slash).trim()
        if (s.length > 32) s = s.substring(0, 30) + "…"
        return s
    }

    function sinkIcon() {
        var n = root.dacName.toLowerCase()
        if (!root.pipewireOk)         return "audio-card"
        if (n.indexOf("headphone") >= 0 || n.indexOf("headset") >= 0)
                                       return "audio-headphones"
        if (n.indexOf("hdmi") >= 0 || n.indexOf("display") >= 0)
                                       return "video-display"
        if (n.indexOf("speaker") >= 0) return "audio-speakers"
        if (n.indexOf("usb") >= 0)     return "audio-card"
        return "audio-headphones"
    }

    // -- UI

    fullRepresentation: Item {
        implicitWidth:  360
        implicitHeight: mainColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

        ColumnLayout {
            id: mainColumn
            anchors { fill: parent; margins: Kirigami.Units.largeSpacing }
            spacing: 0

            // -- Header
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 2
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: root.sinkIcon()
                    implicitWidth:  Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                    opacity: root.pipewireOk ? 1.0 : 0.4
                }
                QQC2.Label {
                    text: "AUDIO HUD"
                    font.bold: true
                    font.family: "monospace"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    color: root.pipewireOk
                        ? Kirigami.Theme.textColor
                        : Kirigami.Theme.disabledTextColor
                    Layout.fillWidth: true
                }

            }

            // -- Status badge
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: badgeLabel.implicitHeight + 8

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: badgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                    height: badgeLabel.implicitHeight + 4
                    radius: 3
                    color: !root.pipewireOk
                        ? Qt.rgba(0.5, 0.5, 0.5, 0.2)
                        : root.streams.length === 0
                            ? Qt.rgba(0.5, 0.5, 0.5, 0.15)
                            : root.bitPerfect
                                ? Qt.rgba(0.1, 0.7, 0.3, 0.25)
                                : Qt.rgba(0.9, 0.2, 0.2, 0.20)
                    border.color: !root.pipewireOk
                        ? Kirigami.Theme.disabledTextColor
                        : root.streams.length === 0
                            ? Kirigami.Theme.disabledTextColor
                            : root.bitPerfect
                                ? Kirigami.Theme.positiveTextColor
                                : Kirigami.Theme.negativeTextColor
                    border.width: 1

                    QQC2.Label {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: !root.pipewireOk
                            ? "⚠ OFFLINE"
                            : root.streams.length === 0
                                ? "IDLE"
                                : root.bitPerfect
                                    ? "✓ BIT-PERFECT"
                                    : "⚠ RESAMPLING"
                        font.family: "monospace"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                        font.bold: true
                        color: !root.pipewireOk
                            ? Kirigami.Theme.disabledTextColor
                            : root.streams.length === 0
                                ? Kirigami.Theme.disabledTextColor
                                : root.bitPerfect
                                    ? Kirigami.Theme.positiveTextColor
                                    : Kirigami.Theme.negativeTextColor
                    }

                    MouseArea {
                        id: badgeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                    QQC2.ToolTip.visible: badgeHover.containsMouse
                    QQC2.ToolTip.delay: 600
                    QQC2.ToolTip.text: !root.pipewireOk
                        ? "PipeWire is not responding."
                        : root.streams.length === 0
                            ? "No audio is currently playing."
                            : root.bitPerfect
                                ? "Stream format matches the PipeWire sink.\nFor true bit-perfect output, also ensure:\n  • Volume is at 100%\n  • No EQ or effects are active\n  • PipeWire is not applying any DSP"
                                : "Stream format doesn't match the sink.\nPipeWire is resampling the audio.\nThis may affect sound quality."
                }
                }

            Kirigami.Separator { Layout.fillWidth: true }

            // -- DAC section
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            QQC2.Label {
                text: "DAC"
                font.bold: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                color: Kirigami.Theme.highlightColor
                font.family: "monospace"
                opacity: root.pipewireOk ? 1.0 : 0.5
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing / 2 }

            InfoRow { label: "Device"; value: root.dacName;    dim: !root.pipewireOk }
            InfoRow { label: "Codec";  value: root.codecName;  dim: false }
            InfoRow { label: "Rate";   value: root.sampleRate !== "—" ? root.sampleRate + " Hz" : "—"; dim: !root.pipewireOk }
            InfoRow { label: "Depth";  value: root.bitDepth   !== "—" ? root.bitDepth + "-bit"  : "—"; dim: !root.pipewireOk }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
            Kirigami.Separator { Layout.fillWidth: true }

            // -- Streams section
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            QQC2.Label {
                text: "STREAMS"
                font.bold: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                color: Kirigami.Theme.highlightColor
                font.family: "monospace"
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing / 2 }

            Repeater {
                model: root.streams.length > 0
                    ? root.streams
                    : [{ app: "No active streams", fmt: "", rate: "", depth: "" }]
                delegate: RowLayout {
                    Layout.fillWidth: true
                    property bool mismatch: modelData.fmt !== "" &&
                        (modelData.rate !== root.sampleRate ||
                         modelData.depth !== root.bitDepth)
                    QQC2.Label {
                        text: modelData.app
                        font.family: "monospace"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: parent.mismatch
                            ? Kirigami.Theme.negativeTextColor
                            : Kirigami.Theme.textColor
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        visible: modelData.fmt !== ""
                        text: modelData.fmt !== ""
                            ? "[" + modelData.fmt + " / " + modelData.rate + " Hz]" : ""
                        font.family: "monospace"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: parent.mismatch
                            ? Kirigami.Theme.negativeTextColor
                            : Kirigami.Theme.disabledTextColor
                    }
                }
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
            Kirigami.Separator { Layout.fillWidth: true }

            // -- Volume section
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            QQC2.Label {
                text: "LEVEL"
                font.bold: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                color: Kirigami.Theme.highlightColor
                font.family: "monospace"
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing / 2 }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: root.isMuted
                        ? "audio-volume-muted"
                        : root.volume > 66
                            ? "audio-volume-high"
                            : root.volume > 33
                                ? "audio-volume-medium"
                                : "audio-volume-low"
                    implicitWidth:  Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                    opacity: root.isMuted ? 0.4 : 1.0
                }
                QQC2.ProgressBar {
                    Layout.fillWidth: true
                    from: 0; to: 100
                    value: root.isMuted ? 0 : root.volume
                    opacity: root.isMuted ? 0.3 : 1.0
                }
                QQC2.Label {
                    text: root.isMuted ? "MUTED" : root.volume + "%"
                    font.family: "monospace"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: root.isMuted
                        ? Kirigami.Theme.disabledTextColor
                        : root.volume > 90
                            ? Kirigami.Theme.negativeTextColor
                            : Kirigami.Theme.textColor
                    Layout.minimumWidth: 42
                    horizontalAlignment: Text.AlignRight
                }
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing / 2 }
        }
    }

    // -- Reusable InfoRow
    component InfoRow: RowLayout {
        property string label: ""
        property string value: ""
        property bool   dim:   false
        Layout.fillWidth: true
        QQC2.Label {
            text: label + ":"
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            Layout.minimumWidth: 70
        }
        QQC2.Label {
            text: value
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: (dim === true)
                ? Kirigami.Theme.disabledTextColor
                : Kirigami.Theme.textColor
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }
}

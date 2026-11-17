import QtQuick
import QtQuick.Layouts
import "Singletons"

/**
 * Post-recording review: scrub the unpacked frames, set the in and out points,
 * optionally thin the frame rate, then copy or save. The panel owns the edit
 * state (in, out, step, playhead) and hands it to the shell with each export
 * request, so the shell only has to know about files and processes.
 */
Item {
    id: panel

    property string frameDir: ""
    property int frameCount: 1
    property int baseFps: 20
    /** Non-empty while an export runs; the buttons go quiet. */
    property string busy: ""

    signal copyGif(int first, int last, int step, int fps)
    signal copyMp4(int first, int last, int step, int fps)
    signal saveMp4(int first, int last, int step, int fps)
    signal cancel()

    property int first: 1
    property int last: frameCount
    property int step: 1
    property int playhead: 1
    property bool playing: false

    /**
     * Playback speed. Thinning and speed are different knobs: step drops
     * frames and holds the duration, speed keeps every frame and shortens it.
     * Both land in the same place, the output frame rate, which is what the
     * exporter writes into the frame timings.
     */
    readonly property var speeds: [0.5, 1, 1.5, 2, 3]
    property int speedIndex: 1
    readonly property real speed: speeds[speedIndex]

    onFrameCountChanged: {
        first = 1;
        last = frameCount;
        playhead = 1;
    }

    readonly property int fps: Math.max(1, Math.round(baseFps / step * speed))
    readonly property int keptFrames: Math.floor((last - first) / step) + 1
    readonly property real seconds: keptFrames / fps

    function clampPlayhead() {
        if (playhead < first) playhead = first;
        if (playhead > last) playhead = last;
    }

    // Playback walks the kept frames only, at the thinned rate, so what you see
    // is what the gif will be.
    Timer {
        interval: Math.max(16, Math.round(1000 / panel.fps))
        repeat: true
        running: panel.playing && panel.busy === ""
        onTriggered: {
            var next = panel.playhead + panel.step;
            panel.playhead = next > panel.last ? panel.first : next;
        }
    }

    component TextButton: Rectangle {
        id: tb
        property string label: ""
        property bool primary: false
        property bool enabled: true
        signal clicked()

        implicitWidth: tbText.implicitWidth + 22
        implicitHeight: 32
        radius: 7
        opacity: enabled ? 1 : 0.4
        color: primary
            ? (tbMa.containsMouse && enabled ? Qt.lighter(Theme.accent, 1.15) : Theme.accent)
            : (tbMa.containsMouse && enabled ? Theme.hoverStrong : Theme.hover)

        Text {
            id: tbText
            anchors.centerIn: parent
            text: tb.label
            color: tb.primary ? Theme.onAccent : Theme.fg
            font.pixelSize: 13
            font.family: Theme.sansFamily
        }

        MouseArea {
            id: tbMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: tb.enabled
            onClicked: tb.clicked()
        }
    }

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        anchors.fill: parent
        color: Theme.panelBg
        implicitWidth: 560
        implicitHeight: col.implicitHeight + 28

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // Preview. The frame files are numbered from 1, five digits wide,
            // the way rishot-record writes them.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 160
                radius: 8
                color: Theme.dim
                clip: true

                /**
                 * Two buffers, not one. A single Image blanks for as long as
                 * the next PNG takes to decode, which reads as a flicker on
                 * every scrub step and all through playback. Here the incoming
                 * frame decodes in the hidden buffer and the two only swap once
                 * it reports Ready, so something is on screen at all times.
                 */
                Item {
                    id: viewport
                    anchors.fill: parent
                    anchors.margins: 6

                    property int front: 0

                    // Nothing is on disk until a recording has been unpacked,
                    // so an unguarded binding warns on every launch.
                    readonly property string src:
                        panel.frameDir === "" || panel.frameCount < 1 || !panel.visible
                            ? ""
                            : "file://" + panel.frameDir + "/f_"
                                + String(panel.playhead).padStart(5, "0") + ".png"

                    /**
                     * Assigning a source the buffer already holds emits no
                     * status change, so scrubbing back onto the previous frame
                     * would leave the stale buffer in front; swap at once in
                     * that case and only wait on a real load otherwise.
                     */
                    function show(buf, which) {
                        if (String(buf.source) === src && buf.status === Image.Ready) {
                            front = which;
                            return;
                        }
                        buf.source = src;
                    }

                    onSrcChanged: {
                        if (src === "") { bufA.source = ""; bufB.source = ""; return; }
                        if (front === 0) show(bufB, 1);
                        else show(bufA, 0);
                    }

                    Image {
                        id: bufA
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        cache: true
                        opacity: viewport.front === 0 ? 1 : 0
                        onStatusChanged: {
                            if (status === Image.Ready && viewport.front !== 0)
                                viewport.front = 0;
                        }
                    }

                    Image {
                        id: bufB
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        cache: true
                        opacity: viewport.front === 1 ? 1 : 0
                        onStatusChanged: {
                            if (status === Image.Ready && viewport.front !== 1)
                                viewport.front = 1;
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: Theme.idle
                font.pixelSize: 12
                font.family: Theme.monoFamily
                text: I18n.tr("gif.frames", { n: panel.keptFrames })
                    + "  ·  " + panel.fps + " fps"
                    + "  ·  " + panel.seconds.toFixed(1) + "s"
                    + (panel.step > 1 ? "  ·  1/" + panel.step : "")
                    + (panel.speed !== 1 ? "  ·  " + panel.speed + "×" : "")
            }

            // Scrub track: the kept range is highlighted, the two handles set it,
            // and a click anywhere moves the playhead.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 26

                Item {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 7
                    anchors.rightMargin: 7
                    height: 26

                    function xAt(i) {
                        return panel.frameCount <= 1
                            ? 0
                            : (i - 1) / (panel.frameCount - 1) * width;
                    }
                    function idxAt(px) {
                        if (panel.frameCount <= 1) return 1;
                        var t = Math.max(0, Math.min(1, px / Math.max(1, width)));
                        return 1 + Math.round(t * (panel.frameCount - 1));
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.sep
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: track.xAt(panel.first)
                        width: Math.max(2, track.xAt(panel.last) - track.xAt(panel.first))
                        height: 4
                        radius: 2
                        color: Theme.accent
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed: (m) => {
                            panel.playhead = track.idxAt(m.x);
                            panel.clampPlayhead();
                        }
                        onPositionChanged: (m) => {
                            if (!pressed) return;
                            panel.playhead = track.idxAt(m.x);
                            panel.clampPlayhead();
                        }
                    }

                    Rectangle {
                        x: track.xAt(panel.playhead) - 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: 18
                        color: Theme.fg
                    }

                    Repeater {
                        model: [{ which: "first" }, { which: "last" }]

                        Rectangle {
                            required property var modelData
                            readonly property bool isFirst: modelData.which === "first"
                            x: track.xAt(isFirst ? panel.first : panel.last) - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 11
                            height: 22
                            radius: 4
                            color: hMa.containsMouse || hMa.pressed
                                ? Qt.lighter(Theme.accent, 1.2)
                                : Theme.accent
                            border.color: Theme.panelBg
                            border.width: 1

                            MouseArea {
                                id: hMa
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                onPositionChanged: (m) => {
                                    if (!pressed) return;
                                    var i = track.idxAt(mapToItem(track, m.x, m.y).x);
                                    if (parent.isFirst) panel.first = Math.min(i, panel.last);
                                    else panel.last = Math.max(i, panel.first);
                                    panel.playhead = parent.isFirst ? panel.first : panel.last;
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                IconButton {
                    icon: panel.playing ? "pause" : "play"
                    dim: panel.busy !== ""
                    onClicked: panel.playing = !panel.playing
                }

                TextButton {
                    label: I18n.tr("gif.halve")
                    enabled: panel.busy === ""
                    // 1 -> 2 -> 4 -> back. Thinning keeps the duration and drops
                    // frames, which is the cheap way to shrink a gif.
                    onClicked: panel.step = panel.step >= 4 ? 1 : panel.step * 2
                }

                TextButton {
                    label: I18n.tr("gif.speed", { n: panel.speed })
                    enabled: panel.busy === ""
                    onClicked: panel.speedIndex =
                        (panel.speedIndex + 1) % panel.speeds.length
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: panel.busy !== ""
                    text: I18n.tr("gif.exporting")
                    color: Theme.idle
                    font.pixelSize: 12
                    font.family: Theme.sansFamily
                }

                TextButton {
                    label: I18n.tr("gif.copy_mp4")
                    enabled: panel.busy === ""
                    onClicked: panel.copyMp4(panel.first, panel.last, panel.step, panel.fps)
                }

                TextButton {
                    label: I18n.tr("gif.copy_gif")
                    enabled: panel.busy === ""
                    onClicked: panel.copyGif(panel.first, panel.last, panel.step, panel.fps)
                }

                TextButton {
                    label: I18n.tr("gif.save_mp4")
                    primary: true
                    enabled: panel.busy === ""
                    onClicked: panel.saveMp4(panel.first, panel.last, panel.step, panel.fps)
                }

                IconButton {
                    icon: "cancel"
                    dim: panel.busy !== ""
                    onClicked: panel.cancel()
                }
            }
        }
    }
}

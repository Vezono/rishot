import QtQuick
import QtQuick.Layouts
import "Singletons"

/**
 * The gif-mode control bar: arm, then pause/stop with a running clock. It is
 * deliberately small and placed outside the recorded rect by its parent, since
 * wf-recorder captures the compositor's output and anything overlapping the
 * rect would be in the recording.
 */
Item {
    id: bar

    /** armed | recording | paused | processing */
    property string phase: "armed"
    property int elapsedMs: 0

    signal record()
    signal pause()
    signal resume()
    signal stop()
    signal cancel()

    /**
     * Incremental drag delta since the last move, in pixels. The bar never
     * moves itself: shell.qml accumulates these into the bar offset, the same
     * arrangement the annotation toolbar uses, so the window keeps ownership of
     * the final position and the clamping. A double-click of the grip resets it.
     */
    signal dragMoved(real dx, real dy)
    signal dragReset()

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    readonly property string clock: {
        var s = Math.floor(elapsedMs / 1000);
        var m = Math.floor(s / 60);
        return (m < 10 ? "0" : "") + m + ":" + ((s % 60) < 10 ? "0" : "") + (s % 60);
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 10
        color: Theme.panelBg
        border.color: Theme.panelBorder
        border.width: 1
        implicitWidth: row.implicitWidth + 20
        implicitHeight: 48

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8

            // Drag grip. The recorded rect is fixed once armed, so moving the
            // bar is the only way out when it sits over something that matters.
            Item {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 26

                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    rowSpacing: 3
                    columnSpacing: 3
                    Repeater {
                        model: 6
                        Rectangle {
                            width: 2.5
                            height: 2.5
                            radius: 1.25
                            color: gripHover.hovered ? Theme.fg : Theme.idle
                        }
                    }
                }

                HoverHandler {
                    id: gripHover
                    cursorShape: gripDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                }
                DragHandler {
                    id: gripDrag
                    target: null
                    property real lastX: 0
                    property real lastY: 0
                    onActiveChanged: {
                        if (active) {
                            lastX = centroid.scenePosition.x;
                            lastY = centroid.scenePosition.y;
                        }
                    }
                    onCentroidChanged: {
                        if (!active) return;
                        var sx = centroid.scenePosition.x;
                        var sy = centroid.scenePosition.y;
                        bar.dragMoved(sx - lastX, sy - lastY);
                        lastX = sx;
                        lastY = sy;
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onDoubleTapped: bar.dragReset()
                }
            }

            // Armed: one obvious button, with the keyboard hint the overlay honours.
            Rectangle {
                visible: bar.phase === "armed"
                Layout.preferredWidth: armRow.implicitWidth + 20
                Layout.preferredHeight: 34
                radius: 7
                color: armMa.containsMouse ? Theme.accent : Theme.hoverStrong

                RowLayout {
                    id: armRow
                    anchors.centerIn: parent
                    spacing: 7

                    Icon {
                        name: "record"
                        size: 15
                        tint: armMa.containsMouse ? Theme.onAccent : Theme.accent
                    }

                    Text {
                        text: I18n.tr("gif.record")
                        color: armMa.containsMouse ? Theme.onAccent : Theme.fg
                        font.pixelSize: 13
                        font.family: Theme.sansFamily
                    }
                }

                MouseArea {
                    id: armMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: bar.record()
                }
            }

            // Recording and paused share the clock; the dot only pulses while
            // frames are actually being written.
            Rectangle {
                visible: bar.phase === "recording" || bar.phase === "paused"
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                radius: 5
                color: Theme.accent
                opacity: bar.phase === "recording" ? 1 : 0.35

                SequentialAnimation on opacity {
                    running: bar.phase === "recording"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutQuad }
                }
            }

            Text {
                visible: bar.phase === "recording" || bar.phase === "paused"
                text: bar.clock
                color: Theme.fg
                font.pixelSize: 15
                font.family: Theme.monoFamily
            }

            IconButton {
                visible: bar.phase === "recording"
                icon: "pause"
                onClicked: bar.pause()
            }

            IconButton {
                visible: bar.phase === "paused"
                icon: "play"
                onClicked: bar.resume()
            }

            IconButton {
                visible: bar.phase === "recording" || bar.phase === "paused"
                icon: "stop"
                onClicked: bar.stop()
            }

            Text {
                visible: bar.phase === "processing"
                text: I18n.tr("gif.processing")
                color: Theme.idle
                font.pixelSize: 13
                font.family: Theme.sansFamily
            }

            IconButton {
                visible: bar.phase === "armed"
                icon: "cancel"
                onClicked: bar.cancel()
            }
        }
    }
}

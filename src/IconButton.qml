import QtQuick
import "Singletons"

Rectangle {
    id: btn
    property string icon: ""
    property bool active: false
    property bool dim: false

    signal clicked()

    width: 32
    height: 32
    radius: 7
    color: active ? Theme.accent : (ma.containsMouse && !dim ? Theme.hover : "transparent")

    readonly property color idle: Theme.idle

    Icon {
        anchors.centerIn: parent
        name: btn.icon
        size: 18
        tint: btn.active ? Theme.onAccent : (btn.dim ? Theme.dimIcon : btn.idle)
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: !btn.dim
        onClicked: btn.clicked()
    }
}

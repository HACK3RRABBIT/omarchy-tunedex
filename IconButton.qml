import QtQuick
import "Model.js" as Model

// Small round hit-target around one Icon — shuffle/repeat/sign-out/clear
// buttons in the Tunedex panel. `active` paints the accent-tinted "on" state
// (shuffle/repeat toggles); plain buttons just hover/press.
Item {
  id: root
  property string icon: "music"
  property real size: 26
  property bool active: false
  property color iconColor: active ? Model.COLOR.accent : Model.COLOR.muted
  property string tooltip: ""

  signal activated()

  width: size
  height: size

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: active ? Qt.rgba(0.176, 0.831, 0.749, 0.16) : (hoverArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
  }

  Icon {
    anchors.centerIn: parent
    name: root.icon
    color: root.iconColor
    width: root.size * 0.55
    height: root.size * 0.55
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}

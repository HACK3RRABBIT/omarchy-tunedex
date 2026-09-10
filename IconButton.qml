import QtQuick
import qs.Commons

// Small round hit-target around one Icon — shuffle/repeat/sign-out/clear
// buttons in the Tunedex panel. Colors come from the shell's own theme
// tokens (Style/Color), same as every first-party bar-widget popup, so the
// plugin re-themes with the rest of Omarchy instead of carrying its own
// fixed palette. `active` paints the shared accent-tinted "on" state
// (shuffle/repeat toggles); plain buttons just hover/press.
Item {
  id: root
  property string icon: "music"
  property real size: 26
  property bool active: false
  property color iconColor: active ? Color.accent : Qt.darker(Color.foreground, 1.5)
  property string tooltip: ""

  signal activated()

  width: size
  height: size

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: active ? Style.selectedFillFor(Color.foreground, Color.accent)
      : (hoverArea.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
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

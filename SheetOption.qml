import QtQuick
import qs.Commons

// One row in a bottom sheet — icon + label, tappable. Mirrors the site's
// own `opt()` helper in ui/sheets.js. `active` paints the "current choice"
// state (e.g. the selected notification level).
Item {
  id: root
  property string icon: "music"
  property string label: ""
  property bool active: false

  signal activated()

  width: parent ? parent.width : implicitWidth
  implicitHeight: Style.space(38)
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.active ? Style.selectedFillFor(Color.foreground, Color.accent)
      : (hoverArea.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    Icon {
      name: root.icon
      color: root.active ? Color.accent : Qt.darker(Color.foreground, 1.3)
      width: Style.space(16); height: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      text: root.label
      color: root.active ? Color.accent : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}

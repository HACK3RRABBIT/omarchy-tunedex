import QtQuick
import qs.Commons
import "Model.js" as Model

// One row in the library/search list. Click plays it (and queues the rest
// of the currently-visible list from that point). Highlighted + an
// animated level-meter glyph when it's the track currently loaded.
Item {
  id: root
  property var track: null
  property bool active: false
  property bool playing: false
  property string coverSrc: ""

  signal activated()

  height: Style.space(52)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.active ? Qt.rgba(0.176, 0.831, 0.749, 0.10) : (hoverArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
  }

  Row {
    anchors.left: parent.left
    anchors.right: durationLabel.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    Rectangle {
      width: Style.space(38); height: Style.space(38)
      radius: Style.space(5)
      color: Model.COLOR.surface
      clip: true
      anchors.verticalCenter: parent.verticalCenter

      Image {
        anchors.fill: parent
        visible: root.coverSrc !== "" && status === Image.Ready
        source: root.coverSrc
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }
      Icon {
        visible: root.coverSrc === ""
        anchors.centerIn: parent
        name: "music"
        color: Model.COLOR.muted
        width: Style.space(16); height: Style.space(16)
      }
    }

    Column {
      width: parent.width - Style.space(48)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(6)

        Icon {
          visible: root.active
          name: "music"
          color: Model.COLOR.accent
          width: Style.space(12); height: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter

          SequentialAnimation on opacity {
            running: root.playing
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 500 }
            NumberAnimation { to: 1.0; duration: 500 }
          }
        }

        Text {
          text: root.track ? Model.trackTitle(root.track) : ""
          color: root.active ? Model.COLOR.accent : Model.COLOR.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width - (root.active ? Style.space(18) : 0)
        }
      }

      Text {
        text: root.track ? Model.trackArtist(root.track) : ""
        visible: text !== ""
        color: Model.COLOR.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }

  Text {
    id: durationLabel
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.track ? Model.formatDuration(root.track.duration) : ""
    color: Model.COLOR.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}

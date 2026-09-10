import QtQuick
import qs.Commons
import "Model.js" as Model

// One row in the library/search list. Click plays it (and queues the rest
// of the currently-visible list from that point); the "…" button opens the
// track context menu (play next, queue, like, add to playlist, …).
// Highlighted + an animated level-meter glyph when it's the track currently
// loaded.
Item {
  id: root
  property var track: null
  property bool active: false
  property bool playing: false
  property string coverSrc: ""
  property bool showMenu: true

  signal activated()
  signal menuRequested()

  height: Style.space(52)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.active ? Style.selectedFillFor(Color.foreground, Color.accent)
      : (hoverArea.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
  }

  Row {
    anchors.left: parent.left
    anchors.right: rightCluster.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    Rectangle {
      width: Style.space(38); height: Style.space(38)
      radius: Style.space(5)
      color: Style.hoverFillFor(Color.foreground, Color.accent)
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
        color: Qt.darker(Color.foreground, 1.5)
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
          color: Color.accent
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
          color: root.active ? Color.accent : Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width - (root.active ? Style.space(18) : 0)
        }
      }

      Text {
        text: root.track ? Model.trackArtist(root.track) : ""
        visible: text !== ""
        color: Qt.darker(Color.foreground, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }

  Row {
    id: rightCluster
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.track ? Model.formatDuration(root.track.duration) : ""
      color: Qt.darker(Color.foreground, 1.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    IconButton {
      visible: root.showMenu
      icon: "more"
      size: Style.space(26)
      anchors.verticalCenter: parent.verticalCenter
      onActivated: root.menuRequested()
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

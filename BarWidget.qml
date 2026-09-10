import QtQuick
import qs.Commons
import qs.Ui

// Bar pill: the Tunedex mark (gradient badge + level-meter bars, exactly the
// motif from the site's own boot splash), pulsing while a track plays.
// Left-click toggles the panel; middle-click toggles play/pause without
// opening it.
BarWidget {
  id: root
  moduleName: "io.github.hack3rrabbit.tunedex"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing — see Panel base.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }
  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  readonly property bool signedIn: panelLoader.item ? !!panelLoader.item.session : false
  readonly property bool playing: panelLoader.item ? panelLoader.item.playing : false
  readonly property string nowTitle: panelLoader.item ? panelLoader.item.currentTitle : ""

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    tooltipText: root.signedIn ? (root.nowTitle || "Tunedex")
      : "Tunedex — " + (panelLoader.item ? panelLoader.item.tr("signin_btn") : "Sign in with Telegram")
    iconComponent: markComponent

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton && panelLoader.item && panelLoader.item.togglePlayback) panelLoader.item.togglePlayback()
      else root.togglePanel()
    }
  }

  // Level-meter mark, no badge box — same monochrome-by-default treatment
  // as the rest of the bar (weather's glyph, chand's plain price text):
  // bar.foreground at rest, the shell's own accent color while playing.
  Component {
    id: markComponent

    Item {
      id: markRoot
      readonly property color barColor: root.playing ? Color.accent : root.bar.foreground
      readonly property bool dim: !root.signedIn

      Row {
        opacity: markRoot.dim ? 0.4 : 1.0
        anchors.centerIn: parent
        spacing: Math.max(1, markRoot.width * 0.09)

        Repeater {
          model: 3
          Rectangle {
            required property int index
            readonly property real baseFrac: [0.35, 0.75, 0.5][index]
            width: Math.max(1, markRoot.width * 0.11)
            radius: width / 2
            color: markRoot.barColor
            height: markRoot.height * (root.playing ? baseFrac : 0.28)
            anchors.bottom: parent.bottom

            Behavior on height {
              NumberAnimation { duration: 260; easing.type: Easing.InOutQuad }
            }

            SequentialAnimation on height {
              running: root.playing
              loops: Animation.Infinite
              NumberAnimation { to: markRoot.height * Math.min(0.85, baseFrac + 0.25); duration: 320 + index * 70; easing.type: Easing.InOutSine }
              NumberAnimation { to: markRoot.height * Math.max(0.18, baseFrac - 0.2); duration: 320 + index * 70; easing.type: Easing.InOutSine }
            }
          }
        }
      }
    }
  }
}

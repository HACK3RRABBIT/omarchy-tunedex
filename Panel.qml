import QtQuick
import QtQuick.Controls
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Unofficial Tunedex client. Signs in through the same browser/desktop code
// flow the site's own PWA uses (POST /api/login/start, poll /api/login/poll
// until confirmed with the Telegram bot), then streams straight from
// Tunedex's API with QtMultimedia — no browser tab, no Telegram window.
Panel {
  id: root
  moduleName: "io.github.hack3rrabbit.tunedex"
  ipcTarget: "io.github.hack3rrabbit.tunedex"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }
  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }
  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }
  function toggle() { root.opened ? root.close() : root.openFromHotkey() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar) root.bar.centerHoverRevealSuppressed = value
  }

  // =====================================================================
  // Session — the site ships a browser/desktop login flow (loginStart +
  // loginPoll in its own static/js/api.js) specifically for clients like
  // this one that aren't the Telegram Mini App. Token is `uid:exp:kind:sig`;
  // it expires, so it's refreshed proactively and persisted locally.
  // =====================================================================
  property var session: null                 // {token,user,admin,notify,langChosen,bot}
  readonly property bool signedIn: !!session

  property FileView sessionFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/tunedex.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyStoredSession(text())
    onLoadFailed: {}
  }

  function applyStoredSession(raw) {
    var d = Model.parseJson(raw, null)
    if (d && typeof d.token === "string" && d.token) {
      root.session = d
      root.refreshSession()
    }
  }

  function persistSession() {
    sessionFile.setText(JSON.stringify(root.session || {}, null, 2) + "\n")
  }

  property bool signOutConfirmOpen: false
  function requestSignOut() { signOutConfirmOpen = true }
  function signOut() {
    signOutConfirmOpen = false
    mediaPlayer.stop()
    root.queueIds = []
    root.queueIndex = -1
    root.tracks = []
    root.trackById = ({})
    root.tracksNext = null
    root.library = null
    root.session = null
    persistSession()
  }

  // ---- login-code flow ----
  property string signinCode: ""
  property string signinSecret: ""
  property string signinUrl: ""
  property string signinBot: "TunedexAppBot"
  property bool signinBusy: false
  property bool signinExpired: false

  function startSignIn() {
    signinExpired = false
    signinBusy = true
    loginStartProc.running = true
  }

  Process {
    id: loginStartProc
    command: Model.authStartArgs()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var j = Model.parseJson(text, null)
        if (!j || !j.code || !j.secret) { root.signinBusy = false; root.signinExpired = true; return }
        root.signinCode = j.code
        root.signinSecret = j.secret
        root.signinBot = j.bot || "TunedexAppBot"
        root.signinUrl = j.url || ("https://t.me/" + root.signinBot + "?start=login_" + j.code)
        pollTimer.restart()
      }
    }
  }

  Timer {
    id: pollTimer
    interval: 2000
    repeat: true
    onTriggered: if (!loginPollProc.running) loginPollProc.running = true
  }

  Process {
    id: loginPollProc
    command: Model.authPollArgs(root.signinCode, root.signinSecret)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 404) { pollTimer.stop(); root.signinBusy = false; root.signinExpired = true; return }
        if (r.status !== 200) return           // transient — keep polling
        var j = Model.parseJson(r.body, null)
        if (j && j.status === "confirmed") {
          pollTimer.stop()
          root.signinBusy = false
          var s = Model.parseSession(j)
          if (s) { root.session = s; root.persistSession(); root.afterSignedIn() }
        }
        // status === "pending" -> keep polling
      }
    }
  }
  function afterSignedIn() {
    root.loadLibrary()
    root.loadMoreTracks()
    tokenWatchTimer.start()
  }

  property bool pendingPlaybackRetry: false
  property var pendingPlaybackRetryTrackId: null
  function refreshSession() {
    if (!root.session) return
    refreshProc.command = Model.authRefreshArgs(root.session.token)
    refreshProc.running = true
  }

  Process {
    id: refreshProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 200) {
          var s = Model.parseSession(Model.parseJson(r.body, null))
          if (s) {
            root.session = s
            root.persistSession()
            if (!root.library) root.afterSignedIn()
            if (root.pendingPlaybackRetry && root.pendingPlaybackRetryTrackId === root.currentTrackId) root.loadCurrent(true)
            root.pendingPlaybackRetry = false
            root.pendingPlaybackRetryTrackId = null
            return
          }
        }
        if (r.status === 401) { root.pendingPlaybackRetry = false; root.pendingPlaybackRetryTrackId = null; root.signOut() }
      }
    }
  }

  // Mini App tokens last 12h; the site's own client refreshes when under 1h
  // left. Check every 5 min.
  Timer {
    id: tokenWatchTimer
    interval: 300000
    repeat: true
    running: false
    onTriggered: {
      if (!root.session) return
      if (Model.tokenSecondsLeft(root.session.token) < 3600) root.refreshSession()
    }
  }

  // =====================================================================
  // Library / search
  // =====================================================================
  property var library: null
  property var tracks: []
  property var trackById: ({})
  property var tracksNext: null
  property bool tracksLoading: false
  property string libraryNotice: ""

  function indexTracks(items) {
    var map = {}
    for (var k in root.trackById) map[k] = root.trackById[k]
    for (var i = 0; i < items.length; i++) map[items[i].id] = items[i]
    root.trackById = map
  }

  function loadLibrary() {
    if (!root.session) return
    libraryProc.command = Model.libraryArgs(root.session.token)
    libraryProc.running = true
  }

  Process {
    id: libraryProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) return
        root.library = Model.parseLibrary(Model.parseJson(r.body, {}))
      }
    }
  }

  function loadMoreTracks() {
    if (!root.session || root.tracksLoading) return
    if (root.tracks.length > 0 && !root.tracksNext) return
    root.tracksLoading = true
    tracksProc.command = Model.tracksArgs(root.session.token, root.tracksNext)
    tracksProc.running = true
  }

  Process {
    id: tracksProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.tracksLoading = false
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status === 402 || r.status === 429) { root.libraryNotice = "Daily limit reached — try again tomorrow"; return }
        if (r.status < 200 || r.status >= 300) return
        var page = Model.parseTracksPage(Model.parseJson(r.body, {}))
        root.indexTracks(page.items)
        root.tracks = root.tracks.concat(page.items)
        root.tracksNext = page.next
      }
    }
  }

  property string searchQuery: ""
  property var searchResults: null
  property bool searchLoading: false
  readonly property bool searchActive: root.searchQuery.trim().length > 0

  Timer {
    id: searchDebounce
    interval: 350
    onTriggered: root.runSearch()
  }
  onSearchQueryChanged: {
    if (!root.searchActive) { root.searchResults = null; searchDebounce.stop(); return }
    searchDebounce.restart()
  }

  function runSearch() {
    if (!root.session || !root.searchActive) return
    root.searchLoading = true
    searchProc.command = Model.searchArgs(root.session.token, root.searchQuery.trim())
    searchProc.running = true
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.searchLoading = false
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) return
        var res = Model.parseSearch(Model.parseJson(r.body, {}))
        root.indexTracks(res.tracks)
        root.searchResults = res
      }
    }
  }

  readonly property var visibleTracks: root.searchActive ? (root.searchResults ? root.searchResults.tracks : []) : root.tracks

  // =====================================================================
  // Playback
  // =====================================================================
  property var queueIds: []
  property int queueIndex: -1
  property bool shuffleOn: false
  property string repeatMode: "off"          // off | all | one
  property string playerError: ""
  property int playbackRetries: 0

  readonly property var currentTrackId: (queueIndex >= 0 && queueIndex < queueIds.length) ? queueIds[queueIndex] : null
  readonly property var currentTrack: currentTrackId !== null ? root.trackById[currentTrackId] : null
  readonly property string currentTitle: currentTrack ? Model.trackTitle(currentTrack) : ""
  readonly property string currentArtist: currentTrack ? Model.trackArtist(currentTrack) : ""
  readonly property string currentCover: (currentTrack && root.session) ? Model.coverUrl(currentTrack, root.session.token) : ""
  readonly property bool playing: mediaPlayer.playbackState === MediaPlayer.PlayingState

  function playFromList(ids, index) {
    root.queueIds = ids.slice()
    root.queueIndex = index
    root.shuffleOn = false
    loadCurrent(true)
  }

  function loadCurrent(autoplay) {
    var id = root.currentTrackId
    if (id === null || id === undefined || !root.session) { mediaPlayer.stop(); mediaPlayer.source = ""; return }
    root.playerError = ""
    mediaPlayer.source = Model.streamUrl(id, root.session.token)
    if (autoplay) mediaPlayer.play()
  }

  function togglePlayback() {
    if (!root.currentTrackId) return
    if (root.playing) mediaPlayer.pause(); else mediaPlayer.play()
  }

  function playNextTrack(auto) {
    if (!root.queueIds.length) return
    if (auto && root.repeatMode === "one") { mediaPlayer.position = 0; mediaPlayer.play(); return }
    var n = root.queueIndex + 1
    if (n >= root.queueIds.length) {
      if (root.repeatMode === "all") n = 0
      else { if (auto) mediaPlayer.pause(); return }
    }
    root.queueIndex = n
    loadCurrent(true)
  }

  function playPrevTrack() {
    if (mediaPlayer.position > 3000) { mediaPlayer.position = 0; return }
    if (!root.queueIds.length) return
    var p = root.queueIndex - 1
    if (p < 0) { if (root.repeatMode !== "all") { mediaPlayer.position = 0; return }; p = root.queueIds.length - 1 }
    root.queueIndex = p
    loadCurrent(true)
  }

  function toggleShuffle() {
    if (!root.queueIds.length) { root.shuffleOn = !root.shuffleOn; return }
    if (!root.shuffleOn) {
      var cur = root.currentTrackId
      var rest = root.queueIds.filter(function(x) { return x !== cur })
      for (var i = rest.length - 1; i > 0; i--) {
        var j = Math.floor(Math.random() * (i + 1))
        var t = rest[i]; rest[i] = rest[j]; rest[j] = t
      }
      root.queueIds = cur !== null ? [cur].concat(rest) : rest
      root.queueIndex = cur !== null ? 0 : root.queueIndex
    }
    root.shuffleOn = !root.shuffleOn
  }

  function cycleRepeat() {
    root.repeatMode = root.repeatMode === "off" ? "all" : (root.repeatMode === "all" ? "one" : "off")
  }

  function seekFraction(frac) {
    if (!isFinite(mediaPlayer.duration) || mediaPlayer.duration <= 0) return
    mediaPlayer.position = Math.round(Math.max(0, Math.min(1, frac)) * mediaPlayer.duration)
  }

  MediaPlayer {
    id: mediaPlayer
    audioOutput: AudioOutput {}
    onErrorOccurred: function(error, errorString) {
      if (root.playbackRetries < 1 && root.session) {
        root.playbackRetries += 1
        root.pendingPlaybackRetry = true
        root.pendingPlaybackRetryTrackId = root.currentTrackId
        root.refreshSession()
      } else {
        root.playerError = errorString || "Playback error"
      }
    }
    onPlaybackStateChanged: if (mediaPlayer.playbackState === MediaPlayer.PlayingState) { root.playbackRetries = 0; root.playerError = "" }
    onMediaStatusChanged: if (mediaPlayer.mediaStatus === MediaPlayer.EndOfMedia) root.playNextTrack(true)
  }

  // =====================================================================
  // UI
  // =====================================================================
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    // false (the default): drop the panel under the bar icon, like every
    // other bar-widget popup. centerOnBar:true — copied from weather's
    // Panel.qml without checking what it does — instead centers on the
    // whole screen regardless of where the icon sits, which is why it
    // opened detached from the pill on the right.
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // No custom background here — KeyboardPanel's own card (Color.popups.background,
      // themed border) already paints the surface, same as every other bar-widget
      // popup. Painting our own over it is what made the panel look un-Omarchy.

      // Plain Item, not Column: trackList below fills whatever height is
      // left, which would be a circular binding under a Column (whose own
      // height is the sum of its children's).
      Item {
        id: shell
        anchors.fill: parent
        anchors.margins: Style.space(14)
        anchors.bottomMargin: root.currentTrackId !== null ? Style.space(88) : Style.space(14)

        // ---- header ----
        Item {
          id: header
          anchors.top: parent.top
          width: parent.width
          height: Style.space(30)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(24); height: Style.space(24)
              radius: width * 0.28
              anchors.verticalCenter: parent.verticalCenter
              color: Color.accent
              Icon { anchors.centerIn: parent; name: "music"; color: Color.background; width: Style.space(14); height: Style.space(14) }
            }

            Text {
              text: "Tunedex"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            visible: root.signedIn

            Text {
              visible: text !== ""
              text: root.session && root.session.user ? (root.session.user.first_name || root.session.user.username || "") : ""
              color: Qt.darker(Color.foreground, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              width: Math.min(implicitWidth, Style.space(110))
            }

            IconButton {
              icon: "logout"
              tooltip: "Sign out"
              onActivated: root.requestSignOut()
            }
          }
        }

        // ---- search ----
        Item {
          id: searchRow
          visible: root.signedIn
          anchors.top: header.bottom
          anchors.topMargin: Style.space(10)
          width: parent.width
          height: root.signedIn ? Style.space(32) : 0

          TextField {
            id: searchField
            anchors.fill: parent
            placeholderText: "Search your library"
            font.family: Style.font.family
            leftPadding: Style.space(30)
            onTextChanged: root.searchQuery = text
          }
          Icon {
            name: "search"
            color: Qt.darker(Color.foreground, 1.5)
            width: Style.space(14); height: Style.space(14)
            anchors.left: parent.left
            anchors.leftMargin: Style.space(9)
            anchors.verticalCenter: parent.verticalCenter
          }
          IconButton {
            visible: searchField.text !== ""
            icon: "close"
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            size: Style.space(22)
            onActivated: { searchField.text = ""; searchField.forceActiveFocus() }
          }
        }

        Text {
          id: notice
          visible: root.libraryNotice !== ""
          anchors.top: searchRow.bottom
          anchors.topMargin: Style.space(6)
          text: root.libraryNotice
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          width: parent.width
          wrapMode: Text.WordWrap
        }

        // ---- sign-in prompt ----
        Column {
          visible: !root.signedIn
          anchors.top: header.bottom
          width: parent.width
          spacing: Style.space(14)
          topPadding: Style.space(28)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(72); height: Style.space(72)
            radius: width / 2
            color: Color.accent
            Icon { anchors.centerIn: parent; name: "music"; color: Color.background; width: Style.space(30); height: Style.space(30) }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Sign in to Tunedex"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(320)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.signinExpired ? "That sign-in code expired." :
                  (root.signinCode !== "" ? "Confirm in Telegram, then come back — this closes on its own." :
                  "Confirms through your Tunedex bot on Telegram. No browser, no re-typing anything here.")
            color: Qt.darker(Color.foreground, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.signinBusy ? "Waiting for confirmation…" : (root.signinExpired ? "Try again" : "Sign in with Telegram")
            foreground: Color.background
            background: Color.accent
            bordered: false
            horizontalPadding: Style.space(18)
            verticalPadding: Style.space(9)
            onClicked: {
              if (root.signinBusy) { Qt.openUrlExternally(root.signinUrl); return }
              root.startSignIn()
            }
          }

          Text {
            visible: root.signinCode !== "" && !root.signinExpired
            anchors.horizontalCenter: parent.horizontalCenter
            text: "or send  /start login_" + root.signinCode + "  to @" + root.signinBot
            color: Qt.darker(Color.foreground, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---- track list ----
        ListView {
          id: trackList
          visible: root.signedIn
          anchors.top: notice.bottom
          anchors.topMargin: Style.space(6)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          clip: true
          spacing: Style.space(2)
          model: root.visibleTracks

          delegate: TrackRow {
            required property var modelData
            required property int index
            width: trackList.width
            track: modelData
            active: root.currentTrackId === modelData.id
            playing: active && root.playing
            coverSrc: (root.session && modelData && modelData.cover) ? Model.coverUrl(modelData, root.session.token) : ""
            onActivated: root.playFromList(root.visibleTracks.map(function(t) { return t.id }), index)
          }

          footer: Item {
            width: trackList.width
            height: footerCol.implicitHeight + Style.space(10)

            Column {
              id: footerCol
              width: parent.width
              spacing: Style.space(8)
              topPadding: Style.space(6)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.signedIn && root.visibleTracks.length === 0 && !root.tracksLoading && !root.searchLoading
                text: root.searchActive ? "No matches" : "Your library is empty"
                color: Qt.darker(Color.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.searchActive && root.tracksNext && !root.tracksLoading
                text: "Load more"
                foreground: Color.foreground
                bordered: true
                onClicked: root.loadMoreTracks()
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.tracksLoading || root.searchLoading
                text: "Loading…"
                color: Qt.darker(Color.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }

      // ---- now playing ----
      Rectangle {
        visible: root.currentTrackId !== null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(78)
        radius: Style.cornerRadius
        color: Style.selectedFillFor(Color.foreground, Color.accent)

        PanelSlider {
          id: seekBar
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: -Style.space(3)
          trackHeight: Style.space(3)
          knobSize: Style.space(11)
          value: mediaPlayer.duration > 0 ? mediaPlayer.position / mediaPlayer.duration : 0
          fillColor: Color.accent
          trackColor: Style.selectedFillFor(Color.foreground, Color.accent)
          knobColor: Color.accent
          onReleased: function(v) { root.seekFraction(v) }
        }

        Text {
          visible: root.playerError !== ""
          text: root.playerError
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          anchors.top: seekBar.bottom
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: Style.space(4)
          spacing: Style.space(8)

          Rectangle {
            width: Style.space(44); height: Style.space(44)
            radius: Style.space(6)
            color: Style.hoverFillFor(Color.foreground, Color.accent)
            clip: true
            anchors.verticalCenter: parent.verticalCenter

            Image {
              anchors.fill: parent
              visible: root.currentCover !== "" && status === Image.Ready
              source: root.currentCover
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
            Icon {
              visible: root.currentCover === ""
              anchors.centerIn: parent
              name: "music"
              color: Qt.darker(Color.foreground, 1.5)
              width: Style.space(18); height: Style.space(18)
            }
          }

          Column {
            width: Style.space(120)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.currentTitle
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              width: parent.width
            }
            Text {
              text: root.currentArtist
              color: Qt.darker(Color.foreground, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        Row {
          anchors.centerIn: parent
          anchors.horizontalCenterOffset: Style.space(60)
          spacing: Style.space(10)

          IconButton {
            icon: "shuffle"
            active: root.shuffleOn
            onActivated: root.toggleShuffle()
          }
          IconButton {
            icon: "previous"
            size: Style.space(28)
            onActivated: root.playPrevTrack()
          }
          Rectangle {
            width: Style.space(34); height: Style.space(34)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: Color.accent
            Icon {
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: root.playing ? 0 : 1
              name: root.playing ? "pause" : "play"
              color: Color.background
              width: Style.space(15); height: Style.space(15)
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePlayback() }
          }
          IconButton {
            icon: "next"
            size: Style.space(28)
            onActivated: root.playNextTrack(false)
          }
          IconButton {
            icon: root.repeatMode === "one" ? "repeatOne" : "repeat"
            active: root.repeatMode !== "off"
            onActivated: root.cycleRepeat()
          }
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: Style.space(4)
          text: Model.formatDuration(mediaPlayer.position / 1000) + " / " + Model.formatDuration(mediaPlayer.duration / 1000)
          color: Qt.darker(Color.foreground, 1.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  ConfirmDialog {
    anchors.fill: parent
    opened: root.signOutConfirmOpen
    message: "Sign out of Tunedex?"
    confirmText: "Sign out"
    onCanceled: root.signOutConfirmOpen = false
    onConfirmed: root.signOut()
  }
}

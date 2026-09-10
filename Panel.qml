import QtQuick
import QtQuick.Controls
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n

// Unofficial Tunedex client. Signs in through the same browser/desktop code
// flow the site's own PWA uses (POST /api/login/start, poll /api/login/poll
// until confirmed with the Telegram bot), then streams straight from
// Tunedex's API with QtMultimedia — no browser tab, no Telegram window.
//
// Scope note: this covers everything Tunedex offers except two things, on
// purpose — the Pro/payment flow (Telegram Stars + card charges: not
// something a background plugin should handle) and the admin console
// (an ops panel for the site's operator, gated to one account). Everything
// else — home, full library taxonomy, playlists, likes, channels, mixes,
// queue, sleep timer, settings — is here.
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

  // UI language follows the account's Tunedex language (same strings the
  // site itself uses for these keys). Layout stays left-to-right even for
  // Persian — no RTL mirroring — but the text is real, not placeholder.
  readonly property string langCode: (session && session.lang) || "en"
  function tr(key, params) { return I18n.t(root.langCode, key, params) }

  // Site's own Home greeting has no name in it; showing one here is a
  // deliberate addition, not a site-parity thing.
  function homeGreeting() {
    var h = new Date().getHours()
    var key = h < 12 ? "greet_morning" : h < 18 ? "greet_afternoon" : "greet_evening"
    var greeting = root.tr(key)
    var name = root.session && root.session.user ? (root.session.user.first_name || root.session.user.username || "") : ""
    return name ? greeting + ", " + name : greeting
  }

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
    root.playlists = []
    root.myChannels = []
    root.suggested = []
    root.likes = []
    root.group = null
    root.groupItems = []
    root.channelDetail = null
    root.mixes = []
    root.mixItemsMap = ({})
    root.recentsItems = []
    root.activeSheet = ""
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
    root.loadRecents()
    root.loadMixes()
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
  // Library — flat track list, playlists, likes, channels, artist/album/
  // genre groups, mixes. Mirrors the site's api.js + library.js.
  // =====================================================================
  property var library: null
  property var tracks: []
  property var trackById: ({})
  property var tracksNext: null
  property bool tracksLoading: false
  property string libraryNotice: ""
  property var playlists: []
  property var myChannels: []
  property var suggested: []
  property var likes: []

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
        var lib = Model.parseLibrary(Model.parseJson(r.body, {}))
        root.library = lib
        root.playlists = lib.playlists
        root.myChannels = lib.channels
        root.suggested = lib.suggested
        root.likes = lib.likes
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
        if (r.status === 402 || r.status === 429) { root.libraryNotice = root.tr("daily_limit"); return }
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

  // ---- likes ----
  function isLiked(id) { return root.likes.indexOf(id) >= 0 }
  function toggleLike(id) {
    if (!root.session) return
    var liked = root.isLiked(id)
    root.likes = liked ? root.likes.filter(function(x) { return x !== id }) : [id].concat(root.likes)
    likeProc.command = Model.likeArgs(root.session.token, id, liked)
    likeProc.rollbackId = id
    likeProc.rollbackWasLiked = liked
    likeProc.running = true
  }
  Process {
    id: likeProc
    property var rollbackId: null
    property bool rollbackWasLiked: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) {
          // failed: put it back the way it was
          var id = likeProc.rollbackId, was = likeProc.rollbackWasLiked
          root.likes = was ? [id].concat(root.likes) : root.likes.filter(function(x) { return x !== id })
        }
      }
    }
  }

  // ---- playlists ----
  property string newPlaylistName: ""
  property bool playlistBusy: false
  function submitNewPlaylist() {
    var title = root.newPlaylistName.trim()
    if (!title || !root.session || root.playlistBusy) return
    root.playlistBusy = true
    createPlaylistProc.command = Model.createPlaylistArgs(root.session.token, title)
    createPlaylistProc.running = true
  }
  Process {
    id: createPlaylistProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.playlistBusy = false
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) { root.libraryNotice = root.tr("could_not_create_playlist"); return }
        var pl = Model.parseJson(r.body, null)
        if (pl) { root.playlists = root.playlists.concat([pl]); root.newPlaylistName = ""; root.activeSheet = "" }
      }
    }
  }

  function deletePlaylist(pid) {
    if (!root.session) return
    deletePlaylistProc.pid = pid
    deletePlaylistProc.command = Model.deletePlaylistArgs(root.session.token, pid)
    deletePlaylistProc.running = true
  }
  Process {
    id: deletePlaylistProc
    property var pid: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) return
        root.playlists = root.playlists.filter(function(p) { return p.id !== deletePlaylistProc.pid })
        if (root.group && root.group.kind === "playlist" && root.group.id === deletePlaylistProc.pid) root.closeGroup()
      }
    }
  }

  function togglePlaylistMembership(pid, trackId) {
    if (!root.session) return
    var pl = root.playlists.find(function(p) { return p.id === pid })
    if (!pl) return
    var has = pl.tracks.indexOf(trackId) >= 0
    playlistItemProc.pid = pid
    playlistItemProc.trackId = trackId
    playlistItemProc.adding = !has
    playlistItemProc.command = has
      ? Model.removeFromPlaylistArgs(root.session.token, pid, trackId)
      : Model.addToPlaylistArgs(root.session.token, pid, trackId)
    playlistItemProc.running = true
  }
  Process {
    id: playlistItemProc
    property var pid: null
    property var trackId: null
    property bool adding: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) return
        root.playlists = root.playlists.map(function(p) {
          if (p.id !== playlistItemProc.pid) return p
          var tracks = playlistItemProc.adding ? p.tracks.concat([playlistItemProc.trackId])
            : p.tracks.filter(function(x) { return x !== playlistItemProc.trackId })
          return Object.assign({}, p, { tracks: tracks })
        })
      }
    }
  }

  // ---- channels ----
  property string connectRef: ""
  property string connectMsg: ""
  property bool connectBusy: false
  function submitConnect() {
    var ref = root.connectRef.trim()
    if (!ref || !root.session || root.connectBusy) return
    root.connectBusy = true
    root.connectMsg = root.tr("connecting")
    connectChannelProc.command = Model.connectChannelArgs(root.session.token, ref)
    connectChannelProc.running = true
  }
  Process {
    id: connectChannelProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.connectBusy = false
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) { root.connectMsg = root.tr("could_not_connect"); return }
        root.connectMsg = root.tr("connected_indexing")
        root.connectRef = ""
        root.loadLibrary()
      }
    }
  }

  function removeChannel(id) {
    if (!root.session) return
    removeChannelProc.cid = id
    removeChannelProc.command = Model.removeChannelArgs(root.session.token, id)
    removeChannelProc.running = true
  }
  Process {
    id: removeChannelProc
    property var cid: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300 && r.status !== 404) return
        root.myChannels = root.myChannels.filter(function(c) { return c.id !== removeChannelProc.cid })
        if (root.group && root.group.kind === "channel" && root.group.id === removeChannelProc.cid) root.closeGroup()
      }
    }
  }

  // =====================================================================
  // Group drill-down: playlist / liked / artist / album / genre / channel /
  // mix detail. One screen, fed by whichever endpoint fits the kind.
  // =====================================================================
  property var group: null                    // {kind,id?,name?,mix?}
  property var groupItems: []
  property var groupNext: null
  property bool groupLoading: false
  property bool groupDone: false
  property var channelDetail: null

  function openGroup(g) {
    root.currentTab = "library"
    root.group = g
    root.groupItems = []
    root.groupNext = null
    root.groupDone = false
    root.channelDetail = null
    if (g.kind === "channel") loadChannelDetail(g.id)
    loadGroupPage()
  }
  function closeGroup() {
    root.group = null
    root.groupItems = []
    root.channelDetail = null
  }

  function loadChannelDetail(id) {
    if (!root.session) return
    channelDetailProc.command = Model.channelArgs(root.session.token, id)
    channelDetailProc.running = true
  }
  Process {
    id: channelDetailProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) return
        root.channelDetail = Model.parseChannel(Model.parseJson(r.body, {}))
      }
    }
  }

  function loadGroupPage() {
    if (!root.session || !root.group || root.groupLoading || root.groupDone) return
    var g = root.group
    root.groupLoading = true
    if (g.kind === "playlist" || g.kind === "liked") {
      var ids = g.kind === "playlist"
        ? ((root.playlists.find(function(p) { return p.id === g.id }) || { tracks: [] }).tracks)
        : root.likes
      ids = ids.slice(0, 300)
      if (!ids.length) { root.groupLoading = false; root.groupDone = true; return }
      groupTracksProc.mode = "ids"
      groupTracksProc.command = Model.tracksByIdsArgs(root.session.token, ids)
    } else if (g.kind === "channel") {
      groupTracksProc.mode = "cursor"
      groupTracksProc.command = Model.channelTracksArgs(root.session.token, g.id, root.groupNext)
    } else if (g.kind === "mix") {
      groupTracksProc.mode = "mix"
      groupTracksProc.command = Model.mixItemsArgs(root.session.token, g.mix)
    } else {
      groupTracksProc.mode = "cursor"
      groupTracksProc.command = Model.groupTracksArgs(root.session.token, g.kind, g.name, root.groupNext)
    }
    groupTracksProc.running = true
  }

  Process {
    id: groupTracksProc
    property string mode: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.groupLoading = false
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) { root.groupDone = true; return }
        var j = Model.parseJson(r.body, null)
        if (groupTracksProc.mode === "ids") {
          var items = j || []
          root.indexTracks(items)
          root.groupItems = items
          root.groupDone = true
        } else if (groupTracksProc.mode === "mix") {
          var items2 = (j && j.items) || []
          root.indexTracks(items2)
          root.groupItems = items2
          root.groupDone = true
        } else {
          var page = Model.parseTracksPage(j)
          root.indexTracks(page.items)
          root.groupItems = root.groupItems.concat(page.items)
          root.groupNext = page.next
          root.groupDone = !page.next
        }
      }
    }
  }

  // ---- artists / albums / genres top lists ----
  property string groupsListKind: ""
  property var groupsListItems: []
  property int groupsListOffset: 0
  property bool groupsListDone: false
  property bool groupsListLoading: false

  function loadGroupsList(kind) {
    if (kind !== root.groupsListKind) {
      root.groupsListKind = kind
      root.groupsListItems = []
      root.groupsListOffset = 0
      root.groupsListDone = false
    }
    if (!root.session || root.groupsListLoading || root.groupsListDone) return
    root.groupsListLoading = true
    groupsListProc.command = Model.groupsArgs(root.session.token, root.groupsListKind, root.groupsListOffset)
    groupsListProc.running = true
  }
  Process {
    id: groupsListProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.groupsListLoading = false
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) { root.groupsListDone = true; return }
        var items = Model.parseGroupsPage(Model.parseJson(r.body, {}))
        root.groupsListItems = root.groupsListItems.concat(items)
        root.groupsListOffset += items.length
        root.groupsListDone = items.length < 100
      }
    }
  }

  // ---- mixes ----
  property var mixes: []
  property var mixItemsMap: ({})
  function loadMixes() {
    if (!root.session) return
    mixesProc.command = Model.mixesArgs(root.session.token)
    mixesProc.running = true
  }
  Process {
    id: mixesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) return
        root.mixes = Model.parseMixes(Model.parseJson(r.body, {}))
      }
    }
  }
  function saveMixAsPlaylist(kind) {
    if (!root.session) return
    saveMixProc.command = Model.saveMixArgs(root.session.token, kind)
    saveMixProc.running = true
  }
  Process {
    id: saveMixProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) return
        var pl = Model.parseJson(r.body, null)
        if (pl) root.playlists = root.playlists.concat([pl])
      }
    }
  }

  // ---- recently played (Home) ----
  property var recentsItems: []
  function loadRecents() {
    if (!root.session) return
    recentsProc.command = Model.recentsArgs(root.session.token)
    recentsProc.running = true
  }
  Process {
    id: recentsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = Model.splitHttpOutput(text)
        if (r.status === 401) { root.refreshSession(); return }
        if (r.status < 200 || r.status >= 300) return
        var items = Model.parseJson(r.body, [])
        root.indexTracks(items)
        root.recentsItems = items
      }
    }
  }

  // ---- settings ----
  function saveLangChoice(code) {
    if (!root.session || root.session.lang === code) return
    root.session = Object.assign({}, root.session, { lang: code, langChosen: true })
    root.persistSession()
    saveLangProc.command = Model.saveLangArgs(root.session.token, code)
    saveLangProc.running = true
  }
  Process {
    id: saveLangProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var r = Model.splitHttpOutput(text); if (r.status === 401) root.refreshSession() } }
  }
  function saveNotifyChoice(level) {
    if (!root.session) return
    root.session = Object.assign({}, root.session, { notify: level })
    root.persistSession()
    saveNotifyProc.command = Model.saveNotifyArgs(root.session.token, level)
    saveNotifyProc.running = true
  }
  Process {
    id: saveNotifyProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var r = Model.splitHttpOutput(text); if (r.status === 401) root.refreshSession() } }
  }

  // =====================================================================
  // Playback
  // =====================================================================
  property var queueIds: []
  property int queueIndex: -1
  property bool shuffleOn: false
  property string repeatMode: "off"          // off | all | one
  property string playerError: ""
  property int playbackRetries: 0
  property var sleepAt: null
  property bool sleepEndOfTrack: false

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

  function removeFromQueue(index) {
    if (index <= root.queueIndex || index < 0 || index >= root.queueIds.length) return
    var ids = root.queueIds.slice()
    ids.splice(index, 1)
    root.queueIds = ids
  }
  function clearUpNext() {
    root.queueIds = root.queueIds.slice(0, root.queueIndex + 1)
  }
  function jumpToQueueIndex(index) {
    if (index < 0 || index >= root.queueIds.length) return
    root.queueIndex = index
    loadCurrent(true)
  }

  // ---- sleep timer ----
  function setSleep(v) {
    if (v === null) { root.sleepAt = null; root.sleepEndOfTrack = false; return }
    if (v === "track") { root.sleepAt = null; root.sleepEndOfTrack = true; return }
    root.sleepEndOfTrack = false
    root.sleepAt = Date.now() + v * 60000
  }
  readonly property int sleepMinutesLeft: root.sleepAt ? Math.max(0, Math.ceil((root.sleepAt - sleepClock.now) / 60000)) : -1
  Timer {
    id: sleepClock
    property real now: Date.now()
    interval: 15000
    running: root.sleepAt !== null
    repeat: true
    onTriggered: {
      now = Date.now()
      if (root.sleepAt && now >= root.sleepAt) { mediaPlayer.pause(); root.sleepAt = null }
    }
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
        root.playerError = errorString || root.tr("playback_error")
      }
    }
    onPlaybackStateChanged: if (mediaPlayer.playbackState === MediaPlayer.PlayingState) { root.playbackRetries = 0; root.playerError = "" }
    onMediaStatusChanged: {
      if (mediaPlayer.mediaStatus === MediaPlayer.EndOfMedia) {
        if (root.sleepEndOfTrack) { root.sleepEndOfTrack = false; mediaPlayer.pause(); return }
        root.playNextTrack(true)
      }
    }
  }

  // =====================================================================
  // Navigation / sheets
  // =====================================================================
  property string currentTab: "home"          // home | library
  property string libChip: "tracks"           // tracks | playlists | liked | artists | albums | genres | channels
  property string activeSheet: ""             // "" | trackMenu | playlistPicker | newPlaylist | connectChannel | sleepTimer | settings | nowPlaying | queue
  property var sheetTrackId: null

  function openTrackMenu(id) { root.sheetTrackId = id; root.activeSheet = "trackMenu" }
  function openPlaylistPicker(id) { root.sheetTrackId = id; root.activeSheet = "playlistPicker" }
  function closeSheet() { root.activeSheet = "" }

  function setLibChip(kind) {
    root.libChip = kind
    if (kind === "liked") { root.openGroup({ kind: "liked" }); return }
    if (kind === "artists" || kind === "albums" || kind === "genres") root.loadGroupsList(kind)
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
    // other bar-widget popup, instead of centering on the whole screen.
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(444))
    contentHeight: panel.fittedContentHeight(Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || newPlaylistField.activeFocus || connectField.activeFocus
      onCloseRequested: root.activeSheet !== "" ? root.closeSheet() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // No custom background here — KeyboardPanel's own card (Color.popups.background,
      // themed border) already paints the surface, same as every other bar-widget
      // popup.

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
            spacing: Style.space(2)
            visible: root.signedIn

            IconButton {
              icon: "settings"
              tooltip: root.tr("settings")
              onActivated: root.activeSheet = "settings"
            }
            IconButton {
              icon: "logout"
              tooltip: root.tr("sign_out")
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
            placeholderText: root.tr("search_placeholder")
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

        // ---- tab bar (Home / Library) ----
        Row {
          id: tabBar
          visible: root.signedIn && !root.searchActive
          anchors.top: searchRow.bottom
          anchors.topMargin: Style.space(8)
          width: parent.width
          height: visible ? Style.space(30) : 0
          spacing: Style.space(6)

          Repeater {
            model: [{ id: "home", label: root.tr("tab_home"), icon: "home" }, { id: "library", label: root.tr("tab_library"), icon: "library" }]
            Rectangle {
              id: tabPill
              required property var modelData
              readonly property bool on: root.currentTab === modelData.id
              width: Style.space(96); height: Style.space(28)
              radius: Style.cornerRadius
              color: on ? Style.selectedFillFor(Color.foreground, Color.accent) : "transparent"

              Row {
                anchors.centerIn: parent
                spacing: Style.space(6)
                Icon { name: tabPill.modelData.icon; color: tabPill.on ? Color.accent : Qt.darker(Color.foreground, 1.4); width: Style.space(14); height: Style.space(14); anchors.verticalCenter: parent.verticalCenter }
                Text { text: tabPill.modelData.label; color: tabPill.on ? Color.accent : Qt.darker(Color.foreground, 1.4); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentTab = modelData.id; if (root.group) root.closeGroup() } }
            }
          }
        }

        Text {
          id: notice
          visible: root.libraryNotice !== ""
          anchors.top: tabBar.bottom
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
            text: root.tr("signin_title")
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
            text: root.signinExpired ? root.tr("signin_expired") :
                  (root.signinCode !== "" ? root.tr("signin_hint_waiting") : root.tr("signin_hint_idle"))
            color: Qt.darker(Color.foreground, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.signinBusy ? root.tr("signin_waiting") : (root.signinExpired ? root.tr("try_again") : root.tr("signin_btn"))
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
            text: root.tr("signin_manual", { code: "/start login_" + root.signinCode, bot: root.signinBot })
            color: Qt.darker(Color.foreground, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---- main content ----
        Item {
          id: mainContent
          visible: root.signedIn
          anchors.top: notice.bottom
          anchors.topMargin: Style.space(6)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          // -- search results --
          ListView {
            anchors.fill: parent
            visible: root.searchActive
            clip: true
            spacing: Style.space(2)
            model: root.visibleTracks
            delegate: TrackRow {
              required property var modelData
              required property int index
              width: ListView.view.width
              track: modelData
              active: root.currentTrackId === modelData.id
              playing: active && root.playing
              coverSrc: (root.session && modelData && modelData.cover) ? Model.coverUrl(modelData, root.session.token) : ""
              onActivated: root.playFromList(root.visibleTracks.map(function(t) { return t.id }), index)
              onMenuRequested: root.openTrackMenu(modelData.id)
            }
            footer: Item {
              width: ListView.view ? ListView.view.width : 0
              height: Style.space(30)
              Text {
                anchors.centerIn: parent
                visible: !root.searchLoading && root.visibleTracks.length === 0
                text: root.tr("no_matches")
                color: Qt.darker(Color.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                anchors.centerIn: parent
                visible: root.searchLoading
                text: root.tr("searching")
                color: Qt.darker(Color.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          // -- home tab --
          Flickable {
            anchors.fill: parent
            visible: !root.searchActive && root.currentTab === "home"
            clip: true
            contentWidth: width
            contentHeight: homeCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: homeCol
              width: parent.width
              spacing: Style.space(16)

              Text {
                text: root.homeGreeting()
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              // continue listening
              Rectangle {
                visible: root.currentTrackId !== null && !root.playing
                width: parent.width
                height: Style.space(58)
                radius: Style.cornerRadius
                color: Style.hoverFillFor(Color.foreground, Color.accent)

                Row {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(10)
                  Rectangle {
                    width: Style.space(42); height: Style.space(42)
                    radius: Style.space(5)
                    color: Style.hoverFillFor(Color.foreground, Color.accent)
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    Image { anchors.fill: parent; visible: root.currentCover !== ""; source: root.currentCover; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                    Icon { visible: root.currentCover === ""; anchors.centerIn: parent; name: "music"; color: Qt.darker(Color.foreground, 1.5); width: Style.space(16); height: Style.space(16) }
                  }
                  Column {
                    width: parent.width - Style.space(96)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)
                    Text { text: root.tr("continue_listening"); color: Qt.darker(Color.foreground, 1.4); font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    Text { text: root.currentTitle; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; elide: Text.ElideRight; width: parent.width }
                  }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePlayback() }
              }

              // quick picks: liked + mixes
              Flow {
                width: parent.width
                spacing: Style.space(8)
                visible: root.likes.length > 0 || root.mixes.length > 0

                Rectangle {
                  visible: root.likes.length > 0
                  width: Style.space(120); height: Style.space(40)
                  radius: Style.cornerRadius
                  color: Style.hoverFillFor(Color.foreground, Color.accent)
                  Row {
                    anchors.left: parent.left; anchors.leftMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)
                    Icon { name: "heartFilled"; color: Color.accent; width: Style.space(14); height: Style.space(14); anchors.verticalCenter: parent.verticalCenter }
                    Text { text: root.tr("liked_songs"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openGroup({ kind: "liked" }) }
                }

                Repeater {
                  model: root.mixes
                  Rectangle {
                    required property var modelData
                    width: Style.space(120); height: Style.space(40)
                    radius: Style.cornerRadius
                    color: Style.hoverFillFor(Color.foreground, Color.accent)
                    Text {
                      anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
                      text: modelData.kind.charAt(0).toUpperCase() + modelData.kind.slice(1)
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openGroup({ kind: "mix", mix: modelData.kind }) }
                  }
                }
              }

              // latest in library
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.tracks.length > 0
                Text { text: root.tr("latest_in_library"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.subtitle; font.bold: true }
                Repeater {
                  model: root.tracks.slice(0, 8)
                  TrackRow {
                    required property var modelData
                    required property int index
                    width: homeCol.width
                    track: modelData
                    active: root.currentTrackId === modelData.id
                    playing: active && root.playing
                    coverSrc: (root.session && modelData.cover) ? Model.coverUrl(modelData, root.session.token) : ""
                    onActivated: root.playFromList(root.tracks.slice(0, 8).map(function(t) { return t.id }), index)
                    onMenuRequested: root.openTrackMenu(modelData.id)
                  }
                }
              }

              // recently played
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.recentsItems.length > 0
                Text { text: root.tr("recently_played"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.subtitle; font.bold: true }
                Repeater {
                  model: root.recentsItems
                  TrackRow {
                    required property var modelData
                    required property int index
                    width: homeCol.width
                    track: modelData
                    active: root.currentTrackId === modelData.id
                    playing: active && root.playing
                    coverSrc: (root.session && modelData.cover) ? Model.coverUrl(modelData, root.session.token) : ""
                    onActivated: root.playFromList(root.recentsItems.map(function(t) { return t.id }), index)
                    onMenuRequested: root.openTrackMenu(modelData.id)
                  }
                }
              }

              Text {
                visible: !root.tracks.length && !root.recentsItems.length && root.mixes.length === 0 && root.likes.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.tr("home_empty")
                wrapMode: Text.WordWrap
                color: Qt.darker(Color.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                topPadding: Style.space(20)
              }

              Item { width: 1; height: Style.space(6) }
            }
          }

          // -- library tab --
          Item {
            anchors.fill: parent
            visible: !root.searchActive && root.currentTab === "library"

            // group drill-down header + list
            Column {
              id: groupHeader
              visible: !!root.group
              anchors.top: parent.top
              width: parent.width
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.space(8)
                IconButton { icon: "back"; onActivated: root.closeGroup() }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(120)
                  elide: Text.ElideRight
                  text: root.groupTitle()
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                Button {
                  text: root.tr("play")
                  foreground: Color.background
                  background: Color.accent
                  bordered: false
                  horizontalPadding: Style.space(14)
                  verticalPadding: Style.space(6)
                  onClicked: if (root.groupItems.length) root.playFromList(root.groupItems.map(function(t) { return t.id }), 0)
                }
                Button {
                  text: root.tr("shuffle")
                  foreground: Color.foreground
                  bordered: true
                  horizontalPadding: Style.space(14)
                  verticalPadding: Style.space(6)
                  onClicked: {
                    if (!root.groupItems.length) return
                    var ids = root.groupItems.map(function(t) { return t.id })
                    for (var i = ids.length - 1; i > 0; i--) {
                      var j = Math.floor(Math.random() * (i + 1))
                      var tmp = ids[i]; ids[i] = ids[j]; ids[j] = tmp
                    }
                    root.playFromList(ids, 0)
                    root.shuffleOn = true
                  }
                }
                IconButton {
                  visible: root.group && root.group.kind === "playlist"
                  icon: "close"
                  tooltip: root.tr("delete_playlist")
                  onActivated: if (root.group) root.deletePlaylist(root.group.id)
                }
                IconButton {
                  visible: root.group && root.group.kind === "channel"
                  icon: "close"
                  tooltip: root.tr("remove_channel")
                  onActivated: if (root.group) root.removeChannel(root.group.id)
                }
                IconButton {
                  visible: root.group && root.group.kind === "mix"
                  icon: "plus"
                  tooltip: root.tr("save_as_playlist")
                  onActivated: if (root.group) root.saveMixAsPlaylist(root.group.mix)
                }
              }
            }

            ListView {
              anchors.top: root.group ? groupHeader.bottom : parent.top
              anchors.topMargin: root.group ? Style.space(8) : 0
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              visible: !!root.group
              clip: true
              spacing: Style.space(2)
              model: root.groupItems
              delegate: TrackRow {
                required property var modelData
                required property int index
                width: ListView.view.width
                track: modelData
                active: root.currentTrackId === modelData.id
                playing: active && root.playing
                coverSrc: (root.session && modelData.cover) ? Model.coverUrl(modelData, root.session.token) : ""
                onActivated: root.playFromList(root.groupItems.map(function(t) { return t.id }), index)
                onMenuRequested: root.openTrackMenu(modelData.id)
              }
              footer: Column {
                width: ListView.view ? ListView.view.width : 0
                topPadding: Style.space(6)
                spacing: Style.space(6)
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !root.groupLoading && root.groupItems.length === 0
                  text: root.tr("nothing_here")
                  color: Qt.darker(Color.foreground, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Button {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !root.groupDone && !root.groupLoading && root.groupItems.length > 0
                  text: root.tr("load_more")
                  foreground: Color.foreground
                  bordered: true
                  onClicked: root.loadGroupPage()
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: root.groupLoading
                  text: root.tr("loading")
                  color: Qt.darker(Color.foreground, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            // chips + chip body (only when not drilled into a group)
            Column {
              id: chipArea
              visible: !root.group
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              spacing: Style.space(8)

              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: [["tracks", root.tr("lib_tracks")], ["playlists", root.tr("lib_playlists")], ["liked", root.tr("lib_liked")], ["artists", root.tr("lib_artists")], ["albums", root.tr("lib_albums")], ["genres", root.tr("lib_genres")], ["channels", root.tr("lib_channels")]]
                  Rectangle {
                    required property var modelData
                    readonly property bool on: root.libChip === modelData[0]
                    width: chipLabel.implicitWidth + Style.space(20); height: Style.space(26)
                    radius: height / 2
                    color: on ? Style.selectedFillFor(Color.foreground, Color.accent) : Style.hoverFillFor(Color.foreground, Color.accent)
                    Text {
                      id: chipLabel
                      anchors.centerIn: parent
                      text: modelData[1]
                      color: parent.on ? Color.accent : Qt.darker(Color.foreground, 1.3)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setLibChip(modelData[0]) }
                  }
                }
              }

              // tracks chip
              ListView {
                width: parent.width
                height: parent.height - Style.space(34)
                visible: root.libChip === "tracks"
                clip: true
                spacing: Style.space(2)
                model: root.tracks
                delegate: TrackRow {
                  required property var modelData
                  required property int index
                  width: ListView.view.width
                  track: modelData
                  active: root.currentTrackId === modelData.id
                  playing: active && root.playing
                  coverSrc: (root.session && modelData.cover) ? Model.coverUrl(modelData, root.session.token) : ""
                  onActivated: root.playFromList(root.tracks.map(function(t) { return t.id }), index)
                  onMenuRequested: root.openTrackMenu(modelData.id)
                }
                footer: Column {
                  width: ListView.view ? ListView.view.width : 0
                  topPadding: Style.space(6)
                  Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.tracksNext && !root.tracksLoading
                    text: root.tr("load_more")
                    foreground: Color.foreground
                    bordered: true
                    onClicked: root.loadMoreTracks()
                  }
                }
              }

              // playlists chip
              Flickable {
                width: parent.width
                height: parent.height - Style.space(34)
                visible: root.libChip === "playlists"
                clip: true
                contentWidth: width
                contentHeight: playlistsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Column {
                  id: playlistsCol
                  width: parent.width
                  spacing: Style.space(4)
                  Button {
                    text: root.tr("new_playlist")
                    foreground: Color.foreground
                    bordered: true
                    width: parent.width
                    onClicked: root.activeSheet = "newPlaylist"
                  }
                  Repeater {
                    model: root.playlists
                    Rectangle {
                      required property var modelData
                      width: playlistsCol.width; height: Style.space(46)
                      radius: Style.cornerRadius
                      color: plHover.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"
                      Row {
                        anchors.fill: parent; anchors.margins: Style.space(8); spacing: Style.space(8)
                        Icon { name: "library"; color: Qt.darker(Color.foreground, 1.4); width: Style.space(18); height: Style.space(18); anchors.verticalCenter: parent.verticalCenter }
                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          Text { text: modelData.title; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
                          Text { text: (modelData.tracks ? modelData.tracks.length : 0) + root.tr("playlist_tracks_sub") + (modelData.followed ? root.tr("saved_sub") : ""); color: Qt.darker(Color.foreground, 1.5); font.family: Style.font.family; font.pixelSize: Style.font.caption }
                        }
                      }
                      MouseArea { id: plHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openGroup({ kind: "playlist", id: modelData.id }) }
                    }
                  }
                  Text {
                    visible: root.playlists.length === 0
                    text: root.tr("no_playlists")
                    color: Qt.darker(Color.foreground, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    topPadding: Style.space(8)
                  }
                }
              }

              // artists / albums / genres chip
              Flickable {
                width: parent.width
                height: parent.height - Style.space(34)
                visible: root.libChip === "artists" || root.libChip === "albums" || root.libChip === "genres"
                clip: true
                contentWidth: width
                contentHeight: groupsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Column {
                  id: groupsCol
                  width: parent.width
                  spacing: Style.space(2)
                  Repeater {
                    model: root.groupsListItems
                    Rectangle {
                      required property var modelData
                      width: groupsCol.width; height: Style.space(42)
                      radius: Style.cornerRadius
                      color: gHover.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"
                      Row {
                        anchors.fill: parent; anchors.margins: Style.space(8)
                        Text {
                          width: parent.width - Style.space(50)
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.name || root.tr("unknown")
                          color: Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.body
                          elide: Text.ElideRight
                        }
                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: (modelData.n || 0) + root.tr("playlist_tracks_sub")
                          color: Qt.darker(Color.foreground, 1.5)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                      }
                      MouseArea { id: gHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openGroup({ kind: root.libChip, name: modelData.name }) }
                    }
                  }
                  Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !root.groupsListDone && !root.groupsListLoading
                    text: root.tr("load_more")
                    foreground: Color.foreground
                    bordered: true
                    onClicked: root.loadGroupsList(root.libChip)
                  }
                }
              }

              // channels chip
              Flickable {
                width: parent.width
                height: parent.height - Style.space(34)
                visible: root.libChip === "channels"
                clip: true
                contentWidth: width
                contentHeight: channelsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Column {
                  id: channelsCol
                  width: parent.width
                  spacing: Style.space(4)
                  Button {
                    text: root.tr("connect_channel")
                    foreground: Color.foreground
                    bordered: true
                    width: parent.width
                    onClicked: root.activeSheet = "connectChannel"
                  }
                  Repeater {
                    model: root.myChannels
                    Rectangle {
                      required property var modelData
                      width: channelsCol.width; height: Style.space(46)
                      radius: Style.cornerRadius
                      color: cHover.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"
                      Row {
                        anchors.fill: parent; anchors.margins: Style.space(8); spacing: Style.space(8)
                        Icon { name: "music"; color: Qt.darker(Color.foreground, 1.4); width: Style.space(18); height: Style.space(18); anchors.verticalCenter: parent.verticalCenter }
                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          Text { text: modelData.title || modelData.username || root.tr("channel_word"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
                          Text { text: modelData.status || ""; color: Qt.darker(Color.foreground, 1.5); font.family: Style.font.family; font.pixelSize: Style.font.caption }
                        }
                      }
                      MouseArea { id: cHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openGroup({ kind: "channel", id: modelData.id }) }
                    }
                  }
                  Text {
                    visible: root.myChannels.length === 0
                    text: root.tr("no_channels")
                    color: Qt.darker(Color.foreground, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    topPadding: Style.space(8)
                  }
                }
              }
            }
          }
        }
      }

      // ---- now playing (mini bar) ----
      Rectangle {
        id: nowPlayingBar
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
          trackColor: Style.hoverFillFor(Color.foreground, Color.accent)
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
          id: nowPlayingInfo
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: Style.space(4)
          spacing: Style.space(6)

          Rectangle {
            width: Style.space(38); height: Style.space(38)
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
              width: Style.space(16); height: Style.space(16)
            }

            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activeSheet = "nowPlaying" }
          }

          Column {
            width: Style.space(66)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.currentTitle
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
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

        // Every control the site puts in its expanded Now Playing view is
        // reachable right from the mini bar too — the panel has the width
        // to spare, and having to open a sheet just to hit shuffle or like
        // made those feel broken/missing.
        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: Style.space(4)
          spacing: Style.space(3)

          IconButton {
            icon: "shuffle"
            active: root.shuffleOn
            size: Style.space(24)
            onActivated: root.toggleShuffle()
          }
          IconButton {
            icon: "previous"
            size: Style.space(24)
            onActivated: root.playPrevTrack()
          }
          Rectangle {
            width: Style.space(32); height: Style.space(32)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: Color.accent
            Icon {
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: root.playing ? 0 : 1
              name: root.playing ? "pause" : "play"
              color: Color.background
              width: Style.space(14); height: Style.space(14)
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePlayback() }
          }
          IconButton {
            icon: "next"
            size: Style.space(24)
            onActivated: root.playNextTrack(false)
          }
          IconButton {
            icon: root.repeatMode === "one" ? "repeatOne" : "repeat"
            active: root.repeatMode !== "off"
            size: Style.space(24)
            onActivated: root.cycleRepeat()
          }
          IconButton {
            icon: root.currentTrackId !== null && root.isLiked(root.currentTrackId) ? "heartFilled" : "heart"
            active: root.currentTrackId !== null && root.isLiked(root.currentTrackId)
            size: Style.space(24)
            onActivated: if (root.currentTrackId !== null) root.toggleLike(root.currentTrackId)
          }
          IconButton {
            icon: "queue"
            size: Style.space(24)
            onActivated: root.activeSheet = "queue"
          }
        }
      }

      // =====================================================================
      // Sheets — one scrim + card overlay, content switched by root.activeSheet.
      // Mirrors the site's own bottom-sheet framework (ui/sheets.js).
      // =====================================================================
      Rectangle {
        id: sheetScrim
        visible: root.activeSheet !== ""
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        z: 50

        MouseArea { anchors.fill: parent; onClicked: root.closeSheet() }

        Rectangle {
          id: sheetCard
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.min(parent.height - Style.space(30), sheetFlick.contentHeight + Style.space(28))
          radius: Style.cornerRadius
          color: Color.popups.background
          border.width: Math.max(1, Style.space(1))
          border.color: Color.popups.border

          MouseArea { anchors.fill: parent }  // swallow clicks so they don't close the sheet

          Flickable {
            id: sheetFlick
            anchors.fill: parent
            anchors.margins: Style.space(14)
            clip: true
            contentWidth: width
            contentHeight: sheetContent.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: sheetContent
              width: parent.width
              spacing: Style.space(10)

              // ---- track menu ----
              Column {
                width: parent.width
                spacing: Style.space(2)
                visible: root.activeSheet === "trackMenu"
                readonly property var t: root.sheetTrackId !== null ? root.trackById[root.sheetTrackId] : null

                Text { text: parent.t ? Model.trackTitle(parent.t) : ""; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; elide: Text.ElideRight; width: parent.width }
                Text { text: parent.t ? Model.trackArtist(parent.t) : ""; visible: text !== ""; color: Qt.darker(Color.foreground, 1.5); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; bottomPadding: Style.space(8) }

                SheetOption { icon: "next"; label: root.tr("play_next"); onActivated: { root.playNextInQueue(root.sheetTrackId); root.closeSheet() } }
                SheetOption { icon: "queue"; label: root.tr("add_to_queue"); onActivated: { root.appendToQueue(root.sheetTrackId); root.closeSheet() } }
                SheetOption {
                  icon: root.sheetTrackId !== null && root.isLiked(root.sheetTrackId) ? "heartFilled" : "heart"
                  label: root.sheetTrackId !== null && root.isLiked(root.sheetTrackId) ? root.tr("unlike") : root.tr("like")
                  onActivated: if (root.sheetTrackId !== null) root.toggleLike(root.sheetTrackId)
                }
                SheetOption { icon: "plus"; label: root.tr("add_to_playlist"); onActivated: root.openPlaylistPicker(root.sheetTrackId) }
                SheetOption {
                  visible: parent.t && parent.t.performer
                  icon: "library"; label: root.tr("go_to_artist")
                  onActivated: { root.closeSheet(); root.openGroup({ kind: "artists", name: parent.t.performer }) }
                }
                SheetOption {
                  visible: parent.t && parent.t.album
                  icon: "library"; label: root.tr("go_to_album")
                  onActivated: { root.closeSheet(); root.openGroup({ kind: "albums", name: parent.t.album }) }
                }
              }

              // ---- playlist picker ----
              Column {
                width: parent.width
                spacing: Style.space(2)
                visible: root.activeSheet === "playlistPicker"
                Text { text: root.tr("add_to_playlist"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; bottomPadding: Style.space(6) }
                Repeater {
                  model: root.playlists.filter(function(p) { return !p.followed })
                  SheetOption {
                    required property var modelData
                    icon: root.sheetTrackId !== null && modelData.tracks.indexOf(root.sheetTrackId) >= 0 ? "check" : "plus"
                    label: modelData.title
                    onActivated: if (root.sheetTrackId !== null) root.togglePlaylistMembership(modelData.id, root.sheetTrackId)
                  }
                }
                SheetOption { icon: "plus"; label: root.tr("new_playlist_ellipsis"); onActivated: root.activeSheet = "newPlaylist" }
              }

              // ---- new playlist ----
              Column {
                width: parent.width
                spacing: Style.space(8)
                visible: root.activeSheet === "newPlaylist"
                Text { text: root.tr("new_playlist"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
                TextField {
                  id: newPlaylistField
                  width: parent.width
                  placeholderText: root.tr("name_placeholder")
                  font.family: Style.font.family
                  text: root.newPlaylistName
                  onTextChanged: root.newPlaylistName = text
                  Keys.onReturnPressed: root.submitNewPlaylist()
                }
                Button {
                  text: root.playlistBusy ? root.tr("creating") : root.tr("create")
                  foreground: Color.background
                  background: Color.accent
                  bordered: false
                  horizontalPadding: Style.space(16)
                  verticalPadding: Style.space(7)
                  onClicked: root.submitNewPlaylist()
                }
              }

              // ---- connect channel ----
              Column {
                width: parent.width
                spacing: Style.space(8)
                visible: root.activeSheet === "connectChannel"
                Text { text: root.tr("connect_title"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
                Text { text: root.tr("connect_hint"); color: Qt.darker(Color.foreground, 1.5); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap; width: parent.width }
                TextField {
                  id: connectField
                  width: parent.width
                  placeholderText: root.tr("connect_placeholder")
                  font.family: Style.font.family
                  text: root.connectRef
                  onTextChanged: root.connectRef = text
                  Keys.onReturnPressed: root.submitConnect()
                }
                Button {
                  text: root.connectBusy ? root.tr("connecting") : root.tr("connect")
                  foreground: Color.background
                  background: Color.accent
                  bordered: false
                  horizontalPadding: Style.space(16)
                  verticalPadding: Style.space(7)
                  onClicked: root.submitConnect()
                }
                Text { visible: root.connectMsg !== ""; text: root.connectMsg; color: Qt.darker(Color.foreground, 1.5); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
              }

              // ---- sleep timer ----
              Column {
                width: parent.width
                spacing: Style.space(2)
                visible: root.activeSheet === "sleepTimer"
                Text {
                  text: root.tr("sleep_timer") + (root.sleepMinutesLeft >= 0 ? root.tr("min_left", { n: root.sleepMinutesLeft }) : root.sleepEndOfTrack ? root.tr("end_of_track_tag") : "")
                  color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; bottomPadding: Style.space(6)
                }
                Repeater {
                  model: [15, 30, 45, 60]
                  SheetOption { required property int modelData; icon: "timer"; label: root.tr("n_minutes", { n: modelData }); onActivated: { root.setSleep(modelData); root.closeSheet() } }
                }
                SheetOption { icon: "music"; label: root.tr("end_of_track"); active: root.sleepEndOfTrack; onActivated: { root.setSleep("track"); root.closeSheet() } }
                SheetOption { icon: "close"; label: root.tr("off"); active: root.sleepMinutesLeft < 0 && !root.sleepEndOfTrack; onActivated: { root.setSleep(null); root.closeSheet() } }
              }

              // ---- settings ----
              Column {
                width: parent.width
                spacing: Style.space(14)
                visible: root.activeSheet === "settings"
                Column {
                  width: parent.width
                  spacing: Style.space(2)
                  Text { text: root.tr("language"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; bottomPadding: Style.space(4) }
                  Text { text: root.tr("language_hint"); color: Qt.darker(Color.foreground, 1.5); font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; width: parent.width; bottomPadding: Style.space(4) }
                  SheetOption { icon: "globe"; label: "English"; active: root.session && root.session.lang === "en"; onActivated: root.saveLangChoice("en") }
                  SheetOption { icon: "globe"; label: "فارسی"; active: root.session && root.session.lang === "fa"; onActivated: root.saveLangChoice("fa") }
                }
                Column {
                  width: parent.width
                  spacing: Style.space(2)
                  Text { text: root.tr("notifications"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; bottomPadding: Style.space(4) }
                  Repeater {
                    model: [["all", root.tr("notif_all")], ["weekly", root.tr("notif_weekly")], ["off", root.tr("notif_off")]]
                    SheetOption {
                      required property var modelData
                      icon: modelData[0] === "off" ? "close" : "bell"
                      label: modelData[1]
                      active: root.session && root.session.notify === modelData[0]
                      onActivated: root.saveNotifyChoice(modelData[0])
                    }
                  }
                }
              }

              // ---- queue ----
              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: root.activeSheet === "queue"
                Text { text: root.tr("queue"); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
                Text { visible: root.currentTrackId !== null; text: root.tr("now_playing"); color: Qt.darker(Color.foreground, 1.5); font.family: Style.font.family; font.pixelSize: Style.font.caption }
                TrackRow {
                  visible: root.currentTrackId !== null
                  width: parent.width
                  track: root.currentTrack
                  active: true
                  playing: root.playing
                  showMenu: false
                  coverSrc: root.currentCover
                }
                Text {
                  visible: root.queueIndex + 1 < root.queueIds.length
                  text: root.tr("up_next") + " · " + (root.queueIds.length - root.queueIndex - 1)
                  color: Qt.darker(Color.foreground, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  topPadding: Style.space(6)
                }
                Repeater {
                  model: root.queueIds.slice(root.queueIndex + 1)
                  Item {
                    id: queueRow
                    required property var modelData
                    required property int index
                    width: sheetContent.width
                    height: Style.space(52)
                    readonly property var queuedTrack: root.trackById[modelData]
                    TrackRow {
                      anchors.left: parent.left
                      anchors.right: removeBtn.left
                      width: parent.width - Style.space(30)
                      track: queueRow.queuedTrack
                      showMenu: false
                      coverSrc: (root.session && queueRow.queuedTrack && queueRow.queuedTrack.cover) ? Model.coverUrl(queueRow.queuedTrack, root.session.token) : ""
                      onActivated: root.jumpToQueueIndex(root.queueIndex + 1 + index)
                    }
                    IconButton {
                      id: removeBtn
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      icon: "close"
                      onActivated: root.removeFromQueue(root.queueIndex + 1 + index)
                    }
                  }
                }
                Text {
                  visible: root.queueIndex + 1 >= root.queueIds.length
                  text: root.tr("nothing_queued")
                  color: Qt.darker(Color.foreground, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Button {
                  visible: root.queueIndex + 1 < root.queueIds.length
                  text: root.tr("clear_up_next")
                  foreground: Color.urgent
                  bordered: true
                  onClicked: root.clearUpNext()
                }
              }

              // ---- now playing (full) ----
              Column {
                width: parent.width
                spacing: Style.space(10)
                visible: root.activeSheet === "nowPlaying"

                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Style.space(160); height: Style.space(160)
                  radius: Style.cornerRadius
                  color: Style.hoverFillFor(Color.foreground, Color.accent)
                  clip: true
                  Image { anchors.fill: parent; visible: root.currentCover !== ""; source: root.currentCover; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                  Icon { visible: root.currentCover === ""; anchors.centerIn: parent; name: "music"; color: Qt.darker(Color.foreground, 1.5); width: Style.space(48); height: Style.space(48) }
                }

                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.currentTitle; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.currentArtist; color: Qt.darker(Color.foreground, 1.5); font.family: Style.font.family; font.pixelSize: Style.font.body }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(18)
                  IconButton { icon: "shuffle"; active: root.shuffleOn; onActivated: root.toggleShuffle() }
                  IconButton { icon: "previous"; size: Style.space(30); onActivated: root.playPrevTrack() }
                  Rectangle {
                    width: Style.space(46); height: Style.space(46)
                    radius: width / 2
                    color: Color.accent
                    anchors.verticalCenter: parent.verticalCenter
                    Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: root.playing ? 0 : 1; name: root.playing ? "pause" : "play"; color: Color.background; width: Style.space(20); height: Style.space(20) }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePlayback() }
                  }
                  IconButton { icon: "next"; size: Style.space(30); onActivated: root.playNextTrack(false) }
                  IconButton { icon: root.repeatMode === "one" ? "repeatOne" : "repeat"; active: root.repeatMode !== "off"; onActivated: root.cycleRepeat() }
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(28)
                  topPadding: Style.space(6)
                  IconButton {
                    icon: root.currentTrackId !== null && root.isLiked(root.currentTrackId) ? "heartFilled" : "heart"
                    active: root.currentTrackId !== null && root.isLiked(root.currentTrackId)
                    onActivated: if (root.currentTrackId !== null) root.toggleLike(root.currentTrackId)
                  }
                  IconButton { icon: "queue"; onActivated: root.activeSheet = "queue" }
                  IconButton { icon: "timer"; active: root.sleepMinutesLeft >= 0 || root.sleepEndOfTrack; onActivated: root.activeSheet = "sleepTimer" }
                }
              }
            }
          }
        }
      }
    }
  }

  // Reusable label for group-detail titles.
  function groupTitle() {
    var g = root.group
    if (!g) return ""
    if (g.kind === "playlist") { var pl = root.playlists.find(function(p) { return p.id === g.id }); return pl ? pl.title : "Playlist" }
    if (g.kind === "liked") return "Liked Songs"
    if (g.kind === "channel") return root.channelDetail ? (root.channelDetail.title || root.channelDetail.username || "Channel") : "Channel"
    if (g.kind === "mix") return g.mix.charAt(0).toUpperCase() + g.mix.slice(1) + " mix"
    return g.name || "Unknown"
  }

  // Track-menu convenience: queue ops target a specific id, not necessarily
  // the one currently loaded.
  function playNextInQueue(id) {
    if (id === null || id === undefined) return
    if (!root.queueIds.length) { root.playFromList([id], 0); return }
    var ids = root.queueIds.filter(function(x) { return x !== id })
    ids.splice(root.queueIndex + 1, 0, id)
    root.queueIds = ids
  }
  function appendToQueue(id) {
    if (id === null || id === undefined) return
    if (!root.queueIds.length) { root.playFromList([id], 0); return }
    if (root.queueIds.indexOf(id) >= 0) return
    root.queueIds = root.queueIds.concat([id])
  }

  ConfirmDialog {
    anchors.fill: parent
    opened: root.signOutConfirmOpen
    message: root.tr("sign_out_confirm")
    confirmText: root.tr("sign_out")
    onCanceled: root.signOutConfirmOpen = false
    onConfirmed: root.signOut()
  }
}

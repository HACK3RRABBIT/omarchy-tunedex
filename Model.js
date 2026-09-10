// Pure helpers for the Tunedex plugin: URL/curl building and response parsing.
// No DOM, no QML — everything here is testable with plain JS. Mirrors the
// contract reverse-engineered from https://tunedex.shahriarshm.com's own
// static/js/{api,session}.js (the site ships a documented browser sign-in
// flow — /api/login/start + /api/login/poll — specifically for non-Telegram
// clients like this one).

var BASE = "https://tunedex.shahriarshm.com"

// ---- icons (exact path data lifted from the site's own SVG sprite) ----
var ICONS = {
  play:        { filled: true,  d: "M8 5.5a1 1 0 011.5-.86l10 6.5a1 1 0 010 1.72l-10 6.5A1 1 0 018 18.5z" },
  pause:       { filled: true,  d: "M6 5a1 1 0 011-1h2.5a1 1 0 011 1v14a1 1 0 01-1 1H7a1 1 0 01-1-1zM13.5 5a1 1 0 011-1H17a1 1 0 011 1v14a1 1 0 01-1 1h-2.5a1 1 0 01-1-1z" },
  previous:    { filled: true,  d: "M5 6a1 1 0 012 0v12a1 1 0 01-2 0zM19 6.6a1 1 0 00-1.55-.83L9.6 11.17a1 1 0 000 1.66l7.85 5.4A1 1 0 0019 17.4z" },
  next:        { filled: true,  d: "M17 6a1 1 0 012 0v12a1 1 0 01-2 0zM5 6.6a1 1 0 011.55-.83l7.85 5.4a1 1 0 010 1.66l-7.85 5.4A1 1 0 015 17.4z" },
  shuffle:     { filled: false, d: "M16 4l4 3.5-4 3.5M20 7.5h-4.2a4 4 0 00-3.2 1.6L8.4 15.2A4 4 0 015.2 16.8H3M16 13l4 3.5-4 3.5M20 16.5h-4.2a4 4 0 01-3.2-1.6l-.9-1.2M3 7.5h2.2a4 4 0 013.2 1.6l.9 1.2" },
  repeat:      { filled: false, d: "M17 3l3.5 3.5L17 10M3.5 12v-1.5a4 4 0 014-4h13M7 21l-3.5-3.5L7 14M20.5 12v1.5a4 4 0 01-4 4h-13" },
  repeatOne:   { filled: false, d: "M17 3l3.5 3.5L17 10M3.5 12v-1.5a4 4 0 014-4h13M7 21l-3.5-3.5L7 14M20.5 12v1.5a4 4 0 01-4 4h-13M12.5 9.5v5M11 10.8l1.5-1.3" },
  heart:       { filled: false, d: "M12 20.3S3.3 15.2 3.3 9.4A4.4 4.4 0 0112 7.3a4.4 4.4 0 018.7 2.1c0 5.8-8.7 10.9-8.7 10.9z" },
  heartFilled: { filled: true,  d: "M12 21s-9.5-5.5-9.5-11.8A5.1 5.1 0 0112 6.4a5.1 5.1 0 019.5 2.8C21.5 15.5 12 21 12 21z" },
  search:      { filled: false, d: "M4.5,11 a6.5,6.5 0 1,0 13,0 a6.5,6.5 0 1,0 -13,0 M20 20l-4.3-4.3" },
  close:       { filled: false, d: "M6 6l12 12M18 6L6 18" },
  chevronDown: { filled: false, d: "M6 9.5l6 6 6-6" },
  logout:      { filled: false, d: "M10 4H6a2 2 0 00-2 2v12a2 2 0 002 2h4M15 8l4 4-4 4M19 12H9" },
  music:       { filled: false, d: "M9 17.5V6l11-2.5v11.5 M4,17.5 a2.5,2.5 0 1,0 5,0 a2.5,2.5 0 1,0 -5,0 M15,15 a2.5,2.5 0 1,0 5,0 a2.5,2.5 0 1,0 -5,0" },
  plus:        { filled: false, d: "M12 5v14M5 12h14" },
  check:       { filled: false, d: "M5 12.5l4.5 4.5L19 7.5" },
  timer:       { filled: false, d: "M9.5 2.5h5M12 8v5l3 2 M4.5,13.5 a7.5,7.5 0 1,0 15,0 a7.5,7.5 0 1,0 -15,0" },
  queue:       { filled: false, d: "M4 6h16M4 12h16M4 18h10" },
  home:        { filled: false, d: "M3.5 10.5L12 3.5l8.5 7M5.5 9v11h13V9M10 20v-5.5h4V20" },
  library:     { filled: false, d: "M4 4.5h3v15H4zM9.5 4.5h3v15h-3zM15 5.6l2.9-.8 3.9 14.5-2.9.8z" },
  back:        { filled: false, d: "M15 5l-7 7 7 7" },
  bell:        { filled: false, d: "M6 16.5V11a6 6 0 0112 0v5.5l1.5 2h-15zM10 20.5a2 2 0 004 0" },
  globe:       { filled: false, d: "M3.5,12 a8.5,8.5 0 1,0 17,0 a8.5,8.5 0 1,0 -17,0 M3.5 12h17M12 3.5c2.5 2.5 3.8 5.3 3.8 8.5s-1.3 6-3.8 8.5c-2.5-2.5-3.8-5.3-3.8-8.5s1.3-6 3.8-8.5z" },
  settings:    { filled: false, d: "M9,12 a3,3 0 1,0 6,0 a3,3 0 1,0 -6,0 M12 2.5l1.6 2.3 2.7-.7.7 2.7 2.3 1.6-1.4 2.4 1.4 2.4-2.3 1.6-.7 2.7-2.7-.7L12 21.5l-1.6-2.3-2.7.7-.7-2.7-2.3-1.6 1.4-2.4-1.4-2.4 2.3-1.6.7-2.7 2.7.7z" },
  more:        { filled: true,  d: "M5 10.25a1.75 1.75 0 110 3.5 1.75 1.75 0 010-3.5zm7 0a1.75 1.75 0 110 3.5 1.75 1.75 0 010-3.5zm7 0a1.75 1.75 0 110 3.5 1.75 1.75 0 010-3.5z" }
}

function tzOffsetMinutes() {
  return -new Date().getTimezoneOffset()
}

function streamUrl(id, token) {
  return BASE + "/stream/" + encodeURIComponent(id) + "?t=" + encodeURIComponent(token || "")
}

function coverUrl(track, token) {
  if (!track || !track.cover) return ""
  return BASE + "/cover/" + encodeURIComponent(track.id) + "?t=" + encodeURIComponent(token || "")
}

// Token shape is `uid:exp:kind:sig`; exp is a unix-seconds expiry.
function tokenSecondsLeft(token, nowMs) {
  var parts = String(token || "").split(":")
  var exp = Number(parts[1])
  if (!isFinite(exp) || exp <= 0) return -1
  var now = nowMs || Date.now()
  return exp - Math.floor(now / 1000)
}

function formatDuration(sec) {
  var n = Math.max(0, Math.floor(Number(sec) || 0))
  var m = Math.floor(n / 60)
  var s = n % 60
  return m + ":" + (s < 10 ? "0" : "") + s
}

function trackTitle(t) {
  if (!t) return ""
  return t.title || t.file_name || "Untitled"
}

function trackArtist(t) {
  return (t && t.performer) || ""
}

// ---- curl argv builders (Quickshell Process.command wants an argv array) ----
function authStartArgs() {
  return ["curl", "-fsS", "-X", "POST", "--max-time", "10",
    "-H", "Content-Type: application/json",
    "-d", JSON.stringify({ tz_offset: tzOffsetMinutes() }),
    BASE + "/api/login/start"]
}

// These four all carry a bearer token (or gate a login code) and need the
// real HTTP status back — a 401 means "refresh the token and retry", which
// curl's blanket -f/--fail can't distinguish from a network hiccup. -w
// appends a status line after the body; the caller splits it off.
function authPollArgs(code, secret) {
  var url = BASE + "/api/login/poll?code=" + encodeURIComponent(code) +
    "&secret=" + encodeURIComponent(secret) + "&tz_offset=" + tzOffsetMinutes()
  return ["curl", "-sS", "-o", "-", "-w", "\n%{http_code}", "--max-time", "10", url]
}

function authRefreshArgs(token) {
  return ["curl", "-sS", "-o", "-", "-w", "\n%{http_code}", "-X", "POST", "--max-time", "10",
    "-H", "Authorization: Bearer " + token,
    "-H", "Content-Type: application/json",
    "-d", JSON.stringify({ tz_offset: tzOffsetMinutes() }),
    BASE + "/api/auth/refresh"]
}

function libraryArgs(token) {
  return ["curl", "-sS", "-o", "-", "-w", "\n%{http_code}", "--max-time", "10",
    "-H", "Authorization: Bearer " + token, BASE + "/api/library"]
}

function tracksArgs(token, cursor) {
  var url = BASE + "/api/tracks?limit=50"
  if (cursor) url += "&cursor=" + encodeURIComponent(cursor)
  return ["curl", "-sS", "-o", "-", "-w", "\n%{http_code}", "--max-time", "10",
    "-H", "Authorization: Bearer " + token, url]
}

function searchArgs(token, q) {
  var url = BASE + "/api/search?q=" + encodeURIComponent(q)
  return ["curl", "-sS", "-o", "-", "-w", "\n%{http_code}", "--max-time", "10",
    "-H", "Authorization: Bearer " + token, url]
}

// Generic authenticated request — every mutation (likes, playlists, channels,
// settings) is one of these, method + path + optional JSON body.
function apiArgs(token, method, path, body) {
  var args = ["curl", "-sS", "-o", "-", "-w", "\n%{http_code}", "-X", method, "--max-time", "10",
    "-H", "Authorization: Bearer " + token]
  if (body !== undefined) args.push("-H", "Content-Type: application/json", "-d", JSON.stringify(body))
  args.push(BASE + path)
  return args
}

function likeArgs(token, id, liked) { return apiArgs(token, liked ? "DELETE" : "PUT", "/api/likes/" + encodeURIComponent(id)) }
function createPlaylistArgs(token, title) { return apiArgs(token, "POST", "/api/playlists", { title: title }) }
function deletePlaylistArgs(token, pid) { return apiArgs(token, "DELETE", "/api/playlists/" + encodeURIComponent(pid)) }
function addToPlaylistArgs(token, pid, trackId) { return apiArgs(token, "POST", "/api/playlists/" + encodeURIComponent(pid) + "/items", { recording_id: trackId }) }
function removeFromPlaylistArgs(token, pid, trackId) { return apiArgs(token, "DELETE", "/api/playlists/" + encodeURIComponent(pid) + "/items/" + encodeURIComponent(trackId)) }
function connectChannelArgs(token, ref) { return apiArgs(token, "POST", "/api/channels/connect", { ref: ref }) }
function removeChannelArgs(token, id) { return apiArgs(token, "DELETE", "/api/channels/" + encodeURIComponent(id)) }
function channelArgs(token, id) { return apiArgs(token, "GET", "/api/channels/" + encodeURIComponent(id)) }
function saveLangArgs(token, lang) { return apiArgs(token, "PATCH", "/api/me", { lang: lang }) }
function saveNotifyArgs(token, notify) { return apiArgs(token, "PATCH", "/api/me", { notify: notify }) }
function saveMixArgs(token, kind) { return apiArgs(token, "POST", "/api/mixes/" + encodeURIComponent(kind) + "/save") }

function groupTracksArgs(token, kind, name, cursor) {
  var FILTER = { artists: "artist", albums: "album", genres: "genre" }
  var url = "/api/tracks?limit=50&" + FILTER[kind] + "=" + encodeURIComponent(name || "")
  if (cursor) url += "&cursor=" + encodeURIComponent(cursor)
  return apiArgs(token, "GET", url)
}
function tracksByIdsArgs(token, ids) {
  return apiArgs(token, "GET", "/api/tracks?ids=" + ids.join(","))
}
function channelTracksArgs(token, channelId, cursor) {
  var url = "/api/tracks?limit=50&channel=" + encodeURIComponent(channelId)
  if (cursor) url += "&cursor=" + encodeURIComponent(cursor)
  return apiArgs(token, "GET", url)
}
function groupsArgs(token, kind, offset) {
  return apiArgs(token, "GET", "/api/library/groups?kind=" + encodeURIComponent(kind) + "&limit=100&offset=" + (offset || 0))
}
function mixesArgs(token) { return apiArgs(token, "GET", "/api/mixes") }
function mixItemsArgs(token, kind) { return apiArgs(token, "GET", "/api/mixes/" + encodeURIComponent(kind)) }
function recentsArgs(token) { return apiArgs(token, "GET", "/api/recents?limit=20") }
function homeArgs(token) { return apiArgs(token, "GET", "/api/home") }
function discoverArgs(token) { return apiArgs(token, "GET", "/api/discover") }

// ---- response parsing (defensive: curl/network hiccups should never throw) ----
function parseJson(raw, fallback) {
  try {
    var v = JSON.parse(String(raw || ""))
    return v === undefined ? fallback : v
  } catch (e) {
    return fallback
  }
}

// Response shape from the four "-w" curl builders above: "<body>\n<http_code>".
// -1 status means the request itself failed (network down, timeout) before
// any response was written.
function splitHttpOutput(raw) {
  var s = String(raw || "")
  var i = s.lastIndexOf("\n")
  if (i < 0) return { status: -1, body: "" }
  var code = parseInt(s.slice(i + 1), 10)
  return { status: isFinite(code) ? code : -1, body: s.slice(0, i) }
}

function parseSession(json) {
  if (!json || typeof json.token !== "string" || !json.token) return null
  return {
    token: json.token,
    user: json.user || null,
    admin: !!json.admin,
    notify: json.notify || "weekly",
    langChosen: !!json.lang_chosen,
    bot: json.bot || "TunedexAppBot"
  }
}

function parseLibrary(json) {
  json = json || {}
  return {
    nTracks: json.n_tracks || 0,
    playlists: json.playlists || [],
    channels: json.channels || [],
    likes: json.likes || [],
    suggested: json.suggested || []
  }
}

function parseTracksPage(json) {
  json = json || {}
  return { items: json.items || [], next: json.next || null }
}

function parseSearch(json) {
  json = json || {}
  return { tracks: json.tracks || [], artists: json.artists || [], albums: json.albums || [] }
}

function parseChannel(json) {
  json = json || {}
  return { id: json.id, title: json.title || "", username: json.username || "", cover_id: json.cover_id || null,
    n_tracks: json.n_tracks || 0, tracks: json.tracks || [], next: json.next || null, kind: json.kind || "channel" }
}

function parseGroupsPage(json) {
  json = json || {}
  return json.items || []
}

function parseMixes(json) {
  json = json || {}
  return json.mixes || []
}

// Boot payload shapes for Home: items carry a `reason` (for_you/discover),
// tag with the seed id up front so recommendation context survives.
function tagReasons(items) {
  var out = []
  for (var i = 0; i < items.length; i++) {
    var t = items[i]
    t._seed = (t.reason && t.reason.seed) || null
    out.push(t)
  }
  return out
}
function parseHome(json) {
  json = json || {}
  return { items: tagReasons(json.items || []), needsConnection: !!json.needs_connection }
}
function parseDiscover(json) {
  json = json || {}
  return tagReasons(json.items || [])
}

if (typeof module !== "undefined") {
  module.exports = {
    BASE: BASE, ICONS: ICONS,
    tzOffsetMinutes: tzOffsetMinutes, streamUrl: streamUrl, coverUrl: coverUrl,
    tokenSecondsLeft: tokenSecondsLeft, formatDuration: formatDuration,
    trackTitle: trackTitle, trackArtist: trackArtist,
    authStartArgs: authStartArgs, authPollArgs: authPollArgs, authRefreshArgs: authRefreshArgs,
    libraryArgs: libraryArgs, tracksArgs: tracksArgs, searchArgs: searchArgs,
    apiArgs: apiArgs, likeArgs: likeArgs,
    createPlaylistArgs: createPlaylistArgs, deletePlaylistArgs: deletePlaylistArgs,
    addToPlaylistArgs: addToPlaylistArgs, removeFromPlaylistArgs: removeFromPlaylistArgs,
    connectChannelArgs: connectChannelArgs, removeChannelArgs: removeChannelArgs, channelArgs: channelArgs,
    saveLangArgs: saveLangArgs, saveNotifyArgs: saveNotifyArgs, saveMixArgs: saveMixArgs,
    groupTracksArgs: groupTracksArgs, channelTracksArgs: channelTracksArgs, groupsArgs: groupsArgs,
    tracksByIdsArgs: tracksByIdsArgs,
    mixesArgs: mixesArgs, mixItemsArgs: mixItemsArgs, recentsArgs: recentsArgs,
    homeArgs: homeArgs, discoverArgs: discoverArgs,
    parseJson: parseJson, splitHttpOutput: splitHttpOutput,
    parseSession: parseSession, parseLibrary: parseLibrary,
    parseTracksPage: parseTracksPage, parseSearch: parseSearch,
    parseChannel: parseChannel, parseGroupsPage: parseGroupsPage, parseMixes: parseMixes,
    parseHome: parseHome, parseDiscover: parseDiscover
  }
}

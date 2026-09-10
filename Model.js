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
  music:       { filled: false, d: "M9 17.5V6l11-2.5v11.5 M4,17.5 a2.5,2.5 0 1,0 5,0 a2.5,2.5 0 1,0 -5,0 M15,15 a2.5,2.5 0 1,0 5,0 a2.5,2.5 0 1,0 -5,0" }
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

if (typeof module !== "undefined") {
  module.exports = {
    BASE: BASE, ICONS: ICONS,
    tzOffsetMinutes: tzOffsetMinutes, streamUrl: streamUrl, coverUrl: coverUrl,
    tokenSecondsLeft: tokenSecondsLeft, formatDuration: formatDuration,
    trackTitle: trackTitle, trackArtist: trackArtist,
    authStartArgs: authStartArgs, authPollArgs: authPollArgs, authRefreshArgs: authRefreshArgs,
    libraryArgs: libraryArgs, tracksArgs: tracksArgs, searchArgs: searchArgs,
    parseJson: parseJson, splitHttpOutput: splitHttpOutput,
    parseSession: parseSession, parseLibrary: parseLibrary,
    parseTracksPage: parseTracksPage, parseSearch: parseSearch
  }
}

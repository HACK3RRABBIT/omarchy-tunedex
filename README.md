# Tunedex — Omarchy bar plugin

An unofficial third-party client for [Tunedex](https://tunedex.shahriarshm.com/)
that lives on the Omarchy bar. Sign in with your own Tunedex account and use
your whole library — playlists, likes, channels, mixes, queue — straight
from the bar, without a browser tab or a Telegram window open.

**This is not the site.** It's an independent Quickshell client for it, built
by reading Tunedex's own public JS bundle. It isn't affiliated with or
endorsed by Tunedex. It only ever acts as *you*, on *your* account, through
the sign-in flow the site ships for that exact purpose (see below) — it does
not scrape, impersonate, or touch anyone else's data. Colors follow your
Omarchy theme (`Color`/`Style` tokens), not Tunedex's own palette — it looks
like an Omarchy plugin first, Tunedex second (icon shapes stay Tunedex's own).

## What it does

- **Bar pill** — a level-meter mark that pulses while a track plays.
  Left-click opens the panel, middle-click toggles play/pause.
- **Sign in** — tap "Sign in with Telegram", confirm via the bot Tunedex
  already uses, come back. No password ever touches this plugin.
- **Home** — greeting with your name, continue listening, Liked Songs + mixes
  quick picks, latest in your library, recently played.
- **Library** — every chip the site has: Tracks, Playlists, Liked, Artists,
  Albums, Genres, Channels. Drilling into any of them (a playlist, an artist,
  a channel, a mix) gets its own screen with Play/Shuffle and the right
  actions (delete playlist, remove channel, save a mix as a playlist).
- **Search** — across your library as you type.
- **Track menu** (the "…" on every row) — play next, add to queue, like/
  unlike, add to (or remove from) a playlist, jump to the artist or album.
- **Now Playing** (tap the mini bar's cover) — full player: like, queue,
  sleep timer, shuffle, repeat (off/all/one), seekable progress, cover art.
- **Queue** — see what's up next, jump to any track, remove one, clear the
  rest.
- **Sleep timer** — 15/30/45/60 min or end-of-track.
- **Settings** — language and notification-frequency, same as the site's.
  Switching language actually re-translates the plugin's own UI (real
  strings lifted from the site's `strings/en.js`/`strings/fa.js`, not just a
  server-side preference) — layout stays left-to-right even for Persian,
  no RTL mirroring.
- **Connect a channel** / **new playlist** — right from the plugin.

Audio is decoded locally via QtMultimedia, streamed directly from Tunedex's
API with your account's token — nothing routes through a browser.

## Deliberately not covered

- **Pro / payments** — Telegram Stars charges and card payments with receipt
  upload. Real money shouldn't move through a background bar plugin; this
  shows nothing about it and never will unless that changes.
- **Admin console** — an ops panel gated to Tunedex's own operator account
  (user stats, refunds, reindexing). Not applicable to a regular account, and
  not something a widget should carry either way.
- **Telegram-native share / deep links, forum-topic sub-chips inside a
  channel, "similar tracks," drag-to-reorder the queue** — present on the
  site, cut here to keep scope sane. Tap-based queue reordering (remove +
  re-add) works instead of drag.

## How sign-in works

Tunedex is primarily a Telegram Mini App, but its own static JS
(`static/js/{api,session,ui/signin}.js`) ships a **browser/desktop login
flow** specifically for non-Telegram clients:

1. `POST /api/login/start` → a short-lived code + a Telegram deep link.
2. You confirm it from the Tunedex bot on Telegram.
3. This plugin polls `GET /api/login/poll` until the server reports it
   confirmed, then gets back the same bearer token the site's own PWA would
   store.

The token is refreshed proactively (it lasts ~12h) and persisted locally at
`~/.local/state/omarchy/settings/tunedex.json` on your machine only, the same
way Tunedex's own browser client persists it.

## Files

```
manifest.json    plugin manifest (bar-widget)
BarWidget.qml    bar pill — mark icon, level-meter animation
Panel.qml        the whole app: session, home, library, sheets, playback
Icon.qml         renders one Tunedex SVG icon as a QtQuick.Shapes path
IconButton.qml   small round icon hit-target (shuffle/repeat/settings/…)
SheetOption.qml  one row in a bottom sheet (track menu, settings, …)
TrackRow.qml     one library/search/queue list row, with its "…" menu
Model.js         pure helpers: curl/URL builders, response parsing, icon data
I18n.js          UI strings, English + Persian (real site copy, keyed the same)
```

## Limitations

- Free-tier daily stream/track caps (402/429 from the API) surface as a
  plain message; there's no in-plugin upgrade flow (see Pro, above).
- Artist/album/genre/channel/playlist/liked detail views cap at 300 tracks
  loaded (a "Load more" appears where the API paginates; ids-based lists —
  playlists, likes — fetch up to 300 in one call and stop there).
- If Tunedex changes its API shape, this breaks until updated to match.

## Install / dev loop

```sh
cp -r . ~/.config/omarchy/plugins/io.github.hack3rrabbit.tunedex
omarchy plugin validate ~/.config/omarchy/plugins/io.github.hack3rrabbit.tunedex
qmllint -I /usr/share/omarchy/shell ~/.config/omarchy/plugins/io.github.hack3rrabbit.tunedex/Panel.qml
omarchy restart shell
```

## License

MIT

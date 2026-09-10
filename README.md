# Tunedex — Omarchy bar plugin

An unofficial third-party client for [Tunedex](https://tunedex.shahriarshm.com/)
that lives on the Omarchy bar. Sign in with your own Tunedex account and play
your library straight from the bar — no browser tab, no Telegram window
kept open.

**This is not the site.** It's an independent Quickshell client for it, built
by reading Tunedex's own public JS bundle. It isn't affiliated with or
endorsed by Tunedex. It only ever acts as *you*, on *your* account, through
the sign-in flow the site ships for that exact purpose (see below) — it does
not scrape, impersonate, or touch anyone else's data.

## What it does

- **Bar pill** — the Tunedex mark; its level-meter bars pulse while a track
  plays. Left-click opens the panel, middle-click toggles play/pause.
- **Sign in** — tap "Sign in with Telegram", confirm via the bot Tunedex
  already uses, come back. No password ever touches this plugin.
- **Library + search** — your Tunedex tracks, paged; type to search.
- **Playback** — play/pause, prev/next, shuffle, repeat (off/all/one), a
  seekable progress bar, cover art. Audio is decoded locally via QtMultimedia,
  streamed directly from Tunedex's API with your account's token.

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

## Look

Colors, gradient, and icon shapes (play/pause/shuffle/repeat/…) are lifted
from Tunedex's own CSS custom properties and SVG sprite, so the panel reads
as Tunedex rather than a generic media widget skinned in the OS theme.

## Files

```
manifest.json   plugin manifest (bar-widget)
BarWidget.qml   bar pill — mark icon, level-meter animation
Panel.qml       sign-in, library/search, now-playing — the whole app
Icon.qml        renders one Tunedex SVG icon as a QtQuick.Shapes path
IconButton.qml  small round icon hit-target (shuffle/repeat/sign-out/…)
TrackRow.qml    one library/search list row
Model.js        pure helpers: curl/URL builders, response parsing, icon data
```

## Limitations

- Free-tier daily stream/track caps (402/429 from the API) surface as a
  plain message; there's no in-plugin upgrade flow.
- No playlists, likes, mixes, queue reordering, or the Telegram-channel
  library sources yet — just your flat track library and search.
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

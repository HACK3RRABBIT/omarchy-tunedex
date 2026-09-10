// Plugin UI strings — English + Persian. Values are lifted verbatim from
// Tunedex's own static/js/strings/{en,fa}.js where a matching key exists
// (same key names, so a diff against the site is easy); a handful of
// plugin-only strings (queue-sheet wording, a couple of settings lines)
// are original, written to match the site's tone. Layout stays
// left-to-right even in Persian — this plugin doesn't attempt full RTL
// mirroring — but the text itself is real Persian, not a placeholder.

var STRINGS = {
  en: {
    app_name: "Tunedex",
    tab_home: "Home", tab_library: "Library",
    search_placeholder: "Songs, artists, albums",
    signin_title: "Sign in to Tunedex",
    signin_hint_idle: "Confirms through your Tunedex bot on Telegram. No browser, no re-typing anything here.",
    signin_hint_waiting: "Confirm in Telegram, then come back — this closes on its own.",
    signin_expired: "That sign-in code expired.",
    signin_btn: "Sign in with Telegram",
    signin_waiting: "Waiting for confirmation…",
    try_again: "Try again",
    signin_manual: "or send  {code}  to @{bot}",
    sign_out: "Sign out",
    sign_out_confirm: "Sign out of Tunedex?",
    settings: "Settings",
    language: "Language",
    language_hint: "Affects notifications and content language on your Tunedex account.",
    notifications: "Notifications",
    notif_all: "Every update", notif_weekly: "Weekly digest", notif_off: "Off",
    greet_morning: "Good morning", greet_afternoon: "Good afternoon", greet_evening: "Good evening",
    continue_listening: "Continue listening",
    liked_songs: "Liked Songs",
    latest_in_library: "Latest in your library",
    recently_played: "Recently played",
    home_empty: "Nothing here yet — head to Library to connect a channel or check your tracks.",
    lib_tracks: "Tracks", lib_playlists: "Playlists", lib_liked: "Liked", lib_artists: "Artists",
    lib_albums: "Albums", lib_genres: "Genres", lib_channels: "Channels",
    new_playlist: "New playlist", no_playlists: "No playlists yet",
    connect_channel: "Connect channel", no_channels: "No channels connected", channel_word: "Channel",
    nothing_here: "Nothing here",
    load_more: "Load more", loading: "Loading…",
    no_matches: "No matches", searching: "Searching…",
    play: "Play", shuffle: "Shuffle",
    delete_playlist: "Delete playlist", remove_channel: "Remove channel", save_as_playlist: "Save as playlist",
    play_next: "Play next", add_to_queue: "Add to queue",
    like: "Like", unlike: "Unlike",
    add_to_playlist: "Add to playlist",
    go_to_artist: "Go to artist", go_to_album: "Go to album",
    new_playlist_ellipsis: "New playlist…",
    name_placeholder: "Name", create: "Create", creating: "Creating…",
    connect_title: "Connect a channel",
    connect_hint: "Paste a public @username or invite link for a Telegram channel with music.",
    connect_placeholder: "@channel or t.me/...", connect: "Connect", connecting: "Connecting…",
    sleep_timer: "Sleep timer", min_left: " — {n} min left", end_of_track_tag: " — end of track",
    n_minutes: "{n} minutes", end_of_track: "End of track", off: "Off",
    now_playing: "Now playing", up_next: "Up next",
    clear_up_next: "Clear up next", nothing_queued: "Nothing queued",
    queue: "Queue",
    track_menu_next: "Play next",
    liked_songs_tile: "Liked Songs",
    unknown: "Unknown", unknown_artist: "Unknown Artist", untitled: "Untitled",
    no_tracks: "No tracks yet", liked_empty: "Nothing here", playlist_empty: "Nothing here",
    playlist_tracks_sub: " tracks", saved_sub: " · saved",
    daily_limit: "Daily limit reached — try again tomorrow",
    playback_error: "Playback error",
    could_not_create_playlist: "Couldn't create the playlist.",
    could_not_connect: "Couldn't connect that channel.",
    connected_indexing: "Connected — indexing will start shortly."
  },
  fa: {
    app_name: "Tunedex",
    tab_home: "خانه", tab_library: "کتابخانه",
    search_placeholder: "آهنگ، هنرمند، آلبوم",
    signin_title: "ورود به Tunedex",
    signin_hint_idle: "با ربات Tunedex در تلگرام تأیید می‌شود. نیازی به مرورگر یا تایپ چیزی اینجا نیست.",
    signin_hint_waiting: "در تلگرام تأیید کنید و برگردید — این خودش بسته می‌شود.",
    signin_expired: "این کد ورود منقضی شد.",
    signin_btn: "ورود با تلگرام",
    signin_waiting: "در انتظار تأیید…",
    try_again: "دوباره تلاش کنید",
    signin_manual: "یا  {code}  را برای @{bot} بفرستید",
    sign_out: "خروج",
    sign_out_confirm: "از Tunedex خارج می‌شوید؟",
    settings: "تنظیمات",
    language: "زبان",
    language_hint: "روی اعلان‌ها و زبان محتوای حساب Tunedex شما اثر می‌گذارد.",
    notifications: "اعلان‌ها",
    notif_all: "هر به‌روزرسانی", notif_weekly: "خلاصه هفتگی", notif_off: "خاموش",
    greet_morning: "صبح بخیر", greet_afternoon: "ظهر بخیر", greet_evening: "عصر بخیر",
    continue_listening: "ادامهٔ گوش دادن",
    liked_songs: "آهنگ‌های پسندیده",
    latest_in_library: "جدیدترین‌های کتابخانهٔ شما",
    recently_played: "اخیراً پخش‌شده",
    home_empty: "هنوز چیزی اینجا نیست — برای اتصال کانال یا دیدن آهنگ‌هایتان به کتابخانه بروید.",
    lib_tracks: "آهنگ‌ها", lib_playlists: "پلی‌لیست‌ها", lib_liked: "پسندیده‌ها", lib_artists: "هنرمندان",
    lib_albums: "آلبوم‌ها", lib_genres: "سبک‌ها", lib_channels: "کانال‌ها",
    new_playlist: "پلی‌لیست جدید", no_playlists: "هنوز پلی‌لیستی نیست",
    connect_channel: "اتصال کانال", no_channels: "کانالی متصل نیست", channel_word: "کانال",
    nothing_here: "چیزی اینجا نیست",
    load_more: "بیشتر", loading: "در حال بارگذاری…",
    no_matches: "چیزی پیدا نشد", searching: "در حال جستجو…",
    play: "پخش", shuffle: "درهم",
    delete_playlist: "حذف پلی‌لیست", remove_channel: "حذف کانال", save_as_playlist: "ذخیره به‌عنوان پلی‌لیست",
    play_next: "پخش بعدی", add_to_queue: "افزودن به صف",
    like: "پسندیدن", unlike: "لغو پسند",
    add_to_playlist: "افزودن به پلی‌لیست",
    go_to_artist: "رفتن به هنرمند", go_to_album: "رفتن به آلبوم",
    new_playlist_ellipsis: "پلی‌لیست جدید…",
    name_placeholder: "نام", create: "ساختن", creating: "در حال ساختن…",
    connect_title: "اتصال کانال",
    connect_hint: "نام کاربری عمومی یا لینک دعوت کانال تلگرامی موسیقی را وارد کنید.",
    connect_placeholder: "@channel یا t.me/...", connect: "اتصال", connecting: "در حال اتصال…",
    sleep_timer: "تایمر خواب", min_left: " — {n} دقیقه مانده", end_of_track_tag: " — پایان آهنگ",
    n_minutes: "{n} دقیقه", end_of_track: "پایان آهنگ", off: "خاموش",
    now_playing: "در حال پخش", up_next: "بعدی‌ها",
    clear_up_next: "پاک کردن بعدی‌ها", nothing_queued: "صف خالی است",
    queue: "صف پخش",
    track_menu_next: "پخش بعدی",
    liked_songs_tile: "آهنگ‌های پسندیده",
    unknown: "ناشناس", unknown_artist: "هنرمند ناشناس", untitled: "بدون عنوان",
    no_tracks: "هنوز آهنگی نیست", liked_empty: "چیزی اینجا نیست", playlist_empty: "چیزی اینجا نیست",
    playlist_tracks_sub: " آهنگ", saved_sub: " · ذخیره‌شده",
    daily_limit: "سقف روزانه پر شد — فردا دوباره امتحان کنید",
    playback_error: "خطا در پخش",
    could_not_create_playlist: "پلی‌لیست ساخته نشد.",
    could_not_connect: "اتصال به آن کانال برقرار نشد.",
    connected_indexing: "متصل شد — فهرست‌کردن به‌زودی آغاز می‌شود."
  }
}

// t(lang, key, params): {name} placeholders substituted, unknown keys and
// unknown languages fall back to English, then to the bare key.
function t(langCode, key, params) {
  var table = STRINGS[langCode] || STRINGS.en
  var s = table[key]
  if (s === undefined) s = STRINGS.en[key]
  if (s === undefined) return key
  if (params) {
    for (var name in params) {
      s = s.split("{" + name + "}").join(String(params[name]))
    }
  }
  return s
}

if (typeof module !== "undefined") {
  module.exports = { STRINGS: STRINGS, t: t }
}

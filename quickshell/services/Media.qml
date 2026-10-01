pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Media — the "current player" every widget agrees on (the player card, the HUD,
// the track-change OSD, lyrics), from native MPRIS: Spotify, browsers (YouTube,
// bilibili and anything else using the Media Session API in Firefox / Edge /
// Chromium), the bilibili client, mpv…
//
// The current player is the one playing; when several play, the one that started
// last; when none does, the last one that played (so pausing doesn't jump away).
//
// `source` names where the sound comes from (SPOTIFY · YOUTUBE · BILIBILI · the
// browser · the player's own name). Video sites put junk in titles ("【MV】…
// Official Music Video", "Artist - Topic"), so `songTitle` / `songArtist` are a
// cleaned guess for lyric lookups; `title` / `artist` stay as the player sent them.
//
// MPRIS doesn't push the playback position: a widget that needs it live sets
// `wantPosition` (a count of users) and `position` then ticks every 250 ms.
Singleton {
    id: root

    readonly property var players: Mpris.players.values

    property MprisPlayer _last: null
    readonly property MprisPlayer player: {
        var ps = players, playing = []
        for (var i = 0; i < ps.length; i++) if (ps[i] && ps[i].isPlaying) playing.push(ps[i])
        if (playing.length === 1) return playing[0]
        if (playing.length > 1) return playing.indexOf(_last) >= 0 ? _last : playing[playing.length - 1]
        if (_last && ps.indexOf(_last) >= 0) return _last
        return ps.length ? ps[0] : null
    }
    onPlayerChanged: if (player && player.isPlaying) _last = player
    Connections {
        target: root.player
        function onIsPlayingChanged() { if (root.player.isPlaying) root._last = root.player }
    }

    readonly property bool   active:  player !== null
    readonly property bool   playing: player ? player.isPlaying : false
    readonly property string title:   player ? (player.trackTitle || "") : ""
    readonly property string artist:  player ? (player.trackArtist || "") : ""
    readonly property string album:   player ? (player.trackAlbum || "") : ""
    readonly property string artUrl:  player ? (player.trackArtUrl || "") : ""
    readonly property real   length:  player && player.lengthSupported && player.length > 0 ? player.length : 0
    readonly property real   position: player && player.positionSupported ? player.position : 0
    readonly property string url: {
        var m = player ? player.metadata : null
        return m && m["xesam:url"] ? String(m["xesam:url"]) : ""
    }

    // ── where it plays ──
    readonly property string source: {
        if (!player) return ""
        var id = (player.identity || "").toLowerCase()
        var bus = (player.dbusName || "").toLowerCase()
        var de = (player.desktopEntry || "").toLowerCase()
        var u = url.toLowerCase()
        if (bus.indexOf("spotify") >= 0 || id === "spotify") return "SPOTIFY"
        if (u.indexOf("youtube.com") >= 0 || u.indexOf("youtu.be") >= 0 || u.indexOf("music.youtube") >= 0) return "YOUTUBE"
        if (u.indexOf("bilibili.com") >= 0 || id.indexOf("bilibili") >= 0 || de.indexOf("bilibili") >= 0) return "BILIBILI"
        // browsers without a URL in the metadata: guess the site from the title
        var browser = bus.indexOf("firefox") >= 0 ? "FIREFOX" : bus.indexOf("edge") >= 0 ? "EDGE"
                    : bus.indexOf("chromium") >= 0 || bus.indexOf("chrome") >= 0 ? "CHROME" : ""
        if (browser !== "") {
            if (/bilibili|哔哩哔哩|嗶哩嗶哩/i.test(title)) return "BILIBILI"
            if (/youtube/i.test(title)) return "YOUTUBE"
            return browser
        }
        return (player.identity || "MEDIA").toUpperCase()
    }
    readonly property bool isVideoSite: source === "YOUTUBE" || source === "BILIBILI"
                                      || source === "FIREFOX" || source === "EDGE" || source === "CHROME"

    // ── a cleaned guess at the song, for lyrics ──
    readonly property string songArtist: _clean(title, artist).artist
    readonly property string songTitle:  _clean(title, artist).title
    function _clean(t, a) {
        var ti = t || "", ar = a || ""
        // site suffixes
        ti = ti.replace(/\s*[-_|｜]\s*(YouTube|YouTube Music|bilibili|哔哩哔哩|嗶哩嗶哩)(\s*[-_|｜].*)?$/i, "")
        ti = ti.replace(/_哔哩哔哩_bilibili$/i, "")
        // bracketed tags that aren't part of the name
        var junk = /(official|music\s*video|lyric|歌詞|歌词|字幕|中字|中文|mv|pv|4k|hd|hq|1080p|audio|video|live|full|ver\.?|version|完整版|高音質|高音质|翻唱|cover|カバー|歌ってみた|主題歌|主题曲|op|ed|ost|feat\.?)/i
        ti = ti.replace(/[\[【\(（〔][^\]】\)）〕]*[\]】\)）〕]/g, function(m) { return junk.test(m) ? " " : m })
        ti = ti.replace(/\b(official\s*(music\s*)?video|official\s*audio|music\s*video|lyrics?\s*video|M\/?V)\b/ig, " ")
        // 「Song」 / 『Song』 hold the name; what's before is usually the artist
        var q = ti.match(/^(.*?)[「『](.+?)[」』]/)
        if (q) { if (q[1].trim() !== "") ar = q[1].trim(); ti = q[2] }
        // "Artist - Song"
        var d = ti.match(/^(.+?)\s+[-–—]\s+(.+)$/)
        if (d && (ar === "" || ar.toLowerCase().indexOf(d[1].trim().toLowerCase()) >= 0
                  || / - topic$|vevo|official|官方|channel/i.test(ar) || isVideoSite)) {
            ar = d[1].trim(); ti = d[2]
        }
        ar = ar.replace(/\s*-\s*Topic$/i, "").replace(/VEVO$/i, "").replace(/\s*(official|官方|channel)$/i, "")
        ti = ti.replace(/[【】\[\]「」『』]/g, " ").replace(/\s{2,}/g, " ").trim()
        return { title: ti, artist: ar.trim() }
    }

    // ── track changes (debounced: browsers send the title and the artist separately) ──
    signal trackChanged()
    readonly property string trackKey: player ? (player.dbusName + "|" + title + "|" + artist) : ""
    property string _lastKey: ""
    onTrackKeyChanged: trackT.restart()
    Timer {
        id: trackT; interval: 350
        onTriggered: {
            if (root.trackKey === root._lastKey || root.title === "") return
            root._lastKey = root.trackKey
            root.trackChanged()
        }
    }

    // ── live position ──
    property int wantPosition: 0
    Timer {
        interval: 250; repeat: true
        running: root.wantPosition > 0 && root.playing
        onTriggered: if (root.player) root.player.positionChanged()
    }

    // ── controls ──
    function togglePlaying() { if (player && player.canTogglePlaying) player.togglePlaying() }
    function next()          { if (player && player.canGoNext) player.next() }
    function previous()      { if (player && player.canGoPrevious) player.previous() }
}

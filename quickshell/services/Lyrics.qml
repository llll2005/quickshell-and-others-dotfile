pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../settings"

// Lyrics — time-synced lyrics for whatever services/Media.qml is playing.
// Sources, in order: lrclib.net exact match (artist + title + duration), lrclib
// search, then NetEase Cloud Music (better for Chinese songs and bilibili). Video
// titles are cleaned first (Media.songTitle / songArtist). Results — including
// "none found" — are cached in Quickshell's cache dir, so a song is looked up once.
//
// `on` starts from `[lyrics] enabled` and is flipped by `qs ipc call hud lyrics`
// (or a click on the HUD's media block). While on and synced lyrics are loaded,
// Media's position ticks and `index` / `current` / `next` / `lineProgress` follow it.
Singleton {
    id: root

    property bool on: Settings.lyricsEnabled
    property var  lines: []            // [{t: seconds, text}]
    property string status: ""         // "" · searching · ok · none
    property string provider: ""       // LRCLIB · NETEASE
    readonly property bool ready: status === "ok" && lines.length > 0
    readonly property string key: Media.songTitle !== "" ? (Media.songArtist + "|" + Media.songTitle).toLowerCase() : ""

    readonly property real offset: Settings.lyricsOffset    // seconds; + shows lines earlier
    readonly property int index: {
        if (!ready) return -1
        var p = Media.position + offset, lo = 0, hi = lines.length - 1, ans = -1
        while (lo <= hi) { var mid = (lo + hi) >> 1; if (lines[mid].t <= p) { ans = mid; lo = mid + 1 } else hi = mid - 1 }
        return ans
    }
    readonly property string current: index >= 0 ? lines[index].text : ""
    readonly property string next: index + 1 < lines.length && ready ? lines[index + 1].text : ""
    readonly property real lineProgress: {
        if (index < 0 || index + 1 >= lines.length) return 0
        var a = lines[index].t, b = lines[index + 1].t
        return Math.max(0, Math.min(1, (Media.position + offset - a) / Math.max(0.1, b - a)))
    }

    // the position only ticks while someone shows the lyrics
    readonly property bool live: on && ready
    onLiveChanged: Media.wantPosition += live ? 1 : -1

    onKeyChanged: { lines = []; status = ""; provider = ""; if (on && key !== "") fetchT.restart() }
    onOnChanged:  if (on && key !== "" && status === "") fetchT.restart()
    Timer { id: fetchT; interval: 700; onTriggered: root._fetch() }

    // ── cache: key → {p: provider, l: lines} (or {p: ""} for none found) ──
    property var _cache: ({})
    FileView {
        id: cacheFile
        path: Quickshell.cachePath("lyrics-cache.json")
        printErrors: false
        atomicWrites: true
        onLoaded: { try { root._cache = JSON.parse(text()) } catch (e) {} }
    }
    function _store(k, p, l) {
        var c = Object.assign({}, _cache)
        c[k] = { p: p, l: l, at: Date.now() }
        var ks = Object.keys(c)
        if (ks.length > 400) {             // keep the newest 400
            ks.sort(function(a, b) { return (c[a].at || 0) - (c[b].at || 0) })
            for (var i = 0; i < ks.length - 400; i++) delete c[ks[i]]
        }
        _cache = c
        cacheFile.setText(JSON.stringify(c))
    }

    function _fetch() {
        var k = key
        if (k === "") return
        var hit = _cache[k]
        if (hit) { _apply(k, hit.p, hit.l); return }
        status = "searching"
        _lookup(k, Media.songArtist, Media.songTitle, Media.length)
    }
    // a name with both CJK and Latin ("周杰倫 Jay Chou", "告白氣球 Love Confession"):
    // the CJK part alone, for a second pass
    function _cjkOnly(t) {
        if (!/[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/.test(t)) return t
        return t.replace(/[A-Za-z][A-Za-z0-9'’.&\- ]*/g, " ").replace(/\s{2,}/g, " ").trim()
    }
    function _lookup(k, artist, title, dur, second) {
        var exact = "https://lrclib.net/api/get?artist_name=" + encodeURIComponent(artist)
                  + "&track_name=" + encodeURIComponent(title) + (dur > 0 ? "&duration=" + Math.round(dur) : "")
        _get(exact, function(d) {
            if (k !== root.key) return
            if (d && d.syncedLyrics) { root._done(k, "LRCLIB", d.syncedLyrics); return }
            _get("https://lrclib.net/api/search?q=" + encodeURIComponent((artist + " " + title).trim()), function(list) {
                if (k !== root.key) return
                var best = root._pick(list || [], dur, function(x) {
                    return x.syncedLyrics && root._same(x.trackName, x.artistName, title, artist, x.duration, dur) ? x.duration : -1
                })
                if (best) { root._done(k, "LRCLIB", best.syncedLyrics); return }
                root._netease(k, artist, title, dur, second)
            })
        })
    }
    function _netease(k, artist, title, dur, second) {
        _get("https://music.163.com/api/search/get?type=1&limit=8&s=" + encodeURIComponent((title + " " + artist).trim()), function(d) {
            if (k !== root.key) return
            var songs = d && d.result && d.result.songs ? d.result.songs : []
            var a = artist.toLowerCase()
            // the right artist first, then the closest length
            songs.sort(function(x, y) {
                var xa = x.artists && x.artists.length && a && x.artists[0].name.toLowerCase().indexOf(a) >= 0 ? 0 : 1
                var ya = y.artists && y.artists.length && a && y.artists[0].name.toLowerCase().indexOf(a) >= 0 ? 0 : 1
                return xa - ya
            })
            var best = root._pick(songs, dur, function(x) {
                var an = x.artists && x.artists.length ? x.artists[0].name : ""
                return root._same(x.name, an, title, artist, x.duration / 1000, dur) ? x.duration / 1000 : -1
            })
            if (!best) { root._miss(k, artist, title, dur, second); return }
            _get("https://music.163.com/api/song/lyric?lv=1&id=" + best.id, function(l) {
                if (k !== root.key) return
                var lrc = l && l.lrc ? l.lrc.lyric : ""
                if (root._parse(lrc).length) root._done(k, "NETEASE", lrc)
                else root._miss(k, artist, title, dur, second)
            })
        })
    }
    // Is a search hit the song playing? Its title must contain ours (or ours its), and
    // the artist must match too — unless the lengths agree within 2 s (covers,
    // romanised names). Stops "Potential" by someone else from supplying the words.
    function _norm(t) { return (t || "").toLowerCase().replace(/[\s\-_'"’.,!?·・()（）\[\]【】「」『』]/g, "") }
    function _same(hitTitle, hitArtist, title, artist, hitLen, dur) {
        var ht = _norm(hitTitle), t = _norm(title)
        if (!ht || !t || (ht.indexOf(t) < 0 && t.indexOf(ht) < 0)) return false
        var ha = _norm(hitArtist), a = _norm(artist)
        if (a && ha && (ha.indexOf(a) >= 0 || a.indexOf(ha) >= 0)) return true
        return dur > 0 && Math.abs(hitLen - dur) <= 2
    }
    // closest length within 8 s (any, if the player gives no length)
    function _pick(list, dur, lenOf) {
        var best = null, bd = 1e9
        for (var i = 0; i < list.length; i++) {
            var L = lenOf(list[i])
            if (L < 0) continue
            var diff = dur > 0 ? Math.abs(L - dur) : 0
            if (diff < bd && (dur <= 0 || diff <= 8)) { best = list[i]; bd = diff }
        }
        return best
    }
    function _miss(k, artist, title, dur, second) {
        var a2 = _cjkOnly(artist), t2 = _cjkOnly(title)
        if (!second && t2 !== "" && (a2 !== artist || t2 !== title)) _lookup(k, a2, t2, dur, true)
        else _done(k, "", "")
    }
    function _done(k, provider, lrc) {
        var parsed = _parse(lrc || "")
        _store(k, parsed.length ? provider : "", parsed)
        _apply(k, parsed.length ? provider : "", parsed)
    }
    function _apply(k, provider, l) {
        if (k !== key) return
        lines = l || []
        root.provider = provider
        status = lines.length ? "ok" : "none"
    }
    function _parse(lrc) {
        var out = [], rows = lrc.split("\n")
        var credit = /^\s*(作词|作曲|编曲|制作人|词|曲|作詞|編曲|製作人|lyrics|composer|arranger)\s*[:：]/i
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i], tags = [], m, re = /\[(\d+):(\d+(?:\.\d+)?)\]/g, last = 0
            while ((m = re.exec(row)) !== null) { tags.push(+m[1] * 60 + +m[2]); last = re.lastIndex }
            if (!tags.length) continue
            var text = row.substring(last).trim()
            if (credit.test(text)) continue
            for (var j = 0; j < tags.length; j++) out.push({ t: tags[j], text: text })
        }
        out.sort(function(a, b) { return a.t - b.t })
        return out
    }
    function _get(url, cb) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var d = null
            try { d = x.status === 200 ? JSON.parse(x.responseText) : null } catch (e) {}
            cb(d)
        }
        x.open("GET", url)
        x.send()
    }
}

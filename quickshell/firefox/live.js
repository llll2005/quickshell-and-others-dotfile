// live.js — Firefox follows the shell's theme while it runs (quickshell/CLAUDE.md, theme sync).
// Loaded at startup by /usr/lib/firefox/qs-firefox.cfg (autoconfig, installed by
// dotfiles/system/firefox-live.sh), privileged. It does what toolkit's legacy userChrome
// loader does — but through the style sheet service, so it can swap the sheets again:
//   · reads the profile's chrome/qs-theme.css, userChrome.css and userContent.css (which
//     scripts/theme-sync.py writes there), inlines the colours into both, and registers
//     them as user sheets (userChrome scoped to chrome:// documents), and sets the pages'
//     dark / light preference from the theme
//   · checks the three files once a second and re-registers when one changed — a theme
//     change in the shell reaches every open window and page within a second
// theme-sync turns toolkit's own loader off while this is installed, so nothing loads twice.
(function () {
  "use strict";
  const { classes: Cc, interfaces: Ci, utils: Cu } = Components;
  const sss = Cc["@mozilla.org/content/style-sheet-service;1"].getService(Ci.nsIStyleSheetService);
  const NAMES = ["qs-theme.css", "userChrome.css", "userContent.css"];
  let chromeDir = null, stamps = "", registered = [], timer = null;

  function file(name) {
    const f = chromeDir.clone();
    f.append(name);
    return f;
  }
  function readText(name) {
    const f = file(name);
    if (!f.exists()) return "";
    const s = Cc["@mozilla.org/network/file-input-stream;1"].createInstance(Ci.nsIFileInputStream);
    s.init(f, 0x01, 0, 0);
    const c = Cc["@mozilla.org/intl/converter-input-stream;1"].createInstance(Ci.nsIConverterInputStream);
    c.init(s, "UTF-8", 0, 0);
    let out = "", part = {};
    while (c.readString(0xffff, part)) out += part.value;
    c.close();
    return out;
  }
  function stamp() {
    return NAMES.map(n => { const f = file(n); return f.exists() ? f.lastModifiedTime + ":" + f.fileSize : "-"; }).join("|");
  }
  const noImport = css => css.replace(/^\s*@import\s+url\(["']?qs-theme\.css["']?\);?\s*$/m, "");

  function apply() {
    const vars = readText("qs-theme.css");
    const chrome = readText("userChrome.css");
    const content = readText("userContent.css");
    const sheets = [];
    // the colours for every document, chrome and pages alike
    if (vars) sheets.push(vars);
    // userChrome's rules only in the browser's own windows (its :root rules would reach pages)
    if (chrome) sheets.push('@-moz-document url-prefix("chrome://") {\n' + noImport(chrome) + "\n}");
    if (content) sheets.push(noImport(content));
    // web pages dark or light like the theme (user.js says the same for the next start)
    const scheme = /--qs-scheme:\s*(dark|light)/.exec(vars);
    if (scheme) Services.prefs.setIntPref("layout.css.prefers-color-scheme.content-override", scheme[1] === "dark" ? 0 : 1);
    for (const uri of registered) {
      if (sss.sheetRegistered(uri, sss.USER_SHEET)) sss.unregisterSheet(uri, sss.USER_SHEET);
    }
    registered = sheets.map(css => Services.io.newURI("data:text/css;charset=utf-8," + encodeURIComponent(css)));
    for (const uri of registered) sss.loadAndRegisterSheet(uri, sss.USER_SHEET);
  }

  function tick() {
    try {
      const s = stamp();
      if (s !== stamps) { stamps = s; apply(); }
    } catch (e) {
      Cu.reportError("quickshell live.js: " + e);
    }
  }

  function start() {
    if (timer) return;
    try {
      chromeDir = Services.dirsvc.get("UChrm", Ci.nsIFile);
    } catch (e) {
      return;   // no profile yet: profile-after-change calls again
    }
    tick();
    timer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
    timer.initWithCallback({ notify: tick }, 1000, Ci.nsITimer.TYPE_REPEATING_SLACK);
  }

  start();
  if (!timer) {
    Services.obs.addObserver(function obs() {
      Services.obs.removeObserver(obs, "profile-after-change");
      start();
    }, "profile-after-change");
  }
})();

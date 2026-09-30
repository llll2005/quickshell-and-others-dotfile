# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A NieR:Automata-themed desktop shell built with [Quickshell](https://quickshell.hyprland.org/) for Hyprland/Wayland. All UI is QML; system data is polled via `Process` spawning shell commands. The `nierlock/` directory is a separate git repo (lockscreen-only Quickshell instance).

## Running and reloading

```bash
# Start the shell
qs

# Reload after editing (Quickshell watches files, but a full restart is sometimes needed)
pkill qs && qs

# Run the lockscreen standalone
~/.config/quickshell/lock.sh          # full video reveal (~4s)
~/.config/quickshell/lock.sh --fast   # static PNG, faster

# Run the nierlock variant directly
QT_MEDIA_BACKEND=ffmpeg qs -p nierlock/shell.qml
```

## IPC commands

```bash
qs ipc call menu toggle        # open/close app launcher
qs ipc call ctrl toggle        # open/close ControlCenter
qs ipc call ctrl hide
qs ipc call bar toggle         # force-show / hide the auto-hide TopBar
qs ipc call bar hide

qs ipc call player toggle      # show/hide the media Player
qs ipc call player hide
qs ipc call player front       # toggle Player z-order (above/below windows)

qs ipc call hud toggle         # CornerHud workspace selector (5×5 grid)
qs ipc call hud stats          # CornerHud stat cluster (SYSTEM/MEDIA/NET/WEATHER/TODO)
qs ipc call hud visible        # show/hide the whole CornerHud
qs ipc call hud close          # collapse selector + stats
```

> **A function named `show` can't be called from the CLI**: `qs ipc call <target> show`
> prints the target's function list instead (qs 0.3.1). `ctrl`/`bar`/`player` still declare
> `show()`, but reach them with `toggle` (or rename the function).

CornerHud keybinds (hyprland binds/dispatchers.lua): `SUPER+\`` = workspace selector,
`SUPER+SHIFT+\`` = stat cluster, `SUPER+CTRL+\`` = show/hide whole HUD.

### CornerHud look

Same family as the popups, turned over for a resident widget (no triangle backdrop):
- **Palette:** the ControlCenter nav bar's dark ink (`cBg #221e17`) with paper text and lines. `cAccent` is light `#fff6cf` for what's active, `cWarn` is brick for warnings, and a picked item is a paper block with ink text (`cInk`) and a `cRed` edge. The frame's lower half still fades to the viewed month's tint (`calBottom`), so the Honkai artwork's dark vignette melts into it.
- **Frame and pages:** diamond corners and a static glass rim (nothing animates at idle). Each reveal sends one paper sweep across (`revealT`). The pages use `HudTab`s (a CatTab in small, fill as width fractions) and slide in the flip direction (`pageDir`/`pageIn`).
- **Rows and controls:**
  - Clickable/interactive rows raise `rowHot`, and the page's `rowSel` (a spring plus two afterimages) slides under them.
  - Clicks call `root.hit(item, strength)`, which pops the item and fires a HitBurst (scaled 0.62) in that item's window.
  - Workspace cells use a sliding light frame.
- **Calendar:** selected day = filled ◆, today = ◇, an event = a tiny ◆. `calNav(d)` slides the artwork and label out, flips the month, and slides them back in (`calOut`/`calIn`). Use it rather than `calShift()` for anything user-driven.

### CornerHud reveal / OSD

The HUD parks off the right edge. `win.revealed` is the single OR that decides whether
it slides in — anything that should make it appear must be a term in it:

- `peeked` — pointer on the edge `trigger` strip or the `catcher`, cleared by `peekHideT` (1.4 s)
- `statsExpanded` — pointer on the frame itself
- `statsPinned` / `wspMode` / `todoEditing` — IPC or keyboard
- `osdMode !== ""` — **volume/brightness OSD**; `_osdT` (1.7 s) clears it and the HUD slides back out

OSD sources: `Audio` volume/mute signals fire it natively (so the media keys need no
binding), while brightness keys must call `qs ipc call hud osd bri` — `Backlight` only
polls every 4 s, and binding on its `value` would also pop the HUD on hypridle dimming.

Two geometry rules the input mask depends on:
- `trigger.width` must be **≥ the frame's 8 px right inset**, else the pixels between
  the strip and the frame belong to no input region and the reveal drops as the pointer
  crosses them.
- `catcher` (frame + 28 px) is what the mask uses, not `frame`. The trigger runs the full
  screen height while the frame is a small box at the top, so without a hold-open region
  the pointer reveals the HUD low down and loses it on the way up.

> The old `/tmp/qs-toggle` / `qs-front` / `qs-menu` file-polling IPC (200 ms `wc -l`
> loop) was removed — Player visibility/z-order now go through the `player`
> `IpcHandler` above, matching `menu`/`ctrl`/`bar`/`capture`.

## Popup windows (layer surfaces)

- Menu / ScreenCapture / WsMover / ControlCenter are **mapped only while open**
  (`visible:` on the PanelWindow) and live on the **Overlay** layer — Hyprland draws fullscreen
  windows above the Top layer, so Top-layer popups vanish behind e.g. a fullscreen browser.
  CornerHud stays on Top for edge-hover and switches to Overlay only for keybind/IPC/OSD reveals.
- Keep the default `quickshell` layer namespace. Hyprland's only `no_anim` layer rule
  (`~/.config/hypr/ui/rules.lua`) matches `^quickshell$`; any other namespace gets the jelly
  `slidefade` layer animation on every map — a full-screen panel then visibly lurches.
- A reveal on a freshly mapped surface must wait for its first frame (`components/MapGate.qml`),
  or the front-loaded OutExpo part of the slide is lost.
- Such a window also gets its **size** a moment after it is shown, so anything laid out on
  "open" sees 0×0 first. `NierTriBg` (widgets/ and the region/ copy) defers its grid until
  the size arrives — otherwise only a 2×2 corner of triangles appears.
- **One backdrop for every popup: `components/GlassBackdrop.qml`** (ScreenCapture, Menu, ControlCenter,
  WsMover). It freezes a frame of the popup's screen and draws `TriField` over it; the look — grid,
  palette, contrast, dark-pane share, pane offset/refraction, glare, stars, flicker, unfold/scatter
  timing — lives only in `TriField.qml` + `shaders/tri.frag`, so edit there and all popups follow.
  Popups keep their own content hidden until `frameReady()` (or ~350 ms) and unmap only after
  `hidden()` (`hideDuration`, 0.7 s). ScreenCapture runs its non-region commands after the unmap.
  `impact(x, y, strength)` sends a shock ring through the panes around a point (item px):
  their rims light up and their offset is kicked outward.
- **Effects anywhere on screen: `components/Fx.qml`** (a singleton, created from shell.qml). `Fx.burst(gx, gy, s)` / `Fx.sparks(gx, gy)` take global layout px; `burstOn` / `sparksOn(monitor, x, y)` take monitor-local px. There is one click-through Overlay surface per screen, mapped only while an effect flies, with three HitBursts in rotation plus `components/Sparks.qml`. It also draws the **click bursts**: the imecaret plugin posts `clickfx>>x,y,button` for presses on windows (not on layer surfaces: bars, the HUD, the shell's panels), gated by `Settings.clickFx` and skipped over fullscreen workspaces. The IME text effects (phrase commit, Enter, typing sparks) use it too. Anything new that needs a burst or sparks outside its own window should call Fx, not add another overlay.
- **One confirm impact for every popup: `components/HitBurst.qml`** — diamond rings + shards,
  and (with `backdrop:` set) the GlassBackdrop shock ring at the same spot. Place it above the
  panel, outside any clipped/masked item; `playAt(item, x, y, strength)` maps from any item.
  ControlCenter, ScreenCapture and Menu all confirm the same way: burst + a ~0.1 s hit-stop
  (`hitT`: the selector pops 5 % and flashes) before the action runs.
- Shaders live in `components/shaders/*.frag` (compile: `/usr/lib/qt6/bin/qsb --qt6 -o X.frag.qsb X.frag`).
  A plain relative `fragmentShader` string resolves against the file that *instantiates* the
  component, so components use `Qt.resolvedUrl(...)`.
- **After recompiling a `.qsb`, bump the `?v=N` on its `fragmentShader` URL** (or restart qs).
  Quickshell keeps its windows across hot reloads and Qt caches a window's shaders by URL,
  so an unchanged URL silently keeps running the old shader — a fresh `qs -p` probe will
  look right while the live shell doesn't.
- **A `ListView` does not move declared children into its content item** (a plain `Flickable`
  does). Anything that must scroll with the rows — Menu's selector, its afterimages, the burst
  anchor — needs `parent: appList.contentItem`, or it drifts off once the list scrolls.
- Close functions must set the "closing" flag **before** clearing the "open" flag: the
  window's `visible` is `open || closing`, and one false evaluation destroys and re-creates
  the layer surface (a one-frame flash + ~30 ms stall).

## Architecture

`shell.qml` is the `ShellRoot` entry point. Its first line, `//@ pragma IconTheme breeze`, gives Qt an icon theme (without it only hicolor resolves: ~70 % of app icons, none of the preferences-*/device ones). **Pragmas are read only at startup** — a hot reload ignores changes; restart `qs` with the running one's environment (`/proc/<pid>/environ`: it carries `QT_SCALE_FACTOR` etc.). It holds global playerctl state and spawns widgets as `Variants { model: Quickshell.screens }` so each widget appears on every monitor.

### Widget map

| File | What it does |
|------|-------------|
| `widgets/TopBar.qml` | Auto-hide full-width bar (hover top strip / `qs ipc call bar toggle`). Polls CPU/GPU/WiFi/BT/Battery/Brightness via separate `Process` instances (volume now from `Audio` service). Reveal/hide is a vertical curtain wipe (OutQuint; reveal top→bottom, hide bottom→top). Active only when `Settings.cornerHudEnabled` is false — every poll `Timer`, its `nmcli monitor` and the Hyprland `rawEvent` handler are gated on `barActive`, so new pollers must be too. |
| `widgets/CornerHud.qml` | Alternative compact NieR bracket HUD, top-right, floating (no exclusion zone). Parks off the right edge; hovering the edge strip slides it in, hovering the frame expands to CPU/GPU/volume/battery. Doubles as the **volume/brightness OSD** — see below. Data from `Sys`/`Audio`/`Battery` services + native `Hyprland`. Active when `Settings.cornerHudEnabled` is true (default). |
| `widgets/ScreenCapture.qml` | Capture panel (`qs ipc call capture toggle`, Print). Categories 複製 (default page on every open) / 截圖 / 錄影 / OCR / 色彩; number keys fire rows, ←/→ or a two-finger horizontal swipe change category (sidebar fill, marker spin and list slide all move in that direction), F toggles the freeze frame, S replays the next open/close style (`Settings.captureOpenStyle`: wipe/rise/scan/iris/blinds, or `qs ipc call capture style <id>`). Open = map transparent ("arming") → `grim -t ppm` freeze frame of this monitor → intro. Region selection runs **in the same window** (phase `selecting`): the panel steps aside and the backdrop becomes the selection layer (exact spotlight via TriField `selection`, crosshair, magnifier fed by `scripts/pixel-probe.py`, W×H/ratio tag). `NIER_CROP` commands crop the freeze PPM immediately; `NIER_GEOM` ones (live grim, wf-recorder) run after the window unmaps, with layout coords from `Hyprland.monitorFor()`. `region/` (the old standalone `qs -p` overlay) is no longer used. Save/copy notifications go through `scripts/shot-notify.sh` (thumbnail + action buttons, run with `setsid -f`). Backdrop is the shared `GlassBackdrop`; a 0.7 s invisible click-through warm-up at start pre-builds its shaders. |
| `widgets/Menu.qml` | App launcher (780×540). Same backdrop and open/close as ScreenCapture: glass TriField over a ScreencopyView frame, diamond-iris reveal, warm-up at start. Reads `.desktop` files via `list-apps.sh`. Keyboard: ↑↓ navigate, ↵ launch, ESC close, ←→ change category. |
| `widgets/WorkspaceSwitcher.qml` | 5-card carousel shown for 2.8s on workspace change. Currently **disabled** in `shell.qml` (workspace state lives in TopBar). Still references `scripts/hypr-events.py` if re-enabled. |
| `widgets/ControlCenter.qml` | System controls panel, toggled via `qs ipc call ctrl`. Cross layout: `top` = Wi-Fi/Bluetooth, `bottom` = audio, `left` = qshare send/receive, `right` = notifications. Three depths (`depth`): 1 = the cross, 2 = a section's sub-list, 3 = the detail panel's actions. Everything is spatial: a focused section steps out along its own direction with its ◆› marker on the outer side; ↵ or the direction toward the detail panel (left for the left section, right otherwise) goes deeper; back is Esc or the way to the cross centre (→/← for the side sections, ↓ past the last sub for the top section, ↑ past the first for the bottom one, ←/→ out of the detail panel); lists otherwise clamp. Hovering a list makes it the active one. The inactive list is dimmed; a nav bar at the bottom shows depth ◆◆◇, the path and the keys for that depth. **Wi-Fi and Bluetooth use Quickshell's native modules** (`Quickshell.Networking`, `Quickshell.Bluetooth`): event-driven, with no nmcli/bluetoothctl polling. Known (saved) or open networks `connect()` directly; only new secured ones prompt, and `connectWithPsk()`. `connectionFailed(NoSecrets)` reopens the prompt, marked "Wrong password" if a password had just been sent. Bluetooth writes `enabled` / `discovering` / `trusted` and calls `pair()` / `connect()` / `forget()`; a pair is followed by a connect once `paired` flips. Discovery goes through `btSetScan()`: it keeps the requested state (the adapter's `discovering` only updates when BlueZ answers), retries once when StartDiscovery bounces with InProgress, and stops after 30 s or when the panel closes. The rows are rebuilt only when their visible content changes (a JSON signature; Wi-Fi signal as 0–3 bars). Shell commands run through `Quickshell.execDetached`: the old shared `actProc` silently dropped a command while a previous one, like a slow `bluetoothctl connect`, was still running. That was the "Enable Bluetooth does nothing" bug. Same glass TriField backdrop and shared palette as ScreenCapture/Menu; the cross stays hidden until the backdrop frame is captured (`ready`). **Hit feel** (all driven from root state, so every path — keys, clicks, the direction that goes deeper — gets it): every confirm goes through `activateCurrent()` → hit-stop (`hitT`: the focused item pops and flashes for ~0.1 s) → `confirmPulse` → the focused item answers with `impactAt(window, x, y)` from its marker → that window's `HitBurst` (rings + shards) and `backdrop.impact()` → then `_afterHit()` does the real action. Focus moves squash-and-spring the new item (`press`, via `focusScale(depth)`); sub and action lists use one sliding `SlideSel` (ink selector on a spring + two afterimages) instead of per-row fills — sub rows are split into `part: "card"` (under it) and `"face"` (over it); pressing past a list end bumps the selector (`bump`); depth changes kick the sub list and detail panel along the way you went (`kick`/`kickDir`) and pop the nav bar's depth diamond; ↵ / → with nothing to enter nudges that way instead (`blocked()`). **Notifications** (`right.history`): rows are keyed `id@ts` (never by index — the copy is a 1.5 s poll behind the daemon) and the list is only reassigned when the polled JSON changes, so rows don't rebuild; a rebuilt list skips entrances (`_seenNotif`) and rows below a removed one slide up into the gap (`_gapAt`/`_gapH`). ↵ opens a notification whose sender still listens (`live`: ◆ marker; invokes its "default" action, then closes the panel), else toggles its details; → / ← expand / collapse; DEL·X·Backspace or × dismisses (row flies out); TAB or CLEAR ALL cascades them out. |
| `widgets/ImePanel.qml` | **Caret position comes from the compositor.** On Hyprland, apps that type through `input-method-v2` (kitty, Chromium/Electron with the Wayland IME flag, GTK4…) never give fcitx5 their caret: its waylandim frontend sets no cursor rect, and only fcitx5's own popup surface gets placed there, by Hyprland. So the **`imecaret` Hyprland plugin** (`hypr-plugin/imecaret`, loaded from `~/.config/hypr/core/autostart.lua`) answers `hyprctl caret` with the focused text input's cursor box in global coords. It uses the same math as Hyprland's `CInputPopup::updateBox`: the owner surface's global box plus `cursorBox()`. The plugin also posts IPC events:
  - `imecommit>>x,y,w,h,n` when text lands in the app (Enter on the phrase, a pick), from each input method's `onCommit`;
  - `imepreedit>>…` when the preedit changes;
  - `imeenter>>…` for Enter in any text input with a caret (English too), from `Event::bus()->m_events.input.keyboard.key`, one per press within 80 ms. The bridge holds an Enter 70 ms so the commit that follows it, if any, replaces it.

  Burst positions scale by the *screen* width (`modelData.width / mw`), not the window's: a window that has just been mapped is 0×0 for a moment, and a burst placed then lands in the corner. That caused the intermittent missing Enter effect. The bridge reads them from `.socket2.sock` and forwards them as `commit` messages (a HitBurst on the phrase: caret − n·h/2, skipped if a candidate pick burst < 250 ms ago) and `spark` messages (re-queried 45 ms later, once the app has moved its caret). Replacing a loaded plugin: build to another file, `hyprctl plugin unload` the old one, `load` the new one, then `mv` it over `imecaret.so`. Never rebuild a `.so` in place while it's loaded. The bridge re-reads the caret on every panel update, and again 40 / 140 ms later (apps report the new box only after drawing the preedit), falling back to fcitx5's rect when the plugin has none (XWayland / D-Bus-module apps). **Rebuild the plugin (`make` in its folder) after every Hyprland update.** It checks the version hash and refuses to load otherwise, and without it the panel sits at the last rect it knew. With `imePanelEnabled: false`, fcitx5 uses its classic window, styled by the generated `quickshell` theme (see Theme sync below), or the static `nier` one in `~/.local/share/fcitx5/themes/nier/` with `[sync] fcitx5 = false`. **fcitx5 candidate window** drawn by the shell (`Settings.imePanelEnabled`). `scripts/imepanel.py` owns the D-Bus name `org.kde.impanel` and speaks the kimpanel protocol: fcitx5 prefers kimpanel (UIPriority 50) over its classic window while the name is owned, and falls back to it the moment the bridge exits, so a dead bridge never blocks typing. The bridge streams JSON lines (table / cands / cursor / aux / preedit / spot) and takes `select N` / `prev` / `next` on stdin. Relative spot rects (Wayland clients) are made absolute with the focused window's `at` from Hyprland's socket, then made monitor-local; QML scales layout px by `width / mw` (QT_SCALE_FACTOR). The panel is a full-screen Overlay surface, mapped only while there's a panel or sparks/burst in flight, with an input mask on the card alone. Look: a paper card, an ink selector springing between candidates, pages sliding in the flip direction, a HitBurst on a pick (detected when fcitx5 empties the list, since it clears the table *before* hiding it), and diamond sparks when the caret steps along a line (`Settings.imeSparks`). **Test without a keyboard:** make a private fcitx5 input context over D-Bus (`org.fcitx.Fcitx.InputMethod1.CreateInputContext` → `FocusIn`, `SetCursorRect`, `Controller1.SetCurrentIM mcbopomofo`, `ProcessKeyEvent`). `ShareInputState=No`, so it doesn't touch the user's apps. |
| `widgets/Player.qml` | Floating media player; toggled via `qs ipc call player toggle`. Controls + metadata use native `Quickshell.Services.Mpris` (event-driven, no `playerctl` subprocess). Cava bars stream from cava's stdout via `SplitParser`. |
| `widgets/Notifications.qml` | Notification daemon + popups (top-left, `leftMargin` 24, 6 % from the top). **A popup that times out is only shelved** (hidden, out of the stack/mask) — its Notification stays tracked so the ControlCenter history can still run its actions; transient ones still close, and entries falling off the 50-item history are dismissed. DND and notifications carried over a reload (`lastGeneration`) arrive shelved (`_quiet`), with no popup. The history (minus live objects) survives config reloads via `PersistentProperties`, and carried-over notifications are relinked by id. Clicks get the shared hit feel (`HitBurst`): an action button or a body click (the default action, else close) pops the card, and ✕, a swipe or a middle/right click throw a lighter burst. **Quickshell closes a non-resident notification the instant an action is invoked, destroying its row**, so the card cuts out first and `invoke()` is the row's last act. |
| `widgets/Companions.qml` | Animated sprites (disabled by default in Settings). |
| `widgets/lockscreen.qml` | Standalone lockscreen, not loaded by main `shell.qml`. |

### Configuration and themes (user-editable, live)

- **`config/shell.conf`**: every option (`[general] theme`, `scale`, `[hud]`, `[backdrop]` opacity/dim/cellSize/flicker, `[effects]`, `[ime]`, `[sync]`, `[capture]`, `[notifications]`, `[player]`, `[companions]`).
- **`config/themes/<name>.conf`**: palettes. Shipped themes:
  - `nier` (default), `yorha-noir`;
  - requested: `lilac` 粉紫, `mono` 黑灰白, `crimson` 紅黑白, `jirai` 地雷系, `jirai-light` 淺色地雷系 (the only light HUD), `aha` 阿哈 (crimson/ivory/gold, from the Honkai: Star Rail card);
  - suggested: `matcha`, `abyss`, `amber`.

  A theme lists only the keys it changes; the rest fall back to the defaults in Theme.qml.
- **`settings/Config.qml`** (singleton) parses both, INI style:
  - `[section]` headers, which may carry a trailing `# note`;
  - `key = value`, read as `section.key`;
  - a comment is a whole line, or ` # ` (whitespace, `#`, whitespace) after a value, so `#a99bc9` in a list stays a colour;
  - `"quoted"` values are kept verbatim.

  It watches both files, so a save updates every binding at once. `Config.themeOverride` backs `qs ipc call theme set <name>` / `reset` / `list` / `current`, which preview without editing shell.conf.
- **`settings/Settings.qml`**: typed options with built-in defaults (`Config.num("hud.hideDelay", 1400)`…). It must NOT import Theme: Theme imports this module for Config, and a cycle breaks both.
- **`theme/Theme.qml`**: roles, not colours.
  - `paper`/`ink`/`inkStrong`/`inkSoft`/`accent`/`light`/`warn`/`good` for the popups' cards;
  - `panel`/`panelRaised`/`panelText`/`panelMuted`/`monitorColors`/`monthTint` for the HUD, plus `panelActive` (`dark.active`, default `light`: selected day, pins, markers) and `panelOnFill` (`dark.onFill`, default `panelRaised`: text on any filled HUD block). A light HUD (jirai-light) needs both, because `light` is also the glint colour and `raised` its track colour;
  - `urgent`/`calm`, `sepia*`, `triangle*`, `mono`/`cjk`, and `alpha(c, a)`.

  All active widgets and components draw from these tokens. Exceptions: the HUD's month-artwork tones, the date numerals on the artwork, masks, and pure black/transparent.
  **Never name a QML property `on` + Capital** (`onPanel` was one): QML treats it as a signal handler, and the binding silently evaluates to black.
- **Theme sync — fcitx5 and Hyprland follow the theme:** `scripts/theme-sync.py [theme]`, run by shell.qml (400 ms debounce) at start and whenever `Config.themeName`, the theme file or shell.conf changes (so `theme set` previews sync too). `[sync] fcitx5` / `hyprland` in shell.conf turn each off.
  - fcitx5: writes the classicui theme `~/.local/share/fcitx5/themes/quickshell/` (the nier SVGs recoloured: paper, ink, accent edge, light rim), points `classicui.conf` `Theme`/`DarkTheme` at it and calls `Controller1.ReloadAddonConfig classicui`. Off → back to the static `nier` theme. It only shows when the kimpanel bridge isn't running (`[ime] panel = false`, or the bridge died).
  - Hyprland: writes `~/.config/hypr/ui/qs_theme.lua` (from the theme's `[hyprland]` section: `border` = 2–3 colours, `borderAngle`, `shadow`, optional `inactive`; defaults `light, accent` / panel at 40 % / accent) and applies it live with `hyprctl eval 'hl.config({...})'`. `ui/theme.lua` `pcall(dofile)`s it on every config load, so it survives `hyprctl reload`; off → `{ enabled = false }` + `hyprctl reload config-only`, and theme.lua falls back to its own Holographic Y2K palette.
  - Idempotent: nothing is reloaded unless a generated file changed. Its parser and fallbacks mirror Config/Theme.
- **Theme workshop (web):** https://claude.ai/artifact/77qs2XJC3BrySY1pjNJZsW. It previews the themes on mock components, edits every token live (web only) and copies a ready `.conf`. Its parser and fallbacks mirror Config/Theme (and theme-sync.py for `[hyprland]`); keep them in step when tokens change. The page isn't kept in this folder: to change it, read it back with the Artifact tool (`action: read`), edit it, replace the `const THEMES = {…}` JSON with every `config/themes/*.conf` (name → file text), and republish to the same URL.
- Popups pick their screen from `Hyprland.focusedMonitor` (shell.qml `focusedMonitor()`, ControlCenter `toggle()`). Before this, each open spawned `active-monitor.sh`, or hyprctl plus python.

### Singletons

- **`settings/Settings.qml`** / **`settings/Config.qml`** / **`theme/Theme.qml`**: see above. `Settings` also provides the `vw()`, `vh()`, `s()` sizing helpers.
- **`nierlock/Config.qml`** — Config singleton for the lockscreen: sounds path, font sizes, TODO file path, color palette.

### Service singletons (`services/`, `import "../services"`)

Shared, reactive data sources that decouple hardware state from the UI so multiple widgets stay in sync without each polling. `qmldir` declares `module Services`.

- **`widgets/Notifications.qml` IPC** (`notifs`): `getHistory` (JSON, each with `key` = `id@ts` and `live`), `dismissKey`/`invokeKey <key>`, `clearAll`, `get/set/toggleDnd`. A history entry's `ref` is nulled when its Notification closes (sender, dismiss, invoke), so `live` and dismissals never touch a closed one; `invokeKey` doesn't dismiss after invoking (the invoke already closed it) except for resident ones.
- **`services/Audio.qml`** — Volume/mute via native `Quickshell.Services.Pipewire` (`volume`, `muted`, `ready`, `setVolume()`, `toggleMute()`). Used by both TopBar and ControlCenter. Volume scale is Pipewire raw (1.0 == 100%, up to ~1.5).
- **`services/Sys.qml`** — CPU (`/proc/stat`, jiffies delta between 2 s ticks) and RAM (`/proc/meminfo`, 3 s) read in-process via `FileView` (no fork); GPU from one long-lived `nvidia-smi -lms 2000` stream. `cpuPct`, `memPct`, `gpuPct`, `gpuMem`, `gpuTemp`, `gpuAvailable`. (TopBar binds cpu/gpu to this; only its process-lists self-poll.)
- **`services/Battery.qml`** — native `Quickshell.Services.UPower`. `available` (false on desktops), `percent` (0–100), `charging`. Note: Quickshell's `UPowerDevice.percentage` is a 0–1 fraction.
- **`services/Net.qml`** — Wi-Fi/Ethernet/Bluetooth from **Quickshell's native `Networking` + `Bluetooth` modules**: bindings on NetworkManager/BlueZ D-Bus signals, no polling. Only NM's wired devices count as Ethernet, so docker/veth/bridges don't show. The IP (not exposed natively) is one `ip -j -4 addr` when the link changes, plus once a minute. `wifiOn/wifiSSID/wifiSig/wifiIP`, `ethOn/ethName/ethIP`, `btOn/btDev/btBat`. It replaced `scripts/netinfo.sh` every 5 s, a busctl BT script every 8 s, an upower pipeline and a resident `nmcli monitor`: about 250 processes a minute. Measured A/B over 40 s: 3.1–4.1 % of a core became ≈1 %. (The scripts are still used by the inactive TopBar. `nmcli dev wifi` polling there must pass `--rescan no`, or nmcli forces a scan whenever the AP list is >30 s old.)
- **`services/Backlight.qml`** — brightness via brightnessctl. `value` (0–1), `available`, `set()`.
- **`services/Weather.qml`** — wttr.in, 20-min poll. `temp`, `desc`, `icon`, `forecast[]` (3-day), `ready`.
- **`services/Cal.qml`** — gcalcli upcoming events (`events[]`).
- **`services/ClaudeUsage.qml`** — scripts/claude-usage.py cost/token totals (today/week/month).

`CornerHud` reaches full TopBar feature parity from these: SYSTEM (cpu/gpu/mem/top-proc) · MEDIA (vol/bri scroll-to-adjust, vol click=mute, bat) · NETWORK · WEATHER (+forecast) · CALENDAR (month + gcal) · TODO · STOPWATCH · CLAUDE. TopBar/ControlCenter still self-poll network/sys — migrate onto these services later to finish the dedup.

### Color palettes (each widget uses its own)

- **Main NieR sepia** (Settings/Theme): `fg:#c8b89a`, `bg:#0b0a09`, accents in `a1–a4`
- **TopBar** (dark purple/pink): `cBg:#0e0914`, `cAccent:#d44090`, `cGlow:#8f1060`
- **Menu** (warm paper): `paper:#d6cfb5`, `ink:#463f2e`, `accent:#6e2a2a`
- **WorkspaceSwitcher** (Y2K dark): `cBg:#07040f`, `cHot:#e8246a`, `cPink:#ff6eb4`
- **Lockscreen** (YoRHa): configured in `nierlock/Config.qml`

### Python helpers

- **`scripts/hypr-events.py`** — Streams Hyprland `socket2` events to stdout, auto-reconnects. Only used by the (disabled) WorkspaceSwitcher. TopBar now uses the native `Quickshell.Hyprland` `rawEvent` signal instead.
- **`scripts/qshare.py`** — LAN/tunnel file sharing (HTTP + QR code), driven from ControlCenter `left.send` / `left.receive`. Requires `python-qrcode`.
  - `send` takes **several paths**: the phone gets an index page listing every item (per-item download + "download all .zip"); directories are zipped on demand.
  - `recv` serves an upload page (multi-file, drag & drop, per-file progress) writing into `-o DIR`.
  - The server **stays up until stopped** (Ctrl-C, or SIGTERM from Quickshell) so one QR handles several transfers. `--once` restores the old shut-down-after-first-transfer behaviour.
  - `--tunnel` routes through a Cloudflare quick tunnel (works on mobile data); without it the URL is LAN-only.
  - Quickshell IPC is the `--event-file`, appended one line at a time: `COUNT`/`SIZE`/`STATUS`/`URL`/`QR`/`READY`/`TICK <name>`/`DONE`/`CANCELLED`/`ERROR`. ControlCenter re-reads the whole file every 250 ms and **rebuilds** state from it, so handlers must stay idempotent.

### Shell scripts

- `list-apps.sh` — wrapper for `scripts/list-apps.py`, which enumerates the `.desktop` files for Menu.qml as `name|id|categories|icon|binary|exec` (one Python process, ~30 ms; the old grep loop took ~2.6 s). Menu resolves the icon with `Quickshell.iconPath()` — Icon=, then the real binary's name, the desktop id, then `-symbolic` — and falls back to a glyph.
- `active-monitor.sh` — Prints the focused monitor name (`hyprctl monitors` + awk).
- `wallpaper.sh` / `setwallpaper.sh` — Wallpaper management.
- `wave-check.sh` / `pixel_wave.py` / `pixel-wave-close-video.py` / `ext_last_fr.py` — Pixel-wave wallpaper transition helpers.
- `nier-welcome.sh` — Welcome animation on shell start.

## External dependencies

The shell calls these tools directly — they must be on PATH:

`hyprctl`, `playerctl`, `nvidia-smi`, `nmcli`, `bluetoothctl`, `wpctl` (PipeWire), `brightnessctl`, `pw-play` (lockscreen audio), `curl` (weather via wttr.in), `kitty`, `yazi`, `zenity` (qshare file picker)

Optional: `cloudflared` (for `qshare --tunnel`), `xdg-open` (qshare "Open that folder")

The qshare file picker falls back `zenity` → `kdialog` → `yazi` in a terminal; all three
print the chosen paths one per line on stdout, which `ControlCenter.pickerProc` reads directly.

## Key customization points

- **Global scale / player position**: `settings/Settings.qml` — `scale`, `playerPositionY`, `playerWidth`, `companionsEnabled`
- **Lockscreen TODO path**: `nierlock/Config.qml` — `todoPath` (default: `~/Documents/Notes/TODO.md`)
- **Lockscreen sounds**: place files in `nierlock/sounds/` (see `nierlock/README.md` for filenames)
- **TopBar todo file**: hardcoded in `widgets/TopBar.qml` as `~/todo_list.md`
- **Hyprland keybindings**: bind `qs ipc call menu toggle` and the `/tmp/qs-*` echo commands in `hyprland.conf`

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A NieR:Automata-themed desktop shell built with [Quickshell](https://quickshell.hyprland.org/) for Hyprland/Wayland. All UI is QML; system data comes from Quickshell's native modules (Pipewire, MPRIS, UPower, NetworkManager, BlueZ, Hyprland IPC) wherever they exist, and from `Process`/`FileView` otherwise. `nierlock/` is a git submodule (xendak/nierlock, the F4 lockscreen).

**Repository:** this folder is `quickshell/` of the dotfiles repo
`git@github.com:llll2005/quickshell-and-others-dotfile.git`, together with `~/.config/hypr`
(`hypr/`), the root `README.md` and `dotfiles/` (screenshots, `install.sh`, the `dot` wrapper).
It is a **bare repo** (`~/.dotfiles.git`) whose work tree is `~/.config`: there is no `.git`
here, so use **`dot`** (`~/.local/bin/dot` → `~/.config/dotfiles/dot`) instead of `git`:
`dot status`, `dot add quickshell/widgets/X.qml`, `dot commit`, `dot push`. Untracked files are
hidden (`status.showUntrackedFiles no`) — new files need an explicit `dot add`. Never commit
`secrets/` (Google OAuth for gtasks/gcal), the third-party art in `assets/` (calendar months,
companion gifs, `nier-arrow.png`; all gitignored and purged from history) or `_attic/`
(retired code kept locally). The pre-merge local repos are backed up in
`~/.local/state/dotfiles-migration/`.

## Running and reloading

```bash
# Start the shell
qs

# Reload after editing (Quickshell watches files, but a full restart is sometimes needed)
pkill qs && qs

# Lock the session (what SUPER+L, hypridle, CC Lock and the launcher's LOCK run):
# lock.qml in its own qs process, hyprlock if it fails
~/.config/quickshell/scripts/lock.sh
# Work on the lock's look without locking (overlay, no keyboard grab)
QS_LOCK_PREVIEW=1 qs -p ~/.config/quickshell/lock.qml
qs -p ~/.config/quickshell/lock.qml ipc call lockpreview type x   # · submit · clear · state · quit

# The Hyprland plugin (hypr-plugin/imecaret): swap a fresh build into the running Hyprland
make -C ~/.config/quickshell/hypr-plugin/imecaret reload

# Run the nierlock variant directly
QT_MEDIA_BACKEND=ffmpeg qs -p nierlock/shell.qml
```

## IPC commands

```bash
qs ipc call menu toggle        # app launcher (= calc · / files · : emoji)
qs ipc call capture toggle     # capture panel; capture stop · capture style <wipe|rise|scan|iris|blinds>
qs ipc call ctrl toggle        # ControlCenter (also hide); ctrl power = straight into the power menu (the power key)
qs ipc call clip toggle        # clipboard history (cliphist)
qs ipc call wsmove open        # move every window of this workspace to another
qs ipc call settings toggle    # settings panel (SUPER+ALT+S): every switch + the helpers' health
qs ipc call player toggle      # media player; hide · front (above/below windows)

qs ipc call hud toggle         # CornerHud workspace selector (5×5 grid)
qs ipc call hud stats          # CornerHud stat cluster (SYSTEM/MEDIA/NET/WEATHER/TODO)
qs ipc call hud visible        # show/hide the whole CornerHud
qs ipc call hud close          # collapse selector + stats
qs ipc call hud osd <vol|bri|mic|caps|ime>
qs ipc call hud lyrics         # synced lyrics on/off · hud nowPlaying · hud lyricsInfo

qs ipc call theme set <name>   # theme preview; reset · list · current
qs ipc call notifs getHistory  # dismissKey/invokeKey <id@ts> · clearAll · setDnd/toggleDnd
```

> **A function named `show` can't be called from the CLI**: `qs ipc call <target> show`
> prints the target's function list instead (qs 0.3.1). `ctrl`/`player`/`hud` still declare
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
- `osdMode !== ""` — **the OSD** (vol · bri · mic · caps · ime); `_osdT` (1.7 s) clears it and the HUD slides back out
- `mediaShow` — the **media block** under the header: a now-playing card for 4.2 s on
  `Media.trackChanged` (`[hud] trackToast`), and the synced lyric line while `Lyrics.on`,
  lyrics were found and the player plays (current line wrapping to 2 lines, its progress,
  the next line; a click toggles `Lyrics.on`). It stays on the Top layer (not Overlay).

OSD sources: `Audio` volume/mute and **mic** mute signals fire it natively (so the media keys
need no binding); **ime** fires on `Ime.switched` (the kimpanel bridge forwards fcitx5's
`/Fcitx/im` property only when the input method really changes); **caps** comes from a
non-consuming Hyprland bind on Caps_Lock (`qs ipc call hud osd caps`) and reads the keyboard
LEDs (`/sys/class/leds/*::capslock`) 60 ms later — sysfs doesn't notify. Brightness keys must
call `qs ipc call hud osd bri` — `Backlight` only polls every 4 s, and binding on its `value`
would also pop the HUD on hypridle dimming.

Two geometry rules the input mask depends on:
- `trigger.width` must be **≥ the frame's 8 px right inset**, else the pixels between
  the strip and the frame belong to no input region and the reveal drops as the pointer
  crosses them.
- `catcher` (frame + 28 px) is what the mask uses, not `frame`. The trigger runs the full
  screen height while the frame is a small box at the top, so without a hold-open region
  the pointer reveals the HUD low down and loses it on the way up.

## Design language (every surface follows it)

- **Three materials**, one per surface:
  - **Paper** — what you *operate*: launcher, capture, CC, clipboard, settings, IME panel.
    Paper card, ink text, diamond corners, glass-triangle backdrop.
  - **Ink** — what *stays and tells*: CornerHud, OSD, lyrics, notifications, nav bars. Dark
    ink panel, paper text.
  - **Void** — the system *changing state or asking for authority*: boot, login, lock,
    password prompts, sleep, shutdown. Pure black, the theme's `light`, a diamond,
    words scrambling in (`components/ScrambleText.qml`), one hairline, glass that
    collapses into the dark. The CC's power exit and `lock.qml` are the reference.
- **One confirm**: hit-stop (~0.1 s pop + flash) → HitBurst (+ backdrop shock ring) → the
  action. **One exit**: collapse into black.
- **Keys**: arrows only (no WASD). ↑↓ select · ←→ the panel's tabs/sections (the CC: its
  spatial cross) · ↵ confirm · Esc back/close. **A row's number is its key**: 1–9 runs
  that row where nothing is typed (capture, settings), Alt+1–9 where you type
  (launcher, clipboard), and Alt works everywhere. Key-hint footers use the same words:
  `ALT 1–9`/`1–9 RUN`, `←→ <tab noun>`, `↑↓ SELECT`, `↵ <verb>`, `ESC CLOSE`.
- **Words**: titles and labels in English caps (the system's voice), explanations in
  Chinese. **Type**: mono (`Theme.mono`) for system labels and numbers, `Theme.cjk` for
  Chinese; a 5-step size scale (to be settled with the mono choice).
- **Colour**: Theme tokens only (see Configuration and themes); theme-sync carries them to
  fcitx5, Hyprland borders and the fallback hyprlock.

## Popup windows (layer surfaces)

- **Every popup is a `components/Popup.qml`** (Menu, ScreenCapture, ControlCenter, WsMover,
  Clipboard): a PanelWindow subtype that owns one Overlay surface, mapped only while needed and
  **moved to the focused screen on every `open()`** (`screen = focusedScreen()`; no per-screen
  Variants), the lifecycle `closed → arming → open → closing → closed`, the glass backdrop
  (`backdrop` alias), a MapGate, the warm-up render, the rhythm clock (`t`, `beatPhase`,
  `beatIndex`, `pulse`) and a HitBurst (`burst`). A panel declares its content inside (the
  `default` property routes it to an inner item) and handles `onOpening` (reset), `onIntro`
  (reveal), `onOutro` (hide, then `panelGone()` — or `autoPanelGone: true`) and `onFinished`.
  `introReady` holds the intro (ScreenCapture waits for its freeze PPM), `clickOutCloses`,
  `grabKeyboard`, `dimAmount` configure it; each panel owns its `IpcHandler`. `collapse`
  scatters the triangles while the popup stays open, over `underlay` (black under the glass,
  so they scatter into the dark rather than onto the desktop); both reset on `open()`.
  - Don't redeclare base names in a panel: `phase`, `shown`, `open()`/`close()`, `closed`
    (that one clashes with the window's own signal — the base uses `finished`).
  - Inside a panel, **refer to the base's parts as `root.backdrop` / `root.burst`**: a bare
    `backdrop` inside e.g. `HitBurst { backdrop: backdrop }` resolves to HitBurst's own
    (null) property — that silently lost ControlCenter's shock ring once.
  - Shared panel pieces: `PaperCard` (paper, grid, glass rim, diamond corners), `IrisHost`
    (the diamond-iris / scan / blinds reveal mask: `reveal()`, `conceal()`, `midReveal`),
    `SpringSelector` (ink selector + two afterimages + sheen + hit-stop pop), `CatTab`.
- Overlay, not Top: Hyprland draws fullscreen windows above the Top layer, so Top-layer
  popups vanish behind e.g. a fullscreen browser. CornerHud stays on Top for edge-hover and
  switches to Overlay only for keybind/IPC/OSD reveals.
- Keep the default `quickshell` layer namespace. Hyprland's only `no_anim` layer rule
  (`~/.config/hypr/ui/rules.lua`) matches `^quickshell$`; any other namespace gets the jelly
  `slidefade` layer animation on every map — a full-screen panel then visibly lurches.
- A reveal on a freshly mapped surface must wait for its first frame (`components/MapGate.qml`),
  or the front-loaded OutExpo part of the slide is lost.
- Such a window also gets its **size** a moment after it is shown, so anything laid out on
  "open" sees 0×0 first: size from `screenW`/`screenH` (the screen), not the window.
- **One backdrop for every popup: `components/GlassBackdrop.qml`** (inside Popup). It freezes a frame of the popup's screen and draws `TriField` over it; the look — grid,
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
- `mapped` must never read false mid-close: one false evaluation destroys and re-creates
  the layer surface (a one-frame flash + ~30 ms stall). Popup's single `phase` goes straight
  from open to closing, which is why it is one string and not two flags.
- **Window effects: `widgets/WindowFx.qml`**, driven by the imecaret plugin's
  `winfx>>open|close|focus,ADDR,X,Y,W,H[,why]` (windows on visible workspaces only):
  - open: `hyprctl winfx hold 900` (re-sent every 20 s — the plugin may load after the
    shell) keeps a new window invisible (its LAYOUT alpha at 0). A live ScreencopyView of
    the window itself (its Toplevel via `Hyprland.toplevels[addr].wayland`; content ~150 ms
    in, even while held) feeds `shaders/rain.frag`: cells fall from above, bottom row first,
    land with a flash and sharpen; then `hyprctl winfx release <addr>` shows the real window
    and the lock-on brackets snap onto it. No content within 300 ms: it rains paper.
  - close: a **one-shot ScreencopyView of the screen per close** (frozen while Hyprland still
    draws the closing window; ~50 ms), cut to the window (a ShaderEffectSource with
    `hideSource` — an invisible source item renders nothing) and melted by
    `shaders/melt.frag`. Needs Hyprland's close *slide* off: theme-sync writes `windowFx`
    into `hypr/ui/qs_theme.lua`, and `animations.lua` then uses `popin 100%` for windowsOut
    (disabling it outright drops the closing window at once, before the frame is taken).
  - focus: NieR brackets on a spring; not for focus-follows-mouse (`why === "ffm"`) unless
    `[effects] focusReticleHover`. Focus events wait 60 ms: a new window's focus arrives
    before its open, and the rain locks on at the end instead.
  - Over fullscreen workspaces nothing plays (the hold still applies).

## Architecture

`shell.qml` is the `ShellRoot` entry point and only lists the parts; each part owns its windows, IPC and data (`ThemeManager`, `CornerHud`, `Notifications`, `ImePanel`, `Player`, `Companions`, `WindowFx`, then the popups). Its first line, `//@ pragma IconTheme breeze`, gives Qt an icon theme (without it only hicolor resolves: ~70 % of app icons, none of the preferences-*/device ones). **Pragmas are read only at startup** — a hot reload ignores changes; restart `qs` with the running one's environment (`/proc/<pid>/environ`: it carries `QT_SCALE_FACTOR` etc.). Resident parts use `Variants { model: Quickshell.screens }`; popups are one window that moves to the focused screen.

### Widget map

| File | What it does |
|------|-------------|
| `widgets/CornerHud.qml` | The compact NieR bracket HUD, top-right, floating (no exclusion zone). Parks off the right edge; hovering the edge strip slides it in, hovering the frame expands the stats. Doubles as the **OSD** and shows the **now-playing card / synced lyrics** — see above. Data from the services + native `Hyprland`. `[hud] enabled` (default true). |
| `widgets/ScreenCapture.qml` | Capture panel (`qs ipc call capture toggle`, Print). Categories 複製 (default page on every open) / 截圖 / 錄影 / OCR / 色彩; number keys fire rows, ←/→ or a two-finger horizontal swipe change category (sidebar fill, marker spin and list slide all move in that direction), F toggles the freeze frame, S replays the next open/close style (`Settings.captureOpenStyle`: wipe/rise/scan/iris/blinds, or `qs ipc call capture style <id>`). Open = map transparent ("arming") → `grim -t ppm` freeze frame of this monitor → intro. Region selection runs **in the same window** (phase `selecting`): the panel steps aside and the backdrop becomes the selection layer (exact spotlight via TriField `selection`, crosshair, magnifier fed by `scripts/pixel-probe.py`, W×H/ratio tag). `NIER_CROP` commands crop the freeze PPM immediately; `NIER_GEOM` ones (live grim, wf-recorder) run after the window unmaps, with layout coords from `Hyprland.monitorFor()`. Region selection is a mode of the open phase (`selecting`), not a phase. Save/copy notifications go through `scripts/shot-notify.sh` (thumbnail + action buttons, run with `setsid -f`). A Popup; its IPC (`toggle`/`stop`/`style`) is in the file. |
| `widgets/Menu.qml` | App launcher (780×540), a Popup with an `IrisHost` reveal. Reads `.desktop` files with `scripts/list-apps.py` (`name\|id\|categories\|icon\|binary\|exec`, ~30 ms) and resolves icons with `Quickshell.iconPath()` (Icon=, the binary, the desktop id, `-symbolic`; a glyph otherwise). **Modes** by the query: text → apps ranked by match (prefix > word start > substring), then launch count (`Quickshell.statePath("launch-counts.json")`), then name in code-point order (`localeCompare` put CJK first); `=…`, plain arithmetic or `N unit to unit` → a qalc row on top (↵ copies); `/name` → `fd` under ~ (↵ `xdg-open`); `:name` → `assets/data/emoji.tsv` (emoji names from Python's unicodedata + tagged kaomoji, `scripts/gen-emoji.py`; ↵ copies). Keyboard: ↑↓ navigate, ↵ run, ESC close, ←→ change category. |
| `widgets/Clipboard.qml` | Clipboard history (`qs ipc call clip toggle`, SUPER+SHIFT+V), a Popup built from PaperCard / IrisHost / SpringSelector / CatTab. `cliphist list` on open; ALL / TEXT / LINK / IMAGE tabs (←→), filter as you type, ↵ copies back (`cliphist decode \| wl-copy`) with the hit-stop, DEL deletes. Image thumbnails are decoded one at a time into `/tmp/qs-clip/<id>.png`; the preview pane shows the full text (decoded on focus) or the image. The watchers (`wl-paste --watch cliphist store`) run from Hyprland's autostart. |
| `widgets/WindowFx.qml` | Window open / close / focus effects — see "Window effects" above. |
| `widgets/SettingsPanel.qml` | Settings (`qs ipc call settings toggle`, SUPER+ALT+S), a Popup. Pages STATUS (the helpers from `services/Health.qml` with ✓/✗, plus repair / rebuild-plugin / reload-qs actions), EFFECTS, LOOK, HUD, IME, OTHER; each row is one `shell.conf` key (`bool` switch, `num` with min/max/step, `choice`, `status`, `action`). Writes go through `scripts/conf-set.py` (in place, comments and alignment kept) and show at once (`_pending`) until Config reloads the file. ←→ page · ↑↓ row · ↵/Space toggle or run · −/+ or the wheel adjust. **Always loaded** — no option disables it, so it can turn everything else back on; when adding an option to `shell.conf`, add its row here too. |
| `widgets/ControlCenter.qml` | System controls panel, toggled via `qs ipc call ctrl`. Cross layout: `top` = Wi-Fi/Bluetooth, `bottom` = audio, `left` = qshare send/receive, `right` = notifications. Three depths (`depth`): 1 = the cross, 2 = a section's sub-list, 3 = the detail panel's actions. Everything is spatial: a focused section steps out along its own direction with its ◆› marker on the outer side; ↵ or the direction toward the detail panel (left for the left section, right otherwise) goes deeper; back is Esc or the way to the cross centre (→/← for the side sections, ↓ past the last sub for the top section, ↑ past the first for the bottom one, ←/→ out of the detail panel); lists otherwise clamp. Hovering a list makes it the active one. The inactive list is dimmed; a nav bar at the bottom shows depth ◆◆◇, the path and the keys for that depth. **Wi-Fi and Bluetooth use Quickshell's native modules** (`Quickshell.Networking`, `Quickshell.Bluetooth`): event-driven, with no nmcli/bluetoothctl polling. Known (saved) or open networks `connect()` directly; only new secured ones prompt, and `connectWithPsk()`. `connectionFailed(NoSecrets)` reopens the prompt, marked "Wrong password" if a password had just been sent. Bluetooth writes `enabled` / `discovering` / `trusted` and calls `pair()` / `connect()` / `forget()`; a pair is followed by a connect once `paired` flips. Discovery goes through `btSetScan()`: it keeps the requested state (the adapter's `discovering` only updates when BlueZ answers), retries once when StartDiscovery bounces with InProgress, and stops after 30 s or when the panel closes. The rows are rebuilt only when their visible content changes (a JSON signature; Wi-Fi signal as 0–3 bars). Shell commands run through `Quickshell.execDetached`: the old shared `actProc` silently dropped a command while a previous one, like a slow `bluetoothctl connect`, was still running. That was the "Enable Bluetooth does nothing" bug. Same glass TriField backdrop and shared palette as ScreenCapture/Menu; the cross stays hidden until the backdrop frame is captured (`ready`). **Hit feel** (all driven from root state, so every path — keys, clicks, the direction that goes deeper — gets it): every confirm goes through `activateCurrent()` → hit-stop (`hitT`: the focused item pops and flashes for ~0.1 s) → `confirmPulse` → the focused item answers with `impactAt(window, x, y)` from its marker → that window's `HitBurst` (rings + shards) and `backdrop.impact()` → then `_afterHit()` does the real action. Focus moves squash-and-spring the new item (`press`, via `focusScale(depth)`); sub and action lists use one sliding `SlideSel` (ink selector on a spring + two afterimages) instead of per-row fills — sub rows are split into `part: "card"` (under it) and `"face"` (over it); pressing past a list end bumps the selector (`bump`); depth changes kick the sub list and detail panel along the way you went (`kick`/`kickDir`) and pop the nav bar's depth diamond; ↵ / → with nothing to enter nudges that way instead (`blocked()`). **Notifications** (`right.history`) come from `services/Notifs.qml` in-process (it used to spawn `qs ipc call notifs getHistory` every 1.5 s): rows are keyed `id@ts` and the list is only reassigned when `Notifs.snapshot()`'s JSON changes (on `historyChanged` / `revisionChanged`, not while removals fly out — `_flushing`), so rows don't rebuild; a rebuilt list skips entrances (`_seenNotif`) and rows below a removed one slide up into the gap (`_gapAt`/`_gapH`). ↵ opens a notification whose sender still listens (`live`: ◆ marker; invokes its "default" action, then closes the panel), else toggles its details; → / ← expand / collapse; DEL·X·Backspace or × dismisses (row flies out); ↓ past the last notification selects CLEAR ALL (the footer row, `action === "clear-all"`) and ↵ cascades them all out. Arrows only — no WASD. **Power mode** (`mode`): ↵ on the centre (MENU) turns the cross over (`setMode`: the arms tuck into the centre, swap labels behind it, spring back out; the centre turns to ink and reads POWER). Arms: top Standby = Lock (`scripts/lock.sh`) · Sleep, left Session = Log out (`hyprctl dispatch 'hl.dsp.exit()'`), right Restart = Reboot · Reboot to UEFI (`--firmware-setup`), bottom Shutdown = Power off · Hibernate (`powerSubs` / `powerActs`). There is no depth 3: ↵ on a sub runs it. Lock runs at once and closes; Sleep goes straight to the exit; the rest ask on a YES / NO card first (NO by default; ←→ / Y / N, Esc = NO, hover only picks once the pointer moves). The exit (`_powerGo`): `collapse` + `underlay`, the arms fold, `exitFade` darkens to "SYSTEM SHUTDOWN" etc., then `powerProc` runs the command. A non-zero exit shows FAILED + stderr and brings the menu back. Sleep / Hibernate return as soon as logind has queued them, so the dark holds until logind's `PrepareForSleep(false)` (a `gdbus monitor` on login1 started with the exit), then the unit's `Result` plus its last failure line since the command decide: success → fade out and close; else FAILED with the reason, back to the menu (awake-time fallbacks: 30 s for the sleep to start, 180 s for it to end; 20 s for the others, should the system stay up). **Hibernate is refused up front** when `scripts/hibernate-check.sh` says the image can't fit in the disk swap (zram doesn't count): the Hibernate detail panel shows the readiness line, ↵ shakes it instead of asking. A hibernation that ran out of swap (2026-10-02: 6 GiB swapfile, 19 GB image, "Image saving failed: -28") came back with the NVIDIA display dead — the system was up, the screen frozen on the last frame. Esc / ↵ on the centre goes back to the main cross. **The power key** runs `qs ipc call ctrl power` (opens straight into power mode); the CC holds a `systemd-inhibit --what=handle-power-key` lock while Quickshell runs, so logind doesn't power off on the press — if Quickshell dies the lock goes and logind's own poweroff is back. **Never test these for real**: swap the command for a dry run (`sh -c 'exit 1'` tests the failure path). |
| `widgets/ImePanel.qml` | **Caret position comes from the compositor.** On Hyprland, apps that type through `input-method-v2` (kitty, Chromium/Electron with the Wayland IME flag, GTK4…) never give fcitx5 their caret: its waylandim frontend sets no cursor rect, and only fcitx5's own popup surface gets placed there, by Hyprland. So the **`imecaret` Hyprland plugin** (`hypr-plugin/imecaret`, loaded from `~/.config/hypr/core/autostart.lua`) answers `hyprctl caret` with the focused text input's cursor box in global coords. It uses the same math as Hyprland's `CInputPopup::updateBox`: the owner surface's global box plus `cursorBox()`. The plugin also posts IPC events:
  - `imecommit>>x,y,w,h,n` when text lands in the app (Enter on the phrase, a pick), from each input method's `onCommit`;
  - `imepreedit>>…` when the preedit changes;
  - `imeenter>>…` for Enter in any text input with a caret (English too), from `Event::bus()->m_events.input.keyboard.key`, one per press within 80 ms. The bridge holds an Enter 70 ms so the commit that follows it, if any, replaces it.

  Burst positions scale by the *screen* width (`modelData.width / mw`), not the window's: a window that has just been mapped is 0×0 for a moment, and a burst placed then lands in the corner. That caused the intermittent missing Enter effect. The bridge reads them from `.socket2.sock` and forwards them as `commit` messages (a HitBurst on the phrase: caret − n·h/2, skipped if a candidate pick burst < 250 ms ago) and `spark` messages (re-queried 45 ms later, once the app has moved its caret). Replacing a loaded plugin: `make reload` (`reload.sh`: builds a new file, unloads the old copy by its recorded load path, loads the new one). Never rebuild a `.so` in place while it's loaded. The bridge re-reads the caret on every panel update, and again 40 / 140 ms later (apps report the new box only after drawing the preedit), falling back to fcitx5's rect when the plugin has none (XWayland / D-Bus-module apps). **Rebuild the plugin (`make` in its folder) after every Hyprland update.** It checks the version hash and refuses to load otherwise, and without it the panel sits at the last rect it knew. With `imePanelEnabled: false`, fcitx5 uses its classic window, styled by the generated `quickshell` theme (see Theme sync below), or the static `nier` one in `~/.local/share/fcitx5/themes/nier/` with `[sync] fcitx5 = false`. **fcitx5 candidate window** drawn by the shell (`Settings.imePanelEnabled`). `scripts/imepanel.py` owns the D-Bus name `org.kde.impanel` and speaks the kimpanel protocol: fcitx5 prefers kimpanel (UIPriority 50) over its classic window while the name is owned, and falls back to it the moment the bridge exits, so a dead bridge never blocks typing. The bridge streams JSON lines (table / cands / cursor / aux / preedit / spot) and takes `select N` / `prev` / `next` on stdin. Relative spot rects (Wayland clients) are made absolute with the focused window's `at` from Hyprland's socket, then made monitor-local; QML scales layout px by `width / mw` (QT_SCALE_FACTOR). The panel is a full-screen Overlay surface, mapped only while there's a panel or sparks/burst in flight, with an input mask on the card alone. Look: a paper card, an ink selector springing between candidates, pages sliding in the flip direction, a HitBurst on a pick (detected when fcitx5 empties the list, since it clears the table *before* hiding it), and diamond sparks when the caret steps along a line (`Settings.imeSparks`). **Test without a keyboard:** make a private fcitx5 input context over D-Bus (`org.fcitx.Fcitx.InputMethod1.CreateInputContext` → `FocusIn`, `SetCursorRect`, `Controller1.SetCurrentIM mcbopomofo`, `ProcessKeyEvent`). `ShareInputState=No`, so it doesn't touch the user's apps. |
| `widgets/Player.qml` / `PlayerCard.qml` | Floating media player on every screen (`qs ipc call player toggle`), fed by `services/Media.qml`. The windows are mapped only while the card is shown or sliding out (`card.mapped`); the reveal waits for MapGate. Cava bars stream from cava's stdout via `SplitParser`. |
| `widgets/Notifications.qml` | Notification daemon + popups (top-left, `leftMargin` 24, 6 % from the top). **A popup that times out is only shelved** (hidden, out of the stack/mask) — its Notification stays tracked so the ControlCenter history can still run its actions; transient ones still close, and entries falling off the 50-item history are dismissed. DND and notifications carried over a reload (`lastGeneration`) arrive shelved (`_quiet`), with no popup. The history (minus live objects) survives config reloads via `PersistentProperties`, and carried-over notifications are relinked by id. Clicks get the shared hit feel (`HitBurst`): an action button or a body click (the default action, else close) pops the card, and ✕, a swipe or a middle/right click throw a lighter burst. **Quickshell closes a non-resident notification the instant an action is invoked, destroying its row**, so the card cuts out first and `invoke()` is the row's last act. |
| `widgets/Companions.qml` / `CompanionsCard.qml` | Animated sprites (`[companions] enabled`, off by default; the gifs aren't in the repo). |
| `lock.qml` + `lockscreen/` | **The session lock**, in its own qs process (`scripts/lock.sh`): `WlSessionLock` + `PamContext` (`pam/lock.conf`: pam_unix only, no faillock — `LockState` slows retries after the third failure). The Void look (`LockFace`): black, the theme's light, a big mono clock, a rule with a diamond, "AUTHORIZATION REQUIRED" scrambling in (`components/ScrambleText.qml`), the password as a diamond per character on a hairline (typed from key events, never a TextInput, so fcitx5 never sees it), FAILED in warn with a shake and a burst, AUTHORIZED with the glass closing over the face. Glass (TriField, no frame) only for those moments — it unfolds over the black and shatters as the face comes in — and the caret/seconds tick in steps, so a locked machine idles. Writes `$XDG_RUNTIME_DIR/qs-lock.ready` once `secure` and `.unlocked` before quitting; **`lock.sh` falls back to hyprlock** if `.ready` doesn't appear in 4 s or the process exits without `.unlocked` (Hyprland's `misc:allow_session_lock_restore` lets hyprlock take over a dead lock; its Void-styled config is generated by theme-sync). hypridle: `lock_cmd = lock.sh`, `inhibit_sleep = 3` (sleep waits until the session is really locked). If the lock ever traps you: Ctrl+Alt+F3, log in, `pkill -f lock.qml` — hyprlock takes over. |

### Configuration and themes (user-editable, live)

- **`config/shell.conf`**: every option (`[general] theme`, `scale`, `[hud]`, `[backdrop]` opacity/dim/cellSize/flicker, `[effects]` (click bursts, window open/close/focus), `[ime]`, `[lyrics]`, `[sync]`, `[capture]`, `[notifications]`, `[player]`, `[companions]`).
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
- **Theme sync — fcitx5 and Hyprland follow the theme:** `scripts/theme-sync.py [theme]`, run by `settings/ThemeManager.qml` (400 ms debounce) at start and whenever `Config.themeName`, the theme file or shell.conf changes (so `theme set` previews sync too). `[sync] fcitx5` / `hyprland` in shell.conf turn each off.
  - fcitx5: writes the classicui theme `~/.local/share/fcitx5/themes/quickshell/` (the nier SVGs recoloured: paper, ink, accent edge, light rim), points `classicui.conf` `Theme`/`DarkTheme` at it and calls `Controller1.ReloadAddonConfig classicui`. Off → back to the static `nier` theme. It only shows when the kimpanel bridge isn't running (`[ime] panel = false`, or the bridge died).
  - Hyprland: writes `~/.config/hypr/ui/qs_theme.lua` (from the theme's `[hyprland]` section: `border` = 2–3 colours, `borderAngle`, `shadow`, optional `inactive`; defaults `light, accent` / panel at 40 % / accent) and applies it live with `hyprctl eval 'hl.config({...})'`. `ui/theme.lua` `pcall(dofile)`s it on every config load, so it survives `hyprctl reload`; off → `{ enabled = false }` + `hyprctl reload config-only`, and theme.lua falls back to its own Holographic Y2K palette.
  - Idempotent: nothing is reloaded unless a generated file changed. Its parser and fallbacks mirror Config/Theme.
- **Theme workshop (web):** https://claude.ai/artifact/77qs2XJC3BrySY1pjNJZsW. It previews the themes on mock components, edits every token live (web only) and copies a ready `.conf`. Its parser and fallbacks mirror Config/Theme (and theme-sync.py for `[hyprland]`); keep them in step when tokens change. Source: `~/.config/dotfiles/palette/template.html`; `dotfiles/palette/build.py <out.html>` injects every `config/themes/*.conf`, then republish the output to the same URL. It also mocks the newer parts (HUD now-playing / lyrics and OSD chips, the clipboard panel, the lock-on reticle): when a part's look or tokens change, update its mock there too. Mock data must stay neutral (it is in the public repo).
- Popups pick their screen from `Hyprland.focusedMonitor` (`Popup.focusedScreen()`).

### Singletons

- **`settings/Settings.qml`** / **`settings/Config.qml`** / **`theme/Theme.qml`**: see above. `Settings` also provides the `vw()`, `vh()`, `s()` sizing helpers.
- **`nierlock/Config.qml`** — Config singleton for the lockscreen: sounds path, font sizes, TODO file path, color palette.

### Service singletons (`services/`, `import "../services"`)

Shared, reactive data sources that decouple hardware state from the UI so multiple widgets stay in sync without each polling. `qmldir` declares `module Services`.

- **`services/Notifs.qml`** — the notification history, DND and their persistence (`PersistentProperties`, survives config reloads), shared by the popups (`Notifications.qml` owns the NotificationServer and calls `Notifs.add/relink`) and the Control Center. `snapshot()` gives plain entries with `key` = `id@ts` and `live`; `removeKey(key, invoke)`, `clearAll()`; `revision` bumps when an entry's Notification closes (its `ref` is nulled then, so `live` and dismissals never touch a closed one). Also the `notifs` IPC: `getHistory`, `dismissKey`/`invokeKey <key>`, `clearAll`, `get/set/toggleDnd`.
- **`services/Audio.qml`** — native `Quickshell.Services.Pipewire`: `volume`, `muted`, `ready`, `setVolume()`, `toggleMute()`; the mic (`source`, `micMuted`, `toggleMic()`); output devices (`sinks`, `setDefaultSink(name)` via `Pipewire.preferredDefaultAudioSink`). Volume scale is Pipewire raw (1.0 == 100%, up to ~1.5).
- **`services/Media.qml`** — the current MPRIS player for everyone: the playing one (the last to start if several), else the last that played. `source` (SPOTIFY · YOUTUBE · BILIBILI · FIREFOX · EDGE · CHROME · the player's name, from the bus name, identity and `xesam:url`), `songTitle`/`songArtist` (video titles cleaned: 【MV】, 「Song」, `Artist【Song】`, `Artist - Song` on video sites, `- Topic`…), a debounced `trackChanged()`, and `position` ticking every 250 ms while `wantPosition > 0`.
- **`services/Lyrics.qml`** — synced lyrics for `Media`: lrclib exact (`/api/get`), lrclib search, then NetEase search + `/api/song/lyric`; a hit must contain the title and match the artist, or the length within 2 s; a second pass with only the CJK part of mixed names; results (and misses) cached in `Quickshell.cachePath("lyrics-cache.json")` (400 newest). `on` (from `[lyrics] enabled`), `ready`, `index`, `current`, `next`, `lineProgress`; `[lyrics] offset` shifts the timing.
- **`services/Health.qml`** — keeps the outside helpers running so every feature is on whenever the shell is (`scripts/health.sh check|fix|rebuild`, one JSON line): `plugin` (imecaret loaded — Hyprland's autostart `hl.plugin.load` has silently failed at boot, so the shell loads it when missing; WindowFx re-sends its hold when `plugin` turns true), `built`, `clip` (both cliphist watchers), `fcitx`, `bridge`. A `fix` runs 1.2 s after start and whenever the 30 s check finds the plugin or the watchers gone (at most every 25 s).
- **`services/Ime.qml`** — the current fcitx5 input method (`name`, `label`) and `switched()`, written by ImePanel from the bridge.
- **`services/Sys.qml`** — CPU (`/proc/stat`, jiffies delta between 2 s ticks) and RAM (`/proc/meminfo`, 3 s) read in-process via `FileView` (no fork); GPU from one long-lived `nvidia-smi -lms 2000` stream. `cpuPct`, `memPct`, `gpuPct`, `gpuMem`, `gpuTemp`, `gpuAvailable`.
- **`services/Battery.qml`** — native `Quickshell.Services.UPower`. `available` (false on desktops), `percent` (0–100), `charging`. Note: Quickshell's `UPowerDevice.percentage` is a 0–1 fraction.
- **`services/Net.qml`** — Wi-Fi/Ethernet/Bluetooth from **Quickshell's native `Networking` + `Bluetooth` modules**: bindings on NetworkManager/BlueZ D-Bus signals, no polling. Only NM's wired devices count as Ethernet, so docker/veth/bridges don't show. The IP (not exposed natively) is one `ip -j -4 addr` when the link changes, plus once a minute. `wifiOn/wifiSSID/wifiSig/wifiIP`, `ethOn/ethName/ethIP`, `btOn/btDev/btBat`. It replaced `scripts/netinfo.sh` every 5 s, a busctl BT script every 8 s, an upower pipeline and a resident `nmcli monitor`: about 250 processes a minute. Measured A/B over 40 s: 3.1–4.1 % of a core became ≈1 %.
- **`services/Backlight.qml`** — brightness via brightnessctl. `value` (0–1), `available`, `set()`.
- **`services/Weather.qml`** — wttr.in, 20-min poll. `temp`, `desc`, `icon`, `forecast[]` (3-day), `ready`.
- **`services/Cal.qml`** — gcalcli upcoming events (`events[]`).
- **`services/ClaudeUsage.qml`** — scripts/claude-usage.py cost/token totals (today/week/month).

CornerHud draws all of its pages from these: SYSTEM (cpu/gpu/mem/top-proc) · MEDIA (vol/bri scroll-to-adjust, vol click=mute, bat) · NETWORK · WEATHER (+forecast) · CALENDAR (month + gcal) · TODO · STOPWATCH · CLAUDE. The Control Center polls nothing on its own any more (notifications, outputs, volume from the services; the qshare event file is watched with FileView).

### Colours

Every active part draws from `theme/Theme.qml` tokens (see above); the lockscreen keeps its
own palette in `nierlock/Config.qml`.

### Python helpers

- **`scripts/theme-sync.py`** — the fcitx5 / Hyprland side of the theme (see Theme sync), plus the `windowFx` flag.
- **`scripts/imepanel.py`** — the kimpanel bridge for ImePanel (see its row).
- **`scripts/list-apps.py`**, **`scripts/gen-emoji.py`** — launcher data.
- **`scripts/pixel-probe.py`** — the capture panel's colour-under-pointer helper.
- **`scripts/qshare.py`** — LAN/tunnel file sharing (HTTP + QR code), driven from ControlCenter `left.send` / `left.receive`. Requires `python-qrcode`.
  - `send` takes **several paths**: the phone gets an index page listing every item (per-item download + "download all .zip"); directories are zipped on demand.
  - `recv` serves an upload page (multi-file, drag & drop, per-file progress) writing into `-o DIR`.
  - The server **stays up until stopped** (Ctrl-C, or SIGTERM from Quickshell) so one QR handles several transfers. `--once` restores the old shut-down-after-first-transfer behaviour.
  - `--tunnel` routes through a Cloudflare quick tunnel (works on mobile data); without it the URL is LAN-only.
  - Quickshell IPC is the `--event-file`, appended one line at a time: `COUNT`/`SIZE`/`STATUS`/`URL`/`QR`/`READY`/`TICK <name>`/`DONE`/`CANCELLED`/`ERROR`. ControlCenter watches the file (FileView `watchChanges`) while a transfer runs, re-reads it whole on each change and **rebuilds** state from it, so handlers must stay idempotent.

### Shell scripts

- `scripts/lock.sh` — lock the session: lock.qml, hyprlock as the fallback (see `lock.qml` above). One at a time (`flock`).
- `scripts/health.sh` — the helpers' status / repair (services/Health.qml).
- `scripts/hibernate-check.sh` — can the hibernation image fit in the free disk swap (JSON: ok, swap, image, need in GiB); the Control Center's Hibernate refuses otherwise.
- `scripts/conf-set.py <section> <key> <value>` — sets one `shell.conf` option in place, keeping its comment column (the settings panel's writer).
- `scripts/shot-notify.sh`, `scripts/move-ws.sh` — capture notifications, the workspace mover.
- `scripts/nier-welcome.sh` — a terminal welcome banner.
- `hypr-plugin/imecaret/reload.sh` (`make reload`) — build and swap the plugin into the running
  Hyprland. **Hyprland tracks a loaded plugin by the path it was loaded from**: unloading by
  another path ("plugin not loaded") leaves the old copy running, and two copies post every
  event twice. The script records the path in `.loaded` and unloads exactly that.

The wallpaper picker / pixel-wave helpers, TopBar, VolumeBar, WorkspaceSwitcher, the old
`region/` overlay and unused components are retired to `_attic/` (local, not in the repo).

## External dependencies

The shell calls these tools directly — they must be on PATH:

`hyprctl`, `python3` (+ `python-gobject` for the IME bridge), `grim`, `wl-copy`, `magick`, `cliphist`, `fd`, `qalc`, `wf-recorder`, `tesseract`, `hyprpicker`, `swappy`, `cava`, `nvidia-smi`, `brightnessctl`, `rfkill`, `curl` (weather via wttr.in), `gcalcli`, `kitty`, `yazi`, `zenity` (qshare file picker), `pw-play` (lockscreen audio). Building the plugin needs Hyprland's headers (`pkg-config hyprland`).

Optional: `cloudflared` (for `qshare --tunnel`), `xdg-open` (qshare "Open that folder", launcher files)

The qshare file picker falls back `zenity` → `kdialog` → `yazi` in a terminal; all three
print the chosen paths one per line on stdout, which `ControlCenter.pickerProc` reads directly.

## Key customization points

- **Every option**: `config/shell.conf` (live); typed defaults in `settings/Settings.qml`.
- **Lockscreen TODO path**: `nierlock/Config.qml` — `todoPath` (default: `~/Documents/Notes/TODO.md`)
- **Lockscreen sounds**: place files in `nierlock/sounds/` (see `nierlock/README.md` for filenames)
- **Hyprland keybindings**: `~/.config/hypr/binds/dispatchers.lua` (`qs ipc call …`).

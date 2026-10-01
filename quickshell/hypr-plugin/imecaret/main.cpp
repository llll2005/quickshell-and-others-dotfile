// imecaret — a Hyprland plugin for the shell's input-method candidate window
// (widgets/ImePanel.qml). It exposes what only the compositor knows:
//
//   hyprctl caret      → {"ok":true,"x":…,"y":…,"w":…,"h":…}  (or {"ok":false})
//                        the focused text input's cursor box, global layout px
//   IPC event imecommit>>X,Y,W,H,N    the IM committed N characters to the app
//                        (Enter on a composed phrase, a picked candidate…)
//   IPC event imepreedit>>X,Y,W,H,N   the preedit changed (now N characters long)
//   IPC event imeenter>>X,Y,W,H,0     Enter pressed in a text input with a caret
//                        (English too, where no IM commit happens)
//   IPC event clickfx>>X,Y,BUTTON     a mouse button went down on a window (not on a
//                        layer surface: bars, the shell's HUD and popups answer
//                        their own clicks), at the pointer, global layout px
//   IPC event winfx>>KIND,ADDR,X,Y,W,H[,REASON]   a window opened / closed / took
//                        focus (KIND = open | close | focus), its box in global layout
//                        px — where it is going for open/focus, where it is for close;
//                        focus adds why: ffm (focus follows mouse) | key | click | other
//   hyprctl winfx hold <ms>  newly opened windows stay invisible (their layout alpha
//                        at 0) while the shell assembles them on its overlay — until
//                        `hyprctl winfx release <addr>`, or at most <ms>; 0 (the
//                        default) = the plugin changes nothing
//
// Why: apps that type through text-input-v3 (kitty, Chromium/Electron with the
// Wayland IME, GTK4…) tell only the compositor where their caret is, and their
// preedit/commits travel IM → compositor → app without the IM's panel seeing them.
// The box is the one Hyprland places fcitx5's own popup from
// (CInputPopup::updateBox: owner surface's global box + the text input's cursorBox()).
// Read-only except for the opt-in open hold above. All listeners go away on unload.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/input/InputMethodRelay.hpp>
#include <hyprland/src/managers/input/TextInput.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/protocols/InputMethodV2.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>

#include <format>
#include <optional>
#include <stdexcept>
#include <vector>

inline HANDLE PHANDLE = nullptr;

static std::optional<CBox> caretBox() {
    if (!g_pInputManager)
        return std::nullopt;
    const auto TI = g_pInputManager->m_relay.getFocusedTextInput();
    if (!TI || !TI->isEnabled() || !TI->hasCursorRectangle())
        return std::nullopt;
    const auto SURF = TI->focusedSurface();
    if (!SURF)
        return std::nullopt;
    const auto OWNER = Desktop::View::CWLSurface::fromResource(SURF);
    if (!OWNER)
        return std::nullopt;
    const auto PARENT = OWNER->getSurfaceBoxGlobal();
    if (!PARENT)
        return std::nullopt;
    const CBox CB = TI->cursorBox();
    return CBox{PARENT->x + CB.x, PARENT->y + CB.y, CB.w, CB.h};
}

static std::string caret(eHyprCtlOutputFormat, std::string) {
    const auto B = caretBox();
    if (!B)
        return R"({"ok":false})";
    return std::format(R"({{"ok":true,"x":{},"y":{},"w":{},"h":{}}})", (int)B->x, (int)B->y, (int)B->w, (int)B->h);
}

static size_t utf8Chars(const std::string& s) {
    size_t n = 0;
    for (unsigned char c : s)
        if ((c & 0xC0) != 0x80)
            n++;
    return n;
}

static void post(const char* name, size_t chars) {
    if (!g_pEventManager)
        return;
    const auto B = caretBox();
    if (!B)   // no text input with a caret: nothing to aim at
        return;
    g_pEventManager->postEvent(SHyprIPCEvent{name, std::format("{},{},{},{},{}", (int)B->x, (int)B->y, (int)B->w, (int)B->h, chars)});
}

// one listener per input method (fcitx5 gets a new one each time it restarts)
struct SIMEHook {
    WP<CInputMethodV2>  ime;
    CHyprSignalListener onCommit;
};
static std::vector<SIMEHook> g_hooks;
static CHyprSignalListener   g_newIME;
static CHyprSignalListener   g_key;
static uint32_t              g_lastEnterMs = 0;

// Enter / keypad Enter (evdev codes). One post per press: the IM hands unhandled keys
// back through its own virtual keyboard, which can surface the same press again.
static CHyprSignalListener g_button;

static void onButton(IPointer::SButtonEvent ev, Event::SCallbackInfo&) {
    try {
        if (ev.state != WL_POINTER_BUTTON_STATE_PRESSED || !g_pEventManager || !g_pInputManager)
            return;
        if (g_pInputManager->m_lastFocusOnLS)
            return;
        const auto P = g_pInputManager->getMouseCoordsInternal();
        g_pEventManager->postEvent(SHyprIPCEvent{"clickfx", std::format("{},{},{}", (int)P.x, (int)P.y, ev.button)});
    } catch (...) {
    }
}

static void onKey(IKeyboard::SKeyEvent ev, Event::SCallbackInfo&) {
    try {
        if (ev.state != WL_KEYBOARD_KEY_STATE_PRESSED || (ev.keycode != 28 && ev.keycode != 96))
            return;
        if (g_lastEnterMs && ev.timeMs - g_lastEnterMs < 80)
            return;
        g_lastEnterMs = ev.timeMs;
        post("imeenter", 0);
    } catch (...) {
    }
}

static void onIMECommit(const WP<CInputMethodV2>& weak) {
    try {
        const auto IME = weak.lock();
        if (!IME)
            return;
        // m_current = this commit's state; it stays until the next one (the relay
        // forwards the same values to the app)
        const auto& CUR = IME->m_current;
        if (CUR.committedString.committed && !CUR.committedString.string.empty())
            post("imecommit", utf8Chars(CUR.committedString.string));
        else if (CUR.preeditString.committed)
            post("imepreedit", utf8Chars(CUR.preeditString.string));
    } catch (...) {
        // never let a formatting hiccup escape into the compositor
    }
}

static void attach(const SP<CInputMethodV2>& ime) {
    if (!ime)
        return;
    std::erase_if(g_hooks, [](const SIMEHook& h) { return h.ime.expired(); });
    for (const auto& h : g_hooks)
        if (h.ime.lock() == ime)
            return;
    WP<CInputMethodV2> weak = ime;
    g_hooks.push_back({weak, ime->m_events.onCommit.listen([weak] { onIMECommit(weak); })});
}

// ── window effects (widgets/WindowFx.qml) ──
static int                              g_holdMs = 0;
static CHyprSignalListener              g_wOpen, g_wClose, g_wActive;
static std::vector<SP<CEventLoopTimer>> g_timers;

// real windows on a workspace that's on screen: no X11 menus / tooltips, nothing
// tiny, nothing on a special or hidden workspace
static bool fxWindow(const PHLWINDOW& w, double minW, double minH) {
    if (!w || !w->m_isMapped || w->isHidden() || w->isX11OverrideRedirect() || w->onSpecialWorkspace())
        return false;
    if (!w->m_workspace || !w->m_workspace->isVisible())
        return false;
    const auto S = w->sizeAnimation()->goal();
    return S.x >= minW && S.y >= minH;
}

static void postWin(const char* kind, const PHLWINDOW& w, bool goal) {
    if (!g_pEventManager)
        return;
    const auto P = goal ? w->positionAnimation()->goal() : w->positionAnimation()->value();
    const auto S = goal ? w->sizeAnimation()->goal() : w->sizeAnimation()->value();
    g_pEventManager->postEvent(SHyprIPCEvent{"winfx", std::format("{},{:x},{},{},{},{}", kind, (uintptr_t)w.get(), (int)P.x, (int)P.y, (int)S.x, (int)S.y)});
}

static void reveal(const PHLWINDOW& W) {
    W->alpha(Desktop::View::WINDOW_ALPHA_LAYOUT)->setValueAndWarp(1.F);
    g_pHyprRenderer->damageWindow(W);
}

static void onWindowOpen(PHLWINDOW w) {
    try {
        if (!fxWindow(w, 120, 80))
            return;
        postWin("open", w, true);
        if (g_holdMs <= 0 || !g_pEventLoopManager)
            return;
        w->alpha(Desktop::View::WINDOW_ALPHA_LAYOUT)->setValueAndWarp(0.F);
        PHLWINDOWREF weak = w;
        auto         t    = makeShared<CEventLoopTimer>(
            std::chrono::milliseconds(g_holdMs),
            [weak](SP<CEventLoopTimer> self, void*) {
                if (const auto W = weak.lock())
                    reveal(W);
                std::erase(g_timers, self);
            },
            nullptr);
        g_timers.push_back(t);
        g_pEventLoopManager->addTimer(t);
    } catch (...) {
    }
}

static std::string winfxCmd(eHyprCtlOutputFormat, std::string req) {
    // "winfx release 55840a8f85f0": the shell's assembly is done, show it now
    const auto rel = req.find("release");
    if (rel != std::string::npos) {
        try {
            const uintptr_t ADDR = std::stoull(req.substr(rel + 7), nullptr, 16);
            for (const auto& w : Desktop::windowState()->windows())
                if (w && (uintptr_t)w.get() == ADDR) {
                    reveal(w);
                    return "ok";
                }
        } catch (...) {
        }
        return "no such window";
    }
    // "winfx hold 900"
    const auto pos = req.find("hold");
    if (pos != std::string::npos) {
        try {
            g_holdMs = std::clamp(std::stoi(req.substr(pos + 4)), 0, 2000);
        } catch (...) {
            return "usage: hyprctl winfx hold <ms>";
        }
    }
    return std::format(R"({{"hold":{}}})", g_holdMs);
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    // built against exactly this Hyprland, or not at all
    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(PHANDLE, "[imecaret] built for a different Hyprland — rebuild it (make)", CHyprColor{1.0, 0.2, 0.2, 1.0}, 8000);
        throw std::runtime_error("[imecaret] version mismatch");
    }

    HyprlandAPI::registerHyprCtlCommand(PHANDLE, SHyprCtlCommand{.name = "caret", .exact = true, .fn = caret});
    HyprlandAPI::registerHyprCtlCommand(PHANDLE, SHyprCtlCommand{.name = "winfx", .exact = false, .fn = winfxCmd});

    if (g_pInputManager)
        attach(g_pInputManager->m_relay.m_inputMethod.lock());
    if (PROTO::ime)
        g_newIME = PROTO::ime->m_events.newIME.listen([](const SP<CInputMethodV2>& ime) { attach(ime); });
    g_key    = Event::bus()->m_events.input.keyboard.key.listen(onKey);
    g_button = Event::bus()->m_events.input.mouse.button.listen(onButton);
    g_wOpen  = Event::bus()->m_events.window.openLate.listen(onWindowOpen);
    g_wClose = Event::bus()->m_events.window.close.listen([](PHLWINDOW w) {
        try {
            if (fxWindow(w, 120, 80))
                postWin("close", w, false);
        } catch (...) {
        }
    });
    g_wActive = Event::bus()->m_events.window.active.listen([](PHLWINDOW w, Desktop::eFocusReason why) {
        try {
            if (!fxWindow(w, 60, 40))
                return;
            // focus,ADDR,X,Y,W,H,REASON — the shell skips focus-follows-mouse by default
            const char* r = why == Desktop::FOCUS_REASON_FFM ? "ffm" : why == Desktop::FOCUS_REASON_KEYBIND ? "key" : why == Desktop::FOCUS_REASON_CLICK ? "click" : "other";
            const auto P = w->positionAnimation()->goal();
            const auto S = w->sizeAnimation()->goal();
            if (g_pEventManager)
                g_pEventManager->postEvent(SHyprIPCEvent{"winfx", std::format("focus,{:x},{},{},{},{},{}", (uintptr_t)w.get(), (int)P.x, (int)P.y, (int)S.x, (int)S.y, r)});
        } catch (...) {
        }
    });

    return {"imecaret", "hyprctl caret/winfx + ime/click/window events for the shell's effects", "quickshell", "1.4"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // drop every listener and timer before this code is unmapped
    for (auto& t : g_timers)
        if (g_pEventLoopManager) {
            t->cancel();
            g_pEventLoopManager->removeTimer(t);
        }
    g_timers.clear();
    g_wOpen.reset();
    g_wClose.reset();
    g_wActive.reset();
    g_button.reset();
    g_key.reset();
    g_newIME.reset();
    g_hooks.clear();
}

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
//
// Why: apps that type through text-input-v3 (kitty, Chromium/Electron with the
// Wayland IME, GTK4…) tell only the compositor where their caret is, and their
// preedit/commits travel IM → compositor → app without the IM's panel seeing them.
// The box is the one Hyprland places fcitx5's own popup from
// (CInputPopup::updateBox: owner surface's global box + the text input's cursorBox()).
// Read-only: it never changes compositor state. All listeners go away on unload.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/input/InputMethodRelay.hpp>
#include <hyprland/src/managers/input/TextInput.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/protocols/InputMethodV2.hpp>
#include <hyprland/src/event/EventBus.hpp>

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

    if (g_pInputManager)
        attach(g_pInputManager->m_relay.m_inputMethod.lock());
    if (PROTO::ime)
        g_newIME = PROTO::ime->m_events.newIME.listen([](const SP<CInputMethodV2>& ime) { attach(ime); });
    g_key    = Event::bus()->m_events.input.keyboard.key.listen(onKey);
    g_button = Event::bus()->m_events.input.mouse.button.listen(onButton);

    return {"imecaret", "hyprctl caret + imecommit/imepreedit/imeenter/clickfx events for the shell's effects", "quickshell", "1.3"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // drop every listener before this code is unmapped
    g_button.reset();
    g_key.reset();
    g_newIME.reset();
    g_hooks.clear();
}

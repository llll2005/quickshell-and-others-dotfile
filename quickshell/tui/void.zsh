# voidbox — passwords and pacman in the Void (quickshell/tui). Sourced from ~/.zshrc
# after glamour-box's init.sh, whose sudo / pacman wrappers these replace.
#   sudo …                  an interactive terminal gets the Void password screen, through
#                           sudo's own askpass mechanism (SUDO_ASKPASS, `sudo -A`);
#                           scripts and pipes get plain sudo
#   pacman … / sudo pacman …  a transaction in the Void (queries run as they are)
#   ssh, git                passphrases, passwords, user names and the unknown-host
#                           question in the same screen (SSH_ASKPASS; git falls back to it)
(( $+commands[voidbox] )) || return 0
export SUDO_ASKPASS="${commands[voidbox]:h}/voidbox-askpass"
export SSH_ASKPASS="$SUDO_ASKPASS" SSH_ASKPASS_REQUIRE=force

sudo() {
    if [[ -o interactive && -t 0 && -t 1 ]]; then
        if [[ "$1" == pacman || "$1" == /usr/bin/pacman ]]; then
            shift
            voidbox pacman "$@"
            return
        fi
        VOIDBOX_CMD="$*" command sudo -A "$@"
    else
        command sudo "$@"
    fi
}

pacman() {
    if [[ -o interactive && -t 0 && -t 1 ]]; then
        voidbox pacman "$@"
    else
        command pacman "$@"
    fi
}

# ── glamour-box's other helpers, its gum menus redone as voidbox cards / themed fzf ──
#   dl URL [FILE]       pick the engine (aria2, many connections · curl), then glamour-box's
#                       download / progress view
#   gclone REPO [DIR]   git clone with glamour-box's progress bar
#   gsnap               search snapper's root snapshots; prints how to undo one
# _qs_say LABEL [TEXT]: one line in the shell's voice (◆  L A B E L  text)
_qs_say() {
    local label=${(U)1} c=${QS[light]:-#fff6cf} m=${QS[muted]:-#8f8873} f=${QS[fg]:-#d6cfb5} text=""
    [[ -n $2 ]] && text="   %F{$m}${2//\%/%%}%f"
    print -P "%F{$c}◆%f  %F{$f}${(j: :)${(s::)label}}%f$text"
}

dl() {
    local url=$1 out=${2:-${1:t}}
    if [[ -z $url ]]; then _qs_say usage "dl URL [FILE]"; return 1; fi
    _qs_say target "$out"
    local engine
    engine=$(voidbox choose "download engine" $'TURBO\taria2, many connections' $'SAFE\tcurl, one connection') || return 1
    case $engine in
        TURBO) /usr/local/bin/glamour-box --mode download --url "$url" --out "$out" ;;
        SAFE)  curl -L --progress-bar -o "$out" "$url" 2>&1 | /usr/local/bin/glamour-box --mode progress ;;
    esac
}

gclone() {
    local repo=$1 dir=${2:-${${1:t}%.git}}
    if [[ -z $repo ]]; then _qs_say usage "gclone REPO [DIR]"; return 1; fi
    _qs_say clone "$repo → $dir"
    git clone --progress "$repo" "$dir" 2>&1 | /usr/local/bin/glamour-box --mode progress
}

gsnap() {
    sudo -v || return 1
    local sel
    sel=$(command sudo snapper -c root list 2>/dev/null | sed '1,2d' |
          fzf --header='SNAPSHOTS · ↵ PICK · ESC CLOSE' --prompt='▸ ') || return 1
    local id=${${=sel}[1]}
    _qs_say snapshot "$id"
    print -P "   %F{${QS[muted]}}undo its changes:%f  %F{${QS[fg]}}sudo snapper -c root undochange $id..0%f"
}

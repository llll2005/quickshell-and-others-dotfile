# voidbox — sudo's password and pacman in the Void (quickshell/tui). Sourced from ~/.zshrc
# after glamour-box's init.sh, whose sudo / pacman wrappers these replace.
#   sudo …                  an interactive terminal gets the Void password screen, through
#                           sudo's own askpass mechanism (SUDO_ASKPASS, `sudo -A`);
#                           scripts and pipes get plain sudo
#   pacman … / sudo pacman …  a transaction in the Void (queries run as they are)
(( $+commands[voidbox] )) || return 0
export SUDO_ASKPASS="${commands[voidbox]:h}/voidbox-askpass"

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

# tools.zsh — the command-line tools, coloured by the theme (qs-theme.zsh, from the
# shell's scripts/theme-sync.py). `manual` shows the cheat sheet (MANUAL.md).
#   z / zi        zoxide: jump to a directory you've been to (zi: pick it with fzf)
#   Ctrl+T        fzf: insert a file path · Alt+C: cd into a directory below
#   Ctrl+R        atuin: search the history (fzf's search when atuin isn't installed)
#   ssh           kitten ssh inside kitty: kitty's terminfo + shell integration remotely
#   git diff/log  paged by delta, when installed
#   unknown cmd   says which package has it (pkgfile)
# Every init script is cached (~/.cache/zsh/init-*.zsh) and rebuilt when its program
# changes, so none of them runs at startup.

typeset -g _qs_cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/zsh
[[ -d $_qs_cache_dir ]] || mkdir -p $_qs_cache_dir

# _qs_init name cmd…: source cmd's output, cached until the program is updated
_qs_init() {
    local name=$1; shift
    local bin=${commands[$1]} out=$_qs_cache_dir/init-$name.zsh
    [[ -n $bin ]] || return 1
    if [[ ! -s $out || $bin -nt $out ]]; then
        "$@" >| $out 2>/dev/null || { rm -f $out; return 1 }
    fi
    source $out
}

# ── the theme's colours into what can't read QS directly (prompt.zsh calls this when
#    qs-theme.zsh changes; fast-syntax-highlighting calls it once it has loaded) ──
_qs_theme_apply() {
    export FZF_DEFAULT_OPTS="$QS_FZF_COLORS --layout=reverse --height=45% --min-height=12 --border=none --info=inline-right --pointer=▸ --marker=◆ --prompt='▸ ' --separator=─ --scrollbar=│ --highlight-line --cycle"
    if (( ${+FAST_HIGHLIGHT_STYLES} )); then
        local k
        for k in ${(k)QS_FSH}; do
            FAST_HIGHLIGHT_STYLES[${FAST_THEME_NAME}$k]=$QS_FSH[$k]
        done
    fi
}
_qs_theme_apply

# ── zoxide ──
_qs_init zoxide zoxide init zsh

# ── fzf: Ctrl+T, Alt+C (and Ctrl+R until atuin takes it) ──
if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:300 {} 2>/dev/null || eza -1 --color=always --icons {}'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always --icons {}'"
_qs_init fzf fzf --zsh

# ── atuin: the history behind Ctrl+R (↑ stays history-substring-search) ──
_qs_init atuin atuin init zsh --disable-up-arrow

# ── delta pages git ──
(( $+commands[delta] )) && export GIT_PAGER=delta

# ── ssh through kitty ──
if [[ -n $KITTY_WINDOW_ID ]] && (( $+commands[kitten] )); then
    alias ssh='kitten ssh'
fi

# ── a command that isn't there: say so in the shell's voice, and where it lives ──
command_not_found_handler() {
    local cmd=${1//\%/%%} pkgs
    print -P "%F{$QS[red]}◆%f %F{$QS[fg]}$cmd%f  %F{$QS[muted]}command not found%f" >&2
    if (( $+commands[pkgfile] )); then
        pkgs=(${(f)"$(pkgfile -b -- "$1" 2>/dev/null)"})
        if (( $#pkgs )); then
            print -P "  %F{$QS[muted]}in%f %F{$QS[light]}${(j:, :)pkgs}%f   %F{$QS[muted]}pacman -S ${pkgs[1]:t}%f" >&2
        fi
    fi
    return 127
}

# ── the cheat sheet ──
manual() {
    local f=${XDG_CONFIG_HOME:-$HOME/.config}/zsh/MANUAL.md
    if (( $+commands[bat] )); then
        bat --style=plain --paging=always --language=markdown -- $f
    else
        ${PAGER:-less} $f
    fi
}

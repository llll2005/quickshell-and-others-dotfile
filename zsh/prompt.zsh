# prompt.zsh — the prompt in the shell's voice (quickshell/CLAUDE.md, "Design language"):
# pure zsh, no program per prompt. Colours from qs-theme.zsh (scripts/theme-sync.py), which
# is re-read at the next prompt whenever the theme changes.
#
#   ◆ ~/.config/quickshell   main ↑1 ●2 ✚1 …3   ◇ ml   2.4s   ✕ 1
#   ▸ _
#
#   ◆ light, or warn after a failure · the path (last three parts) · git: branch, ahead /
#   behind, staged ●, changed ✚, untracked … (read in the background: a slow repo never
#   holds the prompt) · the conda env / venv · how long the last command took (≥ 2 s) ·
#   its exit status. Once a command is entered its prompt folds to `▸ command` (transient),
#   so the scrollback reads as a list of commands and their output.
#   A command of 10 s or more that ends while you're in another window puts a card in the
#   shell's HUD (DONE / FAILED, how long; click it to come back).

zmodload zsh/datetime zsh/stat 2>/dev/null
autoload -Uz add-zle-hook-widget

typeset -g _qs_theme_file=${XDG_CONFIG_HOME:-$HOME/.config}/zsh/qs-theme.zsh
typeset -g _qs_theme_mtime=0
_qs_theme_load() {
    local -a st
    zstat -A st +mtime -- $_qs_theme_file 2>/dev/null || return
    (( st[1] == _qs_theme_mtime )) && return
    _qs_theme_mtime=$st[1]
    source $_qs_theme_file
    (( $+functions[_qs_theme_apply] )) && _qs_theme_apply
}
_qs_theme_load
(( $+QS )) || typeset -gA QS=(fg '#d6cfb5' muted '#8f8873' light '#fff6cf' accent '#6e2a2a' red '#d4806f' green '#9ab58c' yellow '#d9b46a' blue '#8fa6d0' cyan '#7fb7b0' magenta '#c48fb0')

# kitty's prompt mark (its shell integration jumps between prompts by it)
typeset -g _qs_mark=$'%{\e]133;A\a%}'

# ── git, in the background ──
typeset -g _qs_git='' _qs_git_fd=''
_qs_git_start() {
    if [[ -n $_qs_git_fd ]]; then
        zle -F $_qs_git_fd 2>/dev/null
        exec {_qs_git_fd}<&-
        _qs_git_fd=''
    fi
    exec {_qs_git_fd}< <(
        git status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null | command awk '
            /^# branch.oid/  { oid = substr($3, 1, 7) }
            /^# branch.head/ { head = $3 }
            /^# branch.ab/   { ahead = substr($3, 2); behind = substr($4, 2) }
            /^[12u] /        { if (substr($2, 1, 1) != ".") s++; if (substr($2, 2, 1) != ".") m++ }
            /^\? /           { u++ }
            END { if (head == "") exit; if (head == "(detached)") head = "@" oid
                  printf "%s %d %d %d %d %d\n", head, ahead, behind, s, m, u }'
    )
    zle -F $_qs_git_fd _qs_git_done
}
_qs_git_done() {
    local line fd=$1
    read -r line <&$fd
    zle -F $fd
    exec {fd}<&-
    _qs_git_fd=''
    [[ $line == $_qs_git ]] && return
    _qs_git=$line
    _qs_build
    zle && zle .reset-prompt
}

# ── the timer ──
typeset -g _qs_t0=0 _qs_took='' _qs_cmd=''
_qs_preexec() { _qs_t0=$EPOCHREALTIME; _qs_cmd=$1 }

# a command of 10 s or more that ends while its kitty window isn't the focused one: the
# shell's HUD shows a DONE / FAILED card (a click on it comes back here)
_qs_task_card() {
    [[ -n $KITTY_PID && -n $HYPRLAND_INSTANCE_SIGNATURE ]] || return
    local code=$1 secs=$2 cmd=$3
    {
        local aw=$(hyprctl activewindow -j 2>/dev/null)
        [[ $aw =~ '"pid": ([0-9]+)' && $match[1] == $KITTY_PID ]] && return
        qs ipc call hud cmdDone $code $secs "$cmd" $KITTY_PID >/dev/null 2>&1
    } &!
}

# ── the prompt ──
typeset -g _qs_status=0
_qs_build() {
    local c_fg=$QS[fg] c_mu=$QS[muted] c_li=$QS[light] c_wa=$QS[red] c_ok=$QS[green] c_ac=$QS[yellow]
    local info="" dia="%F{$c_li}◆%f"
    (( _qs_status )) && dia="%F{$c_wa}◆%f"
    (( EUID == 0 )) && info+=" %F{$c_wa}ROOT%f"
    [[ -n $SSH_CONNECTION ]] && info+=" %F{$c_mu}%n@%m%f"
    info+=" %F{$c_fg}%(4~|…/%3~|%~)%f"
    if [[ -n $_qs_git ]]; then
        local -a g=(${=_qs_git})
        local gs=" %F{$c_mu}${g[1]//\%/%%}%f"
        (( g[2] )) && gs+=" %F{$c_ac}↑$g[2]%f"
        (( g[3] )) && gs+=" %F{$c_ac}↓$g[3]%f"
        (( g[4] )) && gs+=" %F{$c_ok}●$g[4]%f"
        (( g[5] )) && gs+=" %F{$c_wa}✚$g[5]%f"
        (( g[6] )) && gs+=" %F{$c_mu}…$g[6]%f"
        info+="  $gs"
    fi
    local env=${CONDA_DEFAULT_ENV:#base}
    [[ -n $VIRTUAL_ENV ]] && env=${VIRTUAL_ENV:t}
    [[ -n $env ]] && info+="   %F{$c_mu}◇ $env%f"
    [[ -n $_qs_took ]] && info+="   %F{$c_mu}$_qs_took%f"
    (( _qs_status )) && info+="   %F{$c_wa}✕ $_qs_status%f"
    PROMPT="${_qs_mark}${dia}${info}"$'\n'"%F{$c_li}▸%f "
    RPROMPT=''
}

_qs_precmd() {
    _qs_status=$?
    _qs_theme_load
    _qs_took=''
    if (( _qs_t0 > 0 )); then
        local d=$(( EPOCHREALTIME - _qs_t0 ))
        if (( d >= 3600 )); then _qs_took=$(printf '%dh%02dm' $(( d / 3600 )) $(( d % 3600 / 60 )))
        elif (( d >= 60 )); then _qs_took=$(printf '%dm%02ds' $(( d / 60 )) $(( d % 60 )))
        elif (( d >= 2 )); then _qs_took=$(printf '%.1fs' $d)
        fi
        (( d >= 10 )) && _qs_task_card $_qs_status ${d%.*} $_qs_cmd
        _qs_t0=0
    fi
    [[ $PWD != $_qs_git_pwd ]] && _qs_git=''
    typeset -g _qs_git_pwd=$PWD
    _qs_build
    _qs_git_start
}

# the entered line's prompt folds to one `▸`
_qs_transient() {
    PROMPT="${_qs_mark}%F{$QS[muted]}▸%f "
    RPROMPT=''
    zle .reset-prompt
}
# Ctrl+C on a line folds it too (no line-finish then)
TRAPINT() {
    if [[ -o zle ]] && zle; then
        _qs_transient
    fi
    return $(( 128 + $1 ))
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _qs_preexec
add-zsh-hook precmd _qs_precmd
add-zle-hook-widget line-finish _qs_transient
# the prompt is built as a plain string: no prompt_subst, so a branch named `$(…)` stays text
setopt no_prompt_subst no_prompt_bang
PROMPT2="%F{$QS[muted]}·%f "

#!/bin/bash
# tmonitor.sh - cria uma sessao tmux com N panes de comando e um shell interativo.
# Comandos vem do tmonitor.conf do workdir, da CLI (--pane-N), ou de ambos
# (CLI sobrescreve o conf chave a chave). Ver usage() ou README.md.
#
# Tambem serve de biblioteca para o reload_tmonitor.sh: quando sourceado com
# TMONITOR_LIB_ONLY definido, apenas define funcoes e nao executa main.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.tmux/tmonitor/state"

DETACH=0
FORCE=0
RESTORE_MODE=0
RESTORE_NAME=""
POSITIONAL=""
CLI_SESSION=""
CLI_LAYOUT=""
CLI_SHELL_HEIGHT=""
CLI_PANE_MAX=0

usage() {
  cat <<'EOF'
Use: tmonitor.sh [workdir] [options]

Creates a tmux session with N command panes plus an interactive shell pane.
Commands come from <workdir>/tmonitor.conf (CMD1..CMDN), from the CLI, or
both (CLI overrides the conf, key by key). Without any --pane-N option, a
tmonitor.conf in the workdir is required.

Options:
  --pane-N="command"    command for pane N (overrides CMDN; N starts at 1)
  --label-N="text"      label for pane N (overrides LABELN)
  --session="name"      session name (overrides SESSION_NAME; default: monitoring)
  --layout=NAME         columns | rows | grid (overrides LAYOUT; default: columns)
  --shell-height=PCT    interactive pane height, 10-90 (default: 30)
  --detach              create the session without attaching
  --force               kill and recreate the session if it already exists
  --restore [name]      recreate a session from its snapshot; without a name,
                        lists the available snapshots
  --help                show this help
EOF
}

err() {
  echo "Error: $*" >&2
  exit 1
}

# Nome de arquivo seguro derivado do nome da sessao ('/' e espacos viram '_')
state_file_for() {
  printf '%s' "$1" | tr '/ ' '__'
}

list_snapshots() {
  local f found=0
  for f in "$STATE_DIR"/*.state; do
    [ -f "$f" ] || continue
    [ "$found" -eq 0 ] && echo "Available snapshots:" && found=1
    basename "$f" .state
  done
  [ "$found" -eq 0 ] && echo "No snapshots found in $STATE_DIR"
}

parse_args() {
  local n
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --detach) DETACH=1 ;;
      --force) FORCE=1 ;;
      --restore=*)
        RESTORE_MODE=1
        RESTORE_NAME="${1#*=}"
        ;;
      --restore)
        RESTORE_MODE=1
        if [ $# -gt 1 ] && [ "${2#--}" = "$2" ]; then
          RESTORE_NAME="$2"
          shift
        fi
        ;;
      --session=*) CLI_SESSION="${1#*=}" ;;
      --layout=*) CLI_LAYOUT="${1#*=}" ;;
      --shell-height=*) CLI_SHELL_HEIGHT="${1#*=}" ;;
      --pane-*=*)
        n="${1#--pane-}"
        n="${n%%=*}"
        case "$n" in ''|*[!0-9]*) err "invalid pane index in '$1'" ;; esac
        n=$((10#$n))
        [ "$n" -ge 1 ] || err "pane index must be >= 1 in '$1'"
        eval "CLI_PANE_$n=\${1#*=}"
        [ "$n" -gt "$CLI_PANE_MAX" ] && CLI_PANE_MAX="$n"
        ;;
      --label-*=*)
        n="${1#--label-}"
        n="${n%%=*}"
        case "$n" in ''|*[!0-9]*) err "invalid label index in '$1'" ;; esac
        n=$((10#$n))
        [ "$n" -ge 1 ] || err "label index must be >= 1 in '$1'"
        eval "CLI_LABEL_$n=\${1#*=}"
        ;;
      --*)
        echo "Error: unknown option '$1'" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
      *)
        [ -n "$POSITIONAL" ] && err "unexpected extra argument '$1'"
        POSITIONAL="$1"
        ;;
    esac
    shift
  done
}

# Materializa CMDS/LABELS a partir de CMD1..N / LABEL1..N (conf ou snapshot)
# mesclados com os overrides CLI_PANE_n / CLI_LABEL_n (CLI vence, chave a chave).
# A descoberta e sequencial: para no primeiro indice sem comando.
materialize_commands() {
  CMDS=()
  LABELS=()
  local i=1 cli conf clil confl val
  while :; do
    eval "cli=\${CLI_PANE_$i:-}"
    eval "conf=\${CMD$i:-}"
    val="${cli:-$conf}"
    [ -z "$val" ] && break
    eval "clil=\${CLI_LABEL_$i:-}"
    eval "confl=\${LABEL$i:-}"
    CMDS+=("$val")
    LABELS+=("${clil:-$confl}")
    i=$((i + 1))
  done
  NCMDS=${#CMDS[@]}
}

apply_defaults_and_validate() {
  SESSION_NAME="${CLI_SESSION:-${SESSION_NAME:-monitoring}}"
  LAYOUT="${CLI_LAYOUT:-${LAYOUT:-columns}}"
  SHELL_HEIGHT="${CLI_SHELL_HEIGHT:-${SHELL_HEIGHT:-30}}"
  STATS="${STATS:-on}"

  case "$SESSION_NAME" in
    *:*|*.*) err "SESSION_NAME must not contain ':' or '.'" ;;
  esac
  case "$LAYOUT" in
    columns|rows|grid) ;;
    *) err "invalid LAYOUT '$LAYOUT' (valid values: columns, rows, grid)" ;;
  esac
  case "$SHELL_HEIGHT" in
    ''|*[!0-9]*) err "SHELL_HEIGHT must be an integer between 10 and 90" ;;
  esac
  { [ "$SHELL_HEIGHT" -ge 10 ] && [ "$SHELL_HEIGHT" -le 90 ]; } \
    || err "SHELL_HEIGHT must be between 10 and 90"
  case "$STATS" in
    on|off) ;;
    *) err "STATS must be 'on' or 'off'" ;;
  esac
  [ "$NCMDS" -ge 1 ] \
    || err "no commands defined; set CMD1 in tmonitor.conf or pass --pane-1=\"...\""
  [ "$CLI_PANE_MAX" -le "$NCMDS" ] \
    || err "--pane-$CLI_PANE_MAX skips indexes (commands must be sequential from 1)"
}

# Grava o estado resolvido da sessao como arquivo bash sourceavel,
# permitindo recriar a sessao com --restore.
write_snapshot() {
  mkdir -p "$STATE_DIR" || return
  local f="$STATE_DIR/$(state_file_for "$SESSION_NAME").state" i=0
  {
    echo "# Snapshot do tmonitor - estado resolvido; recrie com: tmonitor.sh --restore <nome>"
    printf 'WORKDIR=%q\n' "$WORKDIR"
    printf 'SESSION_NAME=%q\n' "$SESSION_NAME"
    printf 'LAYOUT=%q\n' "$LAYOUT"
    printf 'SHELL_HEIGHT=%q\n' "$SHELL_HEIGHT"
    printf 'STATS=%q\n' "$STATS"
    while [ "$i" -lt "$NCMDS" ]; do
      printf 'CMD%d=%q\n' "$((i + 1))" "${CMDS[$i]}"
      if [ -n "${LABELS[$i]}" ]; then
        printf 'LABEL%d=%q\n' "$((i + 1))" "${LABELS[$i]}"
      fi
      i=$((i + 1))
    done
  } > "$f"
}

default_label() {
  local cmd="$1"
  if [ "${#cmd}" -gt 30 ]; then
    printf '%s...' "${cmd:0:27}"
  else
    printf '%s' "$cmd"
  fi
}

# Divide o pane $2 na direcao $1 (-h ou -v) reservando 1/$3 do espaco para ele,
# de modo que $3 divisoes sucessivas fiquem equalizadas. Imprime o id do novo pane.
split_even() {
  local pct=$((($3 - 1) * 100 / $3))
  tmux split-window "$1" -l "${pct}%" -P -F '#{pane_id}' -t "$2" -c "$WORKDIR" || {
    tmux kill-session -t "=$SESSION_NAME" 2>/dev/null
    err "could not split panes for layout '$LAYOUT' with $NCMDS commands (terminal too small?)"
  }
}

# Cria a sessao com o pane do shell no rodape e os N panes de comando na area
# superior, conforme LAYOUT. Preenche PANE_IDS (ordem = CMD1..N) e SHELL_ID.
create_session() {
  local first cur new j
  # Tamanho virtual generoso: a sessao nasce detached e sera redimensionada no attach
  first="$(tmux new-session -d -P -F '#{pane_id}' -s "$SESSION_NAME" -c "$WORKDIR" -x 200 -y 50)" \
    || err "could not create tmux session '$SESSION_NAME'"
  # Alvo canonico das operacoes seguintes: o id e imune a colisao de prefixo de
  # nomes e ao fato de set-option nao aceitar o prefixo '=' (tmux 3.5a)
  SESSION_ID="$(tmux display-message -p -t "$first" '#{session_id}')"
  SHELL_ID="$(tmux split-window -v -l "${SHELL_HEIGHT}%" -P -F '#{pane_id}' -t "$first" -c "$WORKDIR")" \
    || err "could not create the shell pane"

  PANE_IDS=("$first")
  case "$LAYOUT" in
    columns)
      cur="$first"
      j="$NCMDS"
      while [ "$j" -gt 1 ]; do
        new="$(split_even -h "$cur" "$j")" || exit 1
        PANE_IDS+=("$new")
        cur="$new"
        j=$((j - 1))
      done
      ;;
    rows)
      cur="$first"
      j="$NCMDS"
      while [ "$j" -gt 1 ]; do
        new="$(split_even -v "$cur" "$j")" || exit 1
        PANE_IDS+=("$new")
        cur="$new"
        j=$((j - 1))
      done
      ;;
    grid)
      # ceil(sqrt(N)) colunas; panes distribuidos coluna a coluna (CMD1..k na primeira)
      local cols=1 base extra c k
      while [ $((cols * cols)) -lt "$NCMDS" ]; do
        cols=$((cols + 1))
      done
      base=$((NCMDS / cols))
      extra=$((NCMDS % cols))
      local COL_IDS=("$first")
      cur="$first"
      j="$cols"
      while [ "$j" -gt 1 ]; do
        new="$(split_even -h "$cur" "$j")" || exit 1
        COL_IDS+=("$new")
        cur="$new"
        j=$((j - 1))
      done
      PANE_IDS=()
      c=0
      while [ "$c" -lt "$cols" ]; do
        k="$base"
        [ "$c" -lt "$extra" ] && k=$((k + 1))
        cur="${COL_IDS[$c]}"
        PANE_IDS+=("$cur")
        j="$k"
        while [ "$j" -gt 1 ]; do
          new="$(split_even -v "$cur" "$j")" || exit 1
          PANE_IDS+=("$new")
          cur="$new"
          j=$((j - 1))
        done
        c=$((c + 1))
      done
      ;;
  esac

  local i=0 label
  while [ "$i" -lt "$NCMDS" ]; do
    label="${LABELS[$i]}"
    [ -z "$label" ] && label="$(default_label "${CMDS[$i]}")"
    tmux select-pane -t "${PANE_IDS[$i]}" -T "$label"
    tmux send-keys -t "${PANE_IDS[$i]}" "${CMDS[$i]}" C-m
    i=$((i + 1))
  done
  tmux select-pane -t "$SHELL_ID" -T "shell"
}

# Aparencia escopada a sessao (nada de -g: outras sessoes do usuario ficam intactas)
configure_appearance() {
  local t="$SESSION_ID"
  tmux set-option -t "$t" status on
  tmux set-option -t "$t" status-interval 5
  tmux set-option -t "$t" status-left "#[bg=blue,fg=yellow,bold] $SESSION_NAME :: #[default]"
  tmux set-option -t "$t" status-left-length 40
  local right="#[fg=white,bg=red,bold] Opt+Q [quit] | Opt+R [reload] "
  if [ "$STATS" = "on" ]; then
    right="#($SCRIPT_DIR/tmonitor_stats.sh) $right"
  fi
  tmux set-option -t "$t" status-right "$right"
  tmux set-option -t "$t" status-right-length 100
  tmux set-option -w -t "$t:0" pane-border-status top
  tmux set-option -w -t "$t:0" pane-border-format " #{pane_title} "
}

configure_bindings() {
  # Estado por sessao: e daqui que o binding de reload descobre o alvo correto
  tmux set-environment -t "$SESSION_ID" TMONITOR_WORKDIR "$WORKDIR"
  tmux set-environment -t "$SESSION_ID" TMONITOR_SESSION "$SESSION_NAME"
  # bind-key e global no servidor tmux; o guard pelo ambiente da sessao torna os
  # atalhos no-op fora de sessoes TMonitor e corretos com multiplas sessoes.
  tmux bind-key -n M-q if-shell 'tmux show-environment -t "#{session_id}" TMONITOR_SESSION >/dev/null 2>&1' \
    'confirm-before -p "Quit TMonitor session? (y/n)" kill-session' ''
  tmux bind-key -n M-r run-shell "\"$SCRIPT_DIR/reload_tmonitor.sh\" \"#{session_name}\""
}

main() {
  parse_args "$@"

  if [ "$RESTORE_MODE" -eq 1 ]; then
    [ -n "$POSITIONAL" ] && err "--restore does not take a workdir argument"
    if [ -z "$RESTORE_NAME" ]; then
      list_snapshots
      exit 0
    fi
    local sf="$STATE_DIR/$(state_file_for "$RESTORE_NAME").state"
    if [ ! -f "$sf" ]; then
      list_snapshots >&2
      err "snapshot '$RESTORE_NAME' not found"
    fi
    . "$sf"
    [ -d "${WORKDIR:-}" ] || err "workdir '$WORKDIR' from snapshot no longer exists"
  else
    WORKDIR="${POSITIONAL:-$PWD}"
    [ -d "$WORKDIR" ] || err "path '$WORKDIR' not found"
    WORKDIR="$(cd "$WORKDIR" && pwd)"
    local config_file="$WORKDIR/tmonitor.conf"
    if [ -f "$config_file" ]; then
      . "$config_file"
    elif [ "$CLI_PANE_MAX" -eq 0 ]; then
      err "configuration file '$config_file' not found (create it with CMD1..CMDN, or pass --pane-1=\"...\")"
    fi
  fi

  materialize_commands
  apply_defaults_and_validate

  if tmux has-session -t "=$SESSION_NAME" 2>/dev/null; then
    if [ "$FORCE" -eq 1 ]; then
      tmux kill-session -t "=$SESSION_NAME"
    else
      if [ "$DETACH" -eq 1 ]; then
        echo "Session '$SESSION_NAME' already exists; attach with: tmux attach -t '$SESSION_NAME'"
        exit 0
      fi
      if [ -n "${TMUX:-}" ]; then
        exec tmux switch-client -t "=$SESSION_NAME"
      fi
      exec tmux attach-session -t "=$SESSION_NAME"
    fi
  fi

  create_session
  configure_appearance
  configure_bindings
  write_snapshot
  tmux select-pane -t "$SHELL_ID"

  if [ "$DETACH" -eq 1 ]; then
    echo "Session '$SESSION_NAME' created (detached); attach with: tmux attach -t '$SESSION_NAME'"
  elif [ -n "${TMUX:-}" ]; then
    exec tmux switch-client -t "=$SESSION_NAME"
  else
    exec tmux attach-session -t "=$SESSION_NAME"
  fi
}

if [ -z "${TMONITOR_LIB_ONLY:-}" ]; then
  main "$@"
fi

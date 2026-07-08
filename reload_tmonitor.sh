#!/bin/bash
# reload_tmonitor.sh - reenvia os comandos aos panes de uma sessao TMonitor viva,
# sem recriar a geometria. Invocado pelo binding Opt+R ou manualmente:
#   reload_tmonitor.sh              (dentro do tmux: recarrega a sessao ativa)
#   reload_tmonitor.sh <sessao>     (recarrega a sessao pelo nome)
#   reload_tmonitor.sh <workdir>    (compat com a assinatura antiga)
#
# Fonte dos comandos: tmonitor.conf do workdir (edicoes recentes vencem); se o
# conf nao existir (sessao criada so via CLI), usa o snapshot da sessao.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reusa as funcoes do tmonitor.sh (err, materialize_commands, write_snapshot, ...)
TMONITOR_LIB_ONLY=1
. "$SCRIPT_DIR/tmonitor.sh"

SESSION=""
if [ $# -ge 1 ] && [ -d "$1" ]; then
  # Assinatura antiga: argumento e um workdir; a sessao vem do conf/snapshot
  WORKDIR="$(cd "$1" && pwd)"
elif [ $# -ge 1 ]; then
  SESSION="$1"
else
  [ -n "${TMUX:-}" ] \
    || err "no session specified and not inside tmux (use: reload_tmonitor.sh <session|workdir>)"
  SESSION="$(tmux display-message -p '#S')"
fi

if [ -n "$SESSION" ]; then
  tmux has-session -t "=$SESSION" 2>/dev/null || err "session '$SESSION' not found"
  # Sessao sem TMONITOR_WORKDIR nao e do TMonitor: no-op silencioso (o binding
  # M-r e global no servidor e pode disparar em qualquer sessao)
  env_line="$(tmux show-environment -t "=$SESSION" TMONITOR_WORKDIR 2>/dev/null)" || exit 0
  WORKDIR="${env_line#TMONITOR_WORKDIR=}"
  [ -d "$WORKDIR" ] || err "workdir '$WORKDIR' of session '$SESSION' no longer exists"
fi

CONF_LOADED=0
if [ -f "$WORKDIR/tmonitor.conf" ]; then
  . "$WORKDIR/tmonitor.conf"
  CONF_LOADED=1
fi
SESSION="${SESSION:-${SESSION_NAME:-monitoring}}"
if [ "$CONF_LOADED" -eq 0 ]; then
  snapshot="$STATE_DIR/$(state_file_for "$SESSION").state"
  [ -f "$snapshot" ] \
    || err "no tmonitor.conf in '$WORKDIR' and no snapshot for session '$SESSION'"
  . "$snapshot"
fi
# O nome da sessao viva e a verdade, nao o que o conf/snapshot diz
SESSION_NAME="$SESSION"

materialize_commands
apply_defaults_and_validate

tmux has-session -t "=$SESSION" 2>/dev/null || err "session '$SESSION' not found"

PANES=()
while IFS= read -r p; do
  PANES+=("$p")
done < <(tmux list-panes -t "=$SESSION:0" -F '#{pane_id}')

TOTAL=${#PANES[@]}
AVAIL=$((TOTAL - 1))
N="$NCMDS"
if [ "$N" -ne "$AVAIL" ]; then
  # Reload nao mexe na geometria: reenvia o que couber e avisa
  [ "$N" -gt "$AVAIL" ] && N="$AVAIL"
  tmux display-message -t "${PANES[0]}" \
    "tmonitor: $NCMDS commands for $AVAIL panes; run tmonitor --force to rebuild the layout" 2>/dev/null
fi

i=0
while [ "$i" -lt "$N" ]; do
  id="${PANES[$i]}"
  label="${LABELS[$i]}"
  [ -z "$label" ] && label="$(default_label "${CMDS[$i]}")"
  tmux select-pane -t "$id" -T "$label"
  tmux send-keys -t "$id" C-c
  tmux send-keys -t "$id" "cd $(printf '%q' "$WORKDIR")" C-m "${CMDS[$i]}" C-m
  i=$((i + 1))
done

write_snapshot
tmux select-pane -t "${PANES[$((TOTAL - 1))]}"

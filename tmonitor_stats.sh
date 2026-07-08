#!/bin/bash
# tmonitor_stats.sh - estatisticas compactas de CPU, memoria e disco para a status bar do tmux.
# Stateless: imprime uma unica linha e sai. Metrica indisponivel degrada para "--".

# Garante ponto decimal independente do locale do usuario
export LC_ALL=C

OS="$(uname -s)"

# Formata bytes em G com uma casa decimal (ex.: 8589934592 -> 8.0G)
format_gb() {
  awk -v b="$1" 'BEGIN { printf "%.1fG", b / 1073741824 }'
}

cpu_stat() {
  case "$OS" in
    Darwin)
      # Load average de 1 min normalizado pelo numero de nucleos (top -l 1 levaria ~1s
      # e a primeira amostra reporta media desde o boot; sysctl e instantaneo)
      local ncpu
      ncpu="$(sysctl -n hw.ncpu 2>/dev/null)" || return
      sysctl -n vm.loadavg 2>/dev/null | awk -v n="$ncpu" \
        '{ if (n > 0) printf "%.0f%%", $2 * 100 / n }'
      ;;
    Linux)
      # Duas amostras de /proc/stat para medir uso no intervalo
      read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
      sleep 0.3
      read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
      awk -v b1=$((u1 + n1 + s1 + q1 + sq1 + st1)) -v t1=$((u1 + n1 + s1 + i1 + w1 + q1 + sq1 + st1)) \
          -v b2=$((u2 + n2 + s2 + q2 + sq2 + st2)) -v t2=$((u2 + n2 + s2 + i2 + w2 + q2 + sq2 + st2)) \
          'BEGIN { dt = t2 - t1; if (dt > 0) printf "%.0f%%", (b2 - b1) * 100 / dt }'
      ;;
  esac
}

mem_stat() {
  case "$OS" in
    Darwin)
      local total used
      total="$(sysctl -n hw.memsize 2>/dev/null)" || return
      used="$(vm_stat 2>/dev/null | awk '
        /page size of/           { page = $8 }
        /^Pages active/          { gsub("\\.", "", $NF); active = $NF }
        /^Pages wired down/      { gsub("\\.", "", $NF); wired = $NF }
        /occupied by compressor/ { gsub("\\.", "", $NF); comp = $NF }
        END { if (page > 0) print (active + wired + comp) * page }')"
      [ -n "$total" ] && [ -n "$used" ] && printf "%s/%s" "$(format_gb "$used")" "$(format_gb "$total")"
      ;;
    Linux)
      awk '
        /^MemTotal:/     { total = $2 }
        /^MemAvailable:/ { avail = $2 }
        END { if (total > 0) printf "%.1fG/%.1fG", (total - avail) / 1048576, total / 1048576 }' /proc/meminfo
      ;;
  esac
}

disk_stat() {
  local target="/"
  # No macOS o volume de dados do usuario e o que interessa, nao o volume selado do sistema
  [ "$OS" = "Darwin" ] && [ -d /System/Volumes/Data ] && target="/System/Volumes/Data"
  df -h "$target" 2>/dev/null | awk 'NR == 2 { gsub("%", "", $5); printf "%s%%", $5 }'
}

CPU="$(cpu_stat)"
MEM="$(mem_stat)"
DISK="$(disk_stat)"

echo "CPU ${CPU:---} | MEM ${MEM:---} | DISK ${DISK:---}"

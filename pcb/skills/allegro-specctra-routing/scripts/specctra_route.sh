#!/usr/bin/env bash
# specctra_route.sh — headless Cadence SPECCTRA / Allegro PCB Router run (DSN in -> SES out).
# Encapsulates the verified invocation: module + LM_LICENSE_FILE + -product + PINNED Xvfb, detached,
# waits for the .ses. See ../SKILL.md for the why behind every piece.
#
#   specctra_route.sh -i board.dsn -o board.ses [-d "route 25;route 50 16"] [--product NAME] \
#                     [--display :177] [--module cadence/allegro/25.10.010]
#
# Env overrides: SPECCTRA_MODULE, SPECCTRA_PRODUCT, SPECCTRA_DISPLAY, SPB_BIN (dir with `specctra`).
set -euo pipefail

DSN= SES= DOSPEC="route 25;route 50 16"
PRODUCT="${SPECCTRA_PRODUCT:-Allegro_performance}"
DISPLAY_N="${SPECCTRA_DISPLAY:-:177}"
MODULE="${SPECCTRA_MODULE:-cadence/allegro/25.10.010}"
while [ $# -gt 0 ]; do case "$1" in
  -i) DSN=$2; shift 2;; -o) SES=$2; shift 2;; -d) DOSPEC=$2; shift 2;;
  --product) PRODUCT=$2; shift 2;; --display) DISPLAY_N=$2; shift 2;; --module) MODULE=$2; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;; esac; done
[ -n "$DSN" ] && [ -n "$SES" ] || { echo "usage: -i board.dsn -o board.ses [-d 'route 25;route 50 16']" >&2; exit 2; }
DSN=$(readlink -f "$DSN"); SES=$(readlink -f "$SES"); WD=$(dirname "$SES"); DO="$WD/route.do"; LOG="$WD/specctra.log"

# environment: module sets PATH + CDS_LIC_FILE; the 32-bit router reads LM_LICENSE_FILE (NOT CDS_LIC_FILE)
source /etc/profile.d/modules.sh 2>/dev/null || true
module load "$MODULE" 2>/dev/null || true
[ -n "${SPB_BIN:-}" ] && export PATH="$SPB_BIN:$PATH"
export LM_LICENSE_FILE="${CDS_LIC_FILE:-${LM_LICENSE_FILE:-}}"
command -v specctra >/dev/null || { echo "specctra not on PATH — set SPB_BIN or the module" >&2; exit 3; }

# do-file: route/write/quit ONLY (DSN goes on the command line, NOT `read design`)
{ printf '%s\n' "$DOSPEC" | tr ';' '\n'; echo "write session $SES"; echo quit; } > "$DO"
rm -f "$SES"

# launch DETACHED (setsid) under a PINNED Xvfb (never xvfb-run -a: it auto-picks :99 and collides)
echo "SPECCTRA: dsn=$DSN product=$PRODUCT display=$DISPLAY_N -> $SES"
setsid bash -c "
  /usr/bin/Xvfb $DISPLAY_N -screen 0 1600x1000x24 -nolisten tcp >/dev/null 2>&1 & XP=\$!; sleep 4
  DISPLAY=$DISPLAY_N specctra '$DSN' -do '$DO' -product '$PRODUCT'
  kill \$XP 2>/dev/null
" > "$LOG" 2>&1 &
disown
echo "launched (log: $LOG). .ses is written only at the end; poll for it:"
echo "  while [ ! -f $SES ]; do sleep 30; done   # then: import_ses.py board.kicad_pcb $SES out.kicad_pcb"
echo "  # live count: import -display $DISPLAY_N -window root shot.png   (status bar: Unconnects/Conflicts/Completion)"
echo "  # progress in $LOG: 'Start Route Pass N of M', 'Unroutes ..', 'Total Conflicts ..'"

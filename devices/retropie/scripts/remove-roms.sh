#!/bin/bash
set -euo pipefail

RETROPIE_HOST="${RETROPIE_HOST:-retropie.local}"
RETROPIE_USER="${RETROPIE_USER:-pi}"

usage() {
  cat <<USAGE
Usage: $0 <system> '<pattern>' [--dry-run] [--yes]
Examples:
  $0 snes 'Zelda*' --dry-run
  $0 gba "Pokemon - Emerald Version (USA, Europe).gba" --yes
USAGE
}

[[ $# -lt 2 ]] && usage && exit 1

SYSTEM="$1"; shift
PATTERN_RAW="$1"; shift
DRY_RUN=""; YES=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes)     YES=1 ;;
    *) echo "Unknown arg: $arg"; usage; exit 1 ;;
  esac
done

# If user didn't include any glob chars, match as substring
if [[ ! "$PATTERN_RAW" =~ [\*\?\[] ]]; then
  PATTERN="*${PATTERN_RAW}*"
else
  PATTERN="$PATTERN_RAW"
fi

[[ -n "${DRY_RUN:-}" ]] && { echo "DRY RUN MODE - No files will be deleted"; echo; }

echo "System:  $SYSTEM"
echo "Pattern: $PATTERN"
echo

# Use -tt only if we'll prompt (no --yes & not dry-run) and stdin is a terminal
FORCE_TTY=""
if [[ -z "${DRY_RUN:-}" && -z "${YES:-}" && -t 0 ]]; then
  FORCE_TTY="1"
fi

ssh ${FORCE_TTY:+-tt} -T "${RETROPIE_USER}@${RETROPIE_HOST}" bash -s -- \
  "$SYSTEM" "$PATTERN" "${DRY_RUN:-}" "${YES:-}" <<'REMOTE'
set -euo pipefail

SYSTEM="$1"
PATTERN="$2"
DRY_RUN="${3:-}"
YES="${4:-}"

ROM_DIR="$HOME/RetroPie/roms/$SYSTEM"
MEDIA_DIR="$HOME/.emulationstation/downloaded_media/$SYSTEM"

if [[ ! -d "$ROM_DIR" ]]; then
  echo "Error: System '$SYSTEM' not found at $ROM_DIR"
  exit 1
fi

cd "$ROM_DIR"

# Collect matches safely
mapfile -d '' MATCHES < <(find . -maxdepth 1 -type f -iname "$PATTERN" -print0 2>/dev/null || true)

if (( ${#MATCHES[@]} == 0 )); then
  echo "No ROMs found matching: $PATTERN"
  exit 1
fi

echo "Found ${#MATCHES[@]} ROM(s):"
for rom in "${MATCHES[@]}"; do echo "  - ${rom#./}"; done
echo

if [[ -n "$DRY_RUN" ]]; then
  echo "DRY RUN - Nothing deleted."
  exit 0
fi

# Confirm (only if not forced with --yes and we have a TTY)
if [[ -z "$YES" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Type 'yes' to confirm deletion: " CONFIRM
    [[ "$CONFIRM" == "yes" ]] || { echo "Cancelled."; exit 1; }
  else
    echo "Refusing to delete without --yes when no TTY is available."
    exit 1
  fi
fi

echo "Deleting ROMs and associated media..."
for rom in "${MATCHES[@]}"; do
  base="${rom#./}"
  name_no_ext="${base%.*}"
  echo "  ROM: $base"
  rm -f -- "$rom"

  if [[ -d "$MEDIA_DIR" ]]; then
    # Remove any media whose filename starts with the ROM base name
    while IFS= read -r -d '' f; do
      echo "    media: ${f#"$HOME/"}"
      rm -f -- "$f"
    done < <(find "$MEDIA_DIR" -type f -iname "$name_no_ext.*" -print0 2>/dev/null || true)
  fi
done

echo
echo "Done. In EmulationStation: START → UI Settings → 'Reload Games List' to refresh."
REMOTE

if [[ -n "${DRY_RUN:-}" ]]; then
  echo "Dry run completed."
else
  echo "Finished."
fi


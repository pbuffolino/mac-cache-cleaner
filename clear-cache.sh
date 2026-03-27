#!/usr/bin/env bash
# =============================================================================
# clear-cache.sh — macOS Cache Cleaner
# https://github.com/pbuffolino/mac-cache-cleaner
#
# DISCLAIMER: This script is provided "as-is", without warranty of any kind,
# express or implied. The author accepts no liability for data loss, system
# instability, or any other damages arising from its use. You are solely
# responsible for reviewing and understanding this script before running it.
# See LICENSE for full terms.
# =============================================================================
#
# Usage:
#   ./clear-cache.sh [--dry-run] [--sudo]
#
#   --dry-run   Preview what would be deleted — no files are touched
#   --sudo      Also clear system-level caches (/Library/Caches, /Library/Logs)
#               Requires sudo password. Use with caution.
#
# Targets cleared (user mode):
#   ~/Library/Caches        macOS app caches
#   ~/Library/Logs          App log files
#   ~/.cache                XDG cache directory
#   npm cache               via: npm cache clean --force
#   Homebrew cache          via: brew cleanup --prune=all
#   pip cache               via: pip3 cache purge
#   DNS cache               via: dscacheutil + mDNSResponder (requires sudo)
#
# Additional targets with --sudo:
#   /Library/Caches         System-level app caches
#   /Library/Logs           System-level logs
#
# Tested on: macOS Sequoia 15.x (Apple Silicon)
# Requires:  bash 3.2+  (ships with macOS)
# =============================================================================

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
DRY_RUN=false
SUDO_MODE=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --sudo)    SUDO_MODE=true ;;
    --help|-h)
      sed -n '/^# Usage/,/^# ====/p' "$0" | grep '^#' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg  (use --help for usage)" >&2
      exit 1
      ;;
  esac
done

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -n "${HOME:-}" ]] || { echo "ERROR: \$HOME is not set. Aborting." >&2; exit 1; }
[[ "$HOME" != "/" ]] || { echo "ERROR: \$HOME is '/'. Aborting." >&2; exit 1; }
[[ -d "$HOME" ]]     || { echo "ERROR: \$HOME ($HOME) is not a directory. Aborting." >&2; exit 1; }

# macOS only
[[ "$(uname -s)" == "Darwin" ]] || { echo "ERROR: This script is for macOS only." >&2; exit 1; }

# ── Colors (disabled if not a terminal) ───────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$(tput bold 2>/dev/null || true)
  RESET=$(tput sgr0 2>/dev/null || true)
  GREEN=$(tput setaf 2 2>/dev/null || true)
  YELLOW=$(tput setaf 3 2>/dev/null || true)
  CYAN=$(tput setaf 6 2>/dev/null || true)
  RED=$(tput setaf 1 2>/dev/null || true)
  MAGENTA=$(tput setaf 5 2>/dev/null || true)
else
  BOLD="" RESET="" GREEN="" YELLOW="" CYAN="" RED="" MAGENTA=""
fi

log()     { echo "${CYAN}▸${RESET} $*"; }
syslog()  { echo "${MAGENTA}▸${RESET} [system] $*"; }
ok()      { echo "  ${GREEN}✔${RESET}  $*"; }
skipped() { echo "  ${YELLOW}–${RESET}  $*"; }
warn()    { echo "  ${RED}!${RESET}  $*"; }

# ── Tool detection ────────────────────────────────────────────────────────────
HAS_NPM=false;  command -v npm  &>/dev/null && HAS_NPM=true
HAS_BREW=false; command -v brew &>/dev/null && HAS_BREW=true
HAS_PIP=false;  command -v pip3 &>/dev/null && HAS_PIP=true

# ── Whitelist — the ONLY paths permitted to be cleared ────────────────────────
# Any path not listed here causes an immediate abort. Defense-in-depth.
ALLOWED_USER_PATHS=(
  "$HOME/Library/Caches"
  "$HOME/Library/Logs"
  "$HOME/.cache"
)
ALLOWED_SUDO_PATHS=(
  "/Library/Caches"
  "/Library/Logs"
)

assert_allowed() {
  local path="$1" mode="$2"
  local allowed=("${ALLOWED_USER_PATHS[@]}")
  [[ "$mode" == "sudo" ]] && allowed=("${ALLOWED_SUDO_PATHS[@]}")
  for a in "${allowed[@]}"; do
    [[ "$path" == "$a" ]] && return 0
  done
  echo "${RED}ABORT: attempted to clear unlisted path: $path${RESET}" >&2
  exit 1
}

# ── Helpers ───────────────────────────────────────────────────────────────────
mb_of() {
  local result
  if [[ -e "$1" ]]; then
    result=$(du -sm "$1" 2>/dev/null | tail -1 | awk '{print $1}' | tr -dc '0-9' || true)
    echo "${result:-0}"
  else
    echo 0
  fi
}

mb_of_sudo() {
  local result
  if [[ -e "$1" ]]; then
    result=$(sudo du -sm "$1" 2>/dev/null | tail -1 | awk '{print $1}' | tr -dc '0-9' || true)
    echo "${result:-0}"
  else
    echo 0
  fi
}

ensure_int() {
  local val="${1:-0}"
  val=$(echo "$val" | tr -dc '0-9')
  echo "${val:-0}"
}

do_rm() {
  local path="$1"
  assert_allowed "$path" "user"
  if [[ ! -d "$path" ]]; then
    skipped "$path — not found, skipping"
    return
  fi
  if $DRY_RUN; then
    echo "      [dry-run] rm -rf ${path}/*"
  else
    find "$path" -mindepth 1 -delete 2>/dev/null || rm -rf "${path:?}/"* 2>/dev/null || true
  fi
}

do_rm_sudo() {
  local path="$1"
  assert_allowed "$path" "sudo"
  if [[ ! -d "$path" ]]; then
    skipped "$path — not found, skipping"
    return
  fi
  if $DRY_RUN; then
    echo "      [dry-run] sudo rm -rf ${path}/*"
  else
    sudo find "$path" -mindepth 1 -delete 2>/dev/null || sudo rm -rf "${path:?}/"* 2>/dev/null || true
  fi
}

brew_cache_dir() { brew --cache 2>/dev/null || echo ""; }
pip_cache_dir()  { pip3 cache dir 2>/dev/null || echo ""; }

# ── Start ─────────────────────────────────────────────────────────────────────
START_TS=$(date +%s)
echo
echo "${BOLD}=== macOS Cache Cleaner ===${RESET}"
$DRY_RUN   && echo "${YELLOW}  DRY RUN — no files will be deleted${RESET}"
$SUDO_MODE && echo "${MAGENTA}  SUDO MODE — system caches will also be cleared${RESET}"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Tools detected: $(
  tools=()
  $HAS_NPM  && tools+=("npm")
  $HAS_BREW && tools+=("brew")
  $HAS_PIP  && tools+=("pip3")
  [[ ${#tools[@]} -eq 0 ]] && echo "none (npm/brew/pip3 steps will be skipped)" || echo "${tools[*]}"
)"
echo

# Pre-flight sudo prompt — avoids password interruption mid-run
if $SUDO_MODE && ! $DRY_RUN; then
  echo "  Requesting sudo access for system cache cleanup..."
  sudo -v
  echo
fi

# ── Measure BEFORE ────────────────────────────────────────────────────────────
log "Measuring disk usage before..."

B_LIB_CACHES=$(ensure_int "$(mb_of "$HOME/Library/Caches")")
B_LIB_LOGS=$(ensure_int "$(mb_of "$HOME/Library/Logs")")
B_DOT_CACHE=$(ensure_int "$(mb_of "$HOME/.cache")")

B_NPM=0
BREW_DIR=""; B_BREW=0
PIP_DIR="";  B_PIP=0
$HAS_NPM  && B_NPM=$(ensure_int "$(mb_of "$HOME/.npm")")
if $HAS_BREW; then BREW_DIR=$(brew_cache_dir); B_BREW=$(ensure_int "$(mb_of "$BREW_DIR")"); fi
if $HAS_PIP;  then PIP_DIR=$(pip_cache_dir);   B_PIP=$(ensure_int "$(mb_of "$PIP_DIR")");   fi

B_TOTAL=$((B_LIB_CACHES + B_LIB_LOGS + B_DOT_CACHE + B_NPM + B_BREW + B_PIP))

B_SYS_CACHES=0; B_SYS_LOGS=0
if $SUDO_MODE; then
  B_SYS_CACHES=$(ensure_int "$(mb_of_sudo "/Library/Caches")")
  B_SYS_LOGS=$(ensure_int "$(mb_of_sudo "/Library/Logs")")
  B_TOTAL=$((B_TOTAL + B_SYS_CACHES + B_SYS_LOGS))
fi

printf "  %-44s %6s MB\n" "~/Library/Caches"  "$B_LIB_CACHES"
printf "  %-44s %6s MB\n" "~/Library/Logs"     "$B_LIB_LOGS"
printf "  %-44s %6s MB\n" "~/.cache"           "$B_DOT_CACHE"
$HAS_NPM  && printf "  %-44s %6s MB\n" "~/.npm (npm cache)"  "$B_NPM"
$HAS_BREW && printf "  %-44s %6s MB\n" "brew cache"          "$B_BREW"
$HAS_PIP  && printf "  %-44s %6s MB\n" "pip cache"           "$B_PIP"
if $SUDO_MODE; then
  printf "  %-44s %6s MB\n" "/Library/Caches (system)" "$B_SYS_CACHES"
  printf "  %-44s %6s MB\n" "/Library/Logs (system)"   "$B_SYS_LOGS"
fi
printf "  ${BOLD}%-44s %6s MB${RESET}\n" "TOTAL BEFORE" "$B_TOTAL"
echo

# ── 1. ~/Library/Caches ───────────────────────────────────────────────────────
log "Clearing ~/Library/Caches  (${B_LIB_CACHES} MB)"
do_rm "$HOME/Library/Caches"
ok "~/Library/Caches cleared"

# ── 2. ~/Library/Logs ─────────────────────────────────────────────────────────
log "Clearing ~/Library/Logs  (${B_LIB_LOGS} MB)"
do_rm "$HOME/Library/Logs"
ok "~/Library/Logs cleared"

# ── 3. ~/.cache ───────────────────────────────────────────────────────────────
log "Clearing ~/.cache  (${B_DOT_CACHE} MB)"
do_rm "$HOME/.cache"
ok "~/.cache cleared"

# ── 4. npm cache ──────────────────────────────────────────────────────────────
if $HAS_NPM; then
  log "Clearing npm cache  (${B_NPM} MB)"
  if $DRY_RUN; then
    echo "      [dry-run] npm cache clean --force"
  else
    npm cache clean --force 2>&1 | sed 's/^/      /'
  fi
  ok "npm cache cleared"
else
  skipped "npm — not installed"
fi

# ── 5. Homebrew cache ─────────────────────────────────────────────────────────
if $HAS_BREW; then
  log "Clearing Homebrew cache  (${B_BREW} MB)"
  if $DRY_RUN; then
    echo "      [dry-run] brew cleanup --prune=all"
  else
    brew cleanup --prune=all 2>&1 | sed 's/^/      /'
  fi
  ok "Homebrew cache cleared"
else
  skipped "brew — not installed"
fi

# ── 6. pip cache ──────────────────────────────────────────────────────────────
if $HAS_PIP; then
  log "Clearing pip cache  (${B_PIP} MB)"
  if $DRY_RUN; then
    echo "      [dry-run] pip3 cache purge"
  else
    pip3 cache purge 2>&1 | sed 's/^/      /'
  fi
  ok "pip cache cleared"
else
  skipped "pip3 — not installed"
fi

# ── 7. DNS cache ──────────────────────────────────────────────────────────────
log "Flushing DNS cache"
if $DRY_RUN; then
  echo "      [dry-run] sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
else
  if sudo dscacheutil -flushcache 2>/dev/null && sudo killall -HUP mDNSResponder 2>/dev/null; then
    ok "DNS cache flushed"
  else
    warn "DNS flush failed (sudo required)"
  fi
fi

# ── System caches (--sudo only) ───────────────────────────────────────────────
if $SUDO_MODE; then
  echo

  syslog "Clearing /Library/Caches  (${B_SYS_CACHES} MB)"
  do_rm_sudo "/Library/Caches"
  ok "/Library/Caches cleared"

  syslog "Clearing /Library/Logs  (${B_SYS_LOGS} MB)"
  do_rm_sudo "/Library/Logs"
  ok "/Library/Logs cleared"
fi

# ── Measure AFTER ─────────────────────────────────────────────────────────────
echo
log "Measuring disk usage after..."

A_LIB_CACHES=$(ensure_int "$(mb_of "$HOME/Library/Caches")")
A_LIB_LOGS=$(ensure_int "$(mb_of "$HOME/Library/Logs")")
A_DOT_CACHE=$(ensure_int "$(mb_of "$HOME/.cache")")
A_NPM=0; A_BREW=0; A_PIP=0
$HAS_NPM  && A_NPM=$(ensure_int "$(mb_of "$HOME/.npm")")
$HAS_BREW && A_BREW=$(ensure_int "$(mb_of "$BREW_DIR")")
$HAS_PIP  && A_PIP=$(ensure_int "$(mb_of "$PIP_DIR")")
A_TOTAL=$((A_LIB_CACHES + A_LIB_LOGS + A_DOT_CACHE + A_NPM + A_BREW + A_PIP))

A_SYS_CACHES=0; A_SYS_LOGS=0
if $SUDO_MODE; then
  A_SYS_CACHES=$(ensure_int "$(mb_of_sudo "/Library/Caches")")
  A_SYS_LOGS=$(ensure_int "$(mb_of_sudo "/Library/Logs")")
  A_TOTAL=$((A_TOTAL + A_SYS_CACHES + A_SYS_LOGS))
fi

FREED=$((B_TOTAL - A_TOTAL))

printf "  %-44s %6s MB\n" "~/Library/Caches"  "$A_LIB_CACHES"
printf "  %-44s %6s MB\n" "~/Library/Logs"     "$A_LIB_LOGS"
printf "  %-44s %6s MB\n" "~/.cache"           "$A_DOT_CACHE"
$HAS_NPM  && printf "  %-44s %6s MB\n" "~/.npm (npm cache)"  "$A_NPM"
$HAS_BREW && printf "  %-44s %6s MB\n" "brew cache"          "$A_BREW"
$HAS_PIP  && printf "  %-44s %6s MB\n" "pip cache"           "$A_PIP"
if $SUDO_MODE; then
  printf "  %-44s %6s MB\n" "/Library/Caches (system)" "$A_SYS_CACHES"
  printf "  %-44s %6s MB\n" "/Library/Logs (system)"   "$A_SYS_LOGS"
fi
printf "  ${BOLD}%-44s %6s MB${RESET}\n" "TOTAL AFTER" "$A_TOTAL"

# ── Summary ───────────────────────────────────────────────────────────────────
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
MINS=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

echo
echo "${BOLD}=== Summary ===${RESET}"
printf "  Before:  %s MB\n"                         "$B_TOTAL"
printf "  After:   %s MB\n"                         "$A_TOTAL"
printf "  ${GREEN}${BOLD}Freed:   %s MB${RESET}\n"  "$FREED"
printf "  Time:    %dm %ds\n"                       "$MINS" "$SECS"
$DRY_RUN && echo "${YELLOW}  (Dry run — rerun without --dry-run to apply)${RESET}"
echo

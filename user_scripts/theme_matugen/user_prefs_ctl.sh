#!/usr/bin/env bash
# ==============================================================================
#  DUSKY USER PREFERENCES CTL — ANIMATION ONLY
#
#  Preserves:
#    • Hyprland animation
#
#  Shader handling intentionally removed.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------------------
readonly ANIM_DIR="${HOME}/.config/hypr/source/animations"
readonly ACTIVE_CONF="${ANIM_DIR}/active/active.conf"

readonly STATE_DIR="${HOME}/.config/dusky/settings/user_prefs"
readonly SNAPSHOT_FILE="${STATE_DIR}/.animation_snapshot"

mkdir -p "${STATE_DIR}"

# ------------------------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
  readonly C_RESET=$'\e[0m'
  readonly C_GRN=$'\e[1;32m'
  readonly C_YLW=$'\e[1;33m'
  readonly C_BLU=$'\e[1;34m'
else
  readonly C_RESET='' C_GRN='' C_YLW='' C_BLU=''
fi

log_ok() { printf '%s[OK   ]%s %s\n' "${C_GRN}" "${C_RESET}" "$1"; }
log_info() { printf '%s[INFO ]%s %s\n' "${C_BLU}" "${C_RESET}" "$1"; }
log_warn() { printf '%s[WARN ]%s %s\n' "${C_YLW}" "${C_RESET}" "$1" >&2; }

# ------------------------------------------------------------------------------
# GET CURRENT ANIMATION
# ------------------------------------------------------------------------------
get_current_animation() {

  [[ -e "${ACTIVE_CONF}" ]] || {
    printf ''
    return
  }

  if [[ -L "${ACTIVE_CONF}" ]]; then
    local target
    target=$(readlink "${ACTIVE_CONF}" 2>/dev/null || true)
    [[ -n "${target}" ]] && {
      printf '%s' "$(basename "${target}")"
      return
    }
  fi

  local candidate
  while IFS= read -r -d '' candidate; do

    local name
    name=$(basename "${candidate}")

    [[ "${name}" == "active.conf" ]] && continue

    if diff -q "${ACTIVE_CONF}" "${candidate}" &>/dev/null; then
      printf '%s' "${name}"
      return
    fi

  done < <(find "${ANIM_DIR}" -maxdepth 1 -name '*.conf' -print0 2>/dev/null)

  printf ''
}

# ------------------------------------------------------------------------------
# APPLY ANIMATION
# ------------------------------------------------------------------------------
apply_animation() {

  local anim="$1"
  local src="${ANIM_DIR}/${anim}"

  [[ -f "${src}" ]] || {
    log_warn "Animation missing: ${src}"
    return 1
  }

  mkdir -p "${ANIM_DIR}/active"

  ln -sf "${src}" "${ACTIVE_CONF}" 2>/dev/null ||
    cp -f "${src}" "${ACTIVE_CONF}"

  if command -v hyprctl &>/dev/null; then
    hyprctl reload &>/dev/null || true
    sleep 0.15
  fi
}

# ------------------------------------------------------------------------------
# SAVE SNAPSHOT
# ------------------------------------------------------------------------------
cmd_save() {

  local anim
  anim=$(get_current_animation)

  printf 'ANIM=%s\n' "${anim}" >"${SNAPSHOT_FILE}"

  log_info "Saved animation='${anim:-unknown}'"
}

# ------------------------------------------------------------------------------
# RESTORE SNAPSHOT
# ------------------------------------------------------------------------------
cmd_restore() {

  [[ -f "${SNAPSHOT_FILE}" ]] || {
    log_info "No animation snapshot to restore"
    return 0
  }

  local ANIM=""

  while IFS='=' read -r key val; do
    case "${key}" in
    ANIM) ANIM="${val}" ;;
    esac
  done <"${SNAPSHOT_FILE}"

  rm -f "${SNAPSHOT_FILE}" || true

  if [[ -n "${ANIM}" ]]; then
    log_info "Restoring animation: ${ANIM}"
    if apply_animation "${ANIM}"; then
      log_ok "Animation restored"
    fi
  fi
}

# ------------------------------------------------------------------------------
# ENTRY POINT
# ------------------------------------------------------------------------------
case "${1:-}" in
--save) cmd_save ;;
--restore) cmd_restore ;;
*)
  echo "Usage: $(basename "$0") --save | --restore"
  exit 1
  ;;
esac

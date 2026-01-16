#!/usr/bin/env bash
# power_saving/lib/common.sh
# Shared configuration and helper functions

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
readonly BRIGHTNESS_LEVEL="1%"
readonly VOLUME_CAP="50"

# DYNAMIC PATH RESOLUTION
# Gets the 'power_saving' directory (parent of this lib file)
readonly POWER_SAVING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MODULES_DIR="${POWER_SAVING_ROOT}/modules"

# -----------------------------------------------------------------------------
# SCRIPT PATHS (Updated for serialized structure)
# -----------------------------------------------------------------------------

# 1. Scripts now located inside 'modules'
readonly ASUS_PROFILE_SCRIPT="${MODULES_DIR}/asus_tuf_profile/quiet_profile_and_keyboard_light.sh"

# 2. External Scripts (These likely remain outside)
readonly BLUR_SCRIPT="${HOME}/user_scripts/hypr/hypr_blur_opacity_shadow_toggle.sh"
readonly THEME_SCRIPT="${HOME}/user_scripts/theme_matugen/matugen_config.sh"

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------
has_cmd() { command -v "$1" &>/dev/null; }
is_numeric() { [[ -n "$1" && "$1" =~ ^[0-9]+$ ]]; }

# Logging
log_step()  { gum style --foreground 212 ":: $*"; }
log_warn()  { gum style --foreground 208 "⚠ $*"; }
log_error() { gum style --foreground 196 "✗ $*" >&2; }

# Execution wrappers
run_quiet() { "$@" &>/dev/null || true; }

spin_exec() {
    local title="$1"
    shift
    gum spin --spinner dot --title "$title" -- "$@"
}

# Run external script (handles uwsm-app logic)
run_external_script() {
    local script_path="$1"
    local description="$2"
    shift 2
    local -a extra_args=("$@")

    if [[ -x "${script_path}" ]]; then
        if has_cmd uwsm-app; then
            spin_exec "${description}" uwsm-app -- "${script_path}" "${extra_args[@]}"
        else
            spin_exec "${description}" "${script_path}" "${extra_args[@]}"
        fi
        return 0
    elif [[ -f "${script_path}" ]]; then
        log_warn "Script not executable: ${script_path}"
        return 1
    else
        log_warn "Script not found: ${script_path}"
        return 1
    fi
}

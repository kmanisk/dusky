#!/usr/bin/env bash
# ==============================================================================
# Script: switch_clipboard.sh
# Purpose: Toggle between Terminal and Rofi clipboard managers for Hyprland.
#          - Terminal mode: Uncomments/adds the custom clipboard keybind.
#          - Rofi mode: Comments out the custom keybind (restores default).
# Config:  ~/.config/hypr/edit_here/source/keybinds.conf
# System:  Arch Linux (Hyprland/Wayland)
# Flags:   --terminal, --rofi, --status (mutually exclusive)
# ==============================================================================

set -euo pipefail

# --- Configuration Constants -------------------------------------------------
readonly CONFIG_DIR="${HOME}/.config/hypr/edit_here/source"
readonly CONFIG_FILE="${CONFIG_DIR}/keybinds.conf"
readonly MARKER_START='# -- TERMINAL-CLIPBOARD-START --'
readonly MARKER_END='# -- TERMINAL-CLIPBOARD-END --'
readonly BIND_SIGNATURE='close_terminal_clipboard.sh'
readonly STATE_FILE="${HOME}/.config/dusky/settings/clipboard_state"
readonly LOCK_FILE="${CONFIG_FILE}.lock"

# --- Global Mutable State ----------------------------------------------------
_CLEANUP_FILE=""
_CONFIG_LINES=()
_CONFIG_LOADED=0
_TRIMMED=""

# --- Terminal Colors (conditional on stderr TTY) ------------------------------
if [[ -t 2 ]]; then
    readonly C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
    readonly C_BLUE=$'\e[34m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_RESET=''
fi

# --- Cleanup (single global EXIT trap) ---------------------------------------
cleanup() {
    if [[ -n "${_CLEANUP_FILE}" && -f "${_CLEANUP_FILE}" ]]; then
        rm -f -- "${_CLEANUP_FILE}"
    fi
}
trap cleanup EXIT

# --- Logging (all output to stderr) ------------------------------------------
die()     { printf '%s[FATAL]%s %s\n' "${C_RED}"    "${C_RESET}" "$1" >&2; exit "${2:-1}"; }
info()    { printf '%s[INFO]%s %s\n'  "${C_BLUE}"   "${C_RESET}" "$1" >&2; }
success() { printf '%s[OK]%s %s\n'    "${C_GREEN}"  "${C_RESET}" "$1" >&2; }
warn()    { printf '%s[WARN]%s %s\n'  "${C_YELLOW}" "${C_RESET}" "$1" >&2; }

# --- Helper: Strip leading/trailing whitespace (sets _TRIMMED, no subshell) ---
trim() {
    _TRIMMED="${1#"${1%%[![:space:]]*}"}"
    _TRIMMED="${_TRIMMED%"${_TRIMMED##*[![:space:]]}"}"
}

# --- Helper: Load config file into cache (idempotent) ------------------------
load_config() {
    (( _CONFIG_LOADED )) && return 0
    [[ -f "${CONFIG_FILE}" ]] || return 1
    mapfile -t _CONFIG_LINES < "${CONFIG_FILE}"
    _CONFIG_LOADED=1
    return 0
}

# --- Helper: Check if marker block exists in cached config --------------------
has_marker_block() {
    (( _CONFIG_LOADED )) || return 1
    local line
    for line in "${_CONFIG_LINES[@]}"; do
        trim "${line}"
        [[ "${_TRIMMED}" == "${MARKER_START}" ]] && return 0
    done
    return 1
}

# --- Helper: Validate marker block integrity before any modification ----------
validate_markers() {
    local start_count=0 end_count=0
    local start_line=-1 end_line=-1
    local i

    for i in "${!_CONFIG_LINES[@]}"; do
        trim "${_CONFIG_LINES[i]}"
        if [[ "${_TRIMMED}" == "${MARKER_START}" ]]; then
            start_count=$(( start_count + 1 ))
            start_line=${i}
        elif [[ "${_TRIMMED}" == "${MARKER_END}" ]]; then
            end_count=$(( end_count + 1 ))
            end_line=${i}
        fi
    done

    (( start_count == 1 )) || \
        die "Marker integrity error: expected 1 start marker, found ${start_count}. Fix ${CONFIG_FILE} manually."
    (( end_count == 1 )) || \
        die "Marker integrity error: expected 1 end marker, found ${end_count}. Fix ${CONFIG_FILE} manually."
    (( start_line < end_line )) || \
        die "Marker integrity error: start marker (line $(( start_line + 1 ))) must precede end marker (line $(( end_line + 1 ))). Fix ${CONFIG_FILE} manually."
}

# --- Detection: Is terminal mode active? (pure — no side effects) ------------
is_terminal_mode() {
    load_config || return 1
    has_marker_block || return 1

    local in_block=0 line
    for line in "${_CONFIG_LINES[@]}"; do
        trim "${line}"

        if [[ "${_TRIMMED}" == "${MARKER_START}" ]]; then
            in_block=1
            continue
        elif [[ "${_TRIMMED}" == "${MARKER_END}" ]]; then
            break
        fi

        if (( in_block )); then
            if [[ "${_TRIMMED}" == *"${BIND_SIGNATURE}"* && "${_TRIMMED}" != '#'* ]]; then
                return 0
            fi
        fi
    done
    return 1
}

# --- Detection: Logging wrapper around is_terminal_mode() --------------------
get_clipboard_state() {
    info "Inspecting configuration state at: ${CONFIG_FILE}"
    if is_terminal_mode; then
        info "Detected active Terminal keybinding."
        return 0
    else
        info "Rofi clipboard mode is active (default)."
        return 1
    fi
}

# --- Helper: Generate the terminal keybind block (stdout) --------------------
generate_terminal_block() {
    printf '%s\n' \
        "${MARKER_START}" \
        'unbind = $mainMod, V' \
        'bindd = $mainMod, V, Clipboard History, exec, $scripts/clipboard/close_terminal_clipboard.sh uwsm-app -- kitty --class terminal_clipboard.sh -e "$scripts/clipboard/terminal_clipboard.sh"' \
        "${MARKER_END}"
}

# --- Helper: Write state file with trailing newline --------------------------
write_state() {
    mkdir -p "${STATE_FILE%/*}"
    printf '%s\n' "$1" > "${STATE_FILE}"
}

# --- Helper: Self-heal state file to match actual config ---------------------
sync_state_file() {
    if is_terminal_mode; then
        write_state "True"
    else
        write_state "False"
    fi
}

# --- Helper: Advisory runtime environment checks -----------------------------
check_environment() {
    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        warn "HYPRLAND_INSTANCE_SIGNATURE not set. Hyprland may not be running."
    fi
    if ! command -v hyprctl &>/dev/null; then
        warn "hyprctl not found on PATH. Configuration reload will be skipped."
    fi
}

# --- Helper: Reload Hyprland configuration ------------------------------------
reload_hyprland() {
    if ! command -v hyprctl &>/dev/null; then
        warn "hyprctl not found. Manual Hyprland reload may be required."
        return 0
    fi
    if ! hyprctl reload &>/dev/null; then
        warn "hyprctl reload failed. Manual Hyprland reload may be required."
        return 0
    fi
    info "Hyprland configuration reloaded."
}

# --- Helper: Atomic write from array to config file --------------------------
#     Used by modify_config_block and the append path to guarantee consistent
#     atomic-rename semantics for every config mutation.
atomic_write_config() {
    local -n _lines_ref=$1

    local tmpfile
    tmpfile=$(mktemp "${CONFIG_FILE}.tmp.XXXXXX") || die "Failed to create temporary file."
    _CLEANUP_FILE="${tmpfile}"

    # Preserve original file permissions when the file already exists
    if [[ -f "${CONFIG_FILE}" ]]; then
        chmod --reference="${CONFIG_FILE}" "${tmpfile}" || die "Failed to preserve file permissions."
    fi

    printf '%s\n' "${_lines_ref[@]}" > "${tmpfile}"
    mv -f -- "${tmpfile}" "${CONFIG_FILE}"

    # Success: disarm cleanup trap and invalidate cache
    _CLEANUP_FILE=""
    _CONFIG_LOADED=0
}

# --- Core: Modify config block (atomic, same-filesystem, permission-safe) ----
modify_config_block() {
    local action="$1"
    info "Starting atomic file modification: ${action}..."

    # Safety: verify marker integrity before touching anything
    validate_markers

    local -a output=()
    local in_block=0 line

    for line in "${_CONFIG_LINES[@]}"; do
        trim "${line}"

        if [[ "${_TRIMMED}" == "${MARKER_START}" ]]; then
            in_block=1
            output+=("${line}")
        elif [[ "${_TRIMMED}" == "${MARKER_END}" ]]; then
            in_block=0
            output+=("${line}")
        elif (( in_block )); then
            if [[ "${action}" == "comment" && "${_TRIMMED}" != '#'* ]]; then
                output+=("# ${line}")
            elif [[ "${action}" == "uncomment" && "${_TRIMMED}" == '#'* ]]; then
                # Check the TRIMMED version for comment style, operate on
                # the untrimmed line to preserve leading whitespace.
                # Using _TRIMMED prevents false matches against '# ' that
                # could appear in the line's content rather than its prefix.
                if [[ "${_TRIMMED}" == '# '* ]]; then
                    output+=("${line/'# '/}")
                else
                    output+=("${line/'#'/}")
                fi
            else
                output+=("${line}")
            fi
        else
            output+=("${line}")
        fi
    done

    atomic_write_config output

    info "Successfully updated configuration file."
}

# --- Action: Enable terminal clipboard mode -----------------------------------
enable_terminal_mode() {
    info "Initiating switch to Terminal Clipboard mode..."

    if load_config; then
        if has_marker_block; then
            modify_config_block "uncomment"
        else
            info "No existing block found. Appending new configuration..."

            # Build the complete new file content as an array for atomic write
            local -a new_content=("${_CONFIG_LINES[@]}")

            # Add a single blank separator line if the file has content
            if (( ${#new_content[@]} > 0 )); then
                new_content+=("")
            fi

            # Append the generated block lines
            local -a block_lines
            mapfile -t block_lines < <(generate_terminal_block)
            new_content+=("${block_lines[@]}")

            atomic_write_config new_content

            info "Configuration appended to ${CONFIG_FILE}."
        fi
    else
        warn "Configuration file does not exist. Creating with clipboard block only."
        mkdir -p "${CONFIG_DIR}"

        local -a block_lines
        mapfile -t block_lines < <(generate_terminal_block)
        atomic_write_config block_lines

        info "Configuration created at ${CONFIG_FILE}."
    fi

    write_state "True"
    reload_hyprland
    success "Terminal Clipboard enabled."
}

# --- Action: Enable rofi clipboard mode --------------------------------------
enable_rofi_mode() {
    info "Initiating switch to Rofi Clipboard mode..."

    if load_config && has_marker_block; then
        modify_config_block "comment"
        success "Rofi Clipboard enabled (Terminal config commented out)."
    else
        warn "No Terminal clipboard configuration found. System is already using Rofi Clipboard."
    fi

    write_state "False"
    reload_hyprland
}

# --- Action: Print current clipboard state and exit ---------------------------
print_status() {
    load_config || true
    sync_state_file

    if is_terminal_mode; then
        printf 'terminal\n'
    else
        printf 'rofi\n'
    fi
}

# --- Interactive menu (all output to stderr) ----------------------------------
show_menu() {
    local current_state="$1"
    local state_label

    if [[ "${current_state}" == "terminal" ]]; then
        state_label="${C_GREEN}Terminal${C_RESET}"
    else
        state_label="${C_YELLOW}Rofi${C_RESET}"
    fi

    printf '\n%s%sClipboard Manager Selection%s\n' "${C_BOLD}" "${C_BLUE}" "${C_RESET}" >&2
    printf 'Current: %s\n\n' "${state_label}" >&2
    printf '  1) %sTerminal Clipboard%s  (with image previews)\n' "${C_GREEN}" "${C_RESET}" >&2
    printf '  2) %sRofi Clipboard%s      (standard text list)\n' "${C_YELLOW}" "${C_RESET}" >&2
    printf '\n%sChoice [1/2]:%s ' "${C_BOLD}" "${C_RESET}" >&2
}

# --- Usage (to stderr) -------------------------------------------------------
usage() {
    cat >&2 <<EOF
Usage: ${0##*/} [OPTIONS]

Toggle between Terminal and Rofi clipboard managers for Hyprland.

Options:
  --terminal   Enable Terminal clipboard mode
  --rofi       Enable Rofi clipboard mode
  --status     Print current mode (terminal or rofi) to stdout and exit
  -h, --help   Show this help message

Options --terminal, --rofi, and --status are mutually exclusive.
If no option is provided, an interactive menu is displayed.
EOF
}

# --- Main ---------------------------------------------------------------------
main() {
    # Guard: do not run as root
    (( EUID != 0 )) || die "Do not run as root. This modifies user configuration."

    local mode=""

    # Argument parsing with mutual-exclusivity enforcement
    while (( $# > 0 )); do
        case "$1" in
            --terminal)
                [[ -z "${mode}" ]] || die "Conflicting options: --terminal and --${mode} are mutually exclusive."
                mode="terminal"
                ;;
            --rofi)
                [[ -z "${mode}" ]] || die "Conflicting options: --rofi and --${mode} are mutually exclusive."
                mode="rofi"
                ;;
            --status)
                [[ -z "${mode}" ]] || die "Conflicting options: --status and --${mode} are mutually exclusive."
                mode="status"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                die "Unexpected argument: $1"
                ;;
        esac
        shift
    done

    # Non-TTY guard: refuse interactive mode when stdin is not a terminal
    if [[ -z "${mode}" && ! -t 0 ]]; then
        die "No mode specified and stdin is not a terminal. Use --terminal or --rofi."
    fi

    # Advisory environment checks (skip for status-only queries)
    if [[ "${mode}" != "status" ]]; then
        check_environment
    fi

    # Ensure config directory exists (required for lock file)
    mkdir -p "${CONFIG_DIR}"

    # Acquire exclusive lock (non-blocking — fail fast on contention)
    local lock_fd
    exec {lock_fd}>"${LOCK_FILE}"
    flock -n "${lock_fd}" || die "Another instance is already running."

    # Status mode: print and exit early (no modifications beyond state sync)
    if [[ "${mode}" == "status" ]]; then
        print_status
        exit 0
    fi

    # Load config (may not exist yet) and self-heal state file
    load_config || true
    sync_state_file

    # Interactive mode if no CLI flags were provided
    if [[ -z "${mode}" ]]; then
        local current_state="rofi"
        if get_clipboard_state; then
            current_state="terminal"
        fi

        show_menu "${current_state}"

        local choice=""
        read -r choice || true

        case "${choice}" in
            1) mode="terminal" ;;
            2) mode="rofi" ;;
            *) die "Invalid selection: '${choice:-<empty>}'" ;;
        esac
        printf '\n' >&2
    fi

    # Execute selected action
    case "${mode}" in
        terminal) enable_terminal_mode ;;
        rofi)     enable_rofi_mode ;;
        *)        die "Internal error: invalid mode '${mode}'" ;;
    esac
}

main "$@"

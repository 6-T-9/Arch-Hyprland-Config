#!/usr/bin/env bash
# shellcheck disable=SC1091

# ================================================================
#  Hyprland Installer — Obsidian
# ================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# Global Configuration
# ==============================================================================
readonly REPO_URL="https://github.com/oobsidian/Arch-Hyprland-Config.git"
readonly WALLPAPER_REPO_URL="https://github.com/oobsidian/wallpapers.git"

readonly CONFIG_DIR="$HOME/.config"
readonly WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

readonly STATE_DIR="$HOME/.local/state/hyprland-installer"
readonly LOG_FILE="$STATE_DIR/install.log.json"
readonly STATE_FILE="$STATE_DIR/state.txt"
readonly BACKUP_DIR="$STATE_DIR/backup"
readonly CONFIG_BACKUP="$BACKUP_DIR/config-full"

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# ==============================================================================
# Runtime Flags
# ==============================================================================
DRY_RUN=false
CI_MODE=false
UNINSTALL=false

# USER OPTIONS (renamed to avoid function conflict)
INSTALL_VSCODIUM=false
INSTALL_WALLPAPERS=false
SET_FISH_SHELL=true
CONFIGURE_BOOTLOADER=true
REBOOT_AFTER=false

STEP=0
TOTAL_STEPS=14

mkdir -p "$STATE_DIR" "$BACKUP_DIR"

# ==============================================================================
# Logging
# ==============================================================================
json_log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","step":%d,"dry_run":%s,"message":"%s"}\n' \
        "$(date --iso-8601=seconds)" \
        "$level" "$STEP" "$DRY_RUN" \
        "$(printf '%s' "$*" | sed 's/"/\\"/g')" \
        >>"$LOG_FILE"
}

log()  { echo -e "${GREEN}[INFO]${NC} $*"; json_log info "$@"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; json_log warn "$@"; }
error(){ echo -e "${RED}[ERROR]${NC} $*" >&2; json_log error "$@"; }
die()  { error "$@"; exit 1; }

step() {
    STEP=$((STEP + 1))
    log "[$STEP/$TOTAL_STEPS] $*"
}

# ==============================================================================
# Helpers
# ==============================================================================
run() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

state_add() {
    echo "$1" >>"$STATE_FILE"
}

pacman_install() {
    for p in "$@"; do
        pacman -Qi "$p" &>/dev/null || state_add "pacman:$p"
    done
    run sudo pacman -S --needed --noconfirm "$@"
}

aur_install() {
    for p in "$@"; do
        pacman -Qi "$p" &>/dev/null || state_add "aur:$p"
    done
    run yay -S --needed --noconfirm "$@"
}

check_os() {
    command -v pacman >/dev/null || die "This installer supports Arch Linux only."
}

# ==============================================================================
# Arguments
# ==============================================================================
parse_args() {
    for arg in "$@"; do
        case "$arg" in
            -h|--help) exit 0 ;;
            --dry-run) DRY_RUN=true ;;
            --ci) CI_MODE=true ;;
            --uninstall) UNINSTALL=true ;;
            *) die "Unknown argument: $arg" ;;
        esac
    done
}

# ==============================================================================
# Uninstall
# ==============================================================================
uninstall() {
    step "Uninstalling"

    [[ -f "$STATE_FILE" ]] || {
        warn "No state file found."
        exit 0
    }

    local p=() a=()

    while read -r e; do
        case "$e" in
            pacman:*) p+=("${e#pacman:}") ;;
            aur:*) a+=("${e#aur:}") ;;
        esac
    done < "$STATE_FILE"

    ((${#a[@]})) && run yay -Rns --noconfirm "${a[@]}"
    ((${#p[@]})) && run sudo pacman -Rns --noconfirm "${p[@]}"

    run rm -rf "$STATE_DIR"
    log "Uninstall completed"
}

# ==============================================================================
# User Config
# ==============================================================================
get_user_choice() {
    step "Collecting user preferences"

    if $CI_MODE; then
        warn "CI mode: using defaults"
        INSTALL_VSCODIUM=true
        return
    fi

    read -r -p "Install VSCodium? [y/N]: " r || true
    [[ "$r" =~ ^[Yy]$ ]] && INSTALL_VSCODIUM=true

    read -r -p "Download wallpapers? [y/N]: " r || true
    [[ "$r" =~ ^[Yy]$ ]] && INSTALL_WALLPAPERS=true

    read -r -p "Set fish as default shell? [Y/n]: " r || true
    [[ "$r" =~ ^[Nn]$ ]] && SET_FISH_SHELL=false

    read -r -p "Configure bootloader timeout? [Y/n]: " r || true
    [[ "$r" =~ ^[Nn]$ ]] && CONFIGURE_BOOTLOADER=false

    read -r -p "Reboot after install? [y/N]: " r || true
    [[ "$r" =~ ^[Yy]$ ]] && REBOOT_AFTER=true
}

# ==============================================================================
# Install Phases
# ==============================================================================
updating_system() {
    step "Updating system"
    run sudo pacman -Syu --noconfirm
}

install_dependencies() {
    step "Installing base dependencies"
    pacman_install base-devel git rsync jq nano
}

install_main_packages() {
    step "Installing main packages"
    pacman_install waybar rofi fish kitty
}

change_shell() {
    $SET_FISH_SHELL || return 0
    step "Setting fish as default shell"
    command -v fish &>/dev/null && run sudo chsh -s /usr/bin/fish "$USER"
}

install_yay() {
    step "Installing yay"
    command -v yay &>/dev/null && return

    run git clone https://aur.archlinux.org/yay.git /tmp/yay
    run bash -c "cd /tmp/yay && makepkg -si --noconfirm"
    run rm -rf /tmp/yay
}

install_aur_packages() {
    step "Installing AUR packages"

    local aur_pkgs=(hypremoji ibus-m17n m17n-db)

    if $INSTALL_VSCODIUM; then
        aur_pkgs+=(vscodium-bin)
    fi

    aur_install "${aur_pkgs[@]}"
}

fix_vscodium_icons() {
    $INSTALL_VSCODIUM || return 0
    command -v codium &>/dev/null || return 0

    step "Adjusting VSCodium icons"

    for f in /usr/share/applications/codium*.desktop; do
        [[ -f "$f" ]] && run sudo sed -i 's/^Icon=.*/Icon=vscode/' "$f"
    done
}

clone_config_repo() {
    step "Cloning config"

    [[ -d "$CONFIG_DIR" && ! -d "$CONFIG_BACKUP" ]] &&
        run cp -a "$CONFIG_DIR" "$CONFIG_BACKUP"

    local tmp
    tmp="$(mktemp -d)"

    run git clone "$REPO_URL" "$tmp"
    run rsync -a --delete --exclude='.git' "$tmp"/ "$CONFIG_DIR"/
    run rm -rf "$tmp"
}

other_tweaks() {
    $CONFIGURE_BOOTLOADER || return 0

    step "Applying bootloader tweaks"

    if command -v bootctl >/dev/null 2>&1 && bootctl is-installed >/dev/null 2>&1; then
        run sudo sed -i.bak 's/^timeout .*/timeout 1/' /boot/loader/loader.conf
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        run sudo sed -i.bak 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
        run sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

reboot_system() {
    $REBOOT_AFTER || return 0
    run sudo reboot
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    parse_args "$@"
    check_os

    $UNINSTALL && { uninstall; exit 0; }

    log "Installer started"

    get_user_choice
    updating_system
    install_dependencies
    install_main_packages
    change_shell
    install_yay
    install_aur_packages
    fix_vscodium_icons
    clone_config_repo
    other_tweaks
    reboot_system

    log "Installation completed successfully"
}

main "$@"

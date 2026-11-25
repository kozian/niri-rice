#!/usr/bin/env bash
set -uo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1
source lib/common.sh

errors=0
warnings=0
error() { printf 'ERROR: %s\n' "$*" >&2; errors=$((errors + 1)); }
warn() { printf 'WARN: %s\n' "$*" >&2; warnings=$((warnings + 1)); }
info() { printf 'INFO: %s\n' "$*"; }

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: %s\n' "$0"
    exit 0
fi
if (( $# )); then
    error 'Unexpected arguments.'
    exit 2
fi
if ! is_arch || ! command -v pacman >/dev/null; then
    error 'Run diagnostics on the target Arch Linux installation.'
    exit 1
fi
if (( EUID == 0 )); then
    error 'Run diagnostics as the account that will use niri.'
    exit 1
fi
info "Kernel $(uname -r)"
[[ $(cat /sys/class/dmi/id/product_name 2>/dev/null) == MacBook10,1 ]] ||
    warn 'DMI product differs from MacBook10,1.'

mapfile -t packages < <(package_names packages/required.txt)
if pacman -Q jack2 >/dev/null 2>&1; then
    packages=("${packages[@]/pipewire-jack/jack2}")
fi
for pkg in "${base_packages[@]}" "${packages[@]}" xdg-desktop-portal; do
    pacman -Q "$pkg" >/dev/null 2>&1 || error "Missing package: $pkg"
done
if pacman -Q xdg-desktop-portal-gnome >/dev/null 2>&1; then
    info 'Optional GNOME screencast backend is installed.'
else
    info 'Optional GNOME screencast backend is absent.'
fi

for cmd in niri niri-session waybar fuzzel foot swaync swaync-client thunar firefox swaylock swayidle \
           wpaperd wl-paste wl-copy cliphist xdg-mime brightnessctl playerctl wpctl nmcli nmtui jq fc-match \
           systemctl loginctl busctl flock timeout pgrep pkill; do
    command -v "$cmd" >/dev/null || error "Missing command: $cmd"
done
[[ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ]] ||
    error 'Missing graphical Polkit agent.'

while IFS= read -r -d '' file; do
    target=$config_home/${file#.config/}
    [[ -f $target && -r $target ]] || error "Missing or unreadable config: $target"
    if [[ -L $file ]]; then
        [[ -L $target && $(readlink -- "$file") == "$(readlink -- "$target")" ]] ||
            error "Unexpected theme link: $target"
    fi
done < <(find .config \( -type f -o -type l \) ! -path '.config/macbook-rice/themes/current' -print0)
theme_root=$config_home/macbook-rice/themes
case "$(readlink -- "$theme_root/current" 2>/dev/null)" in
    tokyonight|catppuccin) info "Theme: $(readlink -- "$theme_root/current")" ;;
    *) error 'Invalid active theme symlink.' ;;
esac
for file in wallpapers/*/*.png; do
    rel=${file#wallpapers/}
    [[ -f $theme_root/${rel%%/*}/wallpapers/${rel#*/} ]] ||
        error "Missing wallpaper: $file"
done
if [[ -r $config_home/wpaperd/config.toml ]] &&
   grep -Fq '@WALLPAPERS@' "$config_home/wpaperd/config.toml"; then
    error 'wpaperd configuration still contains the installer placeholder.'
fi
for file in .local/bin/rice-*; do
    target=$HOME/.local/bin/${file##*/}
    if [[ ! -x $target ]]; then
        error "Missing or non-executable helper: $target"
    elif ! bash -n "$target"; then
        error "Invalid Bash syntax: $target"
    fi
done
if [[ -n ${NIRI_CONFIG:-} ]]; then
    warn "NIRI_CONFIG overrides the managed file: $NIRI_CONFIG"
fi
if command -v niri >/dev/null; then
    if niri validate -c "$config_home/niri/config.kdl"; then
        info 'niri KDL validated.'
    else
        error 'niri configuration validation failed.'
    fi
fi
for theme in tokyonight catppuccin; do
    if command -v fuzzel >/dev/null && ! fuzzel --check-config --config="$theme_root/$theme/fuzzel.ini"; then
        error "Invalid Fuzzel config for $theme."
    fi
    if command -v foot >/dev/null && ! foot --check-config --config="$theme_root/$theme/foot.ini"; then
        error "Invalid Foot config for $theme."
    fi
done
if command -v jq >/dev/null; then
    for file in "$config_home/waybar/config.jsonc" "$config_home/swaync/config.json"; do
        [[ -r $file ]] || continue
        # Managed defaults use plain JSON. Waybar also accepts JSONC in user edits.
        if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
            if [[ $file == *.jsonc ]]; then warn "Waybar config is not plain JSON. Review Waybar logs for JSONC errors."
            else error "Invalid JSON object: $file"
            fi
        fi
    done
fi

if [[ -e $no_autostart ]]; then
    info 'TTY1 autostart is disabled for this account.'
else
    profile=$HOME/$(login_profile)
    if [[ -f $profile ]] && [[ $(grep -Fxc -- "$profile_line" "$profile") == 1 ]] && bash -n "$profile"; then
        info "TTY1 hook present once in $profile."
    else
        error "Missing, duplicated or invalid TTY1 hook in $profile."
    fi
    if [[ $(getent passwd "$EUID" | cut -d: -f7) != */bash ]]; then
        error 'Bash is required as the login shell for TTY1 autostart.'
    fi
    if systemctl --quiet is-enabled display-manager.service || systemctl --quiet is-active display-manager.service; then
        error 'TTY1 autostart conflicts with an enabled or active display manager.'
    fi
    if [[ $(systemctl show getty@tty1.service -p ExecStart --value) == *--autologin* ]]; then
        error 'TTY1 getty is configured for autologin.'
    fi
fi

legacy='\b(hyprctl|start-hyprland|Hyprland|hyprland/(workspaces|window)|hypridle|hyprlock|hyprpicker|hyprpolkitagent|wofi|alacritty|pamixer|grim|slurp)\b'
for path in "$config_home"/{niri,waybar,swaync,foot,fuzzel,wpaperd,swayidle,swaylock,macbook-rice} \
            "$HOME"/.local/bin/rice-*; do
    [[ -e $path ]] || continue
    if grep -rInE --exclude='*.png' "$legacy" "$path"; then
        error "Legacy command or module under $path."
    fi
done
for path in "$HOME/$(login_profile)" "$HOME/.bashrc"; do
    if [[ -r $path ]] && grep -qE '\b(Hyprland|start-hyprland|hyprctl)\b' "$path"; then
        warn "Review inherited Hyprland references in $path."
    fi
done

if command -v fc-match >/dev/null; then
    for font in 'CaskaydiaCove Nerd Font' 'CaskaydiaCove Nerd Font Mono' 'Noto Sans' 'Noto Color Emoji'; do
        [[ $(fc-match -f '%{family}' "$font") == *"$font"* ]] ||
            error "Expected font not matched: $font"
    done
    for glyph in f0f3 f242 f011 f0928; do
        [[ $(fc-match -f '%{family}' "CaskaydiaCove Nerd Font:charset=$glyph") == *CaskaydiaCove* ]] ||
            warn "Check Nerd Font coverage for U+$glyph."
    done
fi

systemctl --quiet is-active NetworkManager.service || error 'NetworkManager.service is inactive.'
systemctl --quiet is-active systemd-logind.service || error 'systemd-logind.service is inactive.'
if systemctl --user show-environment >/dev/null 2>&1; then
    for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
        systemctl --user --quiet is-active "$unit" || warn "Audio unit is inactive: $unit"
    done
    for unit in macbook-rice.target macbook-rice@waybar.service macbook-rice-lock.service swaync.service; do
        [[ $(systemctl --user show -p LoadState --value "$unit") == loaded ]] ||
            error "User unit failed to load: $unit"
    done
    deps=$(systemctl --user show -p Wants --value niri.service)
    [[ " $deps " == *' macbook-rice.target '* ]] || error 'niri.service does not request macbook-rice.target.'
    while IFS= read -r unit; do
        [[ -z $unit ]] || error "Conflicting user unit enabled or active: $unit"
    done < <(competing_units)
else
    error 'Cannot contact the systemd user manager.'
fi
while IFS= read -r path; do
    [[ -z $path ]] || error "Conflicting XDG autostart entry: $path"
done < <(competing_autostarts)

if [[ -n ${NIRI_SOCKET:-} ]]; then
    if timeout 3 niri msg version && timeout 3 niri msg outputs; then
        info 'niri IPC is available.'
    else
        error 'niri IPC failed.'
    fi
    systemctl --user --quiet is-active niri.service || error 'Use niri-session to start the desktop.'
    systemctl --user --quiet is-active macbook-rice.target || error 'Desktop target is inactive.'
    for component in "${desktop_components[@]}"; do
        systemctl --user --quiet is-active "macbook-rice@$component.service" ||
            error "Desktop component is inactive: $component"
    done
    systemctl --user --quiet is-active swaync.service || error 'SwayNC service is inactive.'
    owner=$(busctl --user --timeout=3 call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetConnectionUnixProcessID s org.freedesktop.Notifications 2>/dev/null)
    sway_pid=$(systemctl --user show -p MainPID --value swaync.service)
    [[ $sway_pid != 0 && $owner == "u $sway_pid" ]] ||
        error 'SwayNC does not own org.freedesktop.Notifications.'
    for cmd in mako dunst fnott; do
        if pgrep -u "$EUID" -x "$cmd" >/dev/null; then
            error "Conflicting notification daemon running: $cmd"
        fi
    done
    for cmd in waybar swaync swayidle wpaperd; do
        if (( $(pgrep -c -u "$EUID" -x "$cmd") > 1 )); then
            error "Duplicate processes: $cmd"
        fi
    done
    command -v wpctl >/dev/null && wpctl status >/dev/null 2>&1 || warn 'WirePlumber IPC is unavailable.'
    if ! brightnessctl --class=backlight get >/dev/null 2>&1; then warn 'No readable display backlight device.'; fi
    for unit in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do
        if systemctl --user --quiet is-failed "$unit"; then error "Portal unit failed: $unit"
        else info "$unit: $(systemctl --user is-active "$unit") (on demand)"
        fi
    done
else
    info 'Graphical checks skipped. Run again from a Foot terminal inside niri.'
fi

printf '%d error(s), %d warning(s).\n' "$errors" "$warnings"
(( errors == 0 ))

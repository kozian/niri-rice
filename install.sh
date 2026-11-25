#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source lib/common.sh

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
usage() {
    printf 'Usage: %s [--dry-run] [--screencast] [--no-autostart]\n' "$0"
}
dry_run=0
screencast=0
no_tty=0
while (( $# )); do
    case "$1" in
        --dry-run) dry_run=1 ;;
        --screencast) screencast=1 ;;
        --no-autostart) no_tty=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unknown option: $1" ;;
    esac
    shift
done

(( EUID != 0 )) || die 'Run as the account that will use niri, without sudo.'
is_arch || die 'This installer requires Arch Linux.'
[[ $(uname -m) == x86_64 && $(ps -p 1 -o comm=) == systemd ]] ||
    die 'Expected x86_64 Arch Linux booted with systemd.'
for cmd in pacman pacman-conf curl systemctl loginctl nmcli getent flock; do
    command -v "$cmd" >/dev/null || die "Missing base command: $cmd"
done
for path in "$HOME" "$config_home" "$state_home"; do
    [[ $path == /* && ! $path =~ [[:cntrl:]] ]] || die "Unsupported home/XDG path: $path"
done
pacman -Q "${base_packages[@]}" >/dev/null || die 'Install the missing Arch base packages first.'
repos=$(pacman-conf --repo-list)
for repo in core extra; do
    grep -Fxq "$repo" <<< "$repos" || die "Enable the official [$repo] repository before installing."
done
systemctl --user show-environment >/dev/null || die 'Log in normally on a local TTY to start the systemd user manager.'
systemctl --quiet is-active NetworkManager.service || die 'NetworkManager.service must be active.'
if ! (( no_tty )) && [[ ! -e $no_autostart ]]; then
    shell=$(getent passwd "$EUID" | cut -d: -f7)
    [[ ${shell##*/} == bash ]] || die 'TTY1 autostart requires Bash as the login shell. Use --no-autostart for manual launch.'
    if systemctl --quiet is-enabled display-manager.service || systemctl --quiet is-active display-manager.service; then
        die 'A display manager is enabled or active. Disable it manually for TTY1 autostart, or use --no-autostart.'
    fi
    if [[ $(systemctl show getty@tty1.service -p ExecStart --value) == *--autologin* ]]; then
        die 'TTY1 getty currently uses autologin. Remove its autologin override manually, or use --no-autostart.'
    fi
fi
[[ -z ${NIRI_SOCKET:-}${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] &&
    ! systemctl --user --quiet is-active graphical-session.target ||
    die 'End the graphical session and run from a TTY before replacing its configuration.'
if [[ -n ${NIRI_CONFIG:-} ]]; then
    die 'Unset NIRI_CONFIG before installing and starting this rice.'
fi
conflicts=$(competing_units)
autostarts=$(competing_autostarts)
[[ -z $conflicts && -z $autostarts ]] ||
    die "Conflicting user units or desktop autostart entries:
$conflicts
$autostarts
Disable the listed units or autostart entries for niri before retrying. See README.md."
for pkg in hyprland mako dunst fnott xwayland-satellite hyprpolkitagent polkit-kde-agent; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        warn "$pkg is installed. Review its old startup hooks before logging into niri."
    fi
done

profile=$(login_profile)
if ! (( no_tty )) && [[ ! -e $no_autostart ]]; then
    for path in "$HOME/$profile" "$HOME/.bashrc"; do
        if [[ -f $path ]] && grep -Eq '^[[:space:]]*(exec[[:space:]]+)?(start-hyprland|Hyprland|niri-session)([[:space:]]|$)' "$path"; then
            die "Existing compositor launch in $path. Back up that file and remove the old launch block before retrying."
        fi
    done
fi

server_ok=0
attempts=0
while IFS= read -r server; do
    [[ $server == https://* || $server == http://* ]] || continue
    server=${server//\$repo/core}
    server=${server//\$arch/x86_64}
    attempts=$((attempts + 1))
    if curl --fail --silent --location --head --connect-timeout 3 --max-time 6 "${server%/}/core.db" >/dev/null; then
        server_ok=1
        break
    fi
    (( attempts < 5 )) || break
done < <(pacman-conf -r core Server)
if (( ! server_ok )); then
    if (( dry_run )); then warn 'No response from the first five configured HTTP(S) core mirrors.'
    else die 'No response from the first five configured HTTP(S) core mirrors. Check tethering, Wi-Fi and the mirror list.'
    fi
fi

mapfile -t packages < <(package_names packages/required.txt)
if pacman -Q jack2 >/dev/null 2>&1; then
    packages=("${packages[@]/pipewire-jack/jack2}")
fi
if (( screencast )); then
    mapfile -t optional < <(package_names packages/optional.txt)
    packages+=("${optional[@]}")
fi
printf 'Package transaction: sudo pacman -Syu --needed %s\n' "${packages[*]}"

if (( ! dry_run )); then
    exec 9>"${XDG_RUNTIME_DIR:?Local login required}/macbook-rice-install.lock"
    flock -n 9 || die 'Another install is running.'
fi
stage=$(mktemp -d)
backup=
pending=
trap 'rc=$?; if [[ -n $pending ]]; then rm -f -- "$pending"; fi
      rm -r -- "$stage"
      if (( rc != 0 )); then
          printf "Installation stopped (exit %s).\n" "$rc" >&2
          if [[ -n $backup ]]; then printf "Backup/manifest: %s\n" "$backup" >&2; fi
      fi
      exit "$rc"' EXIT

mkdir -p "$stage/config" "$stage/home/.local/bin"
cp -a -- .config/. "$stage/config/"
cp -a -- .local/bin/. "$stage/home/.local/bin/"
# Merge the managed Thunar shortcuts with the existing GTK accelerator map.
thunar_accels=$config_home/Thunar/accels.scm
if [[ -f $thunar_accels ]]; then
    awk -F '"' '
        NR == FNR { rule[$2] = $0; order[++count] = $2; next }
        /^[[:space:];]*\(gtk_accel_path[[:space:]]/ && $2 in rule {
            if (!seen[$2]++) print rule[$2]
            next
        }
        { print }
        END {
            for (i = 1; i <= count; i++)
                if (!seen[order[i]]) print rule[order[i]]
        }
    ' .config/Thunar/accels.scm "$thunar_accels" > "$stage/config/Thunar/accels.scm"
fi
themes_rel=macbook-rice/themes
active=$config_home/$themes_rel/current
if [[ -L $active ]]; then
    selected=$(readlink -- "$active")
    case "$selected" in
        tokyonight|catppuccin) ln -sfn -- "$selected" "$stage/config/$themes_rel/current" ;;
        *) die "Unsupported theme link: $active" ;;
    esac
elif [[ -e $active ]]; then
    die "Expected a theme symlink at $active."
fi
for theme in tokyonight catppuccin; do
    cp -a -- "wallpapers/$theme" "$stage/config/$themes_rel/$theme/wallpapers"
done
wallpath=$config_home/$themes_rel/current/wallpapers
wallpath=${wallpath//\\/\\\\}
wallpath=${wallpath//\"/\\\"}
while IFS= read -r line; do
    printf '%s\n' "${line//@WALLPAPERS@/"$wallpath"}"
done < .config/wpaperd/config.toml > "$stage/config/wpaperd/config.toml"
if (( no_tty )); then
    : > "$stage/config/macbook-rice/no-tty-autostart"
elif [[ ! -e $no_autostart ]]; then
    if [[ -e $HOME/$profile || -L $HOME/$profile ]]; then
        [[ -f $HOME/$profile && ! -L $HOME/$profile ]] || die "Expected a regular login profile: $HOME/$profile"
        cp -a -- "$HOME/$profile" "$stage/home/$profile"
    else
        printf '%s\n' '[[ -r "$HOME/.bashrc" ]] && . "$HOME/.bashrc"' > "$stage/home/$profile"
    fi
    if ! grep -Fxq -- "$profile_line" "$stage/home/$profile"; then
        chmod u+w -- "$stage/home/$profile"
        printf '\n%s\n' "$profile_line" >> "$stage/home/$profile"
    fi
    bash -n "$stage/home/$profile" || die "Invalid Bash syntax in $HOME/$profile"
fi

destination() {
    case "$1" in
        config/*) printf '%s/%s\n' "$config_home" "${1#config/}" ;;
        home/*) printf '%s/%s\n' "$HOME" "${1#home/}" ;;
    esac
}

safe_destination() {
    local parent=${1%/*}
    while [[ -n $parent ]]; do
        [[ ! -L $parent ]] || die "Destination directory is a symlink: $parent"
        [[ ! -e $parent || -d $parent ]] || die "Destination parent is not a directory: $parent"
        parent=${parent%/*}
    done
    [[ -L $1 || ! -e $1 || -f $1 ]] || die "Destination is not a regular file: $1"
    if [[ -e $1 || -L $1 ]]; then
        [[ $(stat -c %u -- "$1") == "$EUID" ]] || die "Destination is owned by another user: $1"
    fi
}
same_file() {
    if [[ -L $1 ]]; then
        [[ -L $2 && $(readlink -- "$1") == "$(readlink -- "$2")" ]]
    else
        [[ -f $2 && ! -L $2 ]] && cmp -s -- "$1" "$2" &&
            [[ ! -x $1 || -x $2 ]]
    fi
}

changes=()
while IFS= read -r -d '' source; do
    rel=${source#"$stage"/}
    dest=$(destination "$rel")
    safe_destination "$dest"
    if ! same_file "$source" "$dest"; then
        changes+=("$rel")
        if [[ -e $dest || -L $dest ]]; then
            printf 'Back up and replace %s\n' "$dest"
        else
            printf 'Create %s\n' "$dest"
        fi
    fi
done < <(find "$stage" \( -type f -o -type l \) -print0)
if (( dry_run )); then
    if command -v niri >/dev/null; then niri validate -c "$stage/config/niri/config.kdl"
    else printf 'niri validate will run after package installation.\n'
    fi
    exit 0
fi

# Explicit GTK provider prevents a portal selection prompt. Keep pacman's
# transaction confirmation and any conflict/replacement decisions interactive.
sudo pacman -Syu --needed "${packages[@]}"
pacman -Q "${packages[@]}" >/dev/null || die 'The package transaction left required packages missing.'
niri validate -c "$stage/config/niri/config.kdl"
if (( ${#changes[@]} == 0 )); then
    printf 'Configuration files are up to date.\n'
else
    # Keep the completed backup outside the deployment tree. Record additions too.
    safe_destination "$state_home/macbook-rice/backups/.probe"
    mkdir -p -- "$state_home/macbook-rice/backups"
    backup=$(mktemp -d "$state_home/macbook-rice/backups/$(date +%Y%m%d-%H%M%S).XXXXXXXX")
    for rel in "${changes[@]}"; do
        dest=$(destination "$rel")
        safe_destination "$dest"
        if [[ -e $dest || -L $dest ]]; then
            mkdir -p -- "$backup/before/${rel%/*}"
            cp -a -- "$dest" "$backup/before/$rel"
            [[ $(stat -c '%u:%g:%a' -- "$dest") == "$(stat -c '%u:%g:%a' -- "$backup/before/$rel")" ]] ||
                die "Could not preserve the owner, group or mode in the backup of $dest."
            printf 'REPLACE\t%s\t%s\n' "$rel" "$dest" >> "$backup/manifest.tsv"
        else
            printf 'CREATE\t%s\t%s\n' "$rel" "$dest" >> "$backup/manifest.tsv"
        fi
    done
    printf 'Backup and file manifest: %s\n' "$backup"
    for rel in "${changes[@]}"; do
        dest=$(destination "$rel")
        safe_destination "$dest"
        mkdir -p -- "${dest%/*}"
        pending=$(mktemp -- "${dest%/*}/.macbook-rice.XXXXXXXX")
        cp -aT --remove-destination -- "$stage/$rel" "$pending"
        if [[ ! -L $pending && -f $dest && ! -L $dest ]]; then
            chgrp --reference="$dest" -- "$pending"
            chmod --reference="$dest" -- "$pending"
            if [[ -x $stage/$rel && ! -x $pending ]]; then
                chmod u+x -- "$pending"
            fi
        fi
        mv -fT -- "$pending" "$dest"
        pending=
    done
fi
systemctl --user daemon-reload
printf 'Installed. Run ./check.sh, then log in on TTY1 or start niri-session manually.\n'

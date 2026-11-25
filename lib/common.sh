# Shared, read-only helpers for install.sh and check.sh.
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
base_packages=(bash coreutils util-linux systemd sudo networkmanager pipewire pipewire-pulse wireplumber)
desktop_components=(waybar wpaperd swayidle clipboard-text clipboard-image polkit)
other_units=(mako.service dunst.service fnott.service waybar.service
             swayidle.service wpaperd.service hyprpolkitagent.service plasma-polkit-agent.service
             polkit-gnome.service)
profile_line='[ -z "${BASH_VERSION:-}" ] || . "$HOME/.local/bin/rice-tty1" # macbook-niri-rice'
no_autostart=$config_home/macbook-rice/no-tty-autostart

is_arch() {
    [[ -r /etc/os-release ]] && ( . /etc/os-release; [[ $ID == arch ]] )
}

package_names() {
    awk 'NF && $1 !~ /^#/ {print $1}' "$@"
}

login_profile() {
    local name
    for name in .bash_profile .bash_login .profile; do
        if [[ -r $HOME/$name && -f $HOME/$name ]]; then
            printf '%s\n' "$name"
            return
        fi
    done
    printf '.bash_profile\n'
}

competing_units() {
    local unit
    for unit in "${other_units[@]}"; do
        if systemctl --user --quiet is-enabled "$unit" 2>/dev/null ||
           systemctl --user --quiet is-active "$unit" 2>/dev/null; then
            # A package can also ship a static, manually started unit.
            case "$(systemctl --user is-enabled "$unit" 2>/dev/null)" in
                static|indirect|generated|alias) systemctl --user --quiet is-active "$unit" || continue ;;
            esac
            printf '%s\n' "$unit"
        fi
    done
}

competing_autostarts() {
    local file directory entry try_exec
    local -A seen=()
    local -a system_autostart directories=( "$config_home/autostart" )
    IFS=: read -r -a system_autostart <<< "${XDG_CONFIG_DIRS:-/etc/xdg}"
    for directory in "${system_autostart[@]}"; do
        directories+=( "$directory/autostart" )
    done
    for directory in "${directories[@]}"; do
        for file in "$directory"/*.desktop; do
            [[ -f $file ]] || continue
            entry=${file##*/}
            [[ ! ${seen[$entry]+present} ]] || continue
            seen[$entry]=1
            grep -Eqi '^Hidden=true[[:space:]]*$' "$file" && continue
            try_exec=$(sed -n 's/^TryExec=//p' "$file" | head -n 1)
            if [[ -n $try_exec ]] && ! command -v -- "$try_exec" >/dev/null; then
                continue
            fi
            if grep -qi '^OnlyShowIn=' "$file" && ! grep -Eqi '^OnlyShowIn=([^;]*;)*niri([;[:space:]]|$)' "$file"; then
                continue
            fi
            grep -Eqi '^NotShowIn=([^;]*;)*niri([;[:space:]]|$)' "$file" && continue
            if grep -Eq '^Exec=.*\b(mako|dunst|fnott|swaync|waybar|swayidle|wpaperd|[^/[:space:]]*polkit[^/[:space:]]*agent[^/[:space:]]*)\b' "$file"; then
                printf '%s\n' "$file"
            fi
        done
    done
}

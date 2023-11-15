#!/bin/sh
set -e

real_xdg_runtime_dir=$(dirname "${XDG_RUNTIME_DIR}")
real_wayland=${real_xdg_runtime_dir}/${WAYLAND_DISPLAY:-wayland-0}

# On core systems may need to wait for real XDG_RUNTIME_DIR
#wait_for "${real_xdg_runtime_dir}"
#wait_for "${real_wayland}"

mkdir -p "$XDG_RUNTIME_DIR" -m 700
ln -sf "${real_wayland}" "$XDG_RUNTIME_DIR"
ln -sf "${real_wayland}.lock" "$XDG_RUNTIME_DIR"
unset DISPLAY

exec "$@"

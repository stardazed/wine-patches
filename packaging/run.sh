#!/bin/sh
# Compatibility-tool entry point for a vanilla Wine (new WoW64) build.
#
#   run.sh <verb> <command> [args...]        (also shipped as `proton`, for umu-launcher)
#
# Verb handling and environment setup follow upstream Proton's `proton` script
# (CachyOS "native" variant). Only the parts that make sense for vanilla Wine are
# ported: no steam.exe/umu.exe helpers, no protonfixes, no per-game hacks.
# Deliberately NOT set: WINEFSYNC/WINEESYNC (not in vanilla Wine; ntsync is automatic).

tool_dir="$(cd "$(dirname "$0")" && pwd)"
wine="$tool_dir/bin/wine"
wineserver="$tool_dir/bin/wineserver"
dxvk_dir="$tool_dir/lib/wine/dxvk"
vkd3d_dir="$tool_dir/lib/wine/vkd3d-proton"

truthy() { [ -n "$1" ] && [ "$1" != "0" ]; }

if [ -z "$STEAM_COMPAT_DATA_PATH" ]; then
    echo "Proton: No compat data path?" >&2
    exit 1
fi

# Native (non-container) tool: keep Steam's runtime libraries away from Wine.
if [ -n "${STEAM_RUNTIME+set}" ]; then
    unset STEAM_RUNTIME
    [ -n "${SYSTEM_LD_LIBRARY_PATH+set}" ] && export LD_LIBRARY_PATH="$SYSTEM_LD_LIBRARY_PATH"
    [ -n "${SYSTEM_PATH+set}" ] && export PATH="$SYSTEM_PATH"
fi

# Steam sets LC_ALL=C; Wine needs the real locale for path conversion.
if [ -n "$HOST_LC_ALL" ]; then
    export LC_ALL="$HOST_LC_ALL"
else
    unset LC_ALL
fi

# A WoW64-only build cannot create win32 prefixes.
unset WINEARCH

export PATH="$tool_dir/bin:$PATH"
export WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
mkdir -p "$WINEPREFIX"

setup_logging() {
    if truthy "$PROTON_LOG"; then
        export WINEDEBUG="${WINEDEBUG:-+timestamp,+pid,+tid,+seh,+unwind,+threadname,+debugstr,+loaddll,+mscoree}"
        [ "$PROTON_LOG" != "1" ] && export WINEDEBUG="$WINEDEBUG,$PROTON_LOG"
        export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-info}"
        export VKD3D_DEBUG="${VKD3D_DEBUG:-warn}"
        export VKD3D_SHADER_DEBUG="${VKD3D_SHADER_DEBUG:-fixme}"
        log_dir="${PROTON_LOG_DIR:-$HOME}"
        mkdir -p "$log_dir"
        exec >>"$log_dir/steam-${SteamGameId:-proton}.log" 2>&1
    else
        export WINEDEBUG="${WINEDEBUG:--all}"
        export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-none}"
        export VKD3D_DEBUG="${VKD3D_DEBUG:-none}"
        export VKD3D_SHADER_DEBUG="${VKD3D_SHADER_DEBUG:-none}"
    fi
}

install_dll() {   # src dst
    [ -f "$1" ] || return 0
    cmp -s "$1" "$2" 2>/dev/null || cp -f "$1" "$2"
}

# Stands in for upstream's prebuilt default_pfx: create the prefix on first run,
# then copy DXVK / vkd3d-proton into it and force them with native overrides.
prepare_prefix() {
    if [ ! -f "$WINEPREFIX/system.reg" ]; then
        # mono/gecko prompts would hang a headless first launch; Wine still offers them on demand later.
        WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}mscoree,mshtml=d" "$wine" wineboot -u
        "$wineserver" -w
    fi

    sys32="$WINEPREFIX/drive_c/windows/system32"    # 64-bit PE
    sysw="$WINEPREFIX/drive_c/windows/syswow64"     # 32-bit PE
    overrides=""

    for pair in "$dxvk_dir:d3d9 d3d10core d3d11 dxgi" "$vkd3d_dir:d3d12 d3d12core"; do
        src="${pair%%:*}"; names="${pair#*:}"
        for f in $names; do
            [ -f "$src/x86_64-windows/$f.dll" ] || continue
            if truthy "$PROTON_USE_WINED3D"; then
                overrides="$overrides;$f=b"          # ignore any DXVK copies already in the prefix
            else
                [ -d "$sys32" ] && install_dll "$src/x86_64-windows/$f.dll" "$sys32/$f.dll"
                [ -d "$sysw" ]  && install_dll "$src/i386-windows/$f.dll"   "$sysw/$f.dll"
                overrides="$overrides;$f=n"
            fi
        done
    done
    # ours first, so anything the user already exported can still override it
    [ -n "$overrides" ] && export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}${overrides#;}"
}

verb="$1"
[ $# -gt 0 ] && shift

case "$verb" in
    run)
        setup_logging
        prepare_prefix
        exec "$wine" "$@"
        ;;
    waitforexitandrun)
        setup_logging
        "$wineserver" -w
        prepare_prefix
        exec "$wine" "$@"
        ;;
    runinprefix)
        setup_logging
        exec "$wine" "$@"
        ;;
    destroyprefix)
        exit 0
        ;;
    getcompatpath)      # linux -> windows
        exec "$wine" winepath -w "$@"
        ;;
    getnativepath)      # windows -> linux
        exec "$wine" winepath -u "$@"
        ;;
    *)
        echo "Proton: Need a verb." >&2
        exit 1
        ;;
esac
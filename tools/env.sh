# tools/env.sh : your machine's settings for the tools, from the repo's .env (copy .env.example to .env and fill it
# in; .env is git-ignored). Sourced by the shell tools after they cd to the repo root:  . tools/env.sh
#
# - It reads this checkout's .env, else the main git tree's: one .env serves every worktree.
# - A variable already set in your environment wins over .env; an empty value in .env is ignored.
# - Lines are NAME=value (spaces in the value are fine, quotes around it are optional); # starts a comment line.
# - Then it fills in the shared defaults (AC8_PAKS from AC8_DIR; LLVM_BIN onto PATH) and gives sv_need for the tools.
# python -I tools/env.py --check shows every setting, where it came from and whether its path exists.

sv_env_load() {
    [ -f "$1" ] || return 1
    while IFS= read -r sv_line || [ -n "$sv_line" ]; do
        sv_line=$(printf '%s' "$sv_line" | tr -d '\r')
        case "$sv_line" in ''|'#'*|' #'*) continue ;; esac
        case "$sv_line" in *=*) ;; *) continue ;; esac
        sv_key=$(printf '%s' "${sv_line%%=*}" | tr -d ' \t')
        sv_val=$(printf '%s' "${sv_line#*=}" | sed 's/^[ 	]*//; s/[ 	]*$//')
        case "$sv_key" in ''|*[!A-Za-z0-9_]*) continue ;; esac
        case "$sv_val" in
            \"*\") sv_val=${sv_val#\"}; sv_val=${sv_val%\"} ;;
            \'*\') sv_val=${sv_val#\'}; sv_val=${sv_val%\'} ;;
        esac
        [ -n "$sv_val" ] || continue
        eval "sv_set=\${$sv_key+x}"
        [ -n "$sv_set" ] && continue                      # (already in the environment: that wins)
        export "$sv_key=$sv_val"
    done < "$1"
    return 0
}

sv_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
sv_main=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$sv_main" ] && sv_main=$(dirname "$sv_main")
SV_ENV_FILE=
if sv_env_load "$sv_root/.env"; then SV_ENV_FILE="$sv_root/.env"
elif [ -n "$sv_main" ] && sv_env_load "$sv_main/.env"; then SV_ENV_FILE="$sv_main/.env"
fi
export SV_ENV_FILE

# shared defaults
if [ -z "$AC8_PAKS" ] && [ -n "$AC8_DIR" ]; then AC8_PAKS="$AC8_DIR/Game/Content/Paks"; export AC8_PAKS; fi
if [ -z "$AC8_MODS" ] && [ -n "$AC8_DIR" ]; then AC8_MODS="$AC8_DIR/Game/Binaries/Win64/ue4ss/Mods"; export AC8_MODS; fi
if [ -n "$LLVM_BIN" ]; then PATH="$LLVM_BIN:$PATH"; export PATH; fi

# sv_need NAME "what it is": stops the tool with a clear message when a setting is missing
sv_need() {
    eval "sv_v=\${$1:-}"
    if [ -z "$sv_v" ]; then
        echo "$1 isn't set ($2). Copy .env.example to .env and set it (python -I tools/env.py --check shows every setting)." >&2
        exit 2
    fi
}

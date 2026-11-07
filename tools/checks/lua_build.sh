#!/bin/sh
# lua_build.sh : makes build/checks/lua.exe, a Lua 5.4 like UE4SS's, for the Lua checks that run code
# (coop_settings_test.sh, lua_load_test.sh): built with clang (tools/llvm) from lua.org's lua-5.4.6.tar.gz, checked
# against its published SHA-256. Does nothing when it's there already.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
OUT="$HERE/../../build/checks"
LUA="$OUT/lua.exe"
[ -x "$LUA" ] && exit 0
mkdir -p "$OUT"
CLANG="$HERE/../llvm/LLVM/bin/clang.exe"
[ -x "$CLANG" ] || CLANG=clang
rm -rf "$OUT/luasrc" && mkdir -p "$OUT/luasrc"
curl -sSfL -o "$OUT/luasrc/lua.tar.gz" https://www.lua.org/ftp/lua-5.4.6.tar.gz
echo "7d5ea1b9cb6aa0b59ca3dde1c6adcb57ef83a1ba8e5432c0ecd06bf439b3ad88  $OUT/luasrc/lua.tar.gz" | sha256sum -c - > /dev/null
(cd "$OUT/luasrc" && tar xzf lua.tar.gz)
(cd "$OUT/luasrc/lua-5.4.6/src" && "$CLANG" -O2 -w -o "$LUA" $(ls *.c | grep -v '^luac\.c$'))   # (relative: the path has spaces)
echo "built $LUA"

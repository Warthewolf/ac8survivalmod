#!/bin/sh
# lua_check_addons_test.sh : runs tools/checks/lua_check_addons_test.py (lua_check.py --addons, the example add-ons' check)
cd "$(dirname "$0")/../.."
python -X utf8 -I tools/checks/lua_check_addons_test.py

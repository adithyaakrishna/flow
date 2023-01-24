#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

log_file="$FLOW_TEMP_DIR/direct_dependent_files_cache.log"

start_flow src

printf "== Initial there should be 2 errors ==\n"
assert_errors "$FLOW" status --no-auto-start src

printf "\n== Delete unrelated.js and now there is 1 error ==\n"
# Unchanged during `ResolvedRequires`
assert_ok mv src/unrelated{.js,.js.ignored}
assert_ok "$FLOW" force-recheck src/unrelated.js

assert_errors "$FLOW" status --no-auto-start src
printf "\n"

printf "\n== Restore unrelated.js and back to 2 errors ==\n"
# Unchanged during `ResolvedRequires`
assert_ok mv src/unrelated{.js.ignored,.js}
assert_ok "$FLOW" force-recheck src/unrelated.js

assert_errors "$FLOW" status --no-auto-start src
printf "\n"

printf "\n== Delete src/node_modules/dependency.js changes an error ==\n"
# Changed during `ResolvedRequires`
assert_ok mv src/node_modules/dependency{.js,.js.ignored}
assert_ok "$FLOW" force-recheck src/node_modules/dependency.js

assert_errors "$FLOW" status --no-auto-start src
printf "\n"

printf "\n== Restore src/node_modules/dependency.js change it back ==\n"
# Changed during `ResolvedRequires`
assert_ok mv src/node_modules/dependency{.js.ignored,.js}
assert_ok "$FLOW" force-recheck src/node_modules/dependency.js

assert_errors "$FLOW" status --no-auto-start src
printf "\n"

printf "\n== Remove the import from dependent.js ==\n"
# Changed during `ResolvedRequires`
assert_ok mv src/dependent{.js,.js.ignored}
assert_ok echo "// @flow" > src/dependent.js
assert_ok "$FLOW" force-recheck src/dependent.js

assert_errors "$FLOW" status --no-auto-start src
printf "\n"

printf "\n== Add the import back to dependent.js ==\n"
# Changed during `ResolvedRequires`
assert_ok mv src/dependent{.js.ignored,.js}
assert_ok "$FLOW" force-recheck src/dependent.js

assert_errors "$FLOW" status --no-auto-start src
printf "\n"

printf "\n== Adding code that doesn't import has no effect on dep graph ==\n"
# Unchanged during `ResolvedRequires`
assert_ok echo "export var foo: boolean = 123" >> src/node_modules/dependency.js
assert_ok "$FLOW" force-recheck src/node_modules/dependency.js

assert_errors "$FLOW" status --no-auto-start src
printf "\n"

"$FLOW" stop src 1> /dev/null 2>&1

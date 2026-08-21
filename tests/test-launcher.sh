#!/bin/bash

set -euo pipefail

plugin_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fake_bin="$test_root/bin"
argv_file="$test_root/argv"
mkdir -p "$fake_bin"

cat >"$fake_bin/omarchy-shell" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$TEST_ARGV_FILE"
printf '%s\n' ok
EOF
chmod +x "$fake_bin/omarchy-shell"

TEST_ARGV_FILE="$argv_file" \
PATH="$fake_bin:/usr/bin:/bin" \
  "$plugin_dir/bin/omarchy-wallpaper" --no-theme-context "A warm desert at noon"

mapfile -d '' -t argv <"$argv_file"
[[ ${argv[0]} == shell ]]
[[ ${argv[1]} == summon ]]
[[ ${argv[2]} == jesperlugner.wallpaper-agent ]]
jq -e '
  .prompt == "A warm desert at noon"
  and .themeContextEnabled == false
' >/dev/null <<<"${argv[3]}"

echo "launcher integration test: ok"

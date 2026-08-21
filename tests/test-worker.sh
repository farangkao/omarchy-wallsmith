#!/bin/bash

set -euo pipefail

plugin_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fake_home="$test_root/home"
fake_bin="$test_root/bin"
test_log="$test_root/commands.log"
agent_task_file="$test_root/agent-task.txt"
fixture="$test_root/fixture.png"
mkdir -p "$fake_home/.local/state/omarchy/current/theme" "$fake_bin"
printf '%s\n' 'retro-82' >"$fake_home/.local/state/omarchy/current/theme.name"
cat >"$fake_home/.local/state/omarchy/current/theme/colors.toml" <<'EOF'
mode = "dark"
accent = "#82FB9C"
background = "#0B0C16"
EOF
magick -size 1200x800 gradient:'#1a2238-#9daaf2' "$fixture"

cat >"$fake_bin/hyprctl" <<'EOF'
#!/bin/bash
printf '%s\n' '[
  {"name":"DP-2","width":2560,"height":1440,"transform":0,"focused":true,"disabled":false},
  {"name":"DP-3","width":1920,"height":1080,"transform":0,"focused":false,"disabled":false}
]'
EOF

cat >"$fake_bin/codex" <<'EOF'
#!/bin/bash
printf 'codex-arg=%s\n' "$@" >>"$TEST_LOG"
printf '%s' "${!#}" >"$TEST_AGENT_TASK_FILE"
printf 'worker-status %s\n' "$(cat "$XDG_STATE_HOME/omarchy-wallpaper-agent/status")" >>"$TEST_LOG"
while (( $# > 0 )); do
  if [[ $1 == --cd || $1 == -C ]]; then
    workdir=$2
    break
  fi
  shift
done
cp "$TEST_FIXTURE" "$workdir/generated.png"
printf '%s\n' "$workdir/generated.png"
EOF

cat >"$fake_bin/omarchy" <<'EOF'
#!/bin/bash
if [[ $* == "theme current" ]]; then
  printf '%s\n' 'Retro 82'
  exit 0
fi
printf 'omarchy %s\n' "$*" >>"$TEST_LOG"
EOF

cat >"$fake_bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf 'notify %s\n' "$*" >>"$TEST_LOG"
EOF

chmod +x "$fake_bin/hyprctl" "$fake_bin/codex" "$fake_bin/omarchy" "$fake_bin/omarchy-notification-send"

HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_FIXTURE="$fixture" \
TEST_LOG="$test_log" \
TEST_AGENT_TASK_FILE="$agent_task_file" \
  "$plugin_dir/bin/generate-wallpaper" --prompt "A quiet mountain lake"

grep -F 'Theme matching is enabled.' "$agent_task_file" >/dev/null
grep -F 'Current Omarchy theme (JSON string): "Retro 82"' "$agent_task_file" >/dev/null
grep -F 'accent = \"#82FB9C\"' "$agent_task_file" >/dev/null

mapfile -t wallpapers < <(find "$fake_home/.config/omarchy/backgrounds/retro-82" -maxdepth 1 -type f -name 'ai-*.jpg')
[[ ${#wallpapers[@]} -eq 1 ]] || { echo "Expected one generated wallpaper" >&2; exit 1; }
[[ $(magick identify -format '%m' "${wallpapers[0]}") == "JPEG" ]] || {
  echo "Wallpaper is not a JPEG" >&2
  exit 1
}
[[ $(magick identify -format '%wx%h' "${wallpapers[0]}") == "2560x1440" ]] || {
  echo "Wallpaper does not match the largest active monitor" >&2
  exit 1
}
grep -F "omarchy theme bg set ${wallpapers[0]}" "$test_log" >/dev/null
grep -F "Wallpaper ready" "$test_log" >/dev/null
grep -F "worker-status working" "$test_log" >/dev/null
grep -Fx "codex-arg=notify=[]" "$test_log" >/dev/null
grep -Fx "idle" "$fake_home/.local/state/omarchy-wallpaper-agent/status" >/dev/null

HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_FIXTURE="$fixture" \
TEST_LOG="$test_log" \
TEST_AGENT_TASK_FILE="$agent_task_file" \
  "$plugin_dir/bin/generate-wallpaper" --no-theme-context --prompt "A quiet mountain lake"

grep -F 'Theme matching is disabled.' "$agent_task_file" >/dev/null
if grep -Fq 'Current Omarchy theme' "$agent_task_file"; then
  echo "Disabled theme context leaked into the agent task" >&2
  exit 1
fi
grep -Fx "idle" "$fake_home/.local/state/omarchy-wallpaper-agent/status" >/dev/null

echo "worker integration test: ok"

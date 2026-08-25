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
refine_fixture="$test_root/refine-fixture.png"
mkdir -p "$fake_home/.local/state/omarchy/current/theme" "$fake_bin"
printf '%s\n' 'retro-82' >"$fake_home/.local/state/omarchy/current/theme.name"
cat >"$fake_home/.local/state/omarchy/current/theme/colors.toml" <<'EOF'
mode = "dark"
accent = "#82FB9C"
background = "#0B0C16"
EOF
magick -size 1200x800 gradient:'#1a2238-#9daaf2' "$fixture"
magick -size 1200x800 gradient:'#641220-#ffb3c1' "$refine_fixture"

cat >"$fake_bin/hyprctl" <<'EOF'
#!/bin/bash
printf '%s\n' '[
  {"name":"DP-2","width":2560,"height":1440,"transform":0,"focused":true,"disabled":false},
  {"name":"DP-3","width":1920,"height":1080,"transform":0,"focused":false,"disabled":false}
]'
EOF

cat >"$fake_bin/codex" <<'EOF'
#!/bin/bash
if [[ -n ${TEST_CODEX_GATE:-} ]]; then
  for _ in $(seq 1 200); do
    [[ -e $TEST_CODEX_GATE ]] && break
    sleep 0.05
  done
fi
printf 'codex-arg=%s\n' "$@" >>"$TEST_LOG"
task="${!#}"
printf '%s' "$task" >"$TEST_AGENT_TASK_FILE"
if [[ $task == *"Design an Omarchy desktop theme palette"* ]]; then
  args=("$@")
  out=""
  for ((i = 0; i < ${#args[@]}; i++)); do
    [[ ${args[i]} == --output-last-message ]] && out=${args[i + 1]}
  done
  cat >"$out" <<'JSON'
mise ~/.config/mise/config.toml tools: codex@0.149.1
{"name": "Test Lagoon", "mode": "dark", "colors": {"accent": "#89b4fa", "selection": "#45475a", "muted": "#585b70", "background": "#1e1e2e", "dark_background": "#161622", "darker_background": "#101019", "lighter_background": "#313244", "foreground": "#cdd6f4", "dark_foreground": "#6c7086", "light_foreground": "#bac2de", "bright_foreground": "#cdd6f4", "red": "#f38ba8", "yellow": "#f9e2af", "orange": "#f6b6ab", "green": "#a6e3a1", "cyan": "#94e2d5", "blue": "#89b4fa", "magenta": "#f5c2e7", "brown": "#7b5b55", "bright_red": "#f38ba8", "bright_yellow": "#f9e2af", "bright_green": "#a6e3a1", "bright_cyan": "#94e2d5", "bright_blue": "#89b4fa", "bright_magenta": "#f5c2e7"}}

Hope this palette suits the wallpaper.
JSON
  printf '%s\n' \
    'mise ~/.config/mise/config.toml tools: codex@0.149.1' \
    '{"type":"thread.started","thread_id":"theme-thread"}'
  exit 0
fi
printf 'worker-status %s\n' "$(cat "$XDG_STATE_HOME/omarchy-wallsmith/status")" >>"$TEST_LOG"
jq -r '.[0] | "activity \(.mode) \(.recordId)"' \
  "$XDG_STATE_HOME/omarchy-wallsmith/activity.json" >>"$TEST_LOG"
jq -r '"activity-count \(length)"' \
  "$XDG_STATE_HOME/omarchy-wallsmith/activity.json" >>"$TEST_LOG"
output_path=$(sed -n 's/^After .*copy it to this exact path: //p' <<<"$task" | sed -n '1p')
fixture=$TEST_FIXTURE
if [[ ${2:-} == resume ]]; then
  fixture=$TEST_REFINE_FIXTURE
fi
while (( $# > 0 )); do
  if [[ $1 == --output-last-message || $1 == -o ]]; then
    printf '%s\n' "$output_path" >"$2"
  fi
  shift
done
mkdir -p "$(dirname "$output_path")"
cp "$fixture" "$output_path"
# Real setups run codex through a mise shim, which can print a banner to
# stdout before the JSONL events start; the scripts must tolerate that.
printf '%s\n' \
  'mise ~/.config/mise/config.toml tools: codex@0.149.1' \
  '{"type":"thread.started","thread_id":"0199a213-81c0-7800-8aa1-bbab2a035a53"}'
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

cat >"$fake_bin/omarchy-shell" <<'EOF'
#!/bin/bash
printf 'omarchy-shell %s\n' "$*" >>"$TEST_LOG"
EOF

chmod +x "$fake_bin/hyprctl" "$fake_bin/codex" "$fake_bin/omarchy" "$fake_bin/omarchy-notification-send" "$fake_bin/omarchy-shell"

HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_FIXTURE="$fixture" \
TEST_REFINE_FIXTURE="$refine_fixture" \
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
grep -Fx "activity generate " "$test_log" >/dev/null
grep -Fx "codex-arg=notify=[]" "$test_log" >/dev/null
grep -Fx "idle" "$fake_home/.local/state/omarchy-wallsmith/status" >/dev/null
[[ ! -e "$fake_home/.local/state/omarchy-wallsmith/activity.json" ]] || {
  echo "Generation activity was not cleared" >&2
  exit 1
}

mapfile -t records < <(find "$fake_home/.local/state/omarchy-wallsmith/records" -maxdepth 1 -type f -name '*.json')
[[ ${#records[@]} -eq 1 ]] || { echo "Expected one history record" >&2; exit 1; }
record_id=$(jq -r '.recordId' "${records[0]}")
jq -e '
  .prompt == "A quiet mountain lake"
  and .sessionId == "0199a213-81c0-7800-8aa1-bbab2a035a53"
  and (.turns | length) == 1
' "${records[0]}" >/dev/null

before_refine=$(sha256sum "${wallpapers[0]}" | cut -d' ' -f1)
HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_FIXTURE="$fixture" \
TEST_REFINE_FIXTURE="$refine_fixture" \
TEST_LOG="$test_log" \
TEST_AGENT_TASK_FILE="$agent_task_file" \
  "$plugin_dir/bin/generate-wallpaper" --refine "$record_id" --prompt "Make the sunrise warmer"

mapfile -t wallpapers_after_refine < <(find "$fake_home/.config/omarchy/backgrounds/retro-82" -maxdepth 1 -type f -name 'ai-*.jpg')
[[ ${#wallpapers_after_refine[@]} -eq 1 ]] || { echo "Refinement created another wallpaper" >&2; exit 1; }
after_refine=$(sha256sum "${wallpapers_after_refine[0]}" | cut -d' ' -f1)
[[ $before_refine != "$after_refine" ]] || { echo "Refinement did not replace the wallpaper" >&2; exit 1; }
grep -F 'Use $imagegen exactly once to edit the attached desktop wallpaper.' "$agent_task_file" >/dev/null
grep -F 'Requested change' "$agent_task_file" >/dev/null
grep -Fx 'codex-arg=resume' "$test_log" >/dev/null
grep -Fx "codex-arg=--image=${wallpapers[0]}" "$test_log" >/dev/null
grep -Fx "activity refine $record_id" "$test_log" >/dev/null
jq -e '
  .lastInstruction == "Make the sunrise warmer"
  and (.turns | length) == 2
  and .turns[1].kind == "refine"
' "${records[0]}" >/dev/null
session_workspace=$(jq -r '.workspace' "${records[0]}")
[[ ! -e "$session_workspace/generated.png" ]] || { echo "Temporary source image was not cleaned up" >&2; exit 1; }
mapfile -t refresh_links < <(find "$fake_home/.local/state/omarchy-wallsmith/background-refresh" -maxdepth 1 -type l)
[[ ${#refresh_links[@]} -eq 1 ]] || { echo "Expected one live background refresh link" >&2; exit 1; }
[[ $(readlink "${refresh_links[0]}") == "${wallpapers[0]}" ]] || { echo "Refresh link points at the wrong wallpaper" >&2; exit 1; }
grep -F "omarchy-shell -q background set ${refresh_links[0]}" "$test_log" >/dev/null
[[ ! -e "$fake_home/.local/state/omarchy-wallsmith/activity.json" ]] || {
  echo "Refinement activity was not cleared" >&2
  exit 1
}

# The refine must have snapshotted the outgoing pixels, and restore-version
# must bring them back while snapshotting the replaced state.
versions_dir="$fake_home/.local/state/omarchy-wallsmith/versions/$record_id"
mapfile -t snapshots < <(find "$versions_dir" -maxdepth 1 -type f -name 'v*.jpg' | sort)
[[ ${#snapshots[@]} -eq 1 ]] || { echo "Expected one version snapshot after refine" >&2; exit 1; }
[[ $(sha256sum "${snapshots[0]}" | cut -d' ' -f1) == "$before_refine" ]] || {
  echo "Version snapshot does not match the pre-refine wallpaper" >&2
  exit 1
}

HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_LOG="$test_log" \
  "$plugin_dir/bin/restore-version" "$record_id" "$(basename "${snapshots[0]}")"

after_restore=$(sha256sum "${wallpapers[0]}" | cut -d' ' -f1)
[[ $after_restore == "$before_refine" ]] || { echo "Restore did not bring back the earlier version" >&2; exit 1; }
jq -e '(.turns | length) == 3 and .turns[2].kind == "restore"' "${records[0]}" >/dev/null
snapshot_count=$(find "$versions_dir" -maxdepth 1 -type f -name 'v*.jpg' | wc -l)
[[ $snapshot_count -eq 2 ]] || { echo "Restore did not snapshot the replaced pixels" >&2; exit 1; }
grep -F "notify --image ${wallpapers[0]} Wallpaper restored" "$test_log" >/dev/null
HOME="$fake_home" XDG_STATE_HOME="$fake_home/.local/state" "$plugin_dir/bin/wallpaper-history" |
  jq -e --arg id "$record_id" '.[] | select(.recordId == $id) | (.versions | length) == 2' >/dev/null

HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_FIXTURE="$fixture" \
TEST_REFINE_FIXTURE="$refine_fixture" \
TEST_LOG="$test_log" \
TEST_AGENT_TASK_FILE="$agent_task_file" \
  "$plugin_dir/bin/generate-wallpaper" --no-theme-context --prompt "A quiet mountain lake"

grep -F 'Theme matching is disabled.' "$agent_task_file" >/dev/null
if grep -Fq 'Current Omarchy theme' "$agent_task_file"; then
  echo "Disabled theme context leaked into the agent task" >&2
  exit 1
fi
grep -Fx "idle" "$fake_home/.local/state/omarchy-wallsmith/status" >/dev/null

# Theme creation: candidates from the image, palette from the (fake) agent,
# theme directory written, trial-applied, then discarded cleanly.
HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_LOG="$test_log" \
TEST_AGENT_TASK_FILE="$agent_task_file" \
  "$plugin_dir/bin/create-theme" "$record_id"

theme_dir="$fake_home/.config/omarchy/themes/test-lagoon"
[[ -d $theme_dir ]] || { echo "Theme directory was not created" >&2; exit 1; }
grep -q 'mode = "dark"' "$theme_dir/colors.toml"
grep -q 'accent = "#89b4fa"' "$theme_dir/colors.toml"
grep -q 'bright_magenta = "#f5c2e7"' "$theme_dir/colors.toml"
[[ -f "$theme_dir/backgrounds/1-test-lagoon.jpg" ]] || { echo "Theme wallpaper missing" >&2; exit 1; }
[[ -f "$theme_dir/preview.png" ]] || { echo "Theme preview missing" >&2; exit 1; }
grep -F 'Dominant colors extracted from the image' "$agent_task_file" >/dev/null
# --image must use the equals form: codex's space form swallows the task
# argument and then waits for a prompt on stdin.
grep -Fx "codex-arg=--image=${wallpapers[0]}" "$test_log" >/dev/null
grep -F "omarchy theme set test-lagoon" "$test_log" >/dev/null
grep -F "discard-theme test-lagoon retro-82" "$test_log" >/dev/null
jq -e '.generatedThemes == ["test-lagoon"]' "${records[0]}" >/dev/null

HOME="$fake_home" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_LOG="$test_log" \
  "$plugin_dir/bin/discard-theme" test-lagoon retro-82
[[ ! -d $theme_dir ]] || { echo "Discarded theme directory still exists" >&2; exit 1; }
grep -F "omarchy theme set retro-82" "$test_log" >/dev/null

# Refining a record that is already being edited must be refused by the
# per-record lock.
resume_calls_before=$(grep -c '^codex-arg=resume$' "$test_log")
exec 8>"$fake_home/.local/state/omarchy-wallsmith/records/$record_id.lock"
flock -n 8
HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_FIXTURE="$fixture" \
TEST_REFINE_FIXTURE="$refine_fixture" \
TEST_LOG="$test_log" \
TEST_AGENT_TASK_FILE="$agent_task_file" \
  "$plugin_dir/bin/generate-wallpaper" --refine "$record_id" --prompt "Must not start" 8>&-
flock -u 8
exec 8>&-
resume_calls_after=$(grep -c '^codex-arg=resume$' "$test_log")
[[ $resume_calls_before -eq $resume_calls_after ]] || {
  echo "A second edit started while the record lock was held" >&2
  exit 1
}
grep -F "Wallpaper edit already running" "$test_log" >/dev/null

# Two new generations must run in parallel: gate the fake codex, start both,
# and require both to be registered as running at the same time.
activity_file="$fake_home/.local/state/omarchy-wallsmith/activity.json"
status_file="$fake_home/.local/state/omarchy-wallsmith/status"
gate="$test_root/codex-gate"
wallpapers_before_parallel=$(find "$fake_home/.config/omarchy/backgrounds" -type f -name 'ai-*.jpg' | wc -l)

HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_FIXTURE="$fixture" \
TEST_REFINE_FIXTURE="$refine_fixture" \
TEST_LOG="$test_log" \
TEST_AGENT_TASK_FILE="$agent_task_file" \
TEST_CODEX_GATE="$gate" \
  "$plugin_dir/bin/generate-wallpaper" --prompt "Parallel one" &
parallel_pid_one=$!

HOME="$fake_home" \
XDG_STATE_HOME="$fake_home/.local/state" \
PATH="$fake_bin:/usr/bin:/bin" \
TEST_FIXTURE="$fixture" \
TEST_REFINE_FIXTURE="$refine_fixture" \
TEST_LOG="$test_log" \
TEST_AGENT_TASK_FILE="$agent_task_file" \
TEST_CODEX_GATE="$gate" \
  "$plugin_dir/bin/generate-wallpaper" --prompt "Parallel two" &
parallel_pid_two=$!

running_jobs=0
for _ in $(seq 1 200); do
  running_jobs=$(jq 'length' "$activity_file" 2>/dev/null || echo 0)
  [[ $running_jobs == 2 ]] && break
  sleep 0.05
done
[[ $running_jobs == 2 ]] || {
  touch "$gate"
  wait "$parallel_pid_one" "$parallel_pid_two" || true
  echo "Expected two jobs registered in parallel, saw $running_jobs" >&2
  exit 1
}
grep -Fx "working" "$status_file" >/dev/null

touch "$gate"
wait "$parallel_pid_one"
wait "$parallel_pid_two"

grep -Fx "activity-count 2" "$test_log" >/dev/null
wallpapers_after_parallel=$(find "$fake_home/.config/omarchy/backgrounds" -type f -name 'ai-*.jpg' | wc -l)
[[ $((wallpapers_before_parallel + 2)) -eq $wallpapers_after_parallel ]] || {
  echo "Parallel generations did not produce two wallpapers" >&2
  exit 1
}
[[ ! -e $activity_file ]] || { echo "Parallel activity was not cleared" >&2; exit 1; }
grep -Fx "idle" "$status_file" >/dev/null

echo "worker integration test: ok"

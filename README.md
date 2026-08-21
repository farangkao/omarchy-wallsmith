# Wallpaper Agent for Omarchy

Open a native Omarchy prompt, describe a wallpaper, and let Codex generate and apply it in the background using the current theme's palette.

This repository is currently a local preview. It has not been published and its final name is still open.

## Use

Bind the bundled launcher to a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind(
  "SUPER + CTRL + G",
  "Generate wallpaper",
  "$HOME/.config/omarchy/plugins/jesperlugner.wallpaper-agent/bin/omarchy-wallpaper"
)
```

Then reload Hyprland with `hyprctl reload`.

`Super+Ctrl+G` opens the wallpaper prompt. Use `Ctrl+Tab` or the header control to move between a new prompt and generated wallpaper history.

You can optionally prefill the prompt:

```bash
~/.config/omarchy/plugins/jesperlugner.wallpaper-agent/bin/omarchy-wallpaper \
  "A quiet Japanese garden in the rain"
```

Theme matching is enabled by default. To ignore the current theme for one generation:

```bash
~/.config/omarchy/plugins/jesperlugner.wallpaper-agent/bin/omarchy-wallpaper \
  --no-theme-context "A warm desert at noon"
```

The current backend is Codex.

The prompt wraps onto multiple lines and grows with its contents. Press `Alt+Return` to insert a newline, `Return` to generate with the current theme, `Shift+Return` to generate without theme context, or `Esc` to close it.

In history, use the arrow keys to choose a wallpaper. Press `Return` to describe an edit in its existing Codex thread, or `Shift+Return` to copy its original prompt into a new-generation prompt. Refinements replace the selected wallpaper file instead of creating another image. Each original generation therefore occupies one wallpaper slot no matter how many times it is refined.

Every original generation starts a new Codex thread; refinements resume the selected thread. Only one generation or refinement can run at a time. The active history row is marked `Editing…`, and both new prompts and other edits stay locked until that job finishes.

While a generation is running, a small animated `Generating` indicator appears in the top bar. It disappears completely when the worker finishes or stops.

## How it works

1. The plugin reads every active display from `hyprctl monitors -j`.
2. It reads the active theme name and resolved `colors.toml` palette.
3. It asks `codex exec` to refine the idea with that palette and invoke `$imagegen` once.
4. It keeps the composition crop-safe for all display aspect ratios and normalizes the result to the largest active monitor.
5. It stores the JPEG in `~/.config/omarchy/backgrounds/<current-theme>/`.
6. It applies the image with `omarchy theme bg set` and sends a notification.

For refinements, the plugin resumes the exact saved Codex session and attaches the current wallpaper as the editing reference. Conversation context preserves the intent; the attachment preserves the actual pixels. The selected JPEG is then replaced atomically, and the live shell receives a cache-busted path so the updated pixels appear immediately. Prompts, session metadata, and per-turn log paths are kept under `~/.local/state/omarchy-wallpaper-agent/records/`, while detailed job logs remain under `jobs/`.

Omarchy currently uses one shared background and center-crops it independently on each monitor. Mixed portrait and landscape displays therefore share a crop-safe master rather than receiving separate images.

No API key is needed for the default backend. Codex reuses the saved CLI login, and image generation counts against the Codex usage limits. The background invocation disables the user's normal Codex completion hook so only the plugin's progress and completion notifications appear. Job logs live under `~/.local/state/omarchy-wallpaper-agent/jobs/`.

## Requirements

- Omarchy 4 with `omarchy-shell`
- Codex CLI, signed in
- `hyprctl`, `jq`, ImageMagick, and `flock`

## Verify

```bash
omarchy plugin validate ~/.config/omarchy/plugins/jesperlugner.wallpaper-agent
~/.config/omarchy/plugins/jesperlugner.wallpaper-agent/tests/test-launcher.sh
~/.config/omarchy/plugins/jesperlugner.wallpaper-agent/tests/test-worker.sh
```

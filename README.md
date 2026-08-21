# Wallsmith

Generate, revisit, and refine AI wallpapers for [Omarchy](https://omarchy.org) — theme-aware, crop-safe, and keyboard-first. Describe a wallpaper in a native Omarchy prompt and Wallsmith generates and applies it in the background, matched to your current theme's palette.

![The Wallsmith card: prompt on top, generated wallpaper history below](assets/wallsmith-card.jpg)

Select a wallpaper to refine it in its original thread — with your previous edit instructions in view:

![Refining a wallpaper: the strip shows its thumbnail, original prompt, and past edits](assets/wallsmith-refine.jpg)

## Requirements

- Omarchy 4 with `omarchy-shell`
- [Codex CLI](https://github.com/openai/codex), signed in (no API key needed — image generation counts against your Codex usage limits)
- `hyprctl`, `jq`, ImageMagick, and `flock` (all present on a stock Omarchy install)

## Install

```bash
omarchy plugin add https://github.com/jlugner/omarchy-wallsmith.git --enable
```

Then bind the launcher to a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind(
  "SUPER + CTRL + G",
  "Generate wallpaper",
  "$HOME/.config/omarchy/plugins/jesperlugner.wallsmith/bin/wallsmith"
)
```

Reload Hyprland with `hyprctl reload`.

## Use

`Super+Ctrl+G` opens the Wallsmith card: a multiline prompt on top, and your generated wallpaper history directly below it.

**Writing a prompt:** `Return` generates, `Alt+Return` inserts a newline, `Esc` closes. Theme matching is on by default and controlled by the `Match theme` toggle in the footer — click it or press `Ctrl+T`; `Shift+Return` submits once without theme context regardless of the toggle.

**History:** move into the list with `Tab` (or `Down` from the last line of the prompt) and back with `Tab` or `Up` from the top row. On a wallpaper:

- `Return` (or click) selects it for **refinement**: a strip above the history shows its thumbnail, original prompt, and previous edit instructions, and your next `Return` sends the edit to that wallpaper's existing thread. `Esc` backs out.
- `Alt+Return` **applies** it as your background again.
- `Shift+Return` **reuses** its original prompt for a fresh generation.
- `Delete` **deletes** the wallpaper and its history (with confirmation) — or cancels the job if the row is still generating or being edited.

Refinements replace the selected wallpaper file instead of creating another image, so each original generation occupies one wallpaper slot no matter how many times it is refined. Rows show their edit count, and deleting the wallpaper you're currently using switches to the next background automatically.

**Parallel jobs:** up to four jobs run at once. New generations run side by side and show as live rows at the top of the history; reusing a prompt starts a fresh thread immediately even while the source is still generating. Each wallpaper accepts one edit at a time (an edit resumes that wallpaper's session and replaces its file). Whichever job finishes last sets the visible background. While jobs run, an animated `Generating` indicator appears in the top bar (`Generating ×N` for several).

**CLI:** the launcher accepts a prompt to prefill, and flags:

```bash
bin/wallsmith "A quiet Japanese garden in the rain"
bin/wallsmith --no-theme-context "A warm desert at noon"
bin/wallsmith --history
```

## How it works

1. The plugin reads every active display from `hyprctl monitors -j`.
2. It reads the active theme name and resolved `colors.toml` palette.
3. It asks `codex exec` to refine the idea with that palette and invoke `$imagegen` once.
4. It keeps the composition crop-safe for all display aspect ratios and normalizes the result to the largest active monitor.
5. It stores the JPEG in `~/.config/omarchy/backgrounds/<current-theme>/`.
6. It applies the image with `omarchy theme bg set` and sends a notification.

For refinements, the plugin resumes the exact saved Codex session and attaches the current wallpaper as the editing reference. Conversation context preserves the intent; the attachment preserves the actual pixels. The selected JPEG is then replaced atomically, and the live shell receives a cache-busted path so the updated pixels appear immediately.

Omarchy currently uses one shared background and center-crops it independently on each monitor. Mixed portrait and landscape displays therefore share a crop-safe master rather than receiving separate images.

State lives under `~/.local/state/omarchy-wallsmith/`: prompts, session metadata, and per-turn log paths in `records/`, detailed job logs in `jobs/` (pruned after 30 days when no record references them), and the live job list in `activity.json`. The background invocation disables the user's normal Codex completion hook so only the plugin's progress and completion notifications appear.

## Verify

```bash
omarchy plugin validate ~/.config/omarchy/plugins/jesperlugner.wallsmith
~/.config/omarchy/plugins/jesperlugner.wallsmith/tests/test-launcher.sh
~/.config/omarchy/plugins/jesperlugner.wallsmith/tests/test-worker.sh
```

The same checks run in CI on every push.

## License

[MIT](LICENSE)

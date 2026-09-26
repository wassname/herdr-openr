# herdr-openr

Jump to what your agent just did. One keypress → fuzzy picker over the
files and URLs the current pane mentioned. URLs open in your browser,
files in your editor at the right line — or reveal them in Finder /
your file manager, or copy the path.

![openr demo](assets/demo.gif)

> Fork of [wraithyy/herdr-openr](https://github.com/wraithyy/herdr-openr).
> Changes: reads any agent's transcript through [asf](https://github.com/wassname/asf)
> (pi, claude, codex, opencode, ...) instead of Claude only; `ctrl-f` reveals the
> file in yazi; no startup hook that edits your `config.toml`.

`openr.pick` reads the pane's **agent session transcript** when herdr knows the
session, and the **visible viewport** otherwise. `openr.pick-visible` always
reads the viewport, `openr.pick-transcript` only the transcript.

The transcript holds what the agent's TUI hides: pi and other TUIs print a
markdown link `[plot](file:///abs/plot.png)` as a clickable label only, so a
screen scrape sees `plot`. The transcript has the path. It also has every file
path from the agent's tool calls. Paths that don't exist are dropped.

## Quick start

```bash
herdr plugin install wassname/herdr-openr
cargo install --git https://github.com/wassname/asf   # for transcript mode
```

Bind keys in `~/.config/herdr/config.toml`. With `herdr --remote`, keys come
from the client's config, not the server's.

```toml
[[keys.command]]
key = "prefix+f"
type = "plugin_action"
command = "openr.pick"
description = "open file/URL: agent transcript, else visible pane"

[[keys.command]]
key = "prefix+shift+f"
type = "plugin_action"
command = "openr.pick-visible"
description = "open file/URL from visible pane"
```

Then `herdr server reload-config`.

Needs `zsh`, `fzf`, `jq`; `asf` for transcripts; `yazi` for `ctrl-f`
(`bat` optional, nicer preview). macOS + Linux.

## Keys

| key | action |
|---|---|
| `enter` | URL → browser · file → editor at line |
| `ctrl-f` | file → `reveal_cmd` (yazi, cursor on the file) · URL → browser |
| `ctrl-y` | copy path/URL |
| `esc` | cancel |

## Configure

Optional — `~/.config/herdr/plugins/config/openr/openr.conf`:

```sh
file_cmd='nvim +{line} {file}'   # bare {file}/{url}: values are pre-escaped
reveal_cmd='yazi {file}'         # ctrl-f; runs like file_cmd
file_open_in="tab"               # "tab" herdr tab | "detached" GUI editors (file_cmd and reveal_cmd)
url_cmd=""                       # empty = open / xdg-open
preview="1"
scan_source="visible"            # non-agent panes; recent* scrolls the pane
scan_lines=400
transcript_messages=200          # agent panes: last N assistant messages

# VS Code:  file_open_in="detached"; file_cmd='code --goto {file}:{line}'
# Zed:      file_open_in="detached"; file_cmd='zed {file}:{line}'
# Helix:    file_open_in="tab";      file_cmd='hx {file}:{line}'
# IntelliJ: file_open_in="detached"; file_cmd='idea --line {line} {file}'
#   (needs the `idea` shell launcher; macOS without it:
#    file_cmd='open -na "IntelliJ IDEA" --args --line {line} {file}')
```

Popup size: `OPENR_WIDTH` / `OPENR_HEIGHT` (default `75%` / `60%`).

## Troubleshooting

- Key does nothing → check `herdr server reload-config` errors, `fzf`/`jq`
  on PATH; failures show an "openr" toast.
- Nothing opens over another popup/overlay — herdr allows one at a time.
- Paths with spaces are not detected (known limit).
- `~/.config/herdr/plugins/config/openr/last.log` = last dispatched
  command, `last-source.log` = last scanned pane + source.

## Prior art

Inspired by [termscope](https://github.com/iurysza/termscope), which pioneered
the "open what's on screen" jump list for herdr. openr grew out of wanting a
different shape of the same idea: Claude transcript as the primary source
instead of the viewport, a popup picker, and a configurable editor command
instead of a fixed nvim split.

## License

[MIT](LICENSE)

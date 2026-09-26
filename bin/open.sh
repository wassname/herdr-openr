#!/usr/bin/env bash
# Action `openr.pick`: runs on the herdr server (no TTY). Reads the origin
# pane, extracts candidate URLs/paths, filters paths to existing files, and
# hands the finished list to the picker popup via a temp file — the popup
# only runs fzf, so it opens instantly.
set -uo pipefail

# mode: auto (default) = transcript for agent panes, pane read otherwise;
# visible = always read the pane viewport; transcript = agent transcript only
mode="${1:-auto}"

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

fail() {
  "$herdr_bin" notification show "openr" --body "$1" 2>/dev/null
  exit 1
}
command -v jq >/dev/null 2>&1 || fail "jq is not installed"

pane_id=""; cwd=""
if [ -n "$ctx" ]; then
  pane_id="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty')"
  cwd="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty')"
fi
[ -n "$pane_id" ] || fail "could not resolve the focused pane"
[ -d "$cwd" ] || cwd="$HOME"

# user config (scan_source/scan_lines here; file_cmd/url_cmd read by the picker)
# visible by default: history sources (recent/recent-unwrapped) visibly
# scroll the origin pane while the server reads it
scan_source="visible"
scan_lines=400
transcript_messages=200
conf="$HOME/.config/herdr/plugins/config/openr/openr.conf"
# shellcheck disable=SC1090
[ -r "$conf" ] && . "$conf"

# Agent panes: read the session transcript instead of scraping the screen —
# full history, raw markdown (link URLs that the agent's TUI hides), and
# tool-call paths. asf (github.com/wassname/asf) reads the transcript of any
# agent herdr knows the session of: pi, claude, codex, opencode, ...
export PATH="$HOME/.cargo/bin:$PATH"  # cargo install's default; the server PATH may lack it
transcript=""
if [ "$mode" != "visible" ]; then
  transcript="$("$herdr_bin" pane get "$pane_id" 2>/dev/null | jq -r '.result.pane.agent_session.value // empty')"
  if [ -n "$transcript" ] && ! asf --help >/dev/null 2>&1; then
    [ "$mode" = "transcript" ] && fail "asf not runnable: cargo install --git https://github.com/wassname/asf"
    transcript=""
  fi
fi

if [ "$mode" = "transcript" ] && [ -z "$transcript" ]; then
  fail "no agent session for this pane"
fi
[ "$mode" = "visible" ] && scan_source="visible"

printf '%s src=%s pane=%s cwd=%s\n' "$(date '+%H:%M:%S')" \
  "${transcript:-pane-$scan_source}" "$pane_id" "$cwd" \
  > "$HOME/.config/herdr/plugins/config/openr/last-source.log" 2>/dev/null

scan_text() {
  if [ -n "$transcript" ]; then
    # assistant text + one line per tool call; tool results are left out (noise)
    asf -r "$transcript" --role assistant --tools --tail "$transcript_messages" 2>/dev/null
  else
    "$herdr_bin" pane read "$pane_id" --source "$scan_source" --lines "$scan_lines" 2>/dev/null
  fi
}

# URLs, then path-looking tokens (with a slash, or ending .ext[:line]).
# Dedupe, newest mention first.
candidates="$(
  scan_text | awk '
    {
      # $ and backtick excluded: extracted text feeds command templates,
      # keep shell-expansion characters out of candidates entirely
      while (match($0, /https?:\/\/[^[:space:]"'"'"'`$()\]>]+/)) {
        print "url\t" substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART + RLENGTH)
      }
    }
    {
      line = $0
      while (match(line, /(\/[A-Za-z0-9_.@~-][A-Za-z0-9_.@~\/-]*|[A-Za-z0-9_.@~-]+\/[A-Za-z0-9_.@~\/-]+|[A-Za-z0-9_@~][A-Za-z0-9_.@~\/-]*\.[A-Za-z0-9][A-Za-z0-9]*)(:[0-9]+)?/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        print "file\t" tok
      }
    }
  ' | awk '!seen[$0]++' | if command -v tac >/dev/null 2>&1; then tac; else tail -r; fi
)"

# keep files that actually exist (relative to the pane cwd); no subshell forks
list="$(mktemp "${TMPDIR:-/tmp}/openr.XXXXXX")"
while IFS=$'\t' read -r kind tok; do
  if [ "$kind" = "url" ]; then
    printf 'url\t%s\t%s\n' "$tok" "$tok"
    continue
  fi
  p="${tok%%:[0-9]*}"
  p="${p/#\~/$HOME}"
  case "$p" in
    /dev/*) continue ;;
    /*) abs="$p" ;;
    *) abs="$cwd/$p" ;;
  esac
  abs="${abs%/}"  # dedupe dir/ and dir
  if [ -d "$abs" ]; then
    printf 'file\t%s/\t%s\n' "${tok%/}" "$abs"
  elif [ -e "$abs" ]; then
    printf 'file\t%s\t%s\n' "$tok" "$abs"
  fi
done <<< "$candidates" | awk -F'\t' '!seen[$3]++ { print $1 "\t" $2 }' > "$list"

if [ ! -s "$list" ]; then
  rm -f "$list"
  "$herdr_bin" notification show "openr" --body "nothing openable in pane output" 2>/dev/null
  exit 0
fi

if ! "$herdr_bin" plugin pane open \
  --plugin openr \
  --entrypoint picker \
  --placement popup \
  --width "${OPENR_WIDTH:-75%}" \
  --height "${OPENR_HEIGHT:-60%}" \
  --env "OPENR_LIST=$list" \
  --env "OPENR_PANE=$pane_id" \
  --env "OPENR_CWD=$cwd" \
  --focus; then
  rm -f "$list"
  fail "could not open the picker popup"
fi

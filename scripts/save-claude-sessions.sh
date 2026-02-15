#!/usr/bin/env bash
# Save Claude Code session IDs for each tmux pane that has claude running.
# Called by tmux-resurrect's post-save-all hook.
#
# Matches tmux window names to Claude's customTitle (set via /rename).
# Scans JSONL session files directly (sessions-index.json can be stale).
# Requires each Claude session to be renamed to match its tmux window name.

SAVE_FILE="$HOME/.tmux/resurrect/claude-sessions.txt"
CLAUDE_PROJECTS="$HOME/.claude/projects"

: > "$SAVE_FILE"

# Encode a directory path the way Claude Code does:
#   /Users/mike/foo bar → -Users-mike-foo-bar
encode_project_path() {
  echo "$1" | sed 's|[/ ]|-|g'
}

# Scan all JSONL files in a project dir for a custom-title entry matching
# the given title. Renames append new entries, so we use the last one per file.
# If multiple files match, pick the most recently modified.
find_session_by_title() {
  local project_dir="$1"
  local title="$2"

  python3 -c "
import json, glob, os, sys

project_dir = sys.argv[2]
title = sys.argv[1]
best_sid = None
best_mtime = 0

for fpath in glob.glob(os.path.join(project_dir, '*.jsonl')):
    last_title = None
    sid = None
    with open(fpath) as f:
        for line in f:
            if 'custom-title' not in line:
                continue
            try:
                obj = json.loads(line)
            except:
                continue
            if obj.get('type') == 'custom-title':
                last_title = obj.get('customTitle')
                sid = obj.get('sessionId')
    if last_title == title and sid:
        mtime = os.path.getmtime(fpath)
        if mtime > best_mtime:
            best_mtime = mtime
            best_sid = sid
if best_sid:
    print(best_sid)
" "$title" "$project_dir" 2>/dev/null
}

tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}	#{pane_pid}	#{pane_current_path}	#{window_name}" 2>/dev/null | while IFS=$'\t' read -r pane_key shell_pid pane_dir window_name; do
  # Only care about panes running claude
  claude_pid=$(pgrep -P "$shell_pid" -f "claude" 2>/dev/null | head -1)
  [ -z "$claude_pid" ] && continue

  # Find the project directory for this pane's working directory
  encoded=$(encode_project_path "$pane_dir")
  project_dir="$CLAUDE_PROJECTS/$encoded"
  [ -d "$project_dir" ] || continue

  session_id=$(find_session_by_title "$project_dir" "$window_name")
  [ -n "$session_id" ] && printf '%s\t%s\n' "$pane_key" "$session_id" >> "$SAVE_FILE"
done

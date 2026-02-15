#!/usr/bin/env bash
# Restore Claude Code sessions after tmux-resurrect restores the layout.
# Called by tmux-resurrect's post-restore-all hook.

SAVE_FILE="$HOME/.tmux/resurrect/claude-sessions.txt"

[ -f "$SAVE_FILE" ] || exit 0
[ -s "$SAVE_FILE" ] || exit 0

while IFS=$'\t' read -r pane_key session_id; do
  [ -z "$pane_key" ] && continue
  [ -z "$session_id" ] && continue

  # Verify the pane exists after restore
  tmux display-message -t "$pane_key" -p "" 2>/dev/null || continue

  tmux send-keys -t "$pane_key" "claude --resume $session_id" Enter

  # Brief delay to avoid hammering the API
  sleep 0.5
done < "$SAVE_FILE"

#!/usr/bin/env bash
set -e

SCRIPTS_DIR="$HOME/.tmux/scripts"
TMUX_CONF="$HOME/.tmux.conf"
REPO_URL="https://raw.githubusercontent.com/mikedyan/tmux-claude-resurrect/main"

echo "Installing tmux-claude-resurrect..."

# Download scripts
mkdir -p "$SCRIPTS_DIR"
curl -fsSL "$REPO_URL/scripts/save-claude-sessions.sh" -o "$SCRIPTS_DIR/save-claude-sessions.sh"
curl -fsSL "$REPO_URL/scripts/restore-claude-sessions.sh" -o "$SCRIPTS_DIR/restore-claude-sessions.sh"
chmod +x "$SCRIPTS_DIR/save-claude-sessions.sh" "$SCRIPTS_DIR/restore-claude-sessions.sh"
echo "  Scripts installed to $SCRIPTS_DIR"

# Add hooks to .tmux.conf if not already present
if ! grep -q 'save-claude-sessions' "$TMUX_CONF" 2>/dev/null; then
  # Insert before TPM init line if it exists, otherwise append
  if grep -q "tpm/tpm" "$TMUX_CONF" 2>/dev/null; then
    sed -i.bak '/tpm\/tpm/i\
# Save/restore Claude Code sessions across tmux restarts\
set -g @resurrect-hook-post-save-all    '\''~/.tmux/scripts/save-claude-sessions.sh'\''\
set -g @resurrect-hook-post-restore-all '\''~/.tmux/scripts/restore-claude-sessions.sh'\''\
' "$TMUX_CONF"
    rm -f "$TMUX_CONF.bak"
  else
    printf '\n# Save/restore Claude Code sessions across tmux restarts\n' >> "$TMUX_CONF"
    printf "set -g @resurrect-hook-post-save-all    '~/.tmux/scripts/save-claude-sessions.sh'\n" >> "$TMUX_CONF"
    printf "set -g @resurrect-hook-post-restore-all '~/.tmux/scripts/restore-claude-sessions.sh'\n" >> "$TMUX_CONF"
  fi
  echo "  Hooks added to $TMUX_CONF"
else
  echo "  Hooks already present in $TMUX_CONF"
fi

# Reload tmux config if tmux is running
if tmux info &>/dev/null; then
  tmux source-file "$TMUX_CONF"
  echo "  tmux config reloaded"
fi

echo ""
echo "Done! Now rename each Claude Code session to match its tmux window name:"
echo "  > /rename My Window Name"

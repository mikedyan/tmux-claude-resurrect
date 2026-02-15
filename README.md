# tmux-claude-resurrect

Automatically resume Claude Code sessions in the right tmux windows after a tmux restart.

If you use Claude Code across multiple tmux windows — each for a different task or project — this setup ensures every session comes back exactly where it was when tmux restarts, reboots, or crashes.

## The problem

[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) do a great job saving and restoring tmux layouts, window names, and working directories. But they don't know about Claude Code. After a restart, you get your windows back, but every Claude conversation is gone — and if you have 5-10 windows each running a different Claude session, manually resuming the right session in each window is tedious and error-prone.

## The solution

Two small shell scripts that hook into tmux-resurrect's save/restore lifecycle:

1. **On save** — for every tmux pane running Claude Code, match the tmux window name to the Claude session's custom title and record the session UUID.
2. **On restore** — for each saved mapping, send `claude --resume <uuid>` to the correct pane, automatically resuming each conversation in the right window.

The key insight: **Claude Code's `/rename` command** lets you give sessions human-readable names, and these can match your tmux window names exactly. Name your tmux window "Backend API" and `/rename` your Claude session to "Backend API" — the save script matches them up, and the restore script puts them back together.

## How it works

### Save flow (runs automatically every 15 minutes via continuum)

```
tmux panes → find claude processes → get window names
    ↓
~/.claude/projects/<encoded-path>/*.jsonl
    ↓
scan JSONL files for {"type": "custom-title", "customTitle": "..."} entries
    ↓
match window name to customTitle → extract sessionId
    ↓
write mapping to ~/.tmux/resurrect/claude-sessions.txt
```

The save file looks like:

```
main:1.1	fa54585f-fb32-4b30-bb3d-2a27e5f1b3ee
main:5.1	a9908a1b-f1e4-4722-a6c5-2f900ff4b976
p:1.1	6900249b-be10-4f94-94aa-f803e216bee2
```

### Restore flow (runs once after tmux layout is restored)

```
read ~/.tmux/resurrect/claude-sessions.txt
    ↓
for each entry: verify pane exists
    ↓
tmux send-keys "claude --resume <uuid>" Enter
    ↓
0.5s delay between launches (avoid API rate limits)
```

### Why JSONL files, not sessions-index.json?

Claude Code maintains a `sessions-index.json` file per project, but it can be stale — it isn't always updated when you `/rename` a session. The custom title is written immediately to the session's JSONL file as a `{"type": "custom-title", ...}` entry, so scanning the JSONL files directly is more reliable.

Sessions can also be renamed multiple times. Each `/rename` appends a new `custom-title` entry to the JSONL file, so the script reads the **last** one in each file to get the current name.

### How Claude Code stores sessions

Claude Code stores session data in `~/.claude/projects/`, with directory names derived from the working directory:

```
/Users/mike/my-project → ~/.claude/projects/-Users-mike-my-project/
```

Each session is a JSONL file named by UUID (e.g., `fa54585f-fb32-4b30-bb3d-2a27e5f1b3ee.jsonl`). When you `/rename` a session, an entry like this is appended:

```json
{"type": "custom-title", "customTitle": "Backend API", "sessionId": "fa54585f-fb32-4b30-bb3d-2a27e5f1b3ee"}
```

## Prerequisites

- [tmux](https://github.com/tmux-plugins/tpm)
- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)
- [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) (optional, for auto-save/restore)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Python 3 (pre-installed on macOS; used for JSON parsing)

## Installation

### 1. Copy the scripts

```bash
mkdir -p ~/.tmux/scripts
cp scripts/save-claude-sessions.sh ~/.tmux/scripts/
cp scripts/restore-claude-sessions.sh ~/.tmux/scripts/
chmod +x ~/.tmux/scripts/save-claude-sessions.sh
chmod +x ~/.tmux/scripts/restore-claude-sessions.sh
```

### 2. Add hooks to your `.tmux.conf`

Add these lines **before** the TPM initialization line (`run '~/.tmux/plugins/tpm/tpm'`):

```tmux
# Save/restore Claude Code sessions across tmux restarts
set -g @resurrect-hook-post-save-all    '~/.tmux/scripts/save-claude-sessions.sh'
set -g @resurrect-hook-post-restore-all '~/.tmux/scripts/restore-claude-sessions.sh'
```

### 3. Reload tmux config

```bash
tmux source-file ~/.tmux.conf
```

### 4. Name your Claude sessions

In each tmux window running Claude Code, use `/rename` to set a name that matches the tmux window name:

```
> /rename Backend API
```

You can verify the current window name in tmux with `Ctrl-b ,` (which also lets you rename it).

## Usage

Once set up, everything is automatic:

1. **Work normally** — run Claude Code in your tmux windows as usual.
2. **Continuum auto-saves** every 15 minutes, including the Claude session mappings.
3. **When tmux restarts** (reboot, crash, `tmux kill-server`), resurrect restores your layout and the restore script resumes each Claude session in the right window.

### Manual save/restore

You can trigger saves and restores manually:

- **Save**: `prefix + Ctrl-s` (tmux-resurrect default)
- **Restore**: `prefix + Ctrl-r` (tmux-resurrect default)

### Verify the saved mappings

```bash
cat ~/.tmux/resurrect/claude-sessions.txt
```

### Check which sessions have custom titles

```bash
python3 -c "
import json, glob, os
for f in sorted(glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')), key=os.path.getmtime, reverse=True):
    with open(f) as fh:
        title = None
        for line in fh:
            if 'custom-title' not in line: continue
            obj = json.loads(line)
            if obj.get('type') == 'custom-title':
                title = obj.get('customTitle')
        if title:
            print(f'{title:<30} {os.path.basename(f)}')"
```

## Customization

### Skip permissions on resume

If you want Claude to resume without permission prompts (useful for trusted, persistent sessions):

In `restore-claude-sessions.sh`, change the resume line to:

```bash
tmux send-keys -t "$pane_key" "claude --dangerously-skip-permissions --resume $session_id" Enter
```

### Custom pane commands on restore

You can add commands to run in specific windows before Claude starts. For example, to switch to a different user in a window named "MyServer":

```bash
# Add before the Claude restore loop in restore-claude-sessions.sh
server_pane=$(tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}	#{window_name}" 2>/dev/null \
  | awk -F'\t' '$2 == "MyServer" { print $1; exit }')

if [ -n "$server_pane" ]; then
  tmux send-keys -t "$server_pane" "ssh myuser@myserver" Enter
fi
```

## Limitations

- **Requires `/rename`**: Only sessions explicitly renamed with `/rename` are matched. Unnamed sessions are silently skipped.
- **macOS**: The save script uses macOS-specific `pgrep` and `ps` flags. Linux users may need minor adjustments.
- **One Claude per pane**: If a pane has multiple Claude processes, only the first is considered.
- **Python 3 required**: The JSONL scanning uses Python for reliable JSON parsing.

## License

MIT

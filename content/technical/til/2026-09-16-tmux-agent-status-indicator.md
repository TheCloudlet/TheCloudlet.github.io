+++
title = "Agent State in the Tmux Status Line"
author = ["Yi-Ping Pan (Cloudlet)"]
description = "Reading Claude Code, Codex and grok state into the tmux window list by scraping each pane's visible screen, after the title and the foreground command both turned out to carry nothing usable."
date = 2026-09-16
draft = false
[taxonomies]
  tags = ["tmux", "dotfiles", "cli", "workflow", "agents", "pingme"]
  categories = ["til"]
[extra]
  toc = true
+++

## The problem {#the-problem}

With several agent sessions open in tmux windows, telling which one is still
working, which is waiting on a decision, and which is done means visiting each
window.

[Herdr](https://herdr.dev) solves this as an agent-first multiplexer with a state sidebar, and
[agenmux](https://github.com/snirt/agenmux) ports its rules back into tmux. Both put the state in a surface of its
own. I wanted it on the window entries themselves, in the status line I already
look at.

Herdr also tracks `done` — finished while you were looking elsewhere — which
needs per-pane focus history. Skipping that leaves three states.

The target is the same classification, rendered in the tmux window list. Two
signals looked like they carried it and did not.


## The title carries nothing (for Claude) {#the-title-carries-nothing--for-claude}

`pane_title` is the obvious place: tmux tracks it per pane and programs set it
over OSC. Claude Code's never changed. Sampling twice a second through a full
working turn returned two distinct values:

```text
%0 [✳ Tmux config article]
%1 [✳ Claude Code]
```

Grok, on the same server, does update it:

```text
t=2  title=[⠋ - Waiting for response… - Review of tmux agent-status article - grok]
t=7  title=[⠸ - Thinking - Review of tmux agent-status article - grok]
```

A braille spinner, which the original config's yellow rule would have matched.
So title rules work for grok and silently do nothing for Claude.


## The foreground command names the wrong thing {#the-foreground-command-names-the-wrong-thing}

```text
$ tmux list-panes -a -F '#{pane_id} cmd=[#{pane_current_command}]'
%0 cmd=[2.1.267]
%1 cmd=[2.1.273]
```

Not `claude`. Both CLIs launch through a symlink to a versioned binary, and the
process carries that binary's filename:

```text
~/.local/bin/claude -> ~/.local/share/claude/versions/2.1.273
~/.grok/bin/grok    -> ../downloads/grok-1.0.30-macos-aarch64
```

Which is why grok shows up as `grok-1.0.30-mac`, truncated. It also explains
the green icon that never lit here: its rule wanted `pane_current_command` to
end in `claude`.

Matching `ps -o comm=` across the pane's process tree finds the real name. That
answers **which agent**, not what it's doing.


## The screen {#the-screen}

agenmux documents the approach:

> Detection is scraping-only: agents are identified by walking each pane's
> process tree, state is inferred from the pane's visible screen and title.

Claude Code working, via `capture-pane`:

```text
✽ Brewing… (2m 14s · ↓ 3.9k tokens)
❯
  ⏵⏵ auto mode on (shift+tab to cycle) · esc to interrupt · ← for agents
```

Idle, the same pane:

```text
❯
  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
```

`esc to interrupt` can only render while something is interruptible. The
spinner is there too, in `✳ ✽ ✶` rather than the braille set the title rule
looked for.

This is also why the same config seemed fine on a Linux box with an equally
static title: what lit there was green, which only needs
`pane_current_command` to resolve to `claude`.


## Per-agent rules {#per-agent-rules}

Walk the tree for the agent name, capture the screen, then apply that agent's
patterns:

```text
claude, claude-code, pingme:
    working  'esc to interrupt|ctrl+c to interrupt'
    idle     bare '❯' prompt line
    action   'do you want to proceed?|waiting for permission|…'

codex:
    action   'press enter to confirm or esc to cancel|…'
    working  'esc to interrupt'

grok:
    action   '<n>/<n>:select|Allow …?|No, reject|dialog footer hints'
    working  '[stop]|Ctrl+c:cancel'
```

The ordering differs and matters. Claude checks working first, with a
bare-prompt idle rule ahead of the blocked patterns so an answered permission
prompt left on screen doesn't read as waiting. Codex and grok check blocked
first, because their approval prompts keep the indicators of the tool call that
raised them.

Grok's `[stop]` is the one marker that holds for a whole turn — the spinner
text freezes during a long tool call and the cancel hint moves between
`Esc:cancel` and `Ctrl+c:cancel` — and it stays on screen through approval
prompts, which is what forces blocked first.

Title rules are dropped even where they'd work, so detection never depends on
an OSC sequence arriving. Claude's and Codex's screen patterns come from
agenmux; `pingme` rides on Claude's because it wraps Claude Code. Codex is
untested against a live session, and grok's were read off 1.0.30 rather than
taken from [herdr's manifest](https://github.com/herdrdev/herdr/blob/master/src/detect/manifests/grok.toml),
which targets Build 0.2.101.


## Wiring {#wiring}

The poller writes each pane's verdict into a pane-scoped option once a second:

```sh
tmux set-option -p -t "$pane_id" @agent-state "$state"
```

The format string only reads it:

```text
set -g @agent-status \
'#{?#{==:#{@agent-state},action},#[fg=colour196]#[bold]!,'\
'#{?#{==:#{@agent-state},working},#[fg=colour220]●,'\
'#{?#{==:#{@agent-state},idle},#[fg=colour34]✓,}}}'

set-window-option -g window-status-format '#{E:@agent-status}#[fg=colour18]#[nobold]#I:#W#F '
set-window-option -g window-status-current-format '#{E:@agent-status}#[fg=colour252]#[nobold]#I:#W#[fg=colour196]#[bold]* '
```

Both lines are needed — tmux renders the current window through its own format.

An earlier version called the script from `#(...)` inside the format instead.
That doesn't work: `#()` is a job whose result is cached for the next redraw, so
a detached session never updates. Hence the background loop.

The window list shows one icon per window, resolved against the active pane, so
a split running two agents surfaces one of them.


## Result {#result}

Red `!` wants a decision, yellow `●` is working, green `✓` is idle, unmarked is
a plain shell.

![tmux status line showing a green check on an idle Claude window and a yellow dot on a working grok window](/images/2026-09-16-tmux-agent-status.webp)

`✓1:123444` is an idle Claude pane; `●2:grok-1.0.30-mac` is grok mid-turn, its
window name that versioned-binary filename again. The working rule matched on
`Waiting for response… 6.8s` and the `[stop]` chip.

Three agents, three rule sets, matched against footer strings that break when
an agent redesigns its footer — silently, with no version to check.

A lifecycle hook avoids all of that, and herdr prefers one where it exists:
`full_lifecycle_hook_authority` lists pi, omp, mastracode, opencode, kilo and
kimi. Claude Code, Codex and grok aren't on it, so herdr scrapes them too.
Claude Code's hooks could write `@agent-state` directly, but that covers one of
the three and says nothing about a pane running anything else.


## Appendix: the full setup {#appendix-the-full-poller}


### The poller {#the-poller}

`~/.config/tmux/agent-status-poll.sh`, verified against claude 2.1.x and grok
1.0.30 on macOS; codex's patterns are agenmux's, carried over untested. Two
rough edges: the PID file sits at a fixed `/tmp` path, so two tmux servers on
one machine contend for it, and grok's rules are pinned to one release's
footer text.

```sh
#!/bin/sh
# Background poller: every second, classify each pane's agent state and write
# it into that pane's @agent-state user option, which the status line reads.
#
# Two signals, both necessary:
#   - process tree: which agent is running here? These CLIs launch through a
#     symlink to a versioned binary, so pane_current_command reports that
#     filename (claude -> "2.1.267", grok -> "grok-1.0.30-mac") rather than
#     the agent's name. Walking the tree and matching `ps -o comm=` finds it.
#   - visible screen: what is that agent doing? Every agent draws its state
#     there, which is not true of the title: Claude's is a fixed session name
#     while grok's carries a live spinner.
#
# Screen patterns and check order are per-agent. Claude's and Codex's come
# from agenmux's agents/*.conf (which ports herdr's manifests), minus the
# title rules those check first -- dropped on purpose, so detection never
# depends on an OSC sequence reaching tmux. They differ in more than wording:
# Claude treats the interrupt hint as authoritative and checks working first,
# while Codex checks its blocked prompts first.
# Verified against claude 2.1.x and grok 1.0.30; codex is untested.

echo $$ >/tmp/tmux-agent-status-poll.pid

# Exit cleanly when killed: tmux reports any non-zero run-shell exit in the
# status line, and a terminated daemon is routine, not an error worth showing.
trap 'rm -f /tmp/tmux-agent-status-poll.pid; exit 0' EXIT HUP INT TERM

# Echo the agent binary found anywhere in the pane's process tree, if any.
pane_agent() {
    root="$1"
    pids="$root"
    queue="$root"
    while [ -n "$queue" ]; do
        pid="${queue%% *}"
        queue="${queue#"$pid"}"
        queue="${queue# }"
        children=$(pgrep -P "$pid" 2>/dev/null)
        for c in $children; do
            case " $pids " in
            *" $c "*) ;;
            *)
                pids="$pids $c"
                queue="$queue $c"
                ;;
            esac
        done
    done
    # shellcheck disable=SC2086
    ps -o comm= -p $pids 2>/dev/null |
        sed -nE 's|.*/||; /^(claude|claude-code|codex|grok|pingme)$/p' |
        head -n 1
}

CLAUDE_WORKING='esc to interrupt|ctrl\+c to interrupt'
CLAUDE_IDLE='^[[:space:]]*❯[[:space:]]*$'
CLAUDE_BLOCKED='do you want to proceed\?|waiting for permission|do you want to allow this connection\?|enter to select.*esc to cancel|esc to cancel.*enter to select'

CODEX_WORKING='esc to interrupt'
CODEX_BLOCKED='press enter to confirm or esc to cancel|enter to submit answer|enter to submit all|allow command\?|\[y/n\]|yes \(y\)'

# From observing grok 1.0.30. herdr has a grok manifest but targets Build
# 0.2.101, whose footer differs (Ctrl+.:shortcuts vs Ctrl+x:shortcuts here).
# The activity line's "[stop]" affordance is the only marker present for a
# whole turn: the spinner text stops updating while a long tool call runs,
# and the cancel hint moves between Esc and Ctrl+c depending on focus.
# ponytail: Ctrl+c:cancel also appears in permission footers, where herdr
# treats it as a blocked signal -- safe only because BLOCKED is checked
# first; a permission footer those patterns miss would read as working.
GROK_WORKING='\[stop\]|Ctrl\+c:cancel'
GROK_BLOCKED='^[[:space:]]*[0-9]+/[0-9]+:select|Allow .*\?[[:space:]]*$|No, reject|Tab:scrollback|Shift\+x:dismiss|Ctrl\+o:yolo'

classify() {
    agent="$1"
    screen="$2"
    case "$agent" in
    codex)
        # Blocked first, as in agenmux. Untested against a live codex session:
        # the patterns are its screen rules, minus the title checks that come
        # first upstream and are useless here.
        if printf '%s' "$screen" | grep -qiE "$CODEX_BLOCKED"; then
            echo action
        elif printf '%s' "$screen" | grep -qE "$CODEX_WORKING"; then
            echo working
        else
            echo idle
        fi
        ;;
    grok)
        # Blocked first: an approval prompt keeps the spinner and [stop]
        # indicator from the tool call that raised it, so working would win.
        if printf '%s' "$screen" | grep -qiE "$GROK_BLOCKED"; then
            echo action
        elif printf '%s' "$screen" | grep -qE "$GROK_WORKING"; then
            echo working
        else
            echo idle
        fi
        ;;
    claude | claude-code | pingme)
        # Working beats blocked (the interrupt hint is authoritative), and a
        # bare ❯ prompt means idle -- checked before blocked so an answered
        # permission prompt still on screen doesn't read as waiting.
        if printf '%s' "$screen" | grep -qE "$CLAUDE_WORKING"; then
            echo working
        elif printf '%s' "$screen" | grep -qE "$CLAUDE_IDLE"; then
            echo idle
        elif printf '%s' "$screen" | grep -qiE "$CLAUDE_BLOCKED"; then
            echo action
        else
            echo idle
        fi
        ;;
    *)
        echo idle
        ;;
    esac
}

while true; do
    for pane in $(tmux list-panes -a -F '#{pane_id}:#{pane_pid}' 2>/dev/null); do
        pane_id="${pane%%:*}"
        pane_pid="${pane##*:}"

        agent=$(pane_agent "$pane_pid")
        if [ -z "$agent" ]; then
            tmux set-option -p -t "$pane_id" @agent-state '' 2>/dev/null
            continue
        fi

        screen=$(tmux capture-pane -p -t "$pane_id" 2>/dev/null | tail -20)
        state=$(classify "$agent" "$screen")

        tmux set-option -p -t "$pane_id" @agent-state "$state" 2>/dev/null
    done
    sleep 1
done
```


### The tmux config {#the-tmux-config}

`~/.config/tmux/tmux.conf` in full, so the status-line pieces are visible in
the context they run in. The agent-status block is the middle section; the
rest is ordinary setup that happens to surround it.

```text
###############################################################################
# Tmux display settings
###############################################################################
set -g default-terminal "screen-256color"

set -g base-index 1           # start windows numbering at 1
setw -g pane-base-index 1     # make pane numbering consistent with windows

set -g renumber-windows on    # renumber windows when a window is closed
set -g set-titles on          # set terminal title
set -g display-panes-time 800 # slightly longer pane indicators display time
set -g display-time 1000      # slightly longer status messages display time
set -g status-interval 1      # redraw status line every second

# Set status bar background to light grey and foreground to a contrasting color
set -g status-bg colour252 # light grey
set -g status-fg colour18  # dark blue

# Customize the left side of the status bar
set -g status-left '#[bg=colour252,fg=colour18] #S #[bg=colour252,fg=colour18]'

# Customize the right side of the status bar
set -g status-right '#[bg=colour252,fg=colour18] %m-%d %H:%M #[bg=colour252,fg=colour18]'

# Customize the window status format
set-window-option -g window-status-current-style 'bg=colour18,fg=colour252'

# Agent state is written by a background poller (agent-status-poll.sh) into
# each pane's @agent-state option, not looked up here at render time --
# process-tree checks via #() only get re-run when a client redraws, so a
# detached/unwatched session would show stale or blank icons.
set -g @agent-status \
'#{?#{==:#{@agent-state},action},#[fg=colour196]#[bold]!,'\
'#{?#{==:#{@agent-state},working},#[fg=colour220]●,'\
'#{?#{==:#{@agent-state},idle},#[fg=colour34]✓,}}}'
set-window-option -g window-status-format '#{E:@agent-status}#[fg=colour18]#[nobold]#I:#W#F '
set-window-option -g window-status-current-format '#{E:@agent-status}#[fg=colour252]#[nobold]#I:#W#[fg=colour196]#[bold]* '

# Start the poller once per server. PID-file guarded so `tmux source-file`
# reloads don't spawn duplicates -- `pgrep -f` alone false-positives when a
# wrapper shell's argv happens to contain the script name.
if-shell '! kill -0 "$(cat /tmp/tmux-agent-status-poll.pid 2>/dev/null)" 2>/dev/null' \
  'run-shell -b "~/.config/tmux/agent-status-poll.sh"'

###############################################################################
# Tmux bindings
###############################################################################

# Reload tmux config
bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded ~/.config/tmux/tmux.conf!"

# Set new panes to open in current directory
bind c new-window -c "#{pane_current_path}"
bind '"' split-window -c "#{pane_current_path}"
bind % split-window -h -c "#{pane_current_path}"

# mouse on
setw -g mouse on

# set vi mode for copy mode
setw -g mode-keys vi

## Clipboard integration
set -s set-clipboard external
bind Escape copy-mode
bind p paste-buffer
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-and-cancel
bind -T copy-mode-vi Enter send-keys -X copy-selection-and-cancel

## hjkl pane traversal
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

## move window right / left
bind-key -n C-S-Left swap-window -t -1 \; select-window -t -1
bind-key -n C-S-Right swap-window -t +1 \; select-window -t +1
```

Both files live in the same directory, which is what lets the `if-shell`
line reference the script by a fixed path. Stowed as one package, they land
at `~/.config/tmux/` together.

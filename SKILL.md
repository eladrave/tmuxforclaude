---
name: tmuxforclaude
description: Create, list, start, stop and remove Claude Code Remote Control projects on this machine with the tfc command (one tmux window per project folder, reachable from the Claude mobile app and claude.ai/code). Use when the user asks for a new project or session they can open from the phone or web, which projects are running, or to restart, stop or remove one.
---

# tmuxforclaude (`tfc`)

Each project is a folder with its own `claude remote-control` server, running in its own window of the tmux
session `claude`. The user opens it in the Claude app (Code tab) or at claude.ai/code under the project's name. A
registry (`~/.config/tmuxforclaude/projects.tsv`) remembers every project, so `tfc start-all` (also run at boot by
the `tmuxforclaude` user service, when installed) brings them all back.

## Commands

| Task | Command |
|---|---|
| New project (folder defaults to `~/git/<name>`, created if missing) | `tfc new <name> [folder] [--mode M] [--spawn S]` |
| What is registered and what runs | `tfc list` |
| Start one (no-op if it runs) | `tfc start <name>` |
| Restart one | `tfc restart <name>` |
| Start everything registered | `tfc start-all` |
| Stop one (stays registered) | `tfc stop <name>` |
| Stop and unregister (the folder is kept) | `tfc rm <name>` |
| Last lines of a project's terminal | `tfc logs <name> [N]` |
| Health check | `tfc doctor` |

- Names: letters, digits, `_` and `-`, at most 40.
- `--mode` is the permission mode of that project's sessions: `acceptEdits`, `auto`, `bypassPermissions`,
  `default`, `dontAsk` or `plan`. The default is `bypassPermissions` (or `$TFC_MODE`). The app cannot switch a
  session into bypass mode later, so it is chosen here. Bypass mode needs the user's one-time consent
  (`claude --dangerously-skip-permissions` in a terminal, accept the warning); without it, Remote Control
  sessions fall back to default mode and `tfc` prints a WARNING. Tell the user; never record the consent for them.
- `--spawn worktree` gives each chat in that project its own git worktree; only in a git repository.

## How to act

1. **New project.** If the user gives a repository URL, clone it first (`git clone <url> ~/git/<name>`), then
   `tfc new <name> ~/git/<name>`. Otherwise `tfc new <name>`. Use the mode the user asked for; if they named none,
   keep the default and say which it is. `tfc new` waits until the server is up and answers its first-run
   questions (enable Remote Control, trust the folder). When it prints `up` or `running`, tell the user to open the
   Claude app > Code > `<name>` (it can take a few seconds to appear).
2. **If it does not come up,** run `tfc logs <name>` and report what it shows. "not signed in" or a login error:
   the user must run `claude auth login` once on the machine. Do not try to sign in for them. If a question is
   still open on its screen, tell the user to answer it in tmux over SSH.
3. **Never run `tfc attach` or `tmux attach`** from a tool call: they wait for a terminal and hang. Use
   `tfc logs <name>` to see a project's screen.
4. **Never stop, restart or remove the project you are running in.** `tfc` refuses when it detects that (same tmux window);
   it is also the case when the project's folder is your current folder. Ask the user to do it from another project
   or over SSH.
5. **Removing never deletes files.** If the user wants the folder deleted too, confirm with them first and delete
   only that exact folder.
6. After any change, show `tfc list`.

## Requirements

- `tmux`, Claude Code signed in with a claude.ai subscription (`claude auth login`; API keys do not work with
  Remote Control), and the machine kept on.
- Install or update everything: `curl -fsSL https://raw.githubusercontent.com/eladrave/tmuxforclaude/main/install.sh | bash`

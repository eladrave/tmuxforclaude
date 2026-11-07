# tmuxforclaude

Run several [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control) projects on a server,
one tmux window per project folder, and drive them from the Claude mobile app or claude.ai/code. No laptop has to
stay on, and once it is set up you can create new projects from the phone: ask any running project's Claude to
make one (the included skill teaches it how).

## Install

On the server, as your normal user (not root):

```bash
curl -fsSL https://raw.githubusercontent.com/eladrave/tmuxforclaude/main/install.sh | bash
```

It installs, if missing, `tmux` (with sudo) and Claude Code (Anthropic's native installer), then:

- `~/.local/bin/tfc`, the command below;
- `~/.claude/skills/tmuxforclaude/SKILL.md`, so Claude sessions on this machine know how to use `tfc`;
- on Linux with systemd: the user service `tmuxforclaude.service`, which runs `tfc start-all` at boot. It turns on
  linger for your user (`sudo loginctl enable-linger`) when it has passwordless sudo, because a user service
  without linger is stopped at logout (`TFC_NO_LINGER=1` skips this). Without linger it skips the service; run
  `tfc start-all` after a reboot. Stopping the unit does not stop the servers (`KillMode=process`). The unit does
  not read your shell settings: put `TFC_*` variables in `~/.config/environment.d/tfc.conf`.

Then, once:

```bash
claude auth login
```

Open the URL it shows, approve, and paste the code back. Remote Control needs a claude.ai subscription login (Pro,
Max, Team or Enterprise); API keys do not work. Re-run the installer at any time to update.

## Use

```bash
tfc new myproject                  # folder ~/git/myproject, created if missing
tfc new api ~/src/api --mode acceptEdits
tfc list
```

Then open the Claude app > **Code** > `myproject`. One server takes several chats in its folder; add
`--spawn worktree` to give each chat its own git worktree (git repositories only).

| Command | Does |
|---|---|
| `tfc new <name> [dir] [--mode M] [--spawn S] [--no-start]` | register a project and start its server |
| `tfc list` | every project and whether its server runs |
| `tfc start <name>` / `tfc start-all` | start one / every registered project that is not running |
| `tfc restart <name>` | stop, then start |
| `tfc stop <name>` | stop its server and close its window (stays registered) |
| `tfc rm <name>` | stop and unregister (never deletes the folder) |
| `tfc logs <name> [N]` | the last lines of its window |
| `tfc attach [name]` | attach to the tmux session (`Ctrl-b w` lists windows, `Ctrl-b d` detaches) |
| `tfc doctor` | check tmux, claude, the login and the boot service |

**Permission mode.** `--mode` sets the mode of that project's sessions: `acceptEdits`, `auto`,
`bypassPermissions`, `default`, `dontAsk`, `plan`. The default is `bypassPermissions`, which lets Claude run any
command without asking; set `TFC_MODE=default` (or pass `--mode`) if you want prompts. The app cannot switch a
session into bypass mode later. Bypass mode needs your one-time consent: run `claude --dangerously-skip-permissions`
once in a terminal and accept its warning. Without it, Claude Code starts Remote Control sessions in default mode,
and `tfc` warns you.

**First-run questions.** The first start in a folder asks whether to enable Remote Control and whether to trust
the folder. `tfc` answers both by typing into the window, as you would: `y` to the first, and "Yes, I trust this
folder" in the trust menu (it presses that once, never twice). Set `TFC_AUTO_TRUST=0` to answer the trust question
yourself (`tfc attach <name>`).

## Settings (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `TFC_SESSION` | `claude` | the tmux session that holds the windows |
| `TFC_ROOT` | `~/git` | where `tfc new <name>` puts a project without a folder |
| `TFC_MODE` | `bypassPermissions` | default permission mode |
| `TFC_AUTO_TRUST` | `1` | answer the folder-trust question automatically |
| `TFC_WAIT` | `45` | seconds `tfc` waits for a server to come up |
| `TFC_CONFIG_DIR` | `~/.config/tmuxforclaude` | where the registry `projects.tsv` lives |
| `TFC_NO_LINGER` | `0` | installer: do not turn on linger |

## Notes

- The server must stay on and the `claude remote-control` processes must keep running; that is what tmux (and the
  boot service) are for. A project shows a green dot in the app while its server runs.
- `tfc` refuses to stop the project it is running in, so a Claude session cannot stop itself by accident.
- Tested on Ubuntu 26.10 with tmux 3.7 (`tests/run.sh`, with a stand-in for claude that mirrors the real CLI's
  first-run questions; not yet confirmed against a signed-in real CLI). Linux is
  the target; macOS should work without the boot service but is untested.

## Development

```bash
bash tests/run.sh      # uses a stand-in claude and a private tmux server; touches nothing else
```

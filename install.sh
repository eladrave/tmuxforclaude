#!/usr/bin/env bash
# tmuxforclaude installer:
#   curl -fsSL https://raw.githubusercontent.com/eladrave/tmuxforclaude/main/install.sh | bash
# Installs tmux and Claude Code if missing, the tfc command (~/.local/bin/tfc), the Claude skill
# (~/.claude/skills/tmuxforclaude/SKILL.md) and, on Linux with systemd, a user service that starts the
# registered projects at boot. Safe to re-run: it updates in place. Never run it with sudo.
set -euo pipefail

# Everything runs from main, called on the last line, so a partly downloaded script runs nothing.
main() {
	
	REPO=${TFC_REPO:-eladrave/tmuxforclaude}
	REF=${TFC_REF:-main}
	RAW="https://raw.githubusercontent.com/$REPO/$REF"
	BIN="$HOME/.local/bin"
	SKILL_DIR="$HOME/.claude/skills/tmuxforclaude"
	UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
	ORIG_PATH=$PATH
export PATH="$BIN:$PATH"

	say() { echo "tmuxforclaude: $*"; }
	die() { echo "tmuxforclaude: $*" >&2; exit 1; }

	if [[ $(id -u) -eq 0 && ${TFC_ALLOW_ROOT:-0} != 1 ]]; then
		die "run this as your normal user, not root or sudo (it installs into your home folder)"
	fi
	command -v curl >/dev/null || die "curl is required"

	# Where the files come from: a local clone (when run as ./install.sh) or GitHub.
	SRC=""
	if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
		here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
		[[ -f $here/bin/tfc && -f $here/SKILL.md ]] && SRC=$here
	fi
	fetch() { # repo-relative path, destination
		local tmp
		tmp=$(mktemp)
		if [[ -n $SRC ]]; then cp "$SRC/$1" "$tmp"; else curl -fsSL "$RAW/$1" -o "$tmp" || { rm -f "$tmp"; die "download failed: $RAW/$1"; }; fi
		install -m "${3:-0644}" "$tmp" "$2"
		rm -f "$tmp"
	}

	# 1. tmux
	if ! command -v tmux >/dev/null; then
		say "installing tmux"
		if command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y -qq tmux
		elif command -v dnf >/dev/null; then sudo dnf install -y -q tmux
		elif command -v yum >/dev/null; then sudo yum install -y -q tmux
		elif command -v pacman >/dev/null; then sudo pacman -S --noconfirm tmux
		elif command -v zypper >/dev/null; then sudo zypper --non-interactive install tmux
		elif command -v brew >/dev/null; then brew install tmux
		else die "install tmux yourself, then run this again"; fi
	fi
	say "tmux $(tmux -V | cut -d' ' -f2)"

	# 2. Claude Code (Anthropic's native installer, into ~/.local/bin)
	if ! command -v claude >/dev/null; then
		say "installing Claude Code"
		curl -fsSL https://claude.ai/install.sh | bash
		command -v claude >/dev/null || die "Claude Code did not install; see https://code.claude.com/docs"
	fi
	say "claude $(claude --version 2>/dev/null | head -n1)"

	# 3. tfc and the skill
	mkdir -p "$BIN" "$SKILL_DIR"
	fetch bin/tfc "$BIN/tfc" 0755
	fetch SKILL.md "$SKILL_DIR/SKILL.md"
	say "installed $BIN/tfc ($("$BIN/tfc" version)) and $SKILL_DIR/SKILL.md"

	# 4. Start at boot (Linux with systemd). A user service survives logout only with linger on, so the
	#    service is enabled only together with linger; otherwise tmux started from SSH is the safer home.
	if [[ $(uname -s) == Linux ]] && command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
		linger=$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || echo no)
		if [[ $linger != yes && ${TFC_NO_LINGER:-0} != 1 ]] && sudo -n true 2>/dev/null; then
			sudo -n loginctl enable-linger "$(id -un)" && linger=yes
		fi
		if [[ $linger == yes ]]; then
			mkdir -p "$UNIT_DIR"
			fetch systemd/tmuxforclaude.service "$UNIT_DIR/tmuxforclaude.service"
			systemctl --user daemon-reload
			systemctl --user enable tmuxforclaude.service >/dev/null 2>&1 || die "could not enable the boot service (systemctl --user enable tmuxforclaude.service)"
			say "boot service enabled: registered projects start at boot (tfc start-all)"
		else
			say "boot service skipped: it needs linger (sudo loginctl enable-linger $(id -un)), then run this again"
		fi
	else
		say "no systemd user manager: after a reboot, run  tfc start-all"
	fi

	# 5. Next steps
	echo
	if claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
		say "Claude Code is signed in."
	else
		say "next: sign in once:  claude auth login   (open the URL, approve, paste the code back)"
	fi
	say "then create a project:  tfc new <name> [folder]   (folder defaults to ~/git/<name>)"
	say "open it in the Claude app > Code. See all:  tfc list   Help:  tfc help"
	if ! grep -qs '"skipDangerousModePermissionPrompt": *true' "$HOME/.claude/settings.json" &&
		! grep -qs '"bypassPermissionsModeAccepted": *true' "$HOME/.claude.json"; then
		say "for bypass mode (tfc's default), run once and accept its warning:  claude --dangerously-skip-permissions"
	fi
	if ! grep -qs '.local/bin' "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null; then
		say "add ~/.local/bin to your PATH:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
	elif [[ ":$ORIG_PATH:" != *":$BIN:"* ]]; then
		say "open a new login shell first (or run  export PATH=\"\$HOME/.local/bin:\$PATH\"), so claude and tfc are found"
	fi
}

main "$@"

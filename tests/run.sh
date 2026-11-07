#!/usr/bin/env bash
# Tests for tfc with a stand-in claude and a private tmux server (tmux -L). Touches nothing outside a temp folder.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
TFC="$here/../bin/tfc"
command -v tmux >/dev/null || { echo "tmux is required"; exit 1; }

work=$(mktemp -d)
export TFC_SOCKET="tfc-test-$$" TFC_CONFIG_DIR="$work/config" TFC_ROOT="$work/projects" TFC_WAIT=20
export STUB_STATE="$work/stub" HOME="$work/home"
mkdir -p "$STUB_STATE" "$HOME" "$work/bin"
unset TMUX TMUX_PANE
cleanup() { tmux -L "$TFC_SOCKET" kill-server 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

# The stand-in mirrors claude 2.1.319: "Enable Remote Control? (y/n)" is a line question; the folder-trust
# question is a menu with "No, exit" first and selected, which ignores keys for half a second and wraps around.
# Per-project behaviour comes from files (a tmux server keeps the environment it started with):
# $STUB_STATE/fail-<name> exits at once, $STUB_STATE/silent-<name> never prints the ready message.
cat >"$work/bin/claude" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
--version) echo "9.9.9 (stub)"; exit 0 ;;
auth) echo '{ "loggedIn": true }'; exit 0 ;;
remote-control) ;;
*) exit 2 ;;
esac
echo "$*" >"$STUB_STATE/args-$(basename "$PWD")"
if [[ ! -f $STUB_STATE/enabled ]]; then
	echo "Remote Control lets you open this session from the Code tab in the Claude mobile app, or visit claude.ai/code in a browser."
	read -r -p "Enable Remote Control? (y/n) " a; [[ $a == y ]] || { echo "declined"; exit 1; }
	touch "$STUB_STATE/enabled"
fi
name=$(sed -n 's/.*--name \([^ ]*\).*/\1/p' <<<"$*")
[[ -f $STUB_STATE/fail-$name ]] && { echo "Error: something went wrong"; exit 3; }
key=$(printf '%s' "$PWD" | md5sum | cut -c1-8)
if [[ ! -f $STUB_STATE/trusted-$key ]]; then
	sel=0
	draw() {
		printf '\033[2J\033[H Accessing workspace:\n\n %s\n\n Quick safety check: Is this a project you created or one you trust?\n\n' "$PWD"
		if ((sel == 0)); then printf ' > No, exit\n   Yes, I trust this folder\n'; else printf '   No, exit\n > Yes, I trust this folder\n'; fi
		printf '\n Enter to confirm . Esc to cancel\n'
	}
	draw
	read -rs -t 0.5 -n 1000 _ 2>/dev/null || true # keys in the first half second are ignored
	while IFS= read -rsn1 k; do
		if [[ $k == $'\e' ]]; then read -rsn2 r; [[ $r == "[B" || $r == "[A" ]] && sel=$((1 - sel)); draw
		elif [[ -z $k ]]; then break; fi
	done
	printf '\033[2J\033[H'
	((sel == 1)) || { echo "exit: folder not trusted"; exit 1; }
	touch "$STUB_STATE/trusted-$key"
fi
[[ -f $STUB_STATE/silent-$name ]] || echo "Remote Control is on. Open the Code tab in the Claude mobile app, visit claude.ai/code in a browser, or ask Claude to work in this folder."
trap 'echo stopped; exit 0' INT TERM
while :; do sleep 1; done
EOF
chmod +x "$work/bin/claude"
export PATH="$work/bin:$PATH" TFC_CLAUDE="$work/bin/claude"

pass=0 fail=0
ok() { if eval "$2"; then echo "PASS $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
t() { "$TFC" "$@" 2>&1; }

out=$(t new alpha); ok "new alpha comes up" '[[ $out == *"alpha: up"* ]]'
ok "the trust menu was answered after the enable question" 'ls $STUB_STATE/trusted-* >/dev/null 2>&1'
ok "first-run questions answered" '[[ -f $STUB_STATE/enabled ]] && ls $STUB_STATE/trusted-* >/dev/null 2>&1'
ok "folder created under TFC_ROOT" '[[ -d $TFC_ROOT/alpha ]]'
ok "default mode passed" 'grep -q -- "--permission-mode bypassPermissions" $STUB_STATE/args-alpha'
ok "name passed" 'grep -q -- "--name alpha" $STUB_STATE/args-alpha'

mkdir -p "$work/with space"
out=$(t new beta "$work/with space" --mode acceptEdits --spawn worktree)
ok "new beta with a spaced folder, mode and spawn" '[[ $out == *"beta: up"* ]]'
ok "beta args" 'grep -q -- "--permission-mode acceptEdits --spawn worktree" "$STUB_STATE/args-with space"'

s0=$SECONDS; t new kappa --no-start >/dev/null; ok "registry lock released (a later new is quick)" '(( SECONDS - s0 < 5 ))'
t rm kappa >/dev/null
out=$(t list); ok "list shows both running" '[[ $(grep -c running <<<"$out") == 2 ]]'
out=$(t new alpha); ok "re-new alpha is a no-op" '[[ $out == *"already running"* ]]'
out=$(t new alpha /tmp/elsewhere); ok "same name, other folder refused" '[[ $out == *"already registered"* ]]'
out=$(t new 'bad.name'); ok "bad name refused" '[[ $out == *"invalid name"* ]]'
out=$(t new gamma --mode yolo); ok "bad mode refused" '[[ $out == *"unknown mode"* ]]'
ok "refused projects not registered" '! grep -q gamma $TFC_CONFIG_DIR/projects.tsv'

out=$(t stop alpha); ok "stop alpha" '[[ $out == *"alpha: stopped"* ]]'
out=$(t list); ok "alpha stopped, beta running" '[[ $out == *alpha*stopped* && $out == *beta*running* ]]'
out=$(t start alpha); ok "start alpha again (no questions this time)" '[[ $out == *"alpha: up"* ]]'

tmux -L "$TFC_SOCKET" kill-server
out=$(t list); ok "after the tmux server dies, both stopped" '[[ $(grep -c stopped <<<"$out") == 2 ]]'
out=$(t start-all); ok "start-all brings both back" '[[ $(grep -c ": up" <<<"$out") == 2 ]]'

# The self-stop guard: run tfc stop from inside alpha's own window.
id=$(tmux -L "$TFC_SOCKET" list-windows -t =claude -F '#{window_id} #{window_name}' | awk '$2=="alpha"{print $1}')
pane=$(tmux -L "$TFC_SOCKET" display-message -p -t "$id" '#{pane_id}')
out=$(TMUX=x TMUX_PANE=$pane t stop alpha); ok "refuses to stop its own project" '[[ $out == *"runs in"* ]]'
out=$(t list); ok "alpha still running after the refusal" '[[ $out == *alpha*running* ]]'

out=$(t logs beta 5); ok "logs shows the window" '[[ $out == *"Open the Code tab"* ]]'
out=$(t rm beta); ok "rm beta" '[[ $out == *unregistered* ]]'
ok "beta gone from the registry, folder kept" '! grep -q "^beta" $TFC_CONFIG_DIR/projects.tsv && [[ -d "$work/with space" ]]'

out=$(TFC_AUTO_TRUST=0 t new delta); ok "AUTO_TRUST=0 stops at the trust question" '[[ $out == *"folder-trust question"* ]]'
ok "AUTO_TRUST=0 did not trust the folder" '[[ $(ls $STUB_STATE | grep -c trusted-) == 2 ]]'

touch "$STUB_STATE/fail-eps"; out=$(t new eps); ok "a claude that exits is reported" '[[ $out == *"claude exited"* && $out == *"something went wrong"* ]]'
out=$(t list); ok "the exited project shows stopped" '[[ $out == *eps*stopped* ]]'
rm "$STUB_STATE/fail-eps"; out=$(t start eps); ok "start after the failure replaces the dead window" '[[ $out == *"eps: up"* ]]'
ok "only one eps window" '[[ $(tmux -L $TFC_SOCKET list-windows -t =claude -F "#W" | grep -cx eps) == 1 ]]'

touch "$STUB_STATE/silent-zeta"; out=$(TFC_WAIT=30 t new zeta); ok "running without a ready message counts as running" '[[ $out == *"zeta: running"* ]]'

out=$(t restart alpha); ok "restart alpha" '[[ $out == *"alpha: stopped"* && $out == *"alpha: up"* ]]'

out=$(t new eta); ok "bypass without consent warns" '[[ $out == *"WARNING: bypass mode needs"* ]]'
mkdir -p "$HOME/.claude"; echo '{ "skipDangerousModePermissionPrompt": true }' >"$HOME/.claude/settings.json"
out=$(t restart eta); ok "bypass with consent does not warn" '[[ $out != *WARNING* ]]'
out=$(t new theta --mode default); ok "default mode does not warn" '[[ $out != *WARNING* ]]'

tmux -L "$TFC_SOCKET" new-window -d -t =claude: -n foreign "sleep 600"
out=$(t stop foreign); ok "a window tfc did not create is not touched" '[[ $out == *"no project"* ]] && tmux -L $TFC_SOCKET list-windows -t =claude -F "#W" | grep -qx foreign'

out=$(t doctor); ok "doctor sees tmux and claude" '[[ $out == *"ok   tmux"* && $out == *"ok   claude"* ]]'

echo "$pass passed, $fail failed"
((fail == 0))

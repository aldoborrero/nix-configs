#!/usr/bin/env bash

set -euxo pipefail

if [[ -z ${ANT_USERNAME:-} ]]; then
  echo "ANT_USERNAME is not set" >&2
  exit 1
fi

# Bootstrap: ensure nix commands work before anything else
mkdir -p ~/.config/nix
echo 'extra-experimental-features = nix-command flakes fetch-tree' > ~/.config/nix/nix.conf

# nix.conf is managed by home-manager (modules/base.nix)
# Only the system-level /etc/nix/nix.conf needs sandbox=false and accept-flake-config
sudo rm -f /etc/nix/nix.conf
cat <<-EOF | sudo tee /etc/nix/nix.conf >/dev/null
    extra-experimental-features = nix-command flakes fetch-tree
    sandbox = false
    accept-flake-config = true
EOF

# legacy profile symlink
rm -f ~/.nix-profile
ln -sf ~/.local/state/nix/profile ~/.nix-profile

# Protect initial profile as 'ant' (before home-manager changes things).
# Using `nix-store --add-root` registers an indirect gcroot so GC honors it.
# The `ant-N-link` naming makes `nix-collect-garbage -d` treat it as a profile.
mkdir -p ~/.local/state/nix/profiles
if [[ ! -e ~/.local/state/nix/profiles/ant-1-link ]]; then
  nix-store --add-root ~/.local/state/nix/profiles/ant-1-link \
    -r "$(realpath ~/.local/state/nix/profiles/profile)"
  ln -sfn ant-1-link ~/.local/state/nix/profiles/ant
fi

sudo ln -sf /root/.local/state/nix/profiles/ant/bin/kubectl /opt/anthropic/bin/kubectl.real
ln -sfn /root/src/anthropic /root/code 2>/dev/null || true
rm -f ~/.tmux.conf

# Unlock argocd user if locked (containers ship with locked accounts
# which causes sshd to reject pubkey auth entirely)
if passwd -S argocd 2>/dev/null | grep -q ' L '; then
  echo "argocd:$(head -c 32 /dev/urandom | base64)" | sudo chpasswd
fi

# Add argocd to supervisor group
if ! id -nG argocd | grep -qw supervisor 2>/dev/null; then
  sudo usermod -aG supervisor argocd 2>/dev/null || true
fi

# gitconfig — only settings not managed by home-manager
# (git, delta, diff, merge, init, commit, rebase are all in base.nix)
gitconfig="/root/.gitconfig.${ANT_USERNAME}"
if ! grep -q 'path = /root/src/home/.config/git/config' "$gitconfig" 2>/dev/null; then
  cat <<-'EOF' >>"$gitconfig"
	[include]
	    path = /root/src/home/.config/git/config

	[credential "https://gist.github.com"]
	    helper = "gh auth git-credential"

	[github]
	    user = "aldoborrero"
EOF
fi

# --- persistent service dirs ---
mkdir -p /root/src/home/.config/sshd
mkdir -p /root/src/home/.config/pueue

# --- sshd setup (persistent across container restarts) ---
sshd_dir=/root/src/home/.config/sshd
if [[ ! -f "$sshd_dir/ssh_host_ed25519_key" ]]; then
  ssh-keygen -t ed25519 -f "$sshd_dir/ssh_host_ed25519_key" -N '' -q
fi

cat >"$sshd_dir/sshd_config" <<'EOF'
Port 2222
LogLevel INFO
UsePAM no
PubkeyAuthentication yes
AuthorizedKeysFile /root/.ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PrintMotd no
PrintLastLog no
AcceptEnv LANG LC_*
AcceptEnv GIT_*
AcceptEnv COLORTERM
HostKey /root/src/home/.config/sshd/ssh_host_ed25519_key
EOF

cat >"$sshd_dir/start-sshd.sh" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
mkdir -p /var/empty /run/sshd
chmod 755 /var/empty /run/sshd
exec /usr/sbin/sshd -D -e \
  -f /root/src/home/.config/sshd/sshd_config
SCRIPT
chmod +x "$sshd_dir/start-sshd.sh"

# --- supervisord services ---
sudo rm -f /etc/supervisor/conf.d/{sshd,pueued}.conf

sudo tee /etc/supervisor/conf.d/sshd.local.conf >/dev/null <<'EOF'
[program:sshd]
command=/root/src/home/.config/sshd/start-sshd.sh
autostart=true
autorestart=true
startsecs=5
stopwaitsecs=10
killasgroup=true
stopasgroup=true
stdout_logfile=/root/src/home/.config/sshd/sshd.out.log
stderr_logfile=/root/src/home/.config/sshd/sshd.err.log
EOF

sudo tee /etc/supervisor/conf.d/pueued.local.conf >/dev/null <<'EOF'
[program:pueued]
command=/root/.local/state/nix/profile/bin/pueued --verbose
user=argocd
environment=HOME="/root",USER="argocd",XDG_CONFIG_HOME="/root/src/home/.config"
autostart=true
autorestart=true
startsecs=2
stopwaitsecs=10
killasgroup=true
stopasgroup=true
stdout_logfile=/root/src/home/.config/pueue/pueued.out.log
stderr_logfile=/root/src/home/.config/pueue/pueued.err.log
EOF

# Reload supervisord and start/update services
sg supervisor -c 'supervisorctl reread' 2>/dev/null || true
sg supervisor -c 'supervisorctl update pueued' 2>/dev/null || true

# Only start sshd if not already running (prevents session drops)
if ! sg supervisor -c "supervisorctl status sshd" 2>/dev/null | grep -q RUNNING; then
  sg supervisor -c "supervisorctl update sshd" 2>/dev/null || true
fi

# home-manager
export PATH="/root/.local/state/nix/profile/bin:/root/.local/state/nix/profiles/ant/bin:$PATH"
nix run 'git+https://github.com/nix-community/home-manager' -- \
    switch \
    --flake 'git+https://github.com/aldoborrero/nix-configs#antics' \
    --refresh \
    -b hmbk

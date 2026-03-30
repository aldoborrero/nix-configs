# nix-configs

Portable home-manager configurations for remote server environments.

## What's included

- **Shell**: zsh with autosuggestions, syntax highlighting, atuin history
- **Editor**: astronvim (avim)
- **Git**: delta pager, SSH signing, lazygit
- **CLI tools**: bat, eza, fd, ripgrep, jq, yazi, k9s, zoxide, fzf
- **Terminal**: zellij with vim-style keybindings (Catppuccin Mocha)
- **AI**: pi agent with extensions from [agent-kit](https://github.com/aldoborrero/agent-kit)
- **Networking**: iroh-ssh for P2P access, pueue task queue

## Install

```bash
curl -sO https://raw.githubusercontent.com/aldoborrero/nix-configs/main/install.sh
bash install.sh
```

Or if you already have nix and home-manager:

```bash
home-manager switch --flake 'github:aldoborrero/nix-configs#antics' -b hmbk
```

## Update

```bash
home-manager switch --flake 'github:aldoborrero/nix-configs#antics' --refresh -b hmbk
```

## Structure

```
flake.nix              # Entry point, defines homeConfigurations
install.sh             # Bootstrap script for fresh environments
modules/
  base.nix             # Shared config: packages, shells, git, tools
  nxb-hosts.nix        # SSH host definitions
```

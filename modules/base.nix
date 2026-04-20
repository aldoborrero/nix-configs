{
  lib,
  pkgs,
  astronvim,
  llm-agents,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  ###########################################################################
  # Nix
  ###########################################################################

  # Disable HM nix management — container has its own nix wrapper
  nix.enable = false;

  # Write nix.conf declaratively via HM instead of install.sh
  xdg.configFile."nix/nix.conf".text = ''
    !include /root/code/config/remote/nix-shared.conf
    extra-experimental-features = nix-command fetch-tree flakes
    max-jobs = 36
    download-buffer-size = 268435456
    max-substitution-jobs = 36
    cores = 72
    always-allow-substitutes = true
    system-features = benchmark big-parallel nixos-test uid-range kvm
    connect-timeout = 1
    stalled-download-timeout = 10
    auto-optimise-store = true
  '';

  ###########################################################################
  # Home
  ###########################################################################

  # Add nix and which to activation PATH so the corporate nix wrapper works
  home.extraActivationPath = [
    pkgs.nixVersions.latest
    pkgs.which
  ];

  home = {
    sessionPath = [
      "$HOME/.local/state/nix/profile/bin"
      "$HOME/.local/state/nix/profiles/ant/bin"
    ];

    packages =
      with pkgs;
      [
        ast-grep
        bat-extras.batdiff
        bat-extras.batgrep
        bat-extras.batman
        gh
        k9s
        nix-your-shell
        nixVersions.latest
        pueue
        python3Packages.supervisor
      ]
      ++ (with astronvim.packages.${system}; [ avim ])
      ++ (with llm-agents.packages.${system}; [ pi ]);

    sessionVariables = {
      EDITOR = "avim";
      GIT_EXEC_PATH = "${pkgs.git}/libexec/git-core";
    };

    shellAliases = {
      g = "git";
      ga = "git add";
      gaa = "git add --all";
      gco = "git checkout";
      gf = "git fetch";
      gst = "git status";
      gpf = "git push -f";
      k = "kubectl";
      lg = "lazygit";
      lz = "lazygit";
    };

    # Terminal terminfo so TERM works correctly over SSH
    file = {
      ".terminfo/g/ghostty".source = "${pkgs.ghostty.terminfo}/share/terminfo/g/ghostty";
      ".terminfo/x/xterm-256color".source = "${pkgs.wezterm.terminfo}/share/terminfo/x/xterm-256color";
      ".terminfo/x/xterm-ghostty".source = "${pkgs.ghostty.terminfo}/share/terminfo/x/xterm-ghostty";
    };

    ###########################################################################
    # Activation scripts
    ###########################################################################

    # Ensure persistent dirs exist for services managed by supervisord
    activation.createServiceDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/src/home/.config/sshd"
      mkdir -p "$HOME/src/home/.config/pueue"
    '';

    # Install pi agent extensions from agent-kit
    # ~/.pi is ephemeral — symlink it to the persistent volume
    activation.installPiExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      PERSISTENT="$HOME/src/home/.config/pi"
      AGENT_KIT="$HOME/src/home/.config/agent-kit"
      PI_EXT="$PERSISTENT/agent/extensions"

      mkdir -p "$PERSISTENT/agent"
      if [ ! -L "$HOME/.pi" ]; then
        rm -rf "$HOME/.pi"
        ln -sfn "$PERSISTENT" "$HOME/.pi"
      fi

      if [ -d "$AGENT_KIT/.git" ]; then
        ${pkgs.git}/bin/git -C "$AGENT_KIT" pull --ff-only 2>/dev/null || true
      else
        ${pkgs.git}/bin/git clone https://github.com/aldoborrero/agent-kit.git "$AGENT_KIT" 2>/dev/null || true
      fi

      if [ -d "$AGENT_KIT/extensions" ]; then
        mkdir -p "$PI_EXT"
        for ext in \
          ast-grep brave-search btw context diff direnv \
          exa-search exit footer git-checkpoint git-commit-context \
          github-search groq-provider handoff inline-bash jina \
          notify openrouter-provider permission-gate plan-mode \
          questionnaire skill-namespaces subagent together-provider \
          tuicr until; do
          if [ -d "$AGENT_KIT/extensions/$ext" ]; then
            ln -sfn "$AGENT_KIT/extensions/$ext" "$PI_EXT/$ext"
          fi
        done
      fi
    '';
  };

  # No systemd user session in containers — pueued is managed by supervisord
  services.pueue.enable = lib.mkForce false;

  ###########################################################################
  # Programs — SSH
  ###########################################################################

  # No systemd user session or /run/user in containers
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*".controlMaster = lib.mkForce "no";
  };

  ###########################################################################
  # Programs — Shells
  ###########################################################################

  programs = {
    bash = {
      enable = true;
      initExtra = ''
        if command -v nix-your-shell > /dev/null; then
          eval "$(nix-your-shell bash)"
        fi
      '';
    };

    zsh = {
      enable = true;
      autocd = true;
      autosuggestion.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
      history = {
        extended = true;
        ignoreDups = true;
        ignoreSpace = true;
        share = true;
      };
      envExtra = ''
        # Fix PATH clobbering: /etc/environment overwrites HM session vars
        if [ -f /etc/environment ]; then
          set -a
          source /etc/environment
          set +a
        fi
        unset __HM_SESS_VARS_SOURCED
      '';
      initContent = lib.mkMerge [
        ''
          bindkey -e

          # Home / End / Delete
          bindkey '\e[H'  beginning-of-line
          bindkey '\e[1~' beginning-of-line
          bindkey '\eOH'  beginning-of-line
          bindkey '\e[F'  end-of-line
          bindkey '\e[4~' end-of-line
          bindkey '\eOF'  end-of-line
          bindkey '\e[3~' delete-char
          bindkey '^[[3~' delete-char

          if command -v nix-your-shell > /dev/null; then
            eval "$(nix-your-shell zsh)"
          fi
        ''
        (lib.mkAfter ''
          if [[ -f /root/code/config/remote/zshrc ]]; then
            export ANT_PRISTINE_SHELL=1
            source /root/code/config/remote/zshrc
          fi
        '')
      ];
    };

    ###########################################################################
    # Programs — Git
    ###########################################################################

    git = {
      enable = true;
      lfs.enable = true;
      settings = {
        user = {
          name = "Aldo Borrero";
          signingKey = "/root/.ssh/git-commit-signing/coder";
        };
        core.editor = "avim";
        commit.gpgsign = true;
        diff.colorMoved = "default";
        gpg.format = "ssh";
        init.defaultBranch = "main";
        merge.conflictstyle = "diff3";
        pull.rebase = true;
        push = {
          autoSetupRemote = true;
          followTags = true;
        };
        rebase.autoStash = true;
      };
      signing.format = "ssh";
    };

    delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        syntax-theme = "Nord";
      };
    };

    lazygit = {
      enable = true;
      settings.git = {
        autoFetch = false;
        fetchAll = false;
      };
    };

    ###########################################################################
    # Programs — CLI tools
    ###########################################################################

    atuin = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      settings = {
        auto_sync = false;
        sync_enabled = false;
        update_check = false;
        search_mode = "fuzzy";
        filter_mode = "global";
        style = "compact";
        secrets_filter = true;
        enter_accept = true;
      };
    };

    bat = {
      enable = true;
      config = {
        theme = "Catppuccin Mocha";
        map-syntax = [
          ".*ignore:Git Ignore"
          ".gitconfig.local:Git Config"
          "**/mx*:Bourne Again Shell (bash)"
          "**/completions/_*:Bourne Again Shell (bash)"
          ".vimrc.local:VimL"
          "vimrc:VimL"
        ];
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      stdlib = "";
      config.whitelist.exact = [ "/root/code/.envrc" ];
    };

    eza = {
      enable = true;
      icons = "auto";
      git = true;
      extraOptions = [
        "--group-directories-first"
        "--header"
      ];
    };

    fd.enable = true;
    htop.enable = true;
    jq.enable = true;

    starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      settings = {
        format = "$directory$git_branch$git_status$kubernetes$nix_shell$cmd_duration$line_break$character";
        add_newline = false;
        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[❯](bold red)";
        };
        directory = {
          truncation_length = 3;
          truncate_to_repo = true;
          style = "bold blue";
        };
        git_branch = {
          format = "[$branch]($style) ";
          style = "bold mauve";
        };
        git_status = {
          format = "[$all_status$ahead_behind]($style) ";
          style = "bold red";
        };
        kubernetes = {
          disabled = false;
          format = "[$context/$namespace]($style) ";
          style = "bold teal";
        };
        nix_shell = {
          format = "[$symbol$state]($style) ";
          symbol = "❄️ ";
          style = "bold blue";
        };
        cmd_duration = {
          min_time = 3000;
          format = "[$duration]($style) ";
          style = "bold yellow";
        };
      };
    };
    less.enable = true;
    man.enable = true;
    nix-index.enable = true;
    ripgrep.enable = true;
    tealdeer.enable = true;
    zoxide.enable = true;

    yazi = {
      enable = true;
      shellWrapperName = "y";
    };

    ###########################################################################
    # Programs — Terminal multiplexer
    ###########################################################################

    zellij = {
      enable = true;
      settings = {
        theme = "catppuccin-mocha";
        default_layout = "compact";
        pane_frames = false;
        simplified_ui = true;
        copy_on_select = true;
        scrollback_lines = 100000;
        default_shell = "zsh";

        keybinds = {
          unbind = "Ctrl h";
          "shared_except \"locked\"" = {
            "bind \"Alt Enter\"" = {
              NewPane = { };
            };
            "bind \"Alt w\"" = {
              CloseFocus = { };
            };
            "bind \"Alt 1\"" = {
              GoToTab = 1;
            };
            "bind \"Alt 2\"" = {
              GoToTab = 2;
            };
            "bind \"Alt 3\"" = {
              GoToTab = 3;
            };
            "bind \"Alt 4\"" = {
              GoToTab = 4;
            };
            "bind \"Alt 5\"" = {
              GoToTab = 5;
            };
            "bind \"Alt 6\"" = {
              GoToTab = 6;
            };
            "bind \"Alt 7\"" = {
              GoToTab = 7;
            };
            "bind \"Alt 8\"" = {
              GoToTab = 8;
            };
            "bind \"Alt 9\"" = {
              GoToTab = 9;
            };
            "bind \"Alt v\"" = {
              NewPane = "Down";
            };
            "bind \"Alt y\"" = {
              NewPane = "Right";
            };
            "bind \"Alt f\"" = {
              ToggleFocusFullscreen = { };
            };
            "bind \"Alt h\"" = {
              MoveFocus = "Left";
            };
            "bind \"Alt j\"" = {
              MoveFocus = "Down";
            };
            "bind \"Alt k\"" = {
              MoveFocus = "Up";
            };
            "bind \"Alt l\"" = {
              MoveFocus = "Right";
            };
            "bind \"Alt H\"" = {
              Resize = "Increase Left";
            };
            "bind \"Alt J\"" = {
              Resize = "Increase Down";
            };
            "bind \"Alt K\"" = {
              Resize = "Increase Up";
            };
            "bind \"Alt L\"" = {
              Resize = "Increase Right";
            };
            "bind \"Alt t\"" = {
              NewTab = { };
            };
            "bind \"Alt Tab\"" = {
              GoToNextTab = { };
            };
          };
        };
      };
    };
  };
}

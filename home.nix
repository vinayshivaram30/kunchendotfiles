{ config, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # Every pin below is bumped by ./update.sh: daily via the dotfiles-update
  # launchd agent, and from rebuild.sh when that has not succeeded in 24h.

  # kunchenguid single-binary CLIs shipped as GitHub release tarballs
  # (no brew/nixpkgs pkg). Each tarball holds one binary named after the tool.
  # Versions and hashes live in home/pkgs/releases.json.
  # The pinned hashes are for the darwin-arm64 release assets. On any
  # other platform the URL would change AND every hash would be wrong, so fail
  # fast with instructions instead of a hash-mismatch error mid-build.
  releases = builtins.fromJSON (builtins.readFile ./home/pkgs/releases.json);
  releaseBin = pname:
    let inherit (releases.${pname}) version hash; in
    assert pkgs.stdenv.hostPlatform.system == "aarch64-darwin" ||
      throw "releaseBin(${pname}): hashes are pinned for darwin-arm64 assets; add a per-arch (url, hash) pair for ${pkgs.stdenv.hostPlatform.system} before building";
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version;
      src = pkgs.fetchurl {
        url = "https://github.com/kunchenguid/${pname}/releases/download/v${version}/${pname}-v${version}-darwin-arm64.tar.gz";
        inherit hash;
      };
      sourceRoot = ".";
      dontFixup = true;  # keep the release binary's signature intact
      installPhase = ''
        runHook preInstall
        install -Dm755 ${pname} $out/bin/${pname}
        runHook postInstall
      '';
    };
  no-mistakes = releaseBin "no-mistakes";
  treehouse = releaseBin "treehouse";

  # Node CLIs from npm (no brew/nixpkgs pkg). home/pkgs/<pname>/ holds a
  # package.json depending on just that CLI plus npm's lockfile for its
  # closure; importNpmLock fetches from the lockfile's integrity hashes, so
  # there is no separate deps hash to keep in sync.
  npmCli = { pname, nodejs ? pkgs.nodejs }:
    let
      root = ./home/pkgs/${pname};
      lock = builtins.fromJSON (builtins.readFile (root + "/package-lock.json"));
    in
    pkgs.buildNpmPackage {
      inherit pname;
      inherit (lock.packages."node_modules/${pname}") version;
      src = root;
      npmDeps = pkgs.importNpmLock { npmRoot = root; };
      npmConfigHook = pkgs.importNpmLock.npmConfigHook;
      dontNpmBuild = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall
        libdir=$out/lib/${pname}
        mkdir -p $libdir
        cp -r node_modules $libdir/
        makeWrapper ${nodejs}/bin/node $out/bin/${pname} \
          --add-flags "$(readlink -f $libdir/node_modules/.bin/${pname})"
        runHook postInstall
      '';
    };
  gnhf = npmCli { pname = "gnhf"; };
  backpass = npmCli { pname = "backpass"; };
  gh-axi = npmCli { pname = "gh-axi"; };
  tasks-axi = npmCli { pname = "tasks-axi"; };
  quota-axi = npmCli { pname = "quota-axi"; };
  chrome-devtools-axi = npmCli { pname = "chrome-devtools-axi"; };
  lavish-axi = npmCli { pname = "lavish-axi"; nodejs = pkgs.nodejs_22; };

in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    gh
    no-mistakes
    treehouse
    gh-axi
    tasks-axi
    quota-axi
    chrome-devtools-axi
    lavish-axi
    gnhf
    backpass
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    neovim
    nodejs_22  # the Pi agent CLI is a Node program
    # the font everything renders in
    nerd-fonts.hack
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";
  # Pi installs its agent CLI here, outside the Nix store.
  home.sessionPath = [ "$HOME/.pi/agent/bin" ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --dangerously-bypass-approvals-and-sandbox";
      c = "clear";
    };
  };

  programs.git = {
    enable = true;
    settings.user = {
      name = "vinayshivaram30";
      email = "vinu252@gmail.com";
    };
  };
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";

  # Keep Pi's credential and runtime state local by linking only authored files and directories.
  home.file.".pi/agent/themes".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes";
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions";
  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/models.json";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  # Fleet SSH hosts: symlinked out of the Nix store from a gitignored file, so
  # private addresses stay off this repo and cannot vanish on activation.
  home.file.".ssh/config".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/ssh/config";

  # Daily at 5am (or on wake if asleep then): bump every pin, build, test and
  # commit, without activating. ./rebuild.sh applies the result.
  launchd.agents.dotfiles-update = {
    enable = true;
    config = {
      ProgramArguments = [ "${dotfiles}/update.sh" ];
      StartCalendarInterval = [ { Hour = 5; Minute = 0; } ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/dotfiles-update.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/dotfiles-update.log";
      EnvironmentVariables.PATH = "/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/${user}/bin:/usr/bin:/bin";
    };
  };
}

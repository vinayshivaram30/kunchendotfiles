{ config, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # kunchenguid single-binary CLIs shipped as GitHub release tarballs
  # (no brew/nixpkgs pkg). Each tarball holds one binary named after the tool.
  # Update: bump version, then get the new hash with
  #   nix store prefetch-file --json <release-tarball-url>
  # The pinned hashes below are for the darwin-arm64 release assets. On any
  # other platform the URL would change AND every hash would be wrong, so fail
  # fast with instructions instead of a hash-mismatch error mid-build.
  releaseBin = { pname, version, hash }:
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

  no-mistakes = releaseBin {
    pname = "no-mistakes";
    version = "1.79.0";
    hash = "sha256-gML0ubPQHLXWDKKUImtB1zMUCOblzwQApXbPPsJRZtc=";
  };
  treehouse = releaseBin {
    pname = "treehouse";
    version = "2.0.0";
    hash = "sha256-ZgIvNusMedbyQgJfJmt4KslHs6KBcAXxNCXL0Yh08fk=";
  };

  npmTarball = { name, version, hash }: pkgs.fetchurl {
    url = "https://registry.npmjs.org/${name}/-/${builtins.baseNameOf name}-${version}.tgz";
    inherit hash;
  };

  # every axi tool depends on these two
  axiDeps = {
    "@toon-format/toon" = npmTarball { name = "@toon-format/toon"; version = "2.3.1"; hash = "sha256-aSVhPqMpj1YlroSiBWt5Ahqs9zftF4IQf3fYwgrrrCo="; };
    "axi-sdk-js"        = npmTarball { name = "axi-sdk-js";     version = "0.1.12"; hash = "sha256-w1jHONFlcLzxme5rnWePqeae9cwbxdzrsejUbQJcP40="; };
  };
  npmCli = { pname, version, hash, deps, entry ? "dist/bin/${pname}.js" }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version;
      dontUnpack = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      src = npmTarball { name = pname; inherit version hash; };
      installPhase = ''
        runHook preInstall
        libdir=$out/lib/${pname}
        mkdir -p $libdir
        # npm tarballs all extract under a top-level "package/" dir.
        tar xzf $src -C $libdir --strip-components=1
        install_dep() { mkdir -p "$libdir/node_modules/$1"; tar xzf "$2" -C "$libdir/node_modules/$1" --strip-components=1; }
        ${pkgs.lib.concatStringsSep "\n        "
          (pkgs.lib.mapAttrsToList (name: src: "install_dep ${name} ${src}") deps)}
        # node resolves the bare imports from $libdir/node_modules (walks up from dist/).
        makeWrapper ${pkgs.nodejs}/bin/node $out/bin/${pname} --add-flags $libdir/${entry}
        runHook postInstall
      '';
    };

  # gnhf: Node ESM CLI on npm (bin dist/cli.mjs, imports commander + js-yaml at
  # runtime). No brew/nixpkgs pkg, and the repo builds via pnpm+tsdown, so we
  # assemble the prebuilt npm tarball with its flattened runtime closure and run
  # it with nixpkgs node instead of building from source.
  # Update: bump versions, re-fetch each hash with
  #   nix store prefetch-file --json https://registry.npmjs.org/<name>/-/<name>-<ver>.tgz
  gnhf =
    let
      gnhfSrc   = npmTarball { name = "gnhf";      version = "0.1.49";  hash = "sha256-SIKglBLe7UVUhp3CC8ZM6d+9ukqSJQbRNtSkFJ18Abs="; };
      commander = npmTarball { name = "commander"; version = "14.0.3";  hash = "sha256-WElwPFAODzJOsBNA2L2h+exI/De7e+lxLrDdUqrZL2w="; };
      js-yaml   = npmTarball { name = "js-yaml";   version = "4.3.0";   hash = "sha256-hZTuNElt0uQeyTT9IChD3Jk76astfV1HV5FGli+9+uY="; };
      argparse  = npmTarball { name = "argparse";  version = "2.0.1";   hash = "sha256-J5A4R/yCFeb8WjPoFJD3urpmQD+KreM3cbmIzKCXcow="; };
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "gnhf";
      version = "0.1.49";
      dontUnpack = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall
        libdir=$out/lib/gnhf
        # npm tarballs all extract under a top-level "package/" dir.
        mkdir -p $libdir
        tar xzf ${gnhfSrc} -C $libdir --strip-components=1
        install_dep() { mkdir -p "$libdir/node_modules/$1"; tar xzf "$2" -C "$libdir/node_modules/$1" --strip-components=1; }
        install_dep commander ${commander}
        install_dep js-yaml ${js-yaml}
        install_dep argparse ${argparse}
        # node resolves the bare imports from $libdir/node_modules (walks up from dist/).
        makeWrapper ${pkgs.nodejs}/bin/node $out/bin/gnhf --add-flags $libdir/dist/cli.mjs
        runHook postInstall
      '';
    };

  # backpass ships with no runtime dependencies, so the bare tarball is the closure.
  backpass = npmCli {
    pname = "backpass";
    version = "0.1.26";
    hash = "sha256-Nz0PeYAFbPD9gprgBHooHFVTD3uZv/10XS7dbgmL2fM=";
    deps = {};
    entry = "bin/backpass.js";
  };

  gh-axi = npmCli {
    pname = "gh-axi";
    version = "0.1.35";
    hash = "sha256-9yWr5EfJkqPWzA2aYyWGcj7RzxbHlRpAvODHPgkD5q4=";
    deps = axiDeps;
  };
  tasks-axi = npmCli {
    pname = "tasks-axi";
    version = "0.2.6";
    hash = "sha256-kzQv5sga9RZpvYonP56ImjY0KISHc8yQe64fcak5Cdk=";
    deps = axiDeps;
  };
  quota-axi = npmCli {
    pname = "quota-axi";
    version = "0.1.51";
    hash = "sha256-6JvIXJXnYGFbzX1Goc/OMEDz2pFfcOWmmm+mbltdsas=";
    deps = axiDeps // {
      "undici"         = npmTarball { name = "undici";         version = "6.28.0"; hash = "sha256-Mqhsb6KP1IuRVVUEjAW703rTVFfZ6UWVODGkN0yIapw="; };
      "proxy-from-env" = npmTarball { name = "proxy-from-env"; version = "2.1.0";  hash = "sha256-6cUtvx44IxnV2gC42WSAWFm36xQkRQ4EnRJ0PX4Z/Jo="; };
    };
  };
  # npm pins the browser tool's larger dependency closure in its lockfile.
  chrome-devtools-axi = pkgs.buildNpmPackage {
    pname = "chrome-devtools-axi";
    version = "0.1.34";
    src = ./home/pkgs/chrome-devtools-axi;
    npmDepsHash = "sha256-TdBIbSndxHg1FDlYkeNVSVWRM+C/CPXJKJ36dMWzDaA=";
    dontNpmBuild = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      runHook preInstall
      libdir=$out/lib/chrome-devtools-axi
      mkdir -p $libdir
      cp -r node_modules $libdir/
      makeWrapper ${pkgs.nodejs}/bin/node $out/bin/chrome-devtools-axi \
        --add-flags $libdir/node_modules/chrome-devtools-axi/dist/bin/chrome-devtools-axi.js
      runHook postInstall
    '';
  };
  lavish-axi = pkgs.buildNpmPackage {
    pname = "lavish-axi";
    version = "0.1.77";
    src = ./home/pkgs/lavish-axi;
    npmDepsHash = "sha256-/THxjZnIwd7xB/XAxKSiR+Dve0stKIVA81+/qKqwfJc=";
    dontNpmBuild = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      runHook preInstall
      libdir=$out/lib/lavish-axi
      mkdir -p $libdir
      cp -r node_modules $libdir/
      makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/lavish-axi \
        --add-flags $libdir/node_modules/lavish-axi/dist/cli.mjs
      runHook postInstall
    '';
  };

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

}

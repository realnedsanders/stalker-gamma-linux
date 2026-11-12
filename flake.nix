{
  description = "Install and launch S.T.A.L.K.E.R. G.A.M.M.A. on Linux (Mod Organizer 2 under Proton)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # Proton, umu and the game are x86_64 only.
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      # libunrar is unfree (redistributable) and the engine cannot extract the
      # modpack without it: allow that one package, not every unfree one.
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: lib.getName pkg == "unrar";
      };
      py = pkgs.python3Packages;

      # Not in nixpkgs. Same commit as pyproject.toml: a tag can move, a SHA cannot.
      gamma-launcher = py.buildPythonPackage {
        pname = "gamma-launcher";
        version = "3.1";
        pyproject = true;
        src = pkgs.fetchFromGitHub {
          owner = "Mord3rca";
          repo = "gamma-launcher";
          rev = "ade656e029a8547d8853ce1ba54f9b7f0acb9100";
          hash = "sha256-FLxJfP1fl3efRk9iAIAsMUrjQcUNa04GjiAKrYequF8=";
        };
        build-system = [ py.setuptools ];
        dependencies = with py; [
          beautifulsoup4
          cloudscraper
          gitpython
          platformdirs
          py7zr
          requests
          tenacity
          tqdm
          # nixpkgs patches it to load ${pkgs.unrar}/lib/libunrar.so directly.
          unrar
        ];
      };

      stalker-gamma-linux = py.buildPythonApplication {
        pname = "stalker-gamma-linux";
        version = (lib.importTOML ./pyproject.toml).project.version;
        pyproject = true;
        src = ./.;

        build-system = [ py.setuptools ];
        nativeBuildInputs = [
          pkgs.wrapGAppsHook4
          pkgs.gobject-introspection
        ];
        buildInputs = [
          pkgs.gtk4
          pkgs.libadwaita
        ];
        dependencies = [
          gamma-launcher
          py.rich
          py.tomli-w
          py.pygobject3
        ];

        # One wrapper, not two: the Python wrapper also carries the GApps variables.
        dontWrapGApps = true;
        preFixup = ''
          makeWrapperArgs+=(
            "''${gappsWrapperArgs[@]}"
            # The install pipeline stops without them (see `environment.checks`).
            --prefix PATH : ${
              lib.makeBinPath [
                pkgs.umu-launcher
                pkgs._7zz
              ]
            }
            # `doctor` looks for libunrar in the ldconfig cache, which never
            # lists a store path: point it at the library the engine loads.
            --set-default UNRAR_LIB_PATH ${pkgs.unrar}/lib/libunrar.so
          )
        '';

        postInstall = ''
          install -Dm644 data/stalker-gamma-linux-gui.desktop -t $out/share/applications
          install -Dm644 data/icons/stalker-gamma-linux-gui.png -t $out/share/icons/hicolor/512x512/apps
        '';

        nativeCheckInputs = [ py.pytestCheckHook ];
        # They run install.sh, which this package does not ship, with
        # PATH=/usr/bin:/bin: empty in the build sandbox.
        disabledTestPaths = [ "tests/test_install_script.py" ];
        preCheck = ''
          export HOME=$(mktemp -d)
        '';

        meta = {
          description = "Install and launch S.T.A.L.K.E.R. G.A.M.M.A. on Linux";
          homepage = "https://github.com/Fleorens/stalker-gamma-linux";
          license = lib.licenses.gpl3Plus;
          mainProgram = "stalker-gamma-linux";
          platforms = [ system ];
        };
      };
    in
    {
      packages.${system}.default = stalker-gamma-linux;

      # The tools of `.devbox/check`, without building PyGObject from source.
      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ stalker-gamma-linux ];
        packages = [
          (pkgs.python3.withPackages (
            ps:
            stalker-gamma-linux.dependencies
            ++ (with ps; [
              babel
              mypy
              pygobject-stubs
              pytest
            ])
          ))
          pkgs.ruff
          pkgs.xvfb-run
        ];
      };
    };
}

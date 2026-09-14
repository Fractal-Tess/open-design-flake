{
  description = "Open Design standalone Nix packages and modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    source = {
      url = "github:nexu-io/open-design/open-design-v0.16.1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, source }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      lib = nixpkgs.lib;
      sourceMeta = lib.importJSON "${source}/package.json";

      filterSource = includePaths:
        lib.cleanSourceWith {
          src = source;
          filter = path: type:
            let
              root = toString source;
              pathString = toString path;
              relative = lib.removePrefix (root + "/") pathString;
              matches = includePath:
                relative == includePath
                || lib.hasPrefix (includePath + "/") relative
                || (type == "directory" && lib.hasPrefix (relative + "/") includePath);
            in
            relative == "" || builtins.any matches includePaths;
        };

      workspaceManifests = workspacePaths:
        map (workspacePath: "${workspacePath}/package.json") workspacePaths;

      daemonWorkspacePaths = [
        "packages/release"
        "packages/contracts"
        "packages/registry-protocol"
        "packages/agui-adapter"
        "packages/plugin-runtime"
        "packages/sidecar-proto"
        "packages/launcher-proto"
        "packages/sidecar"
        "packages/platform"
        "packages/diagnostics"
        "apps/daemon"
      ];

      webWorkspacePaths = [
        "packages/release"
        "packages/components"
        "packages/contracts"
        "packages/host"
        "packages/platform"
        "packages/sidecar"
        "packages/sidecar-proto"
        "apps/web"
      ];

      baseSourcePaths = [
        "LICENSE"
        "package.json"
        "pnpm-lock.yaml"
        "pnpm-workspace.yaml"
        "tsconfig.json"
      ];

      daemonSrc = filterSource ([
        "assets"
        "plugins"
        "skills"
        "design-systems"
        "design-templates"
        "craft"
        "prompt-templates"
      ] ++ daemonWorkspacePaths ++ baseSourcePaths);

      webSrc = filterSource (webWorkspacePaths ++ baseSourcePaths);
      daemonPnpmDepsSrc = filterSource (baseSourcePaths ++ workspaceManifests daemonWorkspacePaths);
      webPnpmDepsSrc = filterSource (baseSourcePaths ++ workspaceManifests webWorkspacePaths);

      perSystem = lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          nodeMajor = builtins.head (lib.splitString "." (lib.removePrefix "~" sourceMeta.engines.node));
          pnpmVersion = lib.removePrefix "pnpm@" sourceMeta.packageManager;
          pnpmMajor = builtins.head (lib.splitString "." pnpmVersion);
          nodejs = builtins.getAttr "nodejs_${nodeMajor}" pkgs;
          pnpmBase = builtins.getAttr "pnpm_${pnpmMajor}" pkgs;
          pnpm_10 = pnpmBase.overrideAttrs (_old: {
            version = pnpmVersion;
            src = pkgs.fetchurl {
              url = "https://registry.npmjs.org/pnpm/-/pnpm-${pnpmVersion}.tgz";
              hash = "sha256-envPE9f2zrOUbAOXg3PZm+n94cr8MAC9/tTE95EWdhA=";
            };
          });
          daemon = pkgs.callPackage ./packages/daemon.nix {
            inherit nodejs pnpm_10;
            src = daemonSrc;
            pnpmDepsSrc = daemonPnpmDepsSrc;
            workspacePaths = daemonWorkspacePaths;
          };
          web = pkgs.callPackage ./packages/web.nix {
            inherit nodejs pnpm_10;
            src = webSrc;
            pnpmDepsSrc = webPnpmDepsSrc;
            workspacePaths = webWorkspacePaths;
          };
        in
        {
          packages = {
            inherit daemon web;
            default = daemon;
          };

          checks = {
            inherit daemon web;
          };

          apps.default = {
            type = "app";
            program = "${pkgs.writeShellScript "open-design" ''
              export OD_DATA_DIR="''${OD_DATA_DIR:-$HOME/.od}"
              exec ${daemon}/bin/od --no-open "$@"
            ''}";
            meta.description = "Open Design local daemon (od)";
          };

          devShells.default = pkgs.mkShell {
            packages = [ nodejs pnpm_10 ];
            shellHook = ''
              echo "Open Design dev shell"
              echo "Node.js: $(node --version)"
              echo "pnpm:    $(pnpm --version)"
            '';
          };

          formatter = pkgs.nixpkgs-fmt;
        });
    in
    (lib.genAttrs [ "packages" "checks" "apps" "devShells" "formatter" ]
      (output: lib.genAttrs systems (system: perSystem.${system}.${output})))
    // {
      homeManagerModules.default = import ./modules/home-manager.nix { flake = self; };
      nixosModules.default = import ./modules/nixos.nix { flake = self; };
    };
}

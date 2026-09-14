# Thin NixOS integration for the standalone Home Manager service module.
# This module intentionally does not import Home Manager itself. Consumers
# provide Home Manager's NixOS module; this wrapper imports the owned Open
# Design Home Manager module into the selected user's configuration.
{ flake }:
{ config, lib, ... }:
let
  cfg = config.services.open-design;
in
{
  options.services.open-design = {
    enable = lib.mkEnableOption "Open Design through Home Manager";

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Existing local user whose Home Manager configuration receives the
        Open Design module settings. This wrapper never creates or modifies a
        user; the named user must already be managed by Home Manager. Set this
        explicitly when enable is true.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = lib.literalExpression ''
        {
          autoStart = true;
          dataDir = "/home/alice/.od";
          webFrontend = {
            enable = true;
            host = "127.0.0.1";
            port = 5174;
          };
          mcp = {
            enable = true;
            port = 7458;
            keepalive.enable = true;
          };
        }
      '';
      description = ''
        Attribute set forwarded to
        `home-manager.users.<user>.services.open-design`. These are the
        Home Manager service options: autoStart, package, port, dataDir,
        environmentFile, extraEnv, extraBinPaths, webFrontend, and mcp.
        `services.open-design.enable` here is authoritative and is merged
        after this set, so the wrapper can disable the service without
        rewriting settings. Secret values belong in the runtime
        environmentFile, not in this Nix configuration.

        The consuming system must provide Home Manager's NixOS module and
        manage the named user through it. This wrapper imports the owned Open
        Design Home Manager module into that user's configuration; no
        upstream module or separate Home Manager import is needed.
      '';
    };
  };
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || (cfg.user != null && cfg.user != "");
          message = "services.open-design.user must name an existing Home Manager user when services.open-design.enable is true.";
        }
        {
          assertion = !cfg.enable || (cfg.user != null && builtins.hasAttr cfg.user config.users.users);
          message = "services.open-design.user must refer to an existing NixOS user.";
        }
      ];
    }
    (lib.mkIf (cfg.user != null && cfg.user != "") {
      home-manager.users.${if cfg.user == null then "root" else cfg.user} = {
        imports = [ (import ./home-manager.nix { inherit flake; }) ];
        services.open-design = lib.mkMerge [
          cfg.settings
          { enable = lib.mkForce cfg.enable; }
        ];
      };
    })
  ];
}

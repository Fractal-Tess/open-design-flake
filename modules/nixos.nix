# NixOS integration for the standalone Home Manager service module.
# This module intentionally does not import Home Manager itself. Consumers
# must provide Home Manager's NixOS module; this wrapper imports the owned Open
# Design Home Manager module into the selected user's configuration.
{ flake }:
{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.services.open-design;
  common = import ./common.nix {
    inherit lib pkgs flake;
    defaultDataDir =
      if cfg.user != null && builtins.hasAttr cfg.user config.users.users then
        "${config.users.users.${cfg.user}.home}/.od"
      else
        "/var/empty";
  };
in
{
  options.services.open-design = common // {
    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Existing local user whose Home Manager configuration receives the
        Open Design options. This wrapper never creates or modifies a user;
        the named user must already be managed by Home Manager. Set this
        explicitly when enable is true.
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
          message = "services.open-design.user must refer to an existing NixOS user managed by Home Manager.";
        }
      ];
    }
    (lib.mkIf (cfg.user != null && cfg.user != "") {
      home-manager.users.${cfg.user} = {
        imports = [ (import ./home-manager.nix { inherit flake; }) ];
        services.open-design = lib.mkMerge [
          (lib.removeAttrs cfg [ "user" ])
          { enable = lib.mkForce cfg.enable; }
        ];
      };
    })
  ];
}

# Shared option definitions for the standalone Open Design modules.
# This file contains no service configuration and deliberately has no import
# from the upstream repository.
{ lib
, pkgs
, flake
, defaultDataDir
,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  packagesForSystem = if flake ? packages.${system} then flake.packages.${system} else { };
in
{
  enable = lib.mkEnableOption "the Open Design local-first design daemon";

  package = lib.mkOption {
    type = lib.types.package;
    default =
      packagesForSystem.daemon
        or (throw "open-design: no daemon package available for ${system}; set services.open-design.package explicitly");
    defaultText = lib.literalExpression "open-design.packages.\${pkgs.stdenv.hostPlatform.system}.daemon";
    description = "Package providing the Open Design `od` executable.";
  };

  port = lib.mkOption {
    type = lib.types.port;
    default = 7457;
    description = ''
      TCP port used by the daemon API. The bundled web frontend proxies
      /api/*, /artifacts/*, and /frames/* to this loopback endpoint.
    '';
  };

  dataDir = lib.mkOption {
    type = lib.types.path;
    default = defaultDataDir;
    defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.od"'';
    description = ''
      Directory containing Open Design runtime state, including the SQLite
      database, project working trees, and saved artifacts.
    '';
  };

  autoStart = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Register the Open Design user service(s) with systemd so they start
      automatically. When false, daemon, web, MCP, and keepalive units are
      still declared for manual use, but no unit is linked into a startup
      target. Starting the daemon manually still starts enabled companion
      services.
    '';
  };

  environmentFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    example = "/run/secrets/open-design.env";
    description = ''
      Runtime-only KEY=VALUE file for daemon secrets. The path is passed to
      systemd as EnvironmentFile and values are never embedded in the Nix
      store. Generate the file out of band (for example with agenix or
      sops-nix).
    '';
  };

  environment = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = lib.literalExpression ''{ OD_CODEX_DISABLE_PLUGINS = "1"; }'';
    description = ''
      Additional non-secret environment variables for the daemon. Put API
      keys and other secrets in environmentFile instead.
    '';
  };

  extraBinPaths = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "/opt/agents/bin" ];
    description = ''
      Absolute directories prepended to the daemon PATH. Open Design scans
      PATH for agent CLIs; the module supplies user and system profile paths,
      while this option covers custom installations.
    '';
  };

  webFrontend = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve the built static SPA with Caddy and proxy its API, artifacts,
        and frames paths to the daemon. The web service is registered when
        this option is true; autoStart controls only its startup edge.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5174;
      description = "TCP port on which the bundled static frontend listens.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Explicit listener address for the frontend. Loopback is the safe
        default. For a non-loopback bind, set allowedOrigins to every browser
        origin that may access the SPA; the daemon's origin checks otherwise
        reject API writes.
      '';
    };

    allowedOrigins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "https://design.example.test" ];
      description = ''
        Full external HTTP(S) origins accepted by the daemon for browser API
        requests. Entries are passed as OD_ALLOWED_ORIGINS and must not include
        a path. Keep this empty for loopback-only use.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default =
        packagesForSystem.web
          or (throw "open-design: no web package available for ${system}; set services.open-design.webFrontend.package explicitly");
      defaultText = lib.literalExpression "open-design.packages.\${pkgs.stdenv.hostPlatform.system}.web";
      description = "Built static Open Design frontend to serve.";
    };
  };

  mcp = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run the daemon's stdio MCP server behind a local Streamable HTTP
        proxy. The MCP supervisor is registered when this option is true;
        autoStart controls only its startup edge.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.mcp-proxy;
      description = "Package providing the mcp-proxy executable.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address on which the Streamable HTTP MCP proxy listens.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7458;
      description = "TCP port on which the Streamable HTTP MCP proxy listens.";
    };

    proxyArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments passed to mcp-proxy before its endpoint options.";
    };

    daemonArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments appended to the `od mcp` command.";
    };

    keepalive = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Periodically initialize the MCP endpoint and list its tools. This
          keeps the upstream stdio server warm and restarts the supervisor if
          the health check fails.
        '';
      };

      onBootSec = lib.mkOption {
        type = lib.types.str;
        default = "5min";
        description = "Delay before the first MCP keepalive check.";
      };

      onUnitActiveSec = lib.mkOption {
        type = lib.types.str;
        default = "20min";
        description = "Interval between successful MCP keepalive checks.";
      };

      accuracySec = lib.mkOption {
        type = lib.types.str;
        default = "30s";
        description = "Systemd timer scheduling accuracy for MCP keepalive checks.";
      };
    };
  };
}

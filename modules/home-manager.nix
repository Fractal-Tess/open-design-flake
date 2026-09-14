# Standalone Linux Home Manager module for Open Design.
# The upstream repository is a source pin for the package only; this module
# intentionally does not import any upstream Nix files.
{ flake }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.open-design;
  common = import ./common.nix {
    inherit lib pkgs flake;
    defaultDataDir = "${config.home.homeDirectory}/.od";
  };

  daemonExe = lib.getExe cfg.package;
  caddyExe = lib.getExe pkgs.caddy;
  mcpProxyExe = lib.getExe cfg.mcp.package;

  daemonPathEntries =
    cfg.extraBinPaths
    ++ [ "${config.home.profileDirectory}/bin" ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      "/run/wrappers/bin"
      "/etc/profiles/per-user/${config.home.username}/bin"
      "/run/current-system/sw/bin"
      "/nix/var/nix/profiles/default/bin"
      "/usr/local/bin"
      "/usr/bin"
      "/bin"
    ];

  isLoopbackHost =
    host:
    host == "127.0.0.1"
    || host == "localhost"
    || host == "::1"
    || host == "[::1]"
    || lib.hasPrefix "127." host;

  daemonEnvironment = {
    OD_PORT = toString cfg.port;
    OD_DATA_DIR = toString cfg.dataDir;
    PATH = lib.concatStringsSep ":" daemonPathEntries;
  }
  // lib.optionalAttrs cfg.webFrontend.enable {
    OD_WEB_PORT = toString cfg.webFrontend.port;
  }
  // lib.optionalAttrs (cfg.webFrontend.allowedOrigins != [ ]) {
    OD_ALLOWED_ORIGINS = lib.concatStringsSep "," cfg.webFrontend.allowedOrigins;
  }
  // cfg.environment;

  envToList = lib.mapAttrsToList (name: value: "${name}=${value}") daemonEnvironment;
  mcpEndpoint = "http://${cfg.mcp.host}:${toString cfg.mcp.port}/mcp";
  mcpDaemonArgs = [
    "mcp"
    "--daemon-url"
    "http://127.0.0.1:${toString cfg.port}"
  ]
  ++ cfg.mcp.daemonArgs;

  caddyfile = pkgs.writeText "open-design-web.Caddyfile" ''
    {
      auto_https off
      admin off
      persist_config off
    }

    # A host-agnostic site address avoids treating 0.0.0.0 as a Host matcher.
    # The bind directive controls the actual listener interface.
    http://:${toString cfg.webFrontend.port} {
      bind ${builtins.toJSON cfg.webFrontend.host}
      handle /api/* {
        reverse_proxy 127.0.0.1:${toString cfg.port} {
          flush_interval -1
          transport http {
            read_timeout 86400s
            write_timeout 86400s
          }
        }
      }
      handle /artifacts/* {
        reverse_proxy 127.0.0.1:${toString cfg.port}
      }
      handle /frames/* {
        reverse_proxy 127.0.0.1:${toString cfg.port}
      }
      handle {
        root * ${cfg.webFrontend.package}
        try_files {path} {path}/ /index.html
        file_server
        encode gzip
      }
    }
  '';

  mcpProxySupervisor = pkgs.writeShellScript "open-design-mcp-supervisor" ''
    set -u

    proxyPid=""

    cleanup() {
      if [[ -n "$proxyPid" ]] && kill -0 "$proxyPid" 2>/dev/null; then
        kill "$proxyPid" 2>/dev/null || true
      fi
      wait "$proxyPid" 2>/dev/null || true
    }

    trap cleanup EXIT
    trap 'exit 0' INT TERM

    ${mcpProxyExe} ${lib.escapeShellArgs cfg.mcp.proxyArgs} \
      --host ${lib.escapeShellArg cfg.mcp.host} \
      --port ${toString cfg.mcp.port} -- \
      ${daemonExe} ${lib.escapeShellArgs mcpDaemonArgs} &
    proxyPid=$!

    childStarted=false
    for _ in {1..50}; do
      if ! kill -0 "$proxyPid" 2>/dev/null; then
        wait "$proxyPid"
        exit $?
      fi
      if ${lib.getExe' pkgs.procps "pgrep"} -P "$proxyPid" >/dev/null; then
        childStarted=true
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done

    if [[ "$childStarted" != true ]]; then
      echo "Open Design MCP child did not start" >&2
      exit 1
    fi

    while kill -0 "$proxyPid" 2>/dev/null; do
      if ! ${lib.getExe' pkgs.procps "pgrep"} -P "$proxyPid" >/dev/null; then
        echo "Open Design MCP child exited; restarting proxy" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done

    wait "$proxyPid"
  '';

  mcpKeepalive = pkgs.writeShellScript "open-design-mcp-keepalive" ''
    set -u

    headers=$(${pkgs.coreutils}/bin/mktemp)
    response=$(${pkgs.coreutils}/bin/mktemp)
    session=""

    cleanup() {
      if [[ -n "$session" ]]; then
        ${lib.getExe pkgs.curl} --silent --max-time 5 --request DELETE \
          --header "Accept: application/json, text/event-stream" \
          --header "Mcp-Session-Id: $session" \
          ${lib.escapeShellArg mcpEndpoint} >/dev/null 2>&1 || true
      fi
      ${pkgs.coreutils}/bin/rm -f "$headers" "$response"
    }

    recover() {
      echo "Open Design MCP health check failed; restarting proxy" >&2
      trap - EXIT
      cleanup
      ${pkgs.systemd}/bin/systemctl --user restart open-design-mcp.service
      exit 0
    }

    trap cleanup EXIT

    ${lib.getExe pkgs.curl} --silent --show-error --fail-with-body \
      --connect-timeout 3 --max-time 10 \
      --retry 10 --retry-connrefused --retry-delay 1 \
      --dump-header "$headers" --output "$response" \
      --header "Accept: application/json, text/event-stream" \
      --header "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"open-design-mcp-keepalive","version":"1.0.0"}}}' \
      ${lib.escapeShellArg mcpEndpoint} || recover

    session=$(${pkgs.gawk}/bin/awk 'BEGIN { IGNORECASE=1 } /^mcp-session-id:/ { gsub("\\r", "", $2); print $2 }' "$headers")
    [[ -n "$session" ]] || recover

    ${lib.getExe pkgs.curl} --silent --show-error --fail-with-body \
      --connect-timeout 3 --max-time 10 \
      --header "Accept: application/json, text/event-stream" \
      --header "Content-Type: application/json" \
      --header "Mcp-Session-Id: $session" \
      --data '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
      ${lib.escapeShellArg mcpEndpoint} >/dev/null || recover

    ${lib.getExe pkgs.curl} --silent --show-error --fail-with-body \
      --connect-timeout 3 --max-time 10 \
      --output "$response" \
      --header "Accept: application/json, text/event-stream" \
      --header "Content-Type: application/json" \
      --header "Mcp-Session-Id: $session" \
      --data '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
      ${lib.escapeShellArg mcpEndpoint} || recover

    ${lib.getExe pkgs.jq} --exit-status '.result.tools | length > 0' "$response" >/dev/null || recover
  '';
in
{
  options.services.open-design = common;

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ cfg.package ] ++ lib.optional cfg.mcp.enable cfg.mcp.package;

        home.activation.openDesignDataDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run mkdir -p ${lib.escapeShellArg (toString cfg.dataDir)}
        '';

        assertions = [
          {
            assertion =
              !cfg.webFrontend.enable
              || isLoopbackHost cfg.webFrontend.host
              || cfg.webFrontend.allowedOrigins != [ ];
            message = ''
              services.open-design.webFrontend.host = "${cfg.webFrontend.host}" is
              non-loopback, but webFrontend.allowedOrigins is empty. Declare every
              external origin used to load the SPA, or keep the frontend on loopback.
            '';
          }
          {
            assertion = pkgs.stdenv.hostPlatform.isLinux;
            message = "services.open-design is supported only on Linux.";
          }
        ];
      }

      (lib.mkIf (pkgs.stdenv.hostPlatform.isLinux) {
        systemd.user.services.open-design = {
          Unit = {
            Description = "Open Design daemon (user service)";
            After = [ "network-online.target" ];
            Wants = [
              "network-online.target"
            ]
            ++ lib.optional cfg.webFrontend.enable "open-design-web.service"
            ++ lib.optional cfg.mcp.enable "open-design-mcp.service"
            ++ lib.optional (cfg.mcp.enable && cfg.mcp.keepalive.enable) "open-design-mcp-keepalive.timer";
          };
          Service = {
            Type = "simple";
            ExecStart = "${daemonExe} --port ${toString cfg.port} --no-open";
            Environment = envToList;
            Restart = "on-failure";
            RestartSec = 3;
          }
          // lib.optionalAttrs (cfg.environmentFile != null) {
            EnvironmentFile = toString cfg.environmentFile;
          };
        }
        // lib.optionalAttrs cfg.autoStart {
          Install.WantedBy = [ "default.target" ];
        };
      })

      (lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && cfg.webFrontend.enable) {
        systemd.user.services.open-design-web = {
          Unit = {
            Description = "Open Design web frontend (static file server)";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${caddyExe} run --config ${caddyfile} --adapter caddyfile";
            Restart = "on-failure";
            RestartSec = 3;
          };
        }
        // lib.optionalAttrs cfg.autoStart {
          Install.WantedBy = [ "default.target" ];
        };
      })

      (lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && cfg.mcp.enable) {
        systemd.user.services.open-design-mcp = {
          Unit = {
            Description = "Open Design Streamable HTTP MCP proxy";
            After = [
              "network-online.target"
              "open-design.service"
            ];
            Wants = [ "network-online.target" ];
            Requires = [ "open-design.service" ];
            BindsTo = [ "open-design.service" ];
            PartOf = [ "open-design.service" ];
            StartLimitIntervalSec = 0;
          };
          Service = {
            Type = "simple";
            Environment = envToList;
            ExecStart = mcpProxySupervisor;
            Restart = "always";
            RestartSec = 3;
          }
          // lib.optionalAttrs (cfg.environmentFile != null) {
            EnvironmentFile = toString cfg.environmentFile;
          };
        }
        // lib.optionalAttrs cfg.autoStart {
          Install.WantedBy = [ "default.target" ];
        };
      })

      (lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && cfg.mcp.enable && cfg.mcp.keepalive.enable) {
        systemd.user.services.open-design-mcp-keepalive = {
          Unit = {
            Description = "Open Design MCP keepalive and health check";
            After = [ "open-design-mcp.service" ];
            Requires = [ "open-design-mcp.service" ];
            BindsTo = [ "open-design.service" ];
            PartOf = [ "open-design.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = mcpKeepalive;
          };
        };

        systemd.user.timers.open-design-mcp-keepalive = {
          Unit = {
            Description = "Periodically keep Open Design MCP alive";
            After = [ "open-design.service" ];
            Requires = [ "open-design.service" ];
            BindsTo = [ "open-design.service" ];
            PartOf = [ "open-design.service" ];
          };
          Timer = {
            OnBootSec = cfg.mcp.keepalive.onBootSec;
            OnUnitActiveSec = cfg.mcp.keepalive.onUnitActiveSec;
            AccuracySec = cfg.mcp.keepalive.accuracySec;
            Unit = "open-design-mcp-keepalive.service";
          };
        }
        // lib.optionalAttrs cfg.autoStart {
          Install.WantedBy = [ "timers.target" ];
        };
      })

    ]
  );
}

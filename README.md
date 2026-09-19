<p align="center">
  <img src="assets/logo.svg" alt="Open Design + Nix" width="480" />
</p>

<h1 align="center">open-design-flake</h1>
<p align="center">
  <a href="flake.nix"><img src="https://img.shields.io/badge/Nix-flake-5277C3?logo=nixos&logoColor=white" alt="Nix flake" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0 license" /></a>
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey" alt="Linux" />
</p>

[Open Design](https://github.com/nexu-io/open-design), built from source for NixOS. Includes the daemon, web frontend, MCP server, and Home Manager integration.

This flake maintains its own build recipes and modules. Upstream is a locked source input, not an imported flake.

## Build

```sh
nix build .#open-design .#daemon .#web
```

`packages.<system>.open-design` and `packages.<system>.default` are the
daemon package; `packages.<system>.daemon` and `packages.<system>.web` remain
available as the named daemon and static frontend outputs. `nix run .` starts
the daemon with state in `~/.od`.

## Enable on NixOS

Add the flake input:

```nix
inputs.open-design-flake.url = "github:Fractal-Tess/open-design-flake";
```

The NixOS module is a typed wrapper around the Home Manager module, not a
native system service. Your system must import Home Manager's NixOS module and
manage the selected user through it. With `inputs` passed through
`specialArgs`, replace `alice` with that managed user:

```nix
{ inputs, ... }: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.open-design-flake.nixosModules.default
  ];

  services.open-design = {
    enable = true;
    user = "alice";
    webFrontend.enable = true;
    mcp.enable = true;
  };
}
```

`services.open-design` on NixOS exposes the same typed options as the Home
Manager service: `package`, `port`, `dataDir`, `autoStart`, `environmentFile`,
`environment`, and `extraBinPaths`; `webFrontend.{enable,package,host,port,
allowedOrigins}`; and `mcp.{enable,package,host,port,proxyArgs,daemonArgs,
keepalive.{enable,onBootSec,onUnitActiveSec,accuracySec}}`. NixOS adds the
required `user` selector. Package defaults use this flake's tested daemon,
frontend, and MCP proxy packages and can be explicitly overridden.
`enable` is authoritative and is forced onto the delegated Home Manager
service. Secrets belong in `environmentFile`, while `environment` is for
non-secret daemon variables.

`autoStart` defaults to `true`. Set it to `false` to retain daemon, web, MCP,
and MCP keepalive unit definitions for manual operation without startup
WantedBy edges. Starting `open-design.service` manually still starts enabled
companion services. Disabling `enable` removes the integration but does not
delete the user's data directory.

Open **http://127.0.0.1:5174**. MCP is at
`http://127.0.0.1:7458/mcp`; state stays in the user's `~/.od`. Install and
authenticate an agent CLI separately.

For standalone Home Manager, import `homeManagerModules.default` and
configure `services.open-design` directly. The old NixOS
`services.open-design.settings` forwarding attribute is removed: move each
setting to the corresponding typed option, and rename `extraEnv` to
`environment`. Keep services private; origin checks are not authentication.

## Update

Keep this flake's nixpkgs pin. Its Node runtime includes [native-addon fixes](https://github.com/nodejs/node/pull/65943).

The daily [update workflow](.github/workflows/update.yml) advances the locked upstream source, refreshes changed dependency hashes, and commits only after every package passes its flake check. Run the same process locally with:

```sh
./scripts/update.sh
```

In your NixOS repository, run `nix flake update open-design-flake` and rebuild after an automated update lands.

Builds, API/MCP operations, browser rendering, and restart recovery were tested on x86_64-linux. ARM outputs were evaluated only. AI generation was not verified.

## Credits and mirrors

[GitHub](https://github.com/Fractal-Tess/open-design-flake) · Gitadel: `ssh://git@neo.netbird.cloud:2222/fractal-tess/open-design-flake.git`

Build recipes adapted from Open Design under [Apache-2.0](LICENSE). Logo combines its mark with the [Nix snowflake](https://github.com/NixOS/nixos-artwork/tree/master/logo) by Simon Frankau and Tim Cuthbertson ([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)), resized and arranged for this repository.

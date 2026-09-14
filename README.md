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
nix build .#daemon .#web
```

`nix run .` starts the daemon with state in `~/.od`.

## Enable on NixOS

Add the flake input:

```nix
inputs.open-design-flake.url = "github:Fractal-Tess/open-design-flake";
```

With Home Manager's NixOS module enabled and `inputs` passed through `specialArgs`, add this to your system configuration. Replace `alice` with your managed user.

```nix
{ inputs, ... }: {
  imports = [ inputs.open-design-flake.nixosModules.default ];

  services.open-design = {
    enable = true;
    user = "alice";
    settings = {
      autoStart = true;
      webFrontend.enable = true;
      mcp.enable = true;
    };
  };
}
```

Open **http://127.0.0.1:38471**. MCP is at `http://127.0.0.1:38472/mcp`; state stays in the user's `~/.od`. Install and authenticate an agent CLI separately.

Keep this flake's nixpkgs pin. Its Node runtime includes [native-addon fixes](https://github.com/nodejs/node/pull/65943).

For standalone Home Manager, import `homeManagerModules.default` instead and configure `services.open-design` directly. See the [options](modules/common.nix) for ports, runtime secrets, and autostart. Keep services private; origin checks are not authentication.

## Update

Upstream `main` is pinned in `flake.lock`. To update this repository:

```sh
nix flake update source
nix flake check
```

Update [dependency hashes](packages/pnpm-deps.nix) if needed, then commit and publish. In your NixOS repository, run `nix flake update open-design-flake` and rebuild.

Builds, API/MCP operations, browser rendering, and restart recovery were tested on x86_64-linux. ARM outputs were evaluated only. AI generation was not verified.

## Credits and mirrors

[GitHub](https://github.com/Fractal-Tess/open-design-flake) · Gitadel: `ssh://git@neo.netbird.cloud:2222/fractal-tess/open-design-flake.git`

Build recipes adapted from Open Design under [Apache-2.0](LICENSE). Logo combines its mark with the [Nix snowflake](https://github.com/NixOS/nixos-artwork/tree/master/logo) by Simon Frankau and Tim Cuthbertson ([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)), resized and arranged for this repository.

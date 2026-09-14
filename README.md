<h1 align="center">open-design-flake</h1>
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0 license" /></a>
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey" alt="Linux" />
</p>

Build [Open Design](https://github.com/nexu-io/open-design) from source and run it as a user service on NixOS.

This repository owns the daemon and web build recipes, Home Manager module, and NixOS integration. Upstream is a locked source input with `flake = false`; none of its Nix files are imported. Packages are exported for x86_64-linux and aarch64-linux.

## Build

```sh
nix build .#daemon .#web
OD_DATA_DIR="$(mktemp -d)" ./result/bin/od --port 17457 --no-open
```

The daemon package provides `od`. The web package contains a static frontend; the module serves it through Caddy with same-origin API proxying. `nix run .` starts the daemon with state in `$HOME/.od` unless `OD_DATA_DIR` is set.

## Enable on NixOS

Add the input to your system flake:

```nix
inputs.open-design-flake = {
  url = "github:Fractal-Tess/open-design-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

In a system that already imports Home Manager's NixOS module and manages the named user:

```nix
{
  imports = [ inputs.open-design-flake.nixosModules.default ];

  services.open-design = {
    enable = true;
    user = "alice";
    settings = {
      autoStart = true;
      webFrontend = {
        enable = true;
        port = 38471;
      };
      mcp = {
        enable = true;
        port = 38472;
      };
      # Runtime file, not a Nix path literal or secret stored in this repo:
      # environmentFile = "/run/secrets/open-design.env";
    };
  };
}
```

Open `http://127.0.0.1:38471`. The daemon listens on port 7457; MCP is at `http://127.0.0.1:38472/mcp`. State defaults to the selected user's `~/.od`. Agent CLIs must be installed separately; user and system profile binaries are on the daemon's PATH.

For standalone Home Manager, import `homeManagerModules.default` and set `services.open-design` directly using the options shown under `settings`, plus `enable = true`. The NixOS wrapper imports that module for you, so do not import both interfaces into the same Home Manager configuration.

`enable = false` removes the integration's packages, activation step, services, and timer; it does not delete state. `autoStart = false` installs the CLI without declaring services. As user services, these follow the user's systemd session; configure NixOS user lingering separately if they must start before login.

For mesh access, set `webFrontend.host = "0.0.0.0"` and explicitly list browser origins in `webFrontend.allowedOrigins`, for example `[ "http://vd.netbird.cloud:38471" ]`. Allow the web port through the appropriate firewall interface. Keep MCP on loopback unless you deliberately secure and expose it. Origin checks are not authentication; do not expose these services to the public internet without access controls.

Options are defined in [modules/common.nix](modules/common.nix), with NixOS user selection in [modules/nixos.nix](modules/nixos.nix).

## Update the source

Edit the upstream tag on the `source.url` line in `flake.nix`, then run:

```sh
nix flake update source
nix flake check
```

Commit the source pin and lock file, publish to both remotes, then run `nix flake update open-design-flake` in the consuming NixOS repository before rebuilding. Updating a locked tag does not select a newer release tag automatically.

Dependency changes can also require new hashes in `packages/pnpm-deps.nix`, or the pnpm tarball hash in `flake.nix` if upstream changes `packageManager`. These are content hashes, not separate release selections. Review upstream build changes when a bump fails; do not disable lock-file or hash checks.

The initial `open-design-v0.16.1` source tag has root package version `0.15.1`. Package names derive from upstream metadata, so use the locked source revision as well as the daemon's reported version when checking an update.

## Build a local checkout

Clone upstream separately from this repository. To build local changes without replacing the committed source lock:

```sh
git clone https://github.com/nexu-io/open-design.git ../open-design-source
nix build .#daemon .#web \
  --override-input source path:../open-design-source --no-write-lock-file
```

Use `nix develop` for the Node and pnpm versions selected by the source metadata. A checkout with different dependencies needs matching dependency hashes.

## Verification

Verified on x86_64-linux: daemon and web source builds, `nix flake check`, Home Manager and NixOS module evaluation, and an isolated runtime smoke run. The smoke run created a project through Caddy, displayed it in Chromium, listed it through MCP, and retained it after a daemon restart. Disabled configurations declare no Open Design services or timers.

aarch64-linux outputs have been evaluated, not built or run on ARM hardware.

## Repository mirrors

- [GitHub](https://github.com/Fractal-Tess/open-design-flake)
- Gitadel: `ssh://git@neo.netbird.cloud:2222/fractal-tess/open-design-flake.git`

The package recipes adapt upstream's Apache-2.0 Nix build logic. This repository maintains its own copies. See [LICENSE](LICENSE).

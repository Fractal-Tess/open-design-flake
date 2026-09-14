<p align="center">
  <img src="assets/logo.svg" alt="Open Design + Nix" width="480" />
</p>

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
};
```

Keep this input's nixpkgs pin so the package set stays reproducible. The flake backports both fixes from [nodejs/node#65943](https://github.com/nodejs/node/pull/65943) to Node 24: unpatched 24.19 and 24.20 can abort while collecting native SQLite objects. The daemon build exercises SQLite queries and a native PTY together to catch this regression. Remove the backport when the pinned Node release includes both fixes.

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

`source.url` tracks upstream's `main` branch. `flake.lock` pins an exact commit, so builds do not change until you update it:

```sh
nix flake update source
nix flake check
```

Commit the updated lock file, publish to both remotes, then run `nix flake update open-design-flake` in the consuming NixOS repository before rebuilding.

Dependency changes can also require new hashes in `packages/pnpm-deps.nix`, or the pnpm tarball hash in `flake.nix` if upstream changes `packageManager`. These are content hashes, not separate release selections. Review upstream build changes when a bump fails; do not disable lock-file or hash checks.

Package versions derive from upstream metadata. Check the locked source revision as well as the daemon's reported version when verifying an update.

## Build a local checkout

Clone upstream separately from this repository. To build local changes without replacing the committed source lock:

```sh
git clone https://github.com/nexu-io/open-design.git ../open-design-source
nix build .#daemon .#web \
  --override-input source path:../open-design-source --no-write-lock-file
```

Use `nix develop` for the Node and pnpm versions selected by the source metadata. A checkout with different dependencies needs matching dependency hashes.

## Verification

Verified on x86_64-linux: daemon and web source builds, `nix flake check`, Home Manager and NixOS module evaluation, native SQLite queries and PTY processes, and a live NixOS deployment. Project creation, listing, deletion, and restart persistence passed through Caddy. MCP initialization, tool discovery, project listing, and restart recovery passed. Chromium rendered the web frontend and local-agent onboarding. Disabled configurations declare no Open Design services or timers.

AI generation is not covered by these checks. Onboarding requires valid provider credentials; an installed CLI or cached login alone does not establish that its credentials still work.

aarch64-linux outputs have been evaluated, not built or run on ARM hardware.

## Repository mirrors

- [GitHub](https://github.com/Fractal-Tess/open-design-flake)
- Gitadel: `ssh://git@neo.netbird.cloud:2222/fractal-tess/open-design-flake.git`

The package recipes adapt upstream's Apache-2.0 Nix build logic. This repository maintains its own copies. See [LICENSE](LICENSE).

Logo composition: [Open Design](https://github.com/nexu-io/open-design) mark (Apache-2.0) + [Nix snowflake](https://github.com/NixOS/nixos-artwork/tree/master/logo) by Simon Frankau and Tim Cuthbertson ([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)). Original marks resized and arranged for this repository.

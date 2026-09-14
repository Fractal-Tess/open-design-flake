# Adapted from nexu-io/open-design nix/package-daemon.nix at open-design-v0.16.1.
# Copyright 2026 Open Design contributors; SPDX-License-Identifier: Apache-2.0.
{ lib
, stdenv
, nodejs
, pnpm_10
, fetchPnpmDeps
, pnpmConfigHook
, src
, pnpmDepsSrc ? src
, workspacePaths
, makeWrapper
, python3
, gnumake
, pkg-config
,
}:
let
  pname = "open-design-daemon";
  version = (lib.importJSON "${src}/package.json").version;
  pnpmWorkspaceFilters = map (workspacePath: "./${workspacePath}") workspacePaths;
  pnpmDepsHash = (import ./pnpm-deps.nix).daemonHash;
in
stdenv.mkDerivation (finalAttrs: {
  inherit pname version src;

  pnpmWorkspaces = pnpmWorkspaceFilters;

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
    makeWrapper
    python3
    gnumake
    pkg-config
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version;
    src = pnpmDepsSrc;
    hash = pnpmDepsHash;
    pnpm = pnpm_10;
    pnpmWorkspaces = pnpmWorkspaceFilters;
    fetcherVersion = 3;
  };

  env.NODE_ENV = "production";

  buildPhase = ''
    runHook preBuild

    # Rebuild native addons against Nix's Node headers and libraries.
    # Registry prebuilds are not reliable on NixOS.
    export npm_config_nodedir=${nodejs}
    export npm_config_build_from_source=true
    export PATH="${nodejs}/lib/node_modules/npm/bin/node-gyp-bin:$PATH"

    for native in better-sqlite3 node-pty; do
      native_dir=$(realpath "apps/daemon/node_modules/$native")
      ( cd "$native_dir" && node-gyp rebuild --release --build-from-source )
    done
    (
      cd apps/daemon
      # Loading addons alone misses runtime regressions involving statement GC.
      node --input-type=commonjs <<'JS'
      const assert = require("node:assert/strict");
      const db = new (require("better-sqlite3"))(":memory:");
      assert.equal(db.prepare("select 42 as answer").get().answer, 42);
      db.close();
      let output = "";
      const terminal = require("node-pty").spawn(
        "${stdenv.shell}", ["-c", "printf native-pty-ok"],
        { cwd: process.cwd(), env: process.env }
      );
      const deadline = setTimeout(() => {
        terminal.kill();
        process.exit(1);
      }, 10000);
      terminal.onData(data => output += data);
      terminal.onExit(({ exitCode }) => {
        clearTimeout(deadline);
        assert.equal(exitCode, 0);
        assert.match(output, /native-pty-ok/);
        console.log("SQLite query and native PTY spawn passed");
      });
    JS
    )

    pnpm --filter '@open-design/daemon...' --recursive \
      --workspace-concurrency=1 --if-present run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/open-design $out/bin
    cp -r . $out/lib/open-design/

    for target in ${lib.escapeShellArgs workspacePaths}; do
      if [ "$target" = "apps/daemon" ]; then
        find "$out/lib/open-design/$target" -mindepth 1 -maxdepth 1 \
          ! -name dist ! -name bin ! -name node_modules ! -name package.json \
          -exec rm -rf {} +
      else
        find "$out/lib/open-design/$target" -mindepth 1 -maxdepth 1 \
          ! -name dist ! -name node_modules ! -name package.json \
          -exec rm -rf {} +
      fi
    done

    # Root development workspaces are not included in this filtered source.
    rm -f \
      $out/lib/open-design/node_modules/@open-design/components \
      $out/lib/open-design/node_modules/@open-design/tools-dev \
      $out/lib/open-design/node_modules/@open-design/tools-pack \
      $out/lib/open-design/node_modules/@open-design/tools-release \
      $out/lib/open-design/node_modules/@open-design/tools-serve \
      $out/lib/open-design/node_modules/.bin/tools-dev \
      $out/lib/open-design/node_modules/.bin/tools-pack \
      $out/lib/open-design/node_modules/.bin/tools-release \
      $out/lib/open-design/node_modules/.bin/tools-serve

    chmod +x $out/lib/open-design/apps/daemon/dist/cli.js
    makeWrapper ${nodejs}/bin/node $out/bin/od \
      --add-flags $out/lib/open-design/apps/daemon/dist/cli.js \
      --set NODE_ENV production
    runHook postInstall
  '';

  passthru = {
    inherit nodejs;
    pnpmDeps = finalAttrs.pnpmDeps;
  };

  meta = with lib; {
    description = "Open Design daemon — local agent orchestrator + API (od CLI)";
    homepage = "https://github.com/nexu-io/open-design";
    license = licenses.asl20;
    mainProgram = "od";
    platforms = platforms.linux;
  };
})

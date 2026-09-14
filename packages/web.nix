# Adapted from nexu-io/open-design nix/package-web.nix at open-design-v0.16.1.
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
,
}:
let
  pname = "open-design-web";
  version = (lib.importJSON "${src}/package.json").version;
  pnpmWorkspaceFilters = map (workspacePath: "./${workspacePath}") workspacePaths;
  dependencyBuildPaths = lib.filter (workspacePath: workspacePath != "apps/web") workspacePaths;
  pnpmDepsHash = (import ./pnpm-deps.nix).webHash;
in
stdenv.mkDerivation (finalAttrs: {
  inherit pname version src;

  pnpmWorkspaces = pnpmWorkspaceFilters;

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version;
    src = pnpmDepsSrc;
    hash = pnpmDepsHash;
    pnpm = pnpm_10;
    pnpmWorkspaces = pnpmWorkspaceFilters;
    fetcherVersion = 3;
  };

  env = {
    NODE_ENV = "production";
    # Keep the export same-origin; the serving module proxies API paths.
    OD_DAEMON_URL = "";
  };

  buildPhase = ''
    runHook preBuild
    for target in ${lib.escapeShellArgs dependencyBuildPaths}; do
      pnpm -C "$target" run --if-present build
    done
    pnpm --filter @open-design/web run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r apps/web/out/. $out/
    runHook postInstall
  '';

  passthru = {
    inherit nodejs;
    pnpmDeps = finalAttrs.pnpmDeps;
  };

  meta = with lib; {
    description = "Open Design — Next.js static SPA (apps/web)";
    homepage = "https://github.com/nexu-io/open-design";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
})

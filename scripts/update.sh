#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MAX_HASH_REPAIRS=12

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

repair_hash_mismatch() {
  local output="$1"
  local specified got
  local -a matches

  specified="$(sed -nE 's/^[[:space:]]*specified:[[:space:]]*(sha(256|512)-[^[:space:]]+).*$/\1/p' <<<"$output" | head -n 1)"
  got="$(sed -nE 's/^[[:space:]]*got:[[:space:]]*(sha(256|512)-[^[:space:]]+).*$/\1/p' <<<"$output" | head -n 1)"

  [[ -n "$specified" && -n "$got" ]] || return 1
  mapfile -t matches < <(grep -rlF --include='*.nix' "$specified" .)

  if [[ "${#matches[@]}" -ne 1 ]]; then
    fail "expected one Nix file containing $specified, found ${#matches[@]}"
  fi

  printf 'Refreshing dependency hash in %s\n' "${matches[0]}"
  sed -i "s|${specified}|${got}|g" "${matches[0]}"
}

validate_and_repair() {
  local attempt output status

  for ((attempt = 0; attempt <= MAX_HASH_REPAIRS; attempt++)); do
    set +e
    output="$(nix flake check --print-build-logs 2>&1)"
    status=$?
    set -e
    printf '%s\n' "$output"

    if [[ "$status" -eq 0 ]]; then
      return 0
    fi

    if [[ "$attempt" -eq "$MAX_HASH_REPAIRS" ]] || ! repair_hash_mismatch "$output"; then
      fail "flake validation failed"
    fi
  done
}

main() {
  local before after version
  local -a nix_files

  cd "$ROOT_DIR"
  before="$(jq -r '.nodes.source.locked.rev' flake.lock)"
  nix flake update source
  after="$(jq -r '.nodes.source.locked.rev' flake.lock)"

  printf 'Upstream source: %s -> %s\n' "$before" "$after"
  if [[ "$before" == "$after" ]]; then
    printf 'Already up to date.\n'
    exit 0
  fi

  validate_and_repair
  mapfile -t nix_files < <(find . -type f -name '*.nix' -not -path './.git/*' | sort)
  nix fmt "${nix_files[@]}"
  validate_and_repair

  version="$(nix eval --raw .#packages.x86_64-linux.default.version)"
  printf 'Updated and validated package version %s.\n' "$version"
}

main "$@"


#!/usr/bin/env bash
# Fetches the two libraries the contracts and tests are built against.
# They are pinned by tag and are not part of this repository.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p lib
[ -d lib/forge-std ] || git clone --depth 1 --branch v1.9.7 https://github.com/foundry-rs/forge-std lib/forge-std
[ -d lib/openzeppelin-contracts ] || git clone --depth 1 --branch v5.3.0 https://github.com/OpenZeppelin/openzeppelin-contracts lib/openzeppelin-contracts
echo "libraries ready"

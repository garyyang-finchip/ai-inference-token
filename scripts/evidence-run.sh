#!/usr/bin/env bash
# Runs the two worked cases of the specification on a network and records the result.
#
#   bash scripts/evidence-run.sh <anvil|sepolia>
#
#   DEPLOYER_PK   key of the funded deployer; every other account of the run is derived from it
#   RPC_URL       JSON-RPC endpoint of the network (SEPOLIA_RPC_URL is accepted as well)
#   TIP_WEI       priority fee per gas, default 200000000 (0.2 gwei)
#
# deployments/<network>/plan.json must exist. It is written by `node tools/aito.mjs plan <network>`
# and fixes the accounts, records and series of the run. The run writes state.json and
# evidence.json next to it. Gas limits come from the node, never from a local simulation.
# Nothing is sent unless the deployer balance covers the whole run. If a run stops half way,
# run the same command again: it starts over with fresh contracts.
set -euo pipefail

NETWORK="${1:-anvil}"
RPC_URL="${RPC_URL:-${SEPOLIA_RPC_URL:-}}"
: "${DEPLOYER_PK:?set DEPLOYER_PK}"
: "${RPC_URL:?set RPC_URL}"
export NETWORK RPC_URL
cd "$(dirname "$0")/.."

PLAN="deployments/$NETWORK/plan.json"
[ -f "$PLAN" ] || { echo "missing $PLAN"; exit 1; }
[ -d lib/forge-std ] || bash scripts/setup.sh

DEPLOYER="$(cast wallet address --private-key "$DEPLOYER_PK")"
BASE="$(cast base-fee --rpc-url "$RPC_URL")"
TIP="${TIP_WEI:-200000000}"
if [ "${#BASE}" -gt 10 ]; then
  echo "the base fee of $BASE wei is far above normal for a test network; try again later"
  exit 1
fi
# Every transaction of the run is sent with this fee cap: twice the base fee plus the tip.
MAXFEE=$(( BASE * 2 + TIP ))
export GAS_PRICE_WEI="$MAXFEE"

# Gas each account of the run is funded for. The figures are sized for networks that price
# state creation at 1,530 gas per byte (EIP-8037), where the run uses about 65,600,000 gas:
# 48,700,000 by the deployer (three contracts, of which the ledger alone 34,000,000),
# 8,000,000 each by the two issuers and under 1,000,000 by the other accounts.
# Networks without that pricing use about 11,300,000 in total.
export GAS_SUPPLIER=20000000 GAS_ALPHA=20000000 GAS_DISTRIBUTOR=800000 GAS_HOLDER=2000000 GAS_HOLDER2=800000
ACTOR_GAS=$(( GAS_SUPPLIER + GAS_ALPHA + GAS_DISTRIBUTOR + GAS_HOLDER + GAS_HOLDER2 ))
OWN_GAS=70000000
NEED=$(( (ACTOR_GAS + OWN_GAS) * MAXFEE ))
HAVE="$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")"
echo "network   $NETWORK"
echo "deployer  $DEPLOYER"
echo "base fee  $BASE wei, tip $TIP wei, fee cap $MAXFEE wei per gas"
echo "balance   $HAVE wei"
echo "budget    $NEED wei"
if [ "${#HAVE}" -lt "${#NEED}" ] || { [ "${#HAVE}" -eq "${#NEED}" ] && [ "$HAVE" \< "$NEED" ]; }; then
  echo "the deployer balance is below the budget of this run; nothing was sent"
  echo "fund $DEPLOYER up to the budget and run again"
  exit 1
fi

# The test files are left out of the build: the run does not need them, and building them takes
# more memory than a small server has.
phase() {
  echo "== $1"
  forge script script/AITOEvidence.s.sol --sig "$1()" --rpc-url "$RPC_URL" --skip test --broadcast --slow \
    --skip-simulation --with-gas-price "$MAXFEE" --priority-gas-price "$TIP" --timeout 600
}

phase deploy
phase caseA1

# Case A settles by silence: the objection window of the run is 120 seconds.
if [ "$NETWORK" = "anvil" ]; then
  cast rpc evm_increaseTime 180 --rpc-url "$RPC_URL" > /dev/null
  cast rpc evm_mine --rpc-url "$RPC_URL" > /dev/null
else
  echo "waiting 180 seconds for the objection window"
  sleep 180
fi

phase caseA2
phase caseB

echo "== report"
forge script script/AITOEvidence.s.sol --sig "report()" --rpc-url "$RPC_URL" --skip test
LEFT="$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")"
echo "deployer balance after the run: $LEFT wei"
echo "===== BEGIN deployments/$NETWORK/evidence.json ====="
cat "deployments/$NETWORK/evidence.json"
echo
echo "===== END deployments/$NETWORK/evidence.json ====="

# Sepolia evidence run: how it is made

The run of 2026-11-20 and its results are in [sepolia-evidence.md](sepolia-evidence.md). This page describes the procedure.

The run deploys the reference implementation and executes the two worked cases of the specification on Sepolia. It ends by reading the final state back, checking it against the numbers in the specification, and writing `deployments/sepolia/evidence.json`.

## What the run does

Thirty-three transactions in five steps:

| Phase | What happens | Sent by |
| --- | --- | --- |
| `deploy` | Records registry and ledger are deployed; five accounts of the run receive gas money | deployer |
| `caseA1` | Case A up to the usage claim: records anchored, series created, 1,000,000 units issued, transfer, ERC-20 wrapper deployed, 200,000 wrapped, 50,000 moved in wrapped form and unwrapped, authorization and request signed off chain, hold of 4,000, claim of 6,000 input and 2,100 output | supplier, distributor, holder, holder2, deployer |
| wait | 180 seconds, so that the objection window of 120 seconds passes | |
| `caseA2` | The unobjected claim is finalized: 3,600 deducted, 400 released | deployer |
| `caseB` | Case B, whole: an agent issues against its own capacity, a second agent holds units, a third consumes under authorization and accepts the claim by signature: 1,800 deducted, 1,200 released | alpha, deployer |
| `report` | Reads the state, checks it, writes `evidence.json` | read only |

## Accounts

Every account of the run is derived from the deployer key, so only one account is funded by hand.

| Role | Address |
| --- | --- |
| deployer | `0x745a127396A148865A0d54e5bA4fc0c2C35C48aC` |
| supplier (Case A issuer, responsible party, fulfiller) | `0x5154bd2f129b9c4500964edE47696CAF05Ef3106` |
| distributor | `0xaeE302e28750a8D978F4B75b308E77BAfBA06b9e` |
| holder | `0xcEc7648a5567A5fA32117693439dd864293622dd` |
| holder2 | `0x1d05393b791Fe05cf289401cc47ccd946E9Dc37C` |
| consumer (Case A) | `0x9b5219392E78fcac788E3757458255FDCc86cCc2` |
| alpha (Case B issuer, responsible party, fulfiller) | `0x41BB1EfE9B83060407BC5082712c2107791EEB4f` |
| beta (Case B holder) | `0x054f08d3128B5Ba17Ed0e09BB5e831c0F05CA9c8` |
| gamma (Case B consumer) | `0x33A0bb457222204c9bA06b9D92755ADbc1a97AEd` |

The deployer key is not in this repository. It is a throwaway key for this test network only.

The first run from this deployer landed the contracts at:

| Contract | Address |
| --- | --- |
| AITORecords | `0x7863F072581A96C3E147b7e366299EAc49D6E726` |
| AITOLedger | `0xF6c40A9821a8105e550d695B153b64c34b2f89Ca` |
| AITOWrapper20 (Case A) | `0xb3428103825aDDE885036ab01c84a85E9a4bAE01` |

A run that is started again deploys fresh contracts at other addresses.

## Cost

Sepolia prices state creation at 1,530 gas per byte (EIP-8037, active there since the Glamsterdam upgrade of October 2026). Under that pricing the run uses about 65,600,000 gas: 48,700,000 by the deployer, of which the ledger deployment alone is 34,000,000, about 8,000,000 by each of the two issuers, and under 1,000,000 by the other accounts.

The driver sends every transaction with a fixed tip (0.2 gwei unless `TIP_WEI` says otherwise) and a fee cap of twice the base fee plus the tip. Before sending anything it checks that the deployer holds 113,600,000 gas at that cap. With a base fee near zero that is about 0.023 ETH, of which about 0.019 ETH is spent. **0.05 Sepolia ETH on the deployer is enough** unless the base fee is above 0.1 gwei.

## Validity of the plan

`deployments/sepolia/plan.json` fixes the records and series of the run. Its series are valid from 2026-11-19 00:00 UTC; the Case B series expires on 2026-12-19 00:00 UTC. Run before 2026-12-18. After that a new plan is needed (`node tools/aito.mjs plan sepolia` with `DEPLOYER_PK` set, then commit the regenerated `deployments/sepolia`).

The record documents of the run are served from this repository under `deployments/sepolia/records/`. They must be on the `main` branch before the run, because their locations are anchored on chain.

## Steps

Requires Foundry (forge and cast, 1.7.1 or later) and git. Node is not needed for the run. The driver builds the contracts and the script without the test files, which takes about 300 MB of memory.

```sh
git clone https://github.com/garyyang-finchip/ai-inference-token.git
cd ai-inference-token
forge --version
bash scripts/setup.sh
```

Create the environment file outside the repository. It holds the deployer key and the RPC endpoint:

```sh
cat > ~/aito.env <<'EOF'
export DEPLOYER_PK=<deployer key>
export SEPOLIA_RPC_URL=<Sepolia JSON-RPC endpoint>
EOF
chmod 600 ~/aito.env
```

Run:

```sh
source ~/aito.env
bash scripts/evidence-run.sh sepolia
```

The run takes about fifteen minutes. It prints the phases as they go and, at the end, the content of `deployments/sepolia/evidence.json` between two marker lines. That block is the result to keep.

## If something goes wrong

| What the driver prints | What to do |
| --- | --- |
| `the deployer balance is below the budget of this run; nothing was sent` | Nothing happened. Send more Sepolia ETH to the deployer, up to the printed budget, and run again |
| `the base fee ... is far above normal` | Nothing happened. Try again later |
| A phase stops with a timeout | A transaction was not included in ten minutes. Run again with a higher tip, for example `TIP_WEI=1000000000 bash scripts/evidence-run.sh sepolia`; the budget rises in proportion |
| A phase stops with another error | Keep the output. Running the same command again starts over with fresh contracts, provided the deployer still holds the budget |
| `plan is for another deployer key` | `DEPLOYER_PK` is not the key the plan was made for |

## After the run

1. Keep the printed evidence block and commit it as `deployments/sepolia/evidence.json`.
2. The README deployments table and the discussion topic are updated with the addresses.
3. Optional: verify the three contracts on a block explorer. The compiler settings are in `foundry.toml` (solc 0.8.28, optimizer 200 runs, `via_ir`, EVM version cancun, no metadata hash).

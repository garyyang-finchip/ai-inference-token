# Changelog

## 0.2.0 (2026-11-20)

- Sepolia evidence run: both worked cases executed in 33 transactions; `deployments/sepolia/evidence.json`, `docs/sepolia-evidence.md`, README deployments table.
- Runbook commits `evidence.json` only.

## 0.1.2 (2026-11-20)

- Pull request ethereum/ERCs#2188 linked from the README, the discussion post and the filing runbook.

## 0.1.1 (2026-11-20)

- `discussions-to` set to Ethereum Magicians topic 30453.
- Repository name corrected to `ai-inference-token` in the Sepolia plan record locations, the record tool, the runbooks and the discussion post.
- Opening sentence of the discussion post reworded.

## 0.1.0 (2026-11-20)

First package.

- Specification draft `ERCS/erc-9999.md` with placeholder number: five core objects, three optional modules, series, authorized consumption with hold, settlement and release, native ERC-1155 binding, ERC-20 wrapper, periodic allowance and reserved capacity profiles as critical extensions, eleven invariants.
- Reference implementation: `AITOLedger` (core, stock quota, native ERC-1155 binding), `AITOWrapper20`, `AITORecords`. The two optional profiles are specified and not implemented.
- 98 Foundry tests: series, consumption, wrapper, records, four worked cases, invariants, vectors.
- JSON Schemas of the eight record kinds, example records, vectors from an independent implementation (`tools/aito.mjs`), model of the two profile state examples (`tools/profile_examples.py`).
- Evidence run for a live network (`script/AITOEvidence.s.sol`, `scripts/evidence-run.sh`) and the plan for Sepolia.
- Filing package builder with consistency checks (`scripts/make-filing-package.py`), filing and Sepolia runbooks, discussion post draft, design note on pooling.

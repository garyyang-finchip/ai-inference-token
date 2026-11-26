# Changelog

## 0.4.0 (2026-11-27)

Specification revision 2, after posts #5, #9 and #10 of the discussion topic. No interface, contract, record or vector change; the Sepolia deployment stays valid.

- Section 5.4: an acceptance extension adds conditions and does not replace the series' acceptance rule, which applies when the extension's conditions are not met; it never raises a deduction above the claimed amount of section 5.3 and may lower it; it may define the structure of the evidence commitment and names the parties it relies on in its parameters; an extension that changes when a request can end states the resulting release horizon.
- Section 5.5: the three deadlines of a request (claim, acceptance, resolution), the release horizon (`holdUntil`, plus `objectionWindow` under optimistic acceptance, plus `resolutionWindow` with a resolver; at most `maxHoldDuration + objectionWindow + resolutionWindow` after the hold), and a recommendation that signing interfaces show it, including when it passes `validUntil`.
- Security Considerations: the paragraph on holds now separates the amount at stake from the time units can stay held.
- Rationale: why acceptance extensions add conditions and leave the base rule in place.
- Case B: how an acceptance extension with observer statements and a Method could strengthen its evidence.
- Two tests of the release horizon (100 tests in total): a claim at `holdUntil` that is disputed and left undecided can be released by anyone only after `holdUntil + objectionWindow + resolutionWindow`; without a resolver the holder finalizes after the objection window.

## 0.3.1 (2026-11-26)

- ERC-8506 merged into ethereum/ERCs as a Draft on 2026-11-25 (pull request #2188, commit 5c77458); the merged files are byte-identical to `ercs-pr-package/`. README points at the official page https://eips.ethereum.org/EIPS/eip-8506.
- `docs/filing-runbook.md`: the renumbering steps now name the placeholder files correctly, and a section describes update pull requests after the merge.

## 0.3.0 (2026-11-22)

- Number assigned: ERC-8506. `ERCS/erc-9999.md` becomes `ERCS/erc-8506.md`, `assets/erc-9999/` becomes `assets/erc-8506/`, and every path that referred to them follows (specification links, schema identifiers, tests, scripts, tools, README, runbooks). Record identifiers, series identifiers and vectors are unchanged, so the Sepolia evidence stays valid.
- Discussion topic retitled to ERC-8506.

## 0.2.1 (2026-11-20)

- Specification revision 1, after the first discussion question: section 5.3 states that a claim is public from the moment it is recorded; section 5.4 states when the objection window starts, that an objection needs no evidence, how unavailable evidence is treated, and what optimistic acceptance settles when nobody objects; a matching Security Considerations paragraph. No interface or contract change; the reference ledger already refuses an optimistic series with a zero objection window.

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

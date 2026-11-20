# Ethereum Magicians first post

Category: ERCs

Posted as topic 30453: https://ethereum-magicians.org/t/draft-erc-ai-inference-token-onchain-aito-consumable-entitlements-to-ai-inference-supply-with-metering-authorized-consumption-and-settlement/30453

Title:

```text
Draft ERC: AI Inference Token Onchain (AITO) - consumable entitlements to AI inference supply, with metering, authorized consumption and settlement
```

When the number is assigned the title becomes `ERC-<N>: AI Inference Token Onchain`.

Body, everything below the line:

---

This topic is the discussion thread for a draft ERC, **AI Inference Token Onchain (AITO)**.

## Summary

AITO is a framework for holding, transferring and consuming entitlements to AI inference supply on chain.

The "token" in the name is the inference token, the unit in which inference usage is counted. It is the denomination of the entitlement, not a blockchain token. An AITO unit expresses, under a versioned execution specification, metering rules and delivery conditions, an authorizable and consumable entitlement to AI inference supply. Entitlements that meet their transfer conditions are held and circulated through ERC-1155 and ERC-20 tokens.

The draft fixes no price, no conversion rate between suppliers and no ranking of quality. It tries to make five things explicit and checkable: what is counted, what is promised, who owes it, who may consume it, and what was consumed.

## Why

Inference supply is what agents run on. Today it is bought as account credit inside one provider. Attempts to put it on chain keep meeting the same problems:

- A token count is not yet a quantity. Tokenizers differ, reasoning tokens may be billed without being shown, cached input is charged at another rate.
- Equal counts stand for unequal supply: different models, quantizations, configurations, context limits, latencies and retention terms.
- Supply passes through resellers, and a holder cannot see who owes it or on what ground units were issued.
- A prepaid entitlement is a liability of its supplier, and nothing shows whether more was sold than can be delivered.
- Usage is mistaken for an asset. A log of tokens already generated is a record of the past, not a source of new supply.

## What the draft specifies

- **Five core objects.** Unit (what is counted and how), Grade (what is promised, as a versioned set of specifications, conditions and constraints with no global ordering), Source (who issues, who owes supply, on which declared issuance basis), Instrument (a series whose every term is part of its identifier) and Receipt (claim, evidence, acceptance and settlement effect of one request, kept apart).
- **Three optional modules.** Method (typed measurement, calibration and conversion methods, pinned by application), Assessment (who found what under which conditions) and Token Binding.
- **Consumption.** A holder's authorization is a ceiling and reserves nothing. It is never inferred from a transfer allowance or an operator approval. A hold reserves units for one logical request. The ledger computes the deduction from the reported usage, the outcome class and the series schedule, bounded by the hold. A settlement deducts what was accepted and releases the rest, once per logical request.
- **Three acceptance rules**, named in the terms so that a holder knows which applies before buying: consumer co-signature, optimistic acceptance with an objection window, and provider metering.
- **Token binding.** A native ERC-1155 binding in which the balance is the available amount, and an ERC-20 wrapper. Wrapped units are unwrapped before they are consumed, so there is one consumption path per series and no unit can be exercised twice.
- **Two optional entitlement profiles**, periodic allowance and reserved capacity, as critical extensions with worked state examples.
- **Critical extensions.** A party that does not understand a critical extension of a series does not perform an operation the extension can affect.
- **A rule that a receipt is not a ground for issuance.** A record of past usage alone gives nobody the power to issue new unconsumed entitlements.

## What it leaves out

Prices, market making, indices, cash-settled derivatives, proof systems for inference, and the legal classification of an entitlement. Pooling of several suppliers under one redemption promise is not in this version; the draft only records the constraints a later profile has to meet.

## Reference implementation

Repository:

https://github.com/garyyang-finchip/ai-inference-token

- `AITOLedger` (core and native ERC-1155 binding), `AITOWrapper20` and `AITORecords`, with no owner, no upgrade path and no privileged account.
- 98 Foundry tests: unit tests, two worked cases end to end, fuzz tests and invariant tests.
- JSON Schemas for the eight record kinds, example records, and vectors produced by a second implementation outside Solidity and replayed against the contracts.
- The two optional profiles are specified only. The reference ledger does not implement them and does not report them.

A Sepolia deployment with both worked cases executed will be added to this topic.

Pull request: https://github.com/ethereum/ERCs/pull/2188

## Questions I would like feedback on

1. **Record format.** Records are JSON documents in RFC 8785 canonical form, identified by keccak256, with only the terms a ledger enforces held on chain. Is that the right split between chain and documents?
2. **Acceptance rules.** Are co-signature, optimistic acceptance and provider metering the right base set? Evidence from attested hardware or proofs is classified by the proposition it supports and can enter as a further acceptance rule through a critical extension. Should one of those be in the base set?
3. **Cost of a request.** Each request leaves a record on the home ledger. Where state creation is expensive this dominates the cost, so the draft allows cumulative settlement under one request key. Is that enough guidance, or should a session profile be specified?
4. **Other carriers.** The binding interface is independent of the token interface. Is there interest in bindings for ERC-3525 or ERC-6909?
5. **Periodic rights.** The first periodic profile forbids transfer of active rights and makes activation effective at the next period boundary. That is simple and it rules out resetting a used allowance by changing hands. Is it too strict for real subscriptions?
6. **Pools.** A pool that promises supply under one specification is a new series whose responsible party is the pool. Before any issuance it has to fix what holders may demand, which qualifying reserves it holds, and who makes up a shortfall up to what amount. What else has to be fixed?

Thank you for reading. Comments on any part are welcome.

# Design note: unified redemption across several suppliers

Status: not part of version 0.1. Nothing in this note is implemented or specified normatively. It records the constraints a later profile has to meet and one worked illustration, so that the first version does not close any door.

## Two products that must not be confused

| | Basket share | Unified redemption instrument |
| --- | --- | --- |
| What the holder has | A proportional claim on whatever the basket holds | A right to inference supply under one stated specification |
| What a unit stands for | A share of the underlying entitlements | A fixed denomination under one Unit and one Grade |
| Who owes supply | Each underlying supplier, to the basket | The pool, to the holder |
| In this framework | A Token Binding over several series | A new series whose responsible party is the pool and whose issuance basis is the pool |

A basket share is presented as a share. It is not presented as an entitlement with a fixed denomination, because what it stands for changes with the basket.

## What a pool profile has to fix before any issuance

A statement such as "liability is limited to current qualifying coverage and declared guarantees" mixes three things. They are separate terms.

| Term | What it states |
| --- | --- |
| Holder rights | What a holder may demand: how much inference supply, under which specification |
| Qualifying reserves | Which underlying entitlements the pool holds at a given time that meet the conditions and can be used for redemption |
| Guarantor liability | Who makes up a shortfall, under which conditions, and up to what amount |

A ceiling on a guarantee limits the guarantor's additional liability. A fall in reserves does not rewrite what holders were promised. If 100 units were promised and qualifying supply for 40 remains, the pool records a shortfall and handles it as its terms say. It does not silently restate the denomination as 40 and mark the obligation as met.

Limited recourse, pro-rata allocation and holders bearing underlying risk are all legitimate designs, when they are stated beforehand:

- how a shortfall is shared;
- how the undelivered part is recorded and handled;
- whether holders keep rights against the original suppliers;
- when new issuance and new consumption stop;
- whether an exit delivers underlying units, actual inference, or something else that was agreed.

## Four questions a pool answers in order

1. **Admission.** Does this underlying series satisfy every hard condition of the redemption specification? A condition that is unknown is not satisfied. An Assessment that found no breach does not replace an obligation the supplier never took on.
2. **Measurement.** At what rate does an admitted series count toward coverage? This is a Method Application with pinned workload, budget, quality requirement, delivery constraint, subjects, inputs and validity.
3. **Combined behaviour.** Does the pool itself claim anything a single underlying series does not, such as availability through failover? Every such claim needs its own combination Method, mechanism and evidence.
4. **Liability.** Who handles a shortfall, as in the table above.

Admission precedes measurement. No conversion coefficient admits a supply that fails a hard condition.

## Illustration

Two suppliers with different native Units enter one pool. The numbers are an illustration of the mechanics, not a specification.

Redemption specification P: execution object kind `qualifying-pool`; four hard conditions, none compensable: requests and outputs are not retained, as an obligation in the underlying terms; context of at least 128,000 tokens; a third-party capability Assessment no older than 90 days; issuance basis of own capacity or reserved upstream capacity.

Reference unit: one thousandth of the computation an admitted supply needs on average to complete one task of a pinned workload D under budget B, quality requirement Q and delivery constraint S.

| Step | What happens | Numbers |
| --- | --- | --- |
| Admission | The pool checks the terms and records of series X and series Y against the four conditions and records the result | Both admitted |
| Measurement | A Method Application pins D, B, Q, S, both execution objects and both Assessments | One task costs 1,250 units of X or 800 units of Y: coefficients 1.25 and 0.80 |
| Deposit | The suppliers deposit underlying units; the pool becomes their holder | 12,500,000 of X and 8,000,000 of Y, each worth 10,000,000 reference units |
| Issuance | The pool creates series V with itself as responsible party and issues against coverage | 20,000,000 V |
| Request | A consumer's request r reserves V; the pool routes it to X and reserves X under the same request identifier | 4,000 V held; 4,000 x 1.25 = 5,000 X held |
| Claim | X claims 6,000 input and 2,100 output under its own schedule (output 1, input 0.25) | 3,600 X |
| Settlement | Both ledgers settle once, under the same logical request | X: 3,600 deducted, 1,400 released. V: 3,600 / 1.25 = 2,880 deducted, 1,120 released |

If X then fails while the pool still holds 6,000,000 units of X (worth 4,800,000) and Y covers 7,000,000 against 11,800,000 V outstanding, there is a shortfall of 4,800,000. What happens next is exactly what the three terms above have to say. One possible design keeps the holders' claim on the pool for the full amount, records 4,800,000 as undelivered, stops new issuance, routes consumption to Y pro rata, and passes the pool's claim against X to holders in kind. Another names a guarantor up to a stated amount. A pool whose terms said nothing would be outside the profile.

## Why it is not in version 0.1

The core has to be shown to work with one supplier per series first: issuance against a declared basis, transfer, wrapping, authorized consumption and one-time settlement. A pool adds a second ledger effect per request, an admission process, a measurement that expires and a liability structure. Each of those is a place where a holder can be misled, and the profile should be written when the single-supplier core has been reviewed.

A common Unit and Grade do not need a pool. Two suppliers can issue under the same reference Unit and Grade today, and their series are comparable without being one obligation (`test_caseD_sameGradeTwoSuppliersTwoSeries`).

# Sepolia evidence run

The two worked cases of the specification were executed on Sepolia (chain id 11155111) on 2026-11-20, in blocks 12172538 to 12172585, with the reference implementation at commit `0.1.1` of this repository and the plan in [deployments/sepolia/plan.json](../deployments/sepolia/plan.json). The final state was read back at block 12172585 and checked against the numbers of the specification; the result is [deployments/sepolia/evidence.json](../deployments/sepolia/evidence.json).

## Contracts

| Contract | Address | Created in |
| --- | --- | --- |
| AITORecords | [`0x7863F072581A96C3E147b7e366299EAc49D6E726`](https://eth-sepolia.blockscout.com/address/0x7863F072581A96C3E147b7e366299EAc49D6E726) | [tx 1](https://eth-sepolia.blockscout.com/tx/0x0dbad415b7ef7e6162e82745b2a7423493bd917e8e8bc4fe2c8892138d0cd4f2) |
| AITOLedger | [`0xF6c40A9821a8105e550d695B153b64c34b2f89Ca`](https://eth-sepolia.blockscout.com/address/0xF6c40A9821a8105e550d695B153b64c34b2f89Ca) | [tx 2](https://eth-sepolia.blockscout.com/tx/0x082f621c1459432f1eb2eae413cebba0cf20e3f3dc1ff640c5184dc4027bcc9c) |
| AITOWrapper20 (series A) | [`0xb3428103825aDDE885036ab01c84a85E9a4bAE01`](https://eth-sepolia.blockscout.com/address/0xb3428103825aDDE885036ab01c84a85E9a4bAE01) | [tx 16](https://eth-sepolia.blockscout.com/tx/0x0284e72758512a857cf26af5ab937a21b50f2886078b988750d98c340dd23c01) |

Deployer: `0x745a127396A148865A0d54e5bA4fc0c2C35C48aC`. The other accounts of the run are listed in [sepolia-runbook.md](sepolia-runbook.md). The ledger has no owner and no privileged account; the deployer holds no special role in it.

## Series

| | Case A | Case B |
| --- | --- | --- |
| Series id | `0xe81d8009c13d9ab0e3800147df27036f56af9ec4cecd6650e20442e9383597f7` | `0xb4849bc81c5339c2f2ed14bfcfff2f514ad23f622c386d413ece4bc1a458b576` |
| Request key | `0x89d56ece6fd79bea33b4b324a45a4d51d9432364edd739ba3950fb50c91dfd54` | `0x95f06e9ac957405b8c1d6793e83bdb9f674b07597ebf851e0d10183ac192a913` |
| Claim hash | `0xab2052c9c15ac9a7148413b4e825ad783849e8d5da405f3230fd92bd229d75c6` | `0x8b8575fb9ee4cc32063dbacd657fef2380978f6a116a1afdf52a83c3eb40c5a4` |
| Receipt hash | `0xf7dce22b4219c61a930fae6fdc4bdd30c800dbe7b74c40baeecc8d7d19deafea` | `0x73ea5ad7996fa61e1170be7f0d1e8cf2872ad74aa0cbf86952b40b2f8b52320c` |

The series ids equal those computed off chain in the plan, which confirms the series identifier rule across the two implementations.

## Final state

| Quantity | Case A | Expected | Case B | Expected |
| --- | --- | --- | --- | --- |
| Issued | 1,000,000 | 1,000,000 | 1,000,000 | 1,000,000 |
| Held for the request | 4,000 | 4,000 | 3,000 | 3,000 |
| Deducted | 3,600 | 3,600 | 1,800 | 1,800 |
| Released | 400 | 400 | 1,200 | 1,200 |
| Consumed (series total) | 3,600 | 3,600 | 1,800 | 1,800 |
| Distributor available | 700,000 | 700,000 | | |
| Holder available | 100,000 | 100,000 | | |
| Holder2 available | 46,400 | 46,400 | | |
| Units locked in the wrapper | 150,000 | 150,000 | | |
| Alpha available | | | 800,000 | 800,000 |
| Beta available | | | 198,200 | 198,200 |
| Authorization in use | | | 1,800 | 1,800 |

Case A accounting: 700,000 + 100,000 + 46,400 available + 150,000 locked + 3,600 consumed = 1,000,000 issued. Case B: 800,000 + 198,200 + 1,800 = 1,000,000.

## Transactions

Thirty-three transactions, 65,335,315 gas, 0.013067 ETH at a fee of about 0.2 gwei per gas. Gas figures are what Sepolia charged under its state-creation pricing (EIP-8037); they match the local measurement in the README within a few hundred gas per transaction.

| # | Step | Call | Block | Gas | Transaction |
| --- | --- | --- | --- | --- | --- |
| 1 | Deploy AITORecords | `create AITORecords` | 12172538 | 3,925,289 | [0x0dbad415...d4f2](https://eth-sepolia.blockscout.com/tx/0x0dbad415b7ef7e6162e82745b2a7423493bd917e8e8bc4fe2c8892138d0cd4f2) |
| 2 | Deploy AITOLedger | `create AITOLedger` | 12172539 | 33,980,594 | [0x082f621c...cc9c](https://eth-sepolia.blockscout.com/tx/0x082f621c1459432f1eb2eae413cebba0cf20e3f3dc1ff640c5184dc4027bcc9c) |
| 3 | Fund supplier | `transfer` | 12172540 | 204,600 | [0x645f3f69...3695](https://eth-sepolia.blockscout.com/tx/0x645f3f69e51d20aa1b3199ebfd014cecff17bdab10a358f411c0a5e2e93c3695) |
| 4 | Fund alpha | `transfer` | 12172541 | 204,600 | [0x431ff279...f8c8](https://eth-sepolia.blockscout.com/tx/0x431ff279db78349b54fc57880b37e8a263cd2eda5316ed909945ee4408c9f8c8) |
| 5 | Fund distributor | `transfer` | 12172542 | 204,600 | [0xf6bed8ef...f6ee](https://eth-sepolia.blockscout.com/tx/0xf6bed8efdc772d75f52be644ca8d3025e11902b73b5ae965bfe72a3b3ca8f6ee) |
| 6 | Fund holder | `transfer` | 12172543 | 204,600 | [0x88cafb6d...d2ce](https://eth-sepolia.blockscout.com/tx/0x88cafb6ddcf5334fd3399c5b75944c4cf8bb65cf044316500b228e0b9039d2ce) |
| 7 | Fund holder2 | `transfer` | 12172544 | 204,600 | [0xa435b75c...5713](https://eth-sepolia.blockscout.com/tx/0xa435b75c3bb27963584219bcbfd0c157677ee99c764278c5ede8640884035713) |
| 8 | Anchor Unit (Case A) | `anchor` | 12172545 | 686,135 | [0x80d6526e...f4f5](https://eth-sepolia.blockscout.com/tx/0x80d6526e24ee1bfb1fe743cdc035c0ce134da2ea53ca50a3c927c8f16423f4f5) |
| 9 | Anchor Grade (Case A) | `anchor` | 12172546 | 686,147 | [0x4a448ecd...8564](https://eth-sepolia.blockscout.com/tx/0x4a448ecddbb62b36e9442600ecdab94eab4a7286dd16154c2804eeb94fdf8564) |
| 10 | Anchor Source (Case A) | `anchor` | 12172547 | 686,171 | [0xf0cabb98...6968](https://eth-sepolia.blockscout.com/tx/0xf0cabb980d0f6950e1e44668d2b4e8bb26b2129cacd8802bcdea021590956968) |
| 11 | Anchor Terms (Case A) | `anchor` | 12172548 | 686,159 | [0xec689570...e82f](https://eth-sepolia.blockscout.com/tx/0xec689570cd891eb6a06d7e09397b2098424d9dbddc0a3c302e0b78d73e20e82f) |
| 12 | Create series A | `createSeries` | 12172549 | 3,030,218 | [0x4435fa73...28ea](https://eth-sepolia.blockscout.com/tx/0x4435fa735c0499ddffdee897c706268e51a15654f9301cb9ef4e18eaac1728ea) |
| 13 | Allow supplier as fulfiller | `setFulfiller` | 12172550 | 133,646 | [0x13d3e92a...5cbd](https://eth-sepolia.blockscout.com/tx/0x13d3e92ab38fa46a2f14f3e47b78d95b3226691c0a2478d665e1c34fa45c5cbd) |
| 14 | Issue 1,000,000 to distributor | `issue` | 12172551 | 258,387 | [0x1078be14...2719](https://eth-sepolia.blockscout.com/tx/0x1078be148d905735ca0d5a8c68166e89199f693903126b895558895628722719) |
| 15 | Transfer 300,000 to holder | `safeTransferFrom` | 12172552 | 150,728 | [0xcfcfb2cf...583d](https://eth-sepolia.blockscout.com/tx/0xcfcfb2cffc60eb56ad7024d89b5d50d7dae7e3b2d7b43c4193d63b89b57d583d) |
| 16 | Deploy AITOWrapper20 for series A | `create AITOWrapper20` | 12172553 | 8,663,735 | [0x0284e727...3c01](https://eth-sepolia.blockscout.com/tx/0x0284e72758512a857cf26af5ab937a21b50f2886078b988750d98c340dd23c01) |
| 17 | Wrap 200,000 (holder) | `safeTransferFrom` | 12172554 | 376,784 | [0xb9131138...28ce](https://eth-sepolia.blockscout.com/tx/0xb913113870fe20c0d67a39bc0814a9114231590cb642dd7954bb6b2d34ad28ce) |
| 18 | Transfer 50,000 wrapped to holder2 | `transfer` | 12172555 | 140,689 | [0x1f30a94f...a119](https://eth-sepolia.blockscout.com/tx/0x1f30a94ff83f4fa5e639f16aa6a703e2664293e7e9552e073403d2b1d75ea119) |
| 19 | Unwrap 50,000 (holder2) | `unwrap` | 12172556 | 167,392 | [0x2c90effb...c54b](https://eth-sepolia.blockscout.com/tx/0x2c90effb1558dad79672d3261224d8f39f1adc2ba005aab22cb7521ede05c54b) |
| 20 | Hold 4,000 for request r (consumer C, ceiling 20,000) | `hold` | 12172557 | 1,288,653 | [0xeea9a1e4...86a5](https://eth-sepolia.blockscout.com/tx/0xeea9a1e4bd81ec45824fc384b963b33dc9a2db455c36764b8143f0a0732a86a5) |
| 21 | Claim usage 6,000 input, 2,100 output, completed | `claimUsage` | 12172558 | 501,858 | [0x264ffc69...f11c](https://eth-sepolia.blockscout.com/tx/0x264ffc69ebc0afc2228a1a49861c3385f34cc41772ae80a312c0d1db4c74f11c) |
| 22 | Finalize after the 120 s objection window: 3,600 deducted, 400 released | `finalize` | 12172574 | 530,204 | [0x9eefa01d...dae5](https://eth-sepolia.blockscout.com/tx/0x9eefa01d984977b61c6cd81b384fd743dc753dabc0336a30a1d3f5ba0b4adae5) |
| 23 | Anchor Unit (Case B) | `anchor` | 12172575 | 686,135 | [0x2bdd4949...165e](https://eth-sepolia.blockscout.com/tx/0x2bdd494984784876db794d59b0982beaa70c854c2a1dff79802273dab07e165e) |
| 24 | Anchor Grade (Case B) | `anchor` | 12172576 | 686,159 | [0xd3f4ff91...8acd](https://eth-sepolia.blockscout.com/tx/0xd3f4ff91dab8a12415919aa1a0f7eedbf2390ccad2fb3f7e57a425b5f3ec8acd) |
| 25 | Anchor Source (Case B) | `anchor` | 12172577 | 686,171 | [0x4f3e1448...76c8](https://eth-sepolia.blockscout.com/tx/0x4f3e14481b16f199c14dd701ede3c35390fabe301b285171819cf4c41f6a76c8) |
| 26 | Anchor Terms (Case B) | `anchor` | 12172578 | 686,159 | [0x69dc6de9...87f1](https://eth-sepolia.blockscout.com/tx/0x69dc6de99da544da397c50961e6fc49267ced2f6dcf04a5b12e25c6c460987f1) |
| 27 | Create series B | `createSeries` | 12172579 | 2,808,242 | [0x44339033...8feb](https://eth-sepolia.blockscout.com/tx/0x443390332977135e3fc53e09de3be30b4ebeff9ee3a4b5e924174811be388feb) |
| 28 | Allow alpha as fulfiller | `setFulfiller` | 12172580 | 133,658 | [0x6137a56f...50f7](https://eth-sepolia.blockscout.com/tx/0x6137a56f5ca13d99e43fe1c94f43b81381cb4c71b1f24b082f8b7fe6a63650f7) |
| 29 | Issue 1,000,000 to alpha | `issue` | 12172581 | 255,487 | [0x4f6be792...c586](https://eth-sepolia.blockscout.com/tx/0x4f6be792a1a2a637424467db610dc8c8e81a06e25fe4891a83370bfae959c586) |
| 30 | Transfer 200,000 to beta | `safeTransferFrom` | 12172582 | 150,728 | [0xe331055f...69cb](https://eth-sepolia.blockscout.com/tx/0xe331055facb8e82dfefdf0665eac19096922d3651ce2f0446590fe50d97469cb) |
| 31 | Hold 3,000 for request r1 (consumer gamma, ceiling 50,000) | `hold` | 12172583 | 1,288,641 | [0x343efa67...150a](https://eth-sepolia.blockscout.com/tx/0x343efa67f5dafb78e0a61196a0a5f1115fba6f16645d94ad90cd7b499a31150a) |
| 32 | Claim usage 2,000 input, 1,400 output, completed | `claimUsage` | 12172584 | 498,782 | [0x1c65805c...38bc](https://eth-sepolia.blockscout.com/tx/0x1c65805c2af034628e83ac0257e62d1351f604b40dd2f19a04560a29abc238bc) |
| 33 | Accept by gamma's signature: 1,800 deducted, 1,200 released | `accept` | 12172585 | 539,364 | [0x65801787...1cd7](https://eth-sepolia.blockscout.com/tx/0x658017876c0581a4168c8a7cf601c8e2c5a08773a948346808f7f7e25a4a1cd7) |

Transactions 1 to 7 are the `deploy` phase, 8 to 21 `caseA1`, 22 `caseA2` after the objection window, 23 to 33 `caseB`.

## Independent check

Read back through a block explorer after the run: the ledger at `0xF6c40A9821a8105e550d695B153b64c34b2f89Ca` is a contract created by the deployer in transaction 2, and transaction 22 (`finalize`) succeeded in block 12172574 at 02:52:00 UTC. Anyone can repeat the state reads with the view functions of `IAITOInstrument` and `IAITOConsumption` against the addresses above.

## Reproducing

`bash scripts/evidence-run.sh sepolia` with a funded deployer key repeats the run with fresh contracts; see [sepolia-runbook.md](sepolia-runbook.md). The series of the plan are valid until 2026-12-19 00:00 UTC (Case B) and 2027-02-17 00:00 UTC (Case A).

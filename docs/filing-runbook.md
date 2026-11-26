# Filing with the ERCs repository

The specification is filed as a pull request against `ethereum/ERCs`. The pull request contains the specification and its assets and nothing else. The number ERC-8506 was assigned on 2026-11-21 in the review of the pull request; the files carry it.

## What is filed

`python3 scripts/make-filing-package.py` checks the specification against the files it quotes and writes the package to `ercs-pr-package/`:

| Path in the ERCs repository | Content | Files |
| --- | --- | --- |
| `ERCS/erc-8506.md` | The specification | 1 |
| `assets/erc-8506/contracts/` | Reference implementation: `AITOLedger.sol`, `AITORecords.sol`, `AITOWrapper20.sol` | 3 |
| `assets/erc-8506/contracts/interfaces/` | Types and the six interfaces | 7 |
| `assets/erc-8506/schemas/` | JSON Schemas of the eight record kinds | 8 |
| `assets/erc-8506/examples/` | Records of the worked cases | 13 |
| `assets/erc-8506/vectors/` | Test vectors | 4 |

Thirty-six files. Tests, scripts and tools stay in this repository and are not filed.

The script refuses to write the package when an interface quoted in the specification differs from its file, when a quoted identifier or hash is in no vector file, when a state table differs from the model, when an asset is not linked or a link does not resolve, or when a file is empty or not plain ASCII.

## Order of steps

1. **Repository.** The repository is `github.com/garyyang-finchip/ai-inference-token`. The package has no dotfiles in subdirectories. Shell and Python scripts are run as `bash scripts/<name>.sh` and `python3 scripts/<name>.py`, so they need no executable bit.
2. **Discussion topic.** The topic is open on Ethereum Magicians in the category ERCs; its text is [magicians-post.md](magicians-post.md).
3. **Discussion link.** The `discussions-to` line of the specification carries the topic link. A new topic would be set with `python3 scripts/make-filing-package.py --discussions-to <link>`.
4. **Branch.** In your fork of `ethereum/ERCs`, bring `master` up to date with upstream (Sync fork), then create the branch `add-erc-ai-inference-token-onchain` from `master`.
5. **Upload.** In that branch choose Add file, Upload files, and drop the two folders `ERCS` and `assets` from `ercs-pr-package/`. Commit to the branch with the message `Add ERC: AI Inference Token Onchain`.
6. **Pull request.** Open a pull request from the branch to `ethereum/ERCs` `master`. Filed as https://github.com/ethereum/ERCs/pull/2188 from the branch `add-erc-ai-token`.

    Title:

    ```text
    Add ERC: AI Inference Token Onchain
    ```

    Description:

    ```text
    Adds a draft ERC, AI Inference Token Onchain (AITO): a framework for holding,
    transferring and consuming entitlements to AI inference supply.

    - Specification: ERCS/erc-9999.md (placeholder number at the time of filing)
    - Assets: interfaces and reference implementation, JSON Schemas of the record
      kinds, example records and test vectors
    - Discussion: <link of the topic>
    - Reference repository with tests:
      https://github.com/garyyang-finchip/ai-inference-token
    ```

7. **Checks.** The pull request runs the ERCs validator, the Markdown linter, the spell checker and the link checker. The specification passes the first three locally with the configuration of the ERCs repository; the link checker needs the pull request itself.

## When the number was assigned

An editor assigns the number in a review comment on the specification file. For this proposal that happened on 2026-11-21: ERC-8506. The steps below were carried out once on 2026-11-22 and are kept for reference; `<N>` was 8506 and the placeholder was 9999.

1. Run `python3 scripts/make-filing-package.py --number <N> --discussions-to <link>`.
2. In the pull request branch, delete `ERCS/erc-9999.md` and `assets/erc-9999/` and upload `ERCS/erc-<N>.md` and `assets/erc-<N>/` from the regenerated package.
3. Rename the discussion topic to `ERC-<N>: AI Inference Token Onchain (AITO)` and point `discussions-to` at the retitled link.
4. When the checks are green, answer inside the editor's review conversation and resolve it. Leave the pull request title as `Add ERC: <title>`; the review bot sets that form itself when it merges.
5. In this repository, rename `ERCS/erc-9999.md` and `assets/erc-9999/` to the assigned number and replace `erc-9999` and `eip-9999` in the paths used by `foundry.toml`, the tests, the script, the tools and the schema identifiers. Record identifiers and vectors do not depend on the number, so on-chain evidence stays valid.

A new ERC file is merged only after one approving review from an ERC editor; the review bot requests it and merges automatically once it is given and the checks pass.

## After the merge

ERC-8506 was merged into ethereum/ERCs as a Draft on 2026-11-25 (commit 5c77458, pull request #2188). The official page is https://eips.ethereum.org/EIPS/eip-8506. The branch `add-erc-ai-token` is no longer needed and may be deleted; the fork stays for later changes.

Later changes to the specification or its assets go through an update pull request:

1. Open `ERCS/erc-8506.md` in ethereum/ERCs and use the edit button (or upload files from the same place). GitHub puts the change on a new branch of the fork cut from the current upstream master; name it, for example, `update-erc-8506-rev2`. Do not reuse `add-erc-ai-token`, and do not branch from the fork's own master.
2. Change only `ERCS/erc-8506.md` and files under `assets/erc-8506/`. In the preamble, leave `eip`, `title`, `author`, `status`, `type`, `category`, `created` and `requires` as they are unless the change is about one of them.
3. Title the pull request `Update ERC-8506: <what changes>`. In the description, list the sections that change, whether any interface identifier changes, the test count, and whether the Sepolia evidence was rerun.
4. A change to a Draft by its author is approved by the review bot on the author's behalf and merged once the checks pass; no editor review is needed. A status change (to Review, Last Call or Final) is a separate pull request and needs an editor.
5. Mirror the same change into this repository (the specification, the assets, `ercs-pr-package/` via `python3 scripts/make-filing-package.py`) and note it in `CHANGELOG.md`, then mention the update pull request in the discussion topic.

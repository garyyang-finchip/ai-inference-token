# Filing with the ERCs repository

The specification is filed as a pull request against `ethereum/ERCs`. The pull request contains the specification and its assets and nothing else. Until an editor assigns a number, the files carry the placeholder number 9999.

## What is filed

`python3 scripts/make-filing-package.py` checks the specification against the files it quotes and writes the package to `ercs-pr-package/`:

| Path in the ERCs repository | Content | Files |
| --- | --- | --- |
| `ERCS/erc-9999.md` | The specification | 1 |
| `assets/erc-9999/contracts/` | Reference implementation: `AITOLedger.sol`, `AITORecords.sol`, `AITOWrapper20.sol` | 3 |
| `assets/erc-9999/contracts/interfaces/` | Types and the six interfaces | 7 |
| `assets/erc-9999/schemas/` | JSON Schemas of the eight record kinds | 8 |
| `assets/erc-9999/examples/` | Records of the worked cases | 13 |
| `assets/erc-9999/vectors/` | Test vectors | 4 |

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

    - Specification: ERCS/erc-9999.md (placeholder number)
    - Assets: interfaces and reference implementation, JSON Schemas of the record
      kinds, example records and test vectors
    - Discussion: <link of the topic>
    - Reference repository with tests:
      https://github.com/garyyang-finchip/ai-inference-token
    ```

7. **Checks.** The pull request runs the ERCs validator, the Markdown linter, the spell checker and the link checker. The specification passes the first three locally with the configuration of the ERCs repository; the link checker needs the pull request itself.

## When the number is assigned

An editor assigns the number in a review comment on the specification file.

1. Run `python3 scripts/make-filing-package.py --number <N> --discussions-to <link>`.
2. In the pull request branch, delete `ERCS/erc-9999.md` and `assets/erc-9999/` and upload `ERCS/erc-<N>.md` and `assets/erc-<N>/` from the regenerated package.
3. Rename the discussion topic to `ERC-<N>: AI Inference Token Onchain`.
4. When the checks are green, answer inside the editor's review conversation and resolve it.
5. In this repository, rename `ERCS/erc-9999.md` and `assets/erc-9999/` to the assigned number and replace `erc-9999` and `eip-9999` in the paths used by `foundry.toml`, the tests, the script and the tools. Record identifiers and vectors do not depend on the number, so on-chain evidence stays valid.

## After the merge

The specification is then a Draft in the ERCs repository. Later changes are filed as pull requests titled `Update ERC-<N>: <what changes>` from the same fork.

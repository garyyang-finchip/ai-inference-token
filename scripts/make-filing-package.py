#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Checks the specification against the files it quotes and builds the ERCs filing package.

    python3 scripts/make-filing-package.py                      placeholder number 9999
    python3 scripts/make-filing-package.py --number 1234        after a number is assigned
    python3 scripts/make-filing-package.py --discussions-to URL sets the discussion link
    python3 scripts/make-filing-package.py --check              checks only, writes nothing

The package is written to ercs-pr-package/ and holds exactly what goes to the ERCs
repository: ERCS/erc-<number>.md and assets/erc-<number>/.

Before anything is written the script verifies that

  * the preamble satisfies the limits the ERCs repository enforces;
  * every interface quoted in the specification is identical to its file;
  * every identifier, hash and address quoted in the specification is in the vectors;
  * the two state tables are what tools/profile_examples.py computes;
  * every asset is linked from the specification and every link resolves;
  * every file is plain ASCII and non-empty.
"""

import argparse
import hashlib
import importlib.util
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLACEHOLDER = "9999"
SPEC = ROOT / "ERCS" / f"erc-{PLACEHOLDER}.md"
ASSETS = ROOT / "assets" / f"erc-{PLACEHOLDER}"
DISCUSSION = re.compile(r"^https://ethereum-magicians\.org/t/[^/\s]+/[0-9]+$")

problems = []


def problem(message):
    problems.append(message)


def preamble(text):
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not match:
        problem("the specification has no preamble")
        return {}
    fields = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields


def check_preamble(text):
    fields = preamble(text)
    order = ["eip", "title", "description", "author", "discussions-to", "status", "type", "category", "created", "requires"]
    if list(fields) != order:
        problem(f"preamble headers are {list(fields)}, expected {order}")
    if len(fields.get("title", "")) > 44:
        problem("title is longer than 44 characters")
    description = fields.get("description", "")
    if len(description) > 140:
        problem("description is longer than 140 characters")
    if ":" in description:
        problem("description contains a colon")
    if re.search(r"\bstandard\b", description, re.I):
        problem("description contains the word standard")
    if not DISCUSSION.match(fields.get("discussions-to", "")):
        problem("discussions-to is not an ethereum-magicians.org topic link")
    return fields


def interface_body(path):
    """The file without licence line, pragma and imports, as the specification quotes it."""
    kept, in_import = [], False
    for line in path.read_text().splitlines():
        if line.startswith("// SPDX") or line.startswith("pragma "):
            continue
        if in_import or line.startswith("import"):
            in_import = not line.rstrip().endswith(";")
            continue
        kept.append(line)
    return "\n".join(kept).strip("\n")


def check_interfaces(text):
    blocks = re.findall(r"```solidity\n(.*?)\n```", text, re.S)
    files = sorted((ASSETS / "contracts" / "interfaces").glob("*.sol"))
    for path in files:
        if interface_body(path) not in blocks:
            problem(f"{path.name}: the specification does not quote this file as it is")
    if len(blocks) != len(files):
        problem(f"the specification has {len(blocks)} Solidity blocks for {len(files)} interface files")


def check_values(text):
    prose = re.sub(r"```solidity\n.*?\n```", "", text, flags=re.S)
    vectors = "\n".join(p.read_text() for p in sorted((ASSETS / "vectors").glob("*.json"))).lower()
    quoted = set(re.findall(r"0x[0-9a-fA-F]{64}\b|0x[0-9a-fA-F]{40}\b|0x[0-9a-fA-F]{8}\b", prose))
    for value in sorted(quoted):
        if value.lower() not in vectors:
            problem(f"{value} is quoted in the specification and is in no vector file")
    if len(quoted) < 20:
        problem("fewer quoted values than expected; the check may have stopped matching")


def check_tables(text):
    spec = importlib.util.spec_from_file_location("profile_examples", ROOT / "tools" / "profile_examples.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for name, rows in (("periodic allowance", module.periodic_example()), ("reserved capacity", module.reserved_example())):
        if module.table(rows) not in text:
            problem(f"the {name} state table differs from tools/profile_examples.py")


def check_links(text):
    linked = set(re.findall(rf"\]\(\.\./assets/eip-{PLACEHOLDER}/([^)]+)\)", text))
    present = {p.relative_to(ASSETS).as_posix() for p in ASSETS.rglob("*") if p.is_file()}
    for missing in sorted(linked - present):
        problem(f"link to assets/{missing} does not resolve")
    for orphan in sorted(present - linked):
        problem(f"assets/{orphan} is not linked from the specification")
    for target in re.findall(r"\]\(([^)]+)\)", text):
        if target.startswith(f"../assets/eip-{PLACEHOLDER}/") or target == "../LICENSE.md":
            continue
        if re.fullmatch(r"\./eip-[0-9]+\.md", target) or target.startswith("https://www.rfc-editor.org/rfc/"):
            continue
        problem(f"link target {target} is not one the ERCs repository accepts")


def check_plain(path, data):
    if not data:
        problem(f"{path} is empty")
    try:
        data.decode("ascii")
    except UnicodeDecodeError as error:
        problem(f"{path} is not plain ASCII (byte {error.start})")


def renumber(data, number, suffix):
    if suffix not in (".md", ".json", ".sol"):
        return data
    text = data.decode("ascii")
    text = text.replace(f"assets/eip-{PLACEHOLDER}/", f"assets/eip-{number}/")
    text = text.replace(f"assets/erc-{PLACEHOLDER}/", f"assets/erc-{number}/")
    return text.encode("ascii")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--number", default=PLACEHOLDER, help="assigned ERC number (default: the placeholder)")
    parser.add_argument("--discussions-to", help="link to the discussion topic")
    parser.add_argument("--out", default=str(ROOT / "ercs-pr-package"), help="output directory")
    parser.add_argument("--check", action="store_true", help="check only")
    args = parser.parse_args()
    if not re.fullmatch(r"[1-9][0-9]*", args.number):
        sys.exit("--number takes a positive integer")
    if args.discussions_to and not DISCUSSION.match(args.discussions_to):
        sys.exit("--discussions-to takes a link of the form https://ethereum-magicians.org/t/<slug>/<id>")

    text = SPEC.read_text()
    fields = check_preamble(text)
    check_interfaces(text)
    check_values(text)
    check_tables(text)
    check_links(text)

    sources = {SPEC: pathlib.Path("ERCS") / f"erc-{args.number}.md"}
    for path in sorted(ASSETS.rglob("*")):
        if path.is_file():
            sources[path] = pathlib.Path("assets") / f"erc-{args.number}" / path.relative_to(ASSETS)
    for path in sources:
        check_plain(path.relative_to(ROOT), path.read_bytes())

    if problems:
        for message in problems:
            print("FAIL " + message)
        sys.exit(f"{len(problems)} problem(s); nothing was written")
    print(f"checks passed: {len(sources)} files, title \"{fields['title']}\", requires {fields['requires']}")
    if args.check:
        return

    out = pathlib.Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    manifest = []
    for source, relative in sources.items():
        data = renumber(source.read_bytes(), args.number, source.suffix)
        if source == SPEC:
            spec_text = data.decode("ascii").replace(f"eip: {PLACEHOLDER}\n", f"eip: {args.number}\n", 1)
            if args.discussions_to:
                spec_text = re.sub(r"^discussions-to: .*$", f"discussions-to: {args.discussions_to}", spec_text, count=1, flags=re.M)
            data = spec_text.encode("ascii")
        target = out / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        if target.read_bytes() != data or not data:
            sys.exit(f"{relative} was not written correctly")
        manifest.append((relative.as_posix(), len(data), hashlib.sha256(data).hexdigest()))

    leftovers = []
    if args.number != PLACEHOLDER:
        for relative, _, _ in manifest:
            body = (out / relative).read_text()
            if f"eip-{PLACEHOLDER}" in body or f"erc-{PLACEHOLDER}" in body or f"eip: {PLACEHOLDER}" in body:
                leftovers.append(relative)
    if leftovers:
        sys.exit("the placeholder number is still present in: " + ", ".join(leftovers))

    for relative, size, digest in manifest:
        print(f"{digest[:16]}  {size:>7}  {relative}")
    written = preamble((out / "ERCS" / f"erc-{args.number}.md").read_text())
    print(f"wrote {len(manifest)} files to {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out}")
    print(f"number {written['eip']}, discussions-to {written['discussions-to']}")
    if written["discussions-to"].endswith("/99999"):
        print("note: discussions-to is still the placeholder; pass --discussions-to once the topic exists")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate the parts of the docs that must not drift from the code, and check that they did not.

Two things are generated, both read from files of this repository:

  * docs/reference.md, the inputs and outputs of the action, from action.yml;
  * the YAML examples of the docs pages. A page marks an example with a line
    `<!-- example: examples/NAME.yml -->` followed by a ```yaml fence. The fence must hold
    the content of that file, so a page shows the same file that tests/docs-examples.py checks.

Without options the script only checks, prints what is stale and exits 1. With --write it
rewrites the stale files. It also fails when a file of examples/ is not shown by any page.

It reads text and writes text. It never runs the action or a workflow.
"""

import argparse
import glob
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("PyYAML is needed: python3 -m pip install pyyaml (or apt install python3-yaml)\n")
    sys.exit(2)

REFERENCE = "docs/reference.md"
MARKER = re.compile(r"^<!-- example: (examples/[A-Za-z0-9._-]+\.ya?ml) -->\s*$")
FENCE_OPEN = re.compile(r"^```yaml\s*$")
FENCE_CLOSE = re.compile(r"^```\s*$")
HOW_TO_REGENERATE = "run python3 tests/docs-generated.py --write"


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def escape(text):
    """Make a description of action.yml safe in Markdown prose and in a table cell."""
    text = " ".join(str(text).split())
    for char in ("\\", "`", "*", "<", "|"):
        text = text.replace(char, "\\" + char)
    return text


def default_of(spec):
    value = str(spec.get("default", ""))
    return "(empty)" if value == "" else f"`{value}`"


def reference_page(action):
    inputs = action["inputs"]
    current = {k: v for k, v in inputs.items() if not str(v.get("description", "")).startswith("Deprecated")}
    aliases = {k: v for k, v in inputs.items() if k not in current}
    outputs = action.get("outputs", {})
    lines = [
        "# Reference",
        "",
        "<!-- Generated from action.yml by tests/docs-generated.py. Do not edit it by hand: change action.yml, then "
        "run `python3 tests/docs-generated.py --write`. A test fails while this page is out of date. -->",
        "",
        "Every input and output of the action, as `action.yml` declares them. This page is generated from that file, "
        "so it cannot drift from it. The README and the other pages say when to use each one.",
        "",
        "## Inputs",
        "",
        "| Input | Default |",
        "|---|---|",
    ]
    for name, spec in current.items():
        lines.append(f"| `{name}` | {default_of(spec)} |")
    lines += ["", "What each input does:", ""]
    for name, spec in current.items():
        lines += [f"### `{name}`", "", f"Default: {default_of(spec)}", "", escape(spec.get("description", "")), ""]
    lines += [
        "## Outputs",
        "",
        "| Output | Description |",
        "|---|---|",
    ]
    for name, spec in outputs.items():
        lines.append(f"| `{name}` | {escape(spec.get('description', ''))} |")
    lines += [
        "",
        "## Deprecated v2 inputs",
        "",
        "The v2 names are accepted as aliases and print a warning. They are not part of the v3 interface. "
        "The [migration guide](./migration-v2-to-v3.md) says how each one behaves.",
        "",
        "| Alias | Description |",
        "|---|---|",
    ]
    for name, spec in aliases.items():
        lines.append(f"| `{name}` | {escape(spec.get('description', ''))} |")
    return "\n".join(lines) + "\n"


def sync_examples(text, root):
    """Return (new text, the example files it shows, the problems found)."""
    lines = text.split("\n")
    out = []
    shown = []
    problems = []
    index = 0
    while index < len(lines):
        line = lines[index]
        match = MARKER.match(line)
        if not match:
            out.append(line)
            index += 1
            continue
        out.append(line)
        path = match.group(1)
        shown.append(path)
        target = os.path.join(root, path)
        look = index + 1
        while look < len(lines) and not lines[look].strip():
            out.append(lines[look])
            look += 1
        if look >= len(lines) or not FENCE_OPEN.match(lines[look]):
            problems.append(f"the marker for {path} is not followed by a ```yaml fence")
            index += 1
            continue
        end = look + 1
        while end < len(lines) and not FENCE_CLOSE.match(lines[end]):
            end += 1
        if end >= len(lines):
            problems.append(f"the fence after the marker for {path} is never closed")
            index += 1
            continue
        if not os.path.isfile(target):
            problems.append(f"the marker names {path}, which does not exist")
            out.extend(lines[look:end + 1])
        else:
            out.append(lines[look])
            out.extend(read(target).rstrip("\n").split("\n"))
            out.append(lines[end])
        index = end + 1
    return "\n".join(out), shown, problems


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="Generate and check the generated parts of the docs.")
    parser.add_argument("--root", default=os.path.join(here, ".."), help="repository root")
    parser.add_argument("--write", action="store_true", help="rewrite the stale files")
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    stale = []
    problems = []

    action = yaml.safe_load(read(os.path.join(root, "action.yml")))
    wanted = reference_page(action)
    reference_path = os.path.join(root, REFERENCE)
    current = read(reference_path) if os.path.isfile(reference_path) else None
    if current != wanted:
        stale.append(REFERENCE)
        if args.write:
            write(reference_path, wanted)

    shown = set()
    pages = sorted(glob.glob(os.path.join(root, "docs", "*.md")) + glob.glob(os.path.join(root, "examples", "*.md")))
    for page in pages:
        original = read(page)
        updated, used, found = sync_examples(original, root)
        shown.update(used)
        relative = os.path.relpath(page, root)
        problems.extend(f"{relative}: {message}" for message in found)
        if updated != original:
            stale.append(relative)
            if args.write:
                write(page, updated)

    for path in sorted(glob.glob(os.path.join(root, "examples", "*.yml"))):
        relative = os.path.relpath(path, root)
        if relative not in shown:
            problems.append(f"{relative} is not shown by any page. Add `<!-- example: {relative} -->` and a ```yaml fence to a page of docs/.")

    for path in stale:
        verb = "rewrote" if args.write else "is stale:"
        print(f"{verb} {path}" if args.write else f"{path} {verb} {HOW_TO_REGENERATE}")
    for message in problems:
        print(f"error {message}")
    print(f"{len(stale)} stale, {len(shown)} examples shown, {len(problems)} problems")
    if problems:
        return 1
    return 1 if stale and not args.write else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Check the YAML examples in the documentation against action.yml.

This is a structural check. It does not run the action. It reads each YAML snippet of the
given files (the fenced yaml blocks of a Markdown file, or the whole of a .yml file), and
fails when a snippet would not work with the action as it is on this branch:

  * the snippet is not valid YAML;
  * a step uses miguelcolmenares/npm-auto-build with a reference other than @v3, @main or
    a 40 character commit SHA;
  * a step passes an input that action.yml does not declare, a v2 alias input, or a value
    that is not allowed (mode, package-manager, a boolean);
  * in a full workflow: the job has no checkout before the action, a step has both or
    neither of `uses` and `run`, mode commit or pr has no `persist-credentials: false` on
    the checkout, or the job lacks `permissions: contents: write` (and `pull-requests:
    write` for mode pr) when the step uses the default token;
  * a step uses actions/checkout older than v7, or a node-version below 22.

With --tables FILE it also checks that the inputs and outputs tables of that Markdown file
list exactly what action.yml declares, with the same defaults. With --require-modes it
fails when the files together do not show every mode.

A snippet that is on purpose not a v3 example (for example the v2 "before" of the migration
guide) is skipped when the line before its fence is the marker below. Skips are counted
and printed.
"""

import argparse
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("PyYAML is needed: python3 -m pip install pyyaml (or apt install python3-yaml)\n")
    sys.exit(2)

ACTION_NAME = "miguelcolmenares/npm-auto-build"
REF_RE = re.compile(r"^(v3|main|[0-9a-f]{40})$")
MODES = ("commit", "check", "pr", "build")
MANAGERS = ("auto", "npm", "yarn", "pnpm")
BOOLEAN_INPUTS = ("auto-merge", "ignore-scripts", "upload-diff")
# v2 names that action.yml still accepts, so a v3 example must not use them.
DEPRECATED = {
    "github-token": "token",
    "directory": "working-directory",
    "build-dir": "paths",
    "build-only": "mode: build",
    "create-pr": "mode: pr",
}
SKIP_MARKER = "<!-- docs-examples: skip -->"
MIN_CHECKOUT = 7
MIN_NODE = 22

FENCE_OPEN = re.compile(r"^(\s*)```(yaml|yml)\s*$")
FENCE_CLOSE = re.compile(r"^\s*```\s*$")


class Snippet:
    def __init__(self, path, line, text, skipped):
        self.path = path
        self.line = line
        self.text = text
        self.skipped = skipped

    @property
    def where(self):
        return f"{self.path}:{self.line}"


def extract(path):
    """Return the snippets of one file."""
    with open(path, encoding="utf-8") as handle:
        content = handle.read()
    if path.endswith((".yml", ".yaml")):
        return [Snippet(path, 1, content, False)]
    snippets = []
    lines = content.split("\n")
    index = 0
    while index < len(lines):
        match = FENCE_OPEN.match(lines[index])
        if not match:
            index += 1
            continue
        start = index + 1
        # The marker sits on the line before the fence, blank lines in between are allowed.
        before = index - 1
        while before >= 0 and not lines[before].strip():
            before -= 1
        skipped = before >= 0 and lines[before].strip() == SKIP_MARKER
        end = start
        while end < len(lines) and not FENCE_CLOSE.match(lines[end]):
            end += 1
        if end >= len(lines):
            snippets.append(Snippet(path, start + 1, "\0unterminated", skipped))
            break
        snippets.append(Snippet(path, start + 1, "\n".join(lines[start:end]), skipped))
        index = end + 1
    return snippets


def load_action(action_path):
    with open(action_path, encoding="utf-8") as handle:
        action = yaml.safe_load(handle)
    return action


def is_expression(value):
    return isinstance(value, str) and "${{" in value


def as_bool_text(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return value
    return None


def is_false(value):
    return value is False or (isinstance(value, str) and value.strip().lower() == "false")


def walk(node):
    """Yield every dict in a parsed document."""
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def major_of(value):
    match = re.match(r"^v?(\d+)", str(value).strip())
    return int(match.group(1)) if match else None


class Checker:
    def __init__(self, action):
        self.inputs = set(action["inputs"])
        self.modes_seen = set()
        self.errors = []
        self.action_steps = 0

    def error(self, snippet, message):
        self.errors.append(f"{snippet.where}: {message}")

    # One `uses` of this action.
    def check_action_step(self, snippet, step):
        self.action_steps += 1
        ref = step["uses"].split("@", 1)[1] if "@" in step["uses"] else ""
        if not REF_RE.match(ref):
            self.error(snippet, f"'{step['uses']}' must end in @v3, @main or a 40 character commit SHA.")
        with_block = step.get("with") or {}
        if not isinstance(with_block, dict):
            self.error(snippet, "'with' of the action step must be a mapping.")
            return "commit"
        for key, value in with_block.items():
            if key in DEPRECATED:
                self.error(snippet, f"input '{key}' is a v2 name, use {DEPRECATED[key]}.")
            elif key not in self.inputs:
                self.error(snippet, f"input '{key}' does not exist in action.yml.")
            if isinstance(value, (dict, list)):
                self.error(snippet, f"input '{key}' must be a scalar.")
        mode = with_block.get("mode", "commit")
        if not is_expression(mode):
            if mode not in MODES:
                self.error(snippet, f"mode '{mode}' is not one of {', '.join(MODES)}.")
            else:
                self.modes_seen.add(mode)
        manager = with_block.get("package-manager")
        if manager is not None and not is_expression(manager) and manager not in MANAGERS:
            self.error(snippet, f"package-manager '{manager}' is not one of {', '.join(MANAGERS)}.")
        for key in BOOLEAN_INPUTS:
            if key in with_block and not is_expression(with_block[key]):
                if as_bool_text(with_block[key]) not in ("true", "false"):
                    self.error(snippet, f"input '{key}' must be true or false.")
        return mode if isinstance(mode, str) else "commit"

    # Rules that hold for every dict of the snippet, in a workflow or a fragment.
    def check_generic(self, snippet, doc):
        for node in walk(doc):
            uses = node.get("uses")
            if isinstance(uses, str):
                name = uses.split("@", 1)[0]
                ref = uses.split("@", 1)[1] if "@" in uses else ""
                if name == ACTION_NAME:
                    pass  # Checked by the caller, once per step.
                elif name == "actions/checkout" and not re.match(r"^[0-9a-f]{40}$", ref):
                    major = major_of(ref)
                    if major is None or major < MIN_CHECKOUT:
                        self.error(snippet, f"'{uses}' is older than actions/checkout@v{MIN_CHECKOUT}.")
            if "node-version" in node:
                value = node["node-version"]
                if not is_expression(value):
                    major = major_of(value)
                    if major is not None and major < MIN_NODE:
                        self.error(snippet, f"node-version '{value}' is older than {MIN_NODE}.")

    def permission_level(self, permissions, key):
        if permissions == "write-all":
            return "write"
        if isinstance(permissions, dict):
            return permissions.get(key)
        return None

    def check_workflow(self, snippet, doc):
        if "on" not in doc and True not in doc:
            self.error(snippet, "a workflow needs an 'on' key.")
        jobs = doc.get("jobs")
        if not isinstance(jobs, dict) or not jobs:
            self.error(snippet, "'jobs' must be a mapping with at least one job.")
            return
        for job_id, job in jobs.items():
            if not isinstance(job, dict):
                self.error(snippet, f"job '{job_id}' must be a mapping.")
                continue
            if "uses" in job:
                continue  # A reusable workflow call, nothing of ours inside.
            if "runs-on" not in job:
                self.error(snippet, f"job '{job_id}' has no runs-on.")
            steps = job.get("steps")
            if not isinstance(steps, list) or not steps:
                self.error(snippet, f"job '{job_id}' has no steps.")
                continue
            permissions = job.get("permissions", doc.get("permissions"))
            checkout_before = False
            persist_false = False
            for number, step in enumerate(steps, 1):
                if not isinstance(step, dict):
                    self.error(snippet, f"step {number} of job '{job_id}' must be a mapping.")
                    continue
                if ("uses" in step) == ("run" in step):
                    self.error(snippet, f"step {number} of job '{job_id}' needs exactly one of 'uses' and 'run'.")
                    continue
                uses = step.get("uses", "")
                if uses.startswith("actions/checkout@"):
                    checkout_before = True
                    if is_false((step.get("with") or {}).get("persist-credentials")):
                        persist_false = True
                if uses.split("@", 1)[0] != ACTION_NAME:
                    continue
                mode = self.check_action_step(snippet, step)
                where = f"step {number} of job '{job_id}'"
                if not checkout_before:
                    self.error(snippet, f"{where} runs the action with no actions/checkout before it.")
                if mode in ("commit", "pr"):
                    if not persist_false:
                        self.error(snippet, f"{where} is mode {mode}, so the checkout needs 'persist-credentials: false'.")
                    own_token = "token" in (step.get("with") or {})
                    if not own_token:
                        if self.permission_level(permissions, "contents") != "write":
                            self.error(snippet, f"{where} is mode {mode} with the default token, so the job needs 'permissions: contents: write'.")
                        if mode == "pr" and self.permission_level(permissions, "pull-requests") != "write":
                            self.error(snippet, f"{where} is mode pr with the default token, so the job needs 'permissions: pull-requests: write'.")

    def check_snippet(self, snippet):
        if snippet.text == "\0unterminated":
            self.error(snippet, "the code fence is never closed.")
            return None
        try:
            doc = yaml.safe_load(snippet.text)
        except yaml.YAMLError as error:
            self.error(snippet, f"not valid YAML: {str(error).splitlines()[0]}")
            return None
        if not isinstance(doc, (dict, list)):
            self.error(snippet, "the snippet is empty or not a mapping or a list.")
            return None
        is_workflow = isinstance(doc, dict) and "jobs" in doc
        if is_workflow:
            self.check_workflow(snippet, doc)
        else:
            for node in walk(doc):
                uses = node.get("uses")
                if isinstance(uses, str) and uses.split("@", 1)[0] == ACTION_NAME:
                    self.check_action_step(snippet, node)
        self.check_generic(snippet, doc)
        return "workflow" if is_workflow else "fragment"


def table_rows(path, first_header):
    """Return {name: default-or-None} for the Markdown table whose header starts with first_header."""
    rows = {}
    in_table = False
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line.startswith("|"):
                in_table = False
                continue
            cells = [cell.strip() for cell in re.split(r"(?<!\\)\|", line.strip("|"))]
            if cells and cells[0] == first_header:
                in_table = True
                continue
            if not in_table or set(line) <= set("|-: "):
                continue
            name = cells[0].strip("`")
            rows[name] = cells[1].strip("`") if len(cells) > 1 else None
    return rows


def check_tables(checker, action, path):
    inputs = {k: v for k, v in action["inputs"].items() if k not in DEPRECATED}
    found = table_rows(path, "Input")
    for name in inputs:
        if name not in found:
            checker.errors.append(f"{path}: the inputs table has no row for '{name}'.")
    for name in found:
        if name not in inputs:
            checker.errors.append(f"{path}: the inputs table lists '{name}', which action.yml does not declare (or only as a v2 alias).")
    for name, spec in inputs.items():
        if name not in found:
            continue
        expected = str(spec.get("default", ""))
        shown = "" if found[name] == "(empty)" else found[name]
        if shown != expected:
            checker.errors.append(f"{path}: input '{name}' shows default '{found[name]}', action.yml has '{expected or '(empty)'}'.")
    outputs = set(action.get("outputs", {}))
    found_out = set(table_rows(path, "Output"))
    for name in sorted(outputs - found_out):
        checker.errors.append(f"{path}: the outputs table has no row for '{name}'.")
    for name in sorted(found_out - outputs):
        checker.errors.append(f"{path}: the outputs table lists '{name}', which action.yml does not declare.")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="Check the YAML examples of the docs against action.yml.")
    parser.add_argument("files", nargs="+")
    parser.add_argument("--action", default=os.path.join(here, "..", "action.yml"))
    parser.add_argument("--tables", help="Markdown file whose inputs and outputs tables must match action.yml")
    parser.add_argument("--require-modes", action="store_true", help="the files together must show every mode")
    parser.add_argument("--dump", help="write each full workflow snippet to this directory, for actionlint")
    args = parser.parse_args()

    action = load_action(args.action)
    checker = Checker(action)
    skipped = 0
    checked = 0
    for path in args.files:
        snippets = extract(path)
        if not snippets:
            checker.errors.append(f"{path}: no YAML snippet found.")
        for snippet in snippets:
            if snippet.skipped:
                skipped += 1
                print(f"skip  {snippet.where}")
                continue
            before = len(checker.errors)
            kind = checker.check_snippet(snippet)
            checked += 1
            print(f"{'ok  ' if len(checker.errors) == before else 'FAIL'}  {snippet.where} ({kind or 'invalid'})")
            if args.dump and kind == "workflow":
                os.makedirs(args.dump, exist_ok=True)
                name = re.sub(r"[^A-Za-z0-9]+", "-", f"{path}-{snippet.line}").strip("-") + ".yml"
                with open(os.path.join(args.dump, name), "w", encoding="utf-8") as out:
                    out.write(snippet.text + "\n")
    if args.tables:
        check_tables(checker, action, args.tables)
    if args.require_modes:
        for mode in MODES:
            if mode not in checker.modes_seen:
                checker.errors.append(f"no example uses mode '{mode}'.")
    for message in checker.errors:
        print(f"error {message}")
    print(f"{checked} snippets checked, {checker.action_steps} action steps, {skipped} skipped, {len(checker.errors)} errors")
    return 1 if checker.errors else 0


if __name__ == "__main__":
    sys.exit(main())

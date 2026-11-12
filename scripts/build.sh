#!/usr/bin/env bash
# Step 4. Run the build command and check that every path in `paths` exists.
#
# May do: run the project's build script without the token in its environment, read
# the file system. May not: read the token, run git, guess a build directory.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Succeed when package.json defines a script with this exact name.
script_exists() {
    node -e '
        const pkg = JSON.parse(require("fs").readFileSync("package.json", "utf8"));
        const scripts = pkg.scripts || {};
        process.exit(Object.prototype.hasOwnProperty.call(scripts, process.argv[1]) ? 0 : 1);
    ' "$1"
}

list_scripts() {
    node -e '
        const pkg = JSON.parse(require("fs").readFileSync("package.json", "utf8"));
        for (const name of Object.keys(pkg.scripts || {})) console.log("  " + name);
    '
}

main() {
    nab_enter_workdir

    local command=${NAB_COMMAND:-build}
    local paths=${NAB_PATHS:-}
    [ -n "$paths" ] || die "NAB_PATHS is empty, run validate-inputs.sh first."

    if ! script_exists "$command"; then
        log_info "Scripts defined in package.json:"
        list_scripts
        die "Script '$command' is not defined in package.json (working-directory '${NAB_WORKDIR:-.}')."
    fi

    nab_resolve_package_manager
    local pm=$NAB_RESOLVED_PM
    command -v "$pm" >/dev/null 2>&1 ||
        die "The build needs $pm, but it was not found on PATH. Install $pm in a step before this action, add the packageManager field to package.json so that the install step can set it up with corepack, or make your install-command install it."
    log_info "Running the build: $pm run $command"
    run_without_token "$pm" run "$command"

    # Every path must exist after the build. There is no guessing.
    local entry missing=""
    while IFS= read -r entry; do
        if [ ! -e "$entry" ]; then
            missing="${missing:+$missing, }'$entry'"
        fi
    done <<<"$paths"

    if [ -n "$missing" ]; then
        die "The build finished but these paths do not exist (relative to working-directory '${NAB_WORKDIR:-.}'): $missing. Fix 'paths' or the build script."
    fi

    log_info "Build finished, every path exists:"
    while IFS= read -r entry; do
        printf '[INFO]   %s\n' "$entry"
    done <<<"$paths"
}

main

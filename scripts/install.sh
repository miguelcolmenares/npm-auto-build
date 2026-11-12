#!/usr/bin/env bash
# Step 3. Install the project's dependencies.
#
# May do: run the package manager (or install-command) without the token in its
# environment. May not: read the token, run git, write outside the project directory.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

main() {
    nab_enter_workdir

    local install_command=${NAB_INSTALL_COMMAND:-}
    if [ -n "$install_command" ]; then
        log_info "Installing dependencies with install-command"
        if [ "${NAB_IGNORE_SCRIPTS:-false}" = "true" ]; then
            log_warn "ignore-scripts has no effect when install-command is set."
        fi
        run_without_token bash -c "$install_command"
        return
    fi

    local flags=()
    nab_resolve_package_manager
    local pm=$NAB_RESOLVED_PM
    if [ "${NAB_IGNORE_SCRIPTS:-false}" = "true" ]; then
        flags+=(--ignore-scripts)
    fi

    case "$pm" in
        npm)
            if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
                log_info "Installing dependencies with npm ci"
                run_without_token npm ci ${flags[@]+"${flags[@]}"}
            else
                log_info "No npm lockfile found, installing dependencies with npm install"
                run_without_token npm install ${flags[@]+"${flags[@]}"}
            fi
            ;;
        yarn)
            log_info "Installing dependencies with yarn install --frozen-lockfile"
            run_without_token yarn install --frozen-lockfile ${flags[@]+"${flags[@]}"}
            ;;
        pnpm)
            log_info "Installing dependencies with pnpm install --frozen-lockfile"
            run_without_token pnpm install --frozen-lockfile ${flags[@]+"${flags[@]}"}
            ;;
    esac
}

main

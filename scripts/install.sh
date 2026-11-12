#!/usr/bin/env bash
# Step 3. Install the project's dependencies.
#
# May do: run corepack and the package manager (or install-command) without the token
# in its environment. May not: read the token, run git, write outside the project
# directory, write an .npmrc, download anything except through corepack and the
# package manager itself.
#
# Variables the workflow sets for a private registry (NODE_AUTH_TOKEN, NPM_CONFIG_*,
# YARN_*, PNPM_*) reach the install untouched. Only the GitHub token variables are removed.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Warn that the install is not reproducible, once, with the manager's own lockfile name.
warn_no_lockfile() {
    local lockfile=$1
    log_warn "No $lockfile found, so the install is not reproducible. Commit the lockfile."
}

main() {
    nab_enter_workdir
    nab_resolve_package_manager
    local pm=$NAB_RESOLVED_PM

    local install_command=${NAB_INSTALL_COMMAND:-}
    if [ -n "$install_command" ]; then
        log_info "Installing dependencies with install-command (the build will use $pm)"
        if [ "${NAB_IGNORE_SCRIPTS:-false}" = "true" ]; then
            log_warn "ignore-scripts has no effect when install-command is set."
        fi
        run_without_token bash -c "$install_command"
        return
    fi

    nab_prepare_package_manager

    local flags=()
    if [ "${NAB_IGNORE_SCRIPTS:-false}" = "true" ]; then
        flags+=(--ignore-scripts)
    fi

    case "$pm" in
        npm)
            if nab_has_lockfile npm; then
                log_info "Installing dependencies with npm ci"
                run_without_token npm ci ${flags[@]+"${flags[@]}"}
            else
                warn_no_lockfile "package-lock.json"
                log_info "Installing dependencies with npm install"
                run_without_token npm install ${flags[@]+"${flags[@]}"}
            fi
            ;;
        pnpm)
            if nab_has_lockfile pnpm; then
                log_info "Installing dependencies with pnpm install --frozen-lockfile"
                run_without_token pnpm install --frozen-lockfile ${flags[@]+"${flags[@]}"}
            else
                warn_no_lockfile "pnpm-lock.yaml"
                log_info "Installing dependencies with pnpm install --no-frozen-lockfile"
                run_without_token pnpm install --no-frozen-lockfile ${flags[@]+"${flags[@]}"}
            fi
            ;;
        yarn)
            nab_detect_yarn_berry
            if [ "$NAB_YARN_BERRY" = "true" ]; then
                # Yarn berry has no --ignore-scripts flag, a setting in the environment
                # of this one command does the same.
                local berry_env=()
                if [ "${NAB_IGNORE_SCRIPTS:-false}" = "true" ]; then
                    berry_env+=(YARN_ENABLE_SCRIPTS=false)
                fi
                if nab_has_lockfile yarn; then
                    log_info "Installing dependencies with yarn install --immutable (yarn berry)"
                    run_without_token env ${berry_env[@]+"${berry_env[@]}"} yarn install --immutable
                else
                    warn_no_lockfile "yarn.lock"
                    log_info "Installing dependencies with yarn install --no-immutable (yarn berry)"
                    run_without_token env ${berry_env[@]+"${berry_env[@]}"} yarn install --no-immutable
                fi
            elif nab_has_lockfile yarn; then
                log_info "Installing dependencies with yarn install --frozen-lockfile (yarn classic)"
                run_without_token yarn install --frozen-lockfile ${flags[@]+"${flags[@]}"}
            else
                warn_no_lockfile "yarn.lock"
                log_info "Installing dependencies with yarn install (yarn classic)"
                run_without_token yarn install ${flags[@]+"${flags[@]}"}
            fi
            ;;
    esac
}

main

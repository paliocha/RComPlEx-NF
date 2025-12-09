#!/bin/bash
# RComPlEx Script Runner - Orion HPC Path Compatibility
#
# Wrapper to handle Orion HPC NFS mount point issues where:
# - Nextflow canonicalizes paths to /net/fs-2/scale/OrionStore/Home/...
# - Compute nodes can only access /mnt/users/... mount point
#
# This script translates paths transparently before invoking Rscript

set -e

# Helper function to translate Orion HPC paths
translate_path() {
    local path="$1"
    # If path doesn't exist and uses /net/fs-2, try /mnt/users alternative
    if [[ "$path" == /net/fs-2* ]] && [[ ! -f "$path" && ! -d "$path" ]]; then
        # Translate /net/fs-2/scale/OrionStore/Home/ to /mnt/users/
        echo "${path//\/net\/fs-2\/scale\/OrionStore\/Home\//\/mnt\/users\/}"
    else
        echo "$path"
    fi
}

# First argument is the script to run
SCRIPT="$1"
shift

# Translate script path
SCRIPT=$(translate_path "$SCRIPT")

# Debug mode (set RUN_SCRIPT_DEBUG=1 to see path translations)
if [[ -n "$RUN_SCRIPT_DEBUG" ]]; then
    echo "[run_script.sh] Resolved script path: $SCRIPT" >&2
fi

# Verify script exists before executing
if [[ ! -f "$SCRIPT" ]]; then
    echo "ERROR: Script not found: $SCRIPT" >&2
    echo "  (Failed to locate or translate path)" >&2
    exit 1
fi

# Translate all remaining arguments that are file paths
declare -a ARGS
for arg in "$@"; do
    if [[ "$arg" == --*=* ]]; then
        # Handle --key=value arguments
        KEY="${arg%%=*}"
        VALUE="${arg#*=}"
        # Translate VALUE if it looks like a path
        if [[ "$VALUE" == /* ]]; then
            VALUE=$(translate_path "$VALUE")
        fi
        ARGS+=("${KEY}=${VALUE}")
    elif [[ "$arg" == --* ]] && [[ -z "${NEXT_IS_VALUE:-}" ]]; then
        # Handle --key or --key value arguments
        ARGS+=("$arg")
        # Check if next arg might be a value for this key
        if [[ "$arg" == --config ]] || [[ "$arg" == --workdir ]] || [[ "$arg" == --outdir ]] || [[ "$arg" == --indir ]] || [[ "$arg" == --results_dir ]]; then
            NEXT_IS_VALUE=1
        fi
    elif [[ -n "${NEXT_IS_VALUE:-}" ]]; then
        # This is a value for the previous --key argument
        if [[ "$arg" == /* ]]; then
            arg=$(translate_path "$arg")
        fi
        ARGS+=("$arg")
        NEXT_IS_VALUE=""
    else
        ARGS+=("$arg")
    fi
done

# Execute Rscript with all remaining arguments
exec Rscript "$SCRIPT" "${ARGS[@]}"

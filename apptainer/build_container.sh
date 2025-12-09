#!/bin/bash
# ==============================================================================
# RComPlEx Container Build Script
# ==============================================================================
# Builds the Apptainer container for the RComPlEx pipeline
# ==============================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEF_FILE="${PROJECT_DIR}/RComPlEx.def"
OUTPUT_FILE="${PROJECT_DIR}/RComPlEx.sif"

# Use project directory for final SIF image
SIF_FILE="${PROJECT_DIR}/RComPlEx.sif"

# Use fakeroot for building (user-namespace, non-root)
FAKEROOT_FLAG="--fakeroot"

# Build in local /tmp, then move SIF to project directory
# This avoids NFS ownership issues entirely

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if apptainer is installed
    if ! command -v apptainer &> /dev/null; then
        log_error "Apptainer not found. Please install Apptainer 1.4.5 or later."
        log_info "Installation: https://apptainer.org/docs/user/latest/installation.html"
        exit 1
    fi

    # Check apptainer version
    APPTAINER_VERSION=$(apptainer --version | cut -d' ' -f3)
    log_info "Apptainer version: $APPTAINER_VERSION"

    # Check if definition file exists
    if [ ! -f "$DEF_FILE" ]; then
        log_error "Definition file not found: $DEF_FILE"
        exit 1
    fi
    log_info "Definition file found: $DEF_FILE"

    # Check write permissions
    if [ ! -w "$PROJECT_DIR" ]; then
        log_error "No write permissions in project directory: $PROJECT_DIR"
        exit 1
    fi
    log_info "Write permissions verified"
}

# Build container in sandbox mode (avoids NFS ownership issues)
build_container() {
    log_info "Building Apptainer container in sandbox mode..."
    log_info "This may take 15-30 minutes depending on your system."
    echo ""

    # Determine best temporary location for build
    # Priority: /tmp (local SSD) > /dev/shm (if >50GB) > fallback
    # AVOID: $WORK, $TMPDIR (likely NFS mounted)

    TEMP_BUILD_DIR=""

    # Check /tmp (local SSD on login node)
    if [ -w "/tmp" ]; then
        TMP_AVAIL=$(df /tmp 2>/dev/null | awk 'NR==2 {print $4}')
        if [ "$TMP_AVAIL" -gt 53687091 ]; then
            # /tmp has >50GB free
            TEMP_BUILD_DIR="/tmp"
            log_info "Using /tmp (local SSD, 57GB+ available) ✓"
        else
            log_warn "/tmp has insufficient space (need 50GB, have $(($TMP_AVAIL/1024/1024))GB)"
        fi
    fi

    # Fallback to /dev/shm if /tmp didn't work
    if [ -z "$TEMP_BUILD_DIR" ] && [ -w "/dev/shm" ]; then
        SHM_AVAIL=$(df /dev/shm 2>/dev/null | awk 'NR==2 {print $4}')
        if [ "$SHM_AVAIL" -gt 53687091 ]; then
            TEMP_BUILD_DIR="/dev/shm"
            log_info "Using /dev/shm (tmpfs, RAM-based)"
        else
            log_warn "/dev/shm has insufficient space (need 50GB, have $(($SHM_AVAIL/1024/1024))GB)"
        fi
    fi

    # Final error check
    if [ -z "$TEMP_BUILD_DIR" ]; then
        log_error "No suitable temporary directory found with 50GB+ free space!"
        log_error "Checked: /tmp, /dev/shm"
        log_error "Tip: Free up space or use qlogin on a different login node"
        exit 1
    fi

    TEMP_SIF="$TEMP_BUILD_DIR/RComPlEx_$$.sif"
    log_warn "Build location: $TEMP_SIF (local filesystem, /tmp)"
    log_warn "Final location: $SIF_FILE (NFS project directory)"

    # Force Apptainer to use local filesystem (not NFS)
    export TMPDIR="$TEMP_BUILD_DIR"
    export APPTAINER_TMPDIR="$TEMP_BUILD_DIR"
    export APPTAINER_CACHEDIR="$TEMP_BUILD_DIR/.apptainer_cache"
    mkdir -p "$APPTAINER_CACHEDIR"

    log_info "Environment variables set:"
    log_info "  TMPDIR=$TMPDIR"
    log_info "  APPTAINER_TMPDIR=$APPTAINER_TMPDIR"
    log_info "  APPTAINER_CACHEDIR=$APPTAINER_CACHEDIR"
    echo ""

    # Build command: create SIF image file (not sandbox directory)
    CMD="apptainer build --fakeroot $TEMP_SIF $DEF_FILE"
    log_info "Executing: $CMD"
    echo ""

    if eval "$CMD"; then
        log_info "Container SIF build successful in temporary directory"

        # Remove old SIF if it exists in project directory
        if [ -f "$SIF_FILE" ]; then
            log_info "Removing old SIF image..."
            rm -f "$SIF_FILE"
        fi

        # Move SIF from temp location to project directory
        log_info "Moving SIF image to project directory..."
        if mv "$TEMP_SIF" "$SIF_FILE"; then
            log_info "SIF successfully moved to: $SIF_FILE"
        else
            log_error "Failed to move SIF to project directory"
            rm -f "$TEMP_SIF"
            exit 1
        fi
    else
        log_error "Container build failed"
        log_error "Cleaning up temporary files from $TEMP_SIF..."
        rm -f "$TEMP_SIF"
        exit 1
    fi

    echo ""
}

# Clean up temporary build files (not SIF)
cleanup() {
    # SIF is kept for runtime use, so we don't delete it
    log_info "Container SIF image is ready for use"
    log_info "Location: $SIF_FILE"
}

# Verify container SIF
verify_container() {
    log_info "Verifying container SIF..."
    echo ""

    if [ ! -f "$SIF_FILE" ]; then
        log_error "Container SIF not found: $SIF_FILE"
        exit 1
    fi

    # Get file size
    SIZE=$(du -h "$SIF_FILE" | cut -f1)
    log_info "Container SIF size: $SIZE"

    # Run test
    log_info "Running container tests..."
    if apptainer test "$SIF_FILE"; then
        log_info "Container verification passed"
        echo ""
        return 0
    else
        log_error "Container verification failed"
        exit 1
    fi
}

# Print usage information
print_usage() {
    cat << 'EOF'
Container SIF image built successfully!

Usage with Nextflow (default - no container):
  nextflow run main.nf --tissues root --test_mode true

Usage with Nextflow + Apptainer container:
  nextflow run main.nf -profile slurm,singularity_hpc --tissues root --test_mode true

Usage with Apptainer directly (SIF image):
  apptainer exec RComPlEx.sif Rscript scripts/rcomplex_01_load_filter.R \
    --tissue root --pair_id Species1_Species2 \
    --config config/pipeline_config.yaml \
    --workdir . --outdir results

Container image details:
EOF
    apptainer inspect "$SIF_FILE"
}

# Main execution
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         RComPlEx Apptainer Container Builder                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    echo ""

    build_container
    cleanup

    echo ""
    verify_container
    echo ""

    print_usage
    echo ""
    log_info "Build complete!"
    log_info "Container SIF image ready at: $SIF_FILE"
}

# Run main
main "$@"
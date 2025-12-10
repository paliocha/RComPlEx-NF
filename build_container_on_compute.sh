#!/bin/bash
# Build RComPlEx container on a compute node using qlogin
# This script should be run after qlogin to a compute node
#
# Usage:
#   qlogin
#   cd /mnt/project/FjellheimLab/martpali/AnnualPerennial/RComPlEx
#   bash build_container_on_compute.sh

set -e  # Exit on any error

echo "======================================"
echo "RComPlEx Container Build Script"
echo "======================================"
echo ""

# Check if we're on a compute node (not login node)
if [[ $(hostname) == login* ]]; then
    echo "ERROR: Please run this script on a compute node after 'qlogin'"
    echo "Usage:"
    echo "  qlogin"
    echo "  cd /mnt/project/FjellheimLab/martpali/AnnualPerennial/RComPlEx"
    echo "  bash build_container_on_compute.sh"
    exit 1
fi

# Get current location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Build directory: $SCRIPT_DIR"
echo "Current node: $(hostname)"
echo ""

# Create temp directory for build
BUILD_TMP="/tmp/rcomplex_build_$$"
mkdir -p "$BUILD_TMP"
echo "Created temporary build directory: $BUILD_TMP"
echo ""

# Copy necessary files
cp "$SCRIPT_DIR/RComPlEx.def" "$BUILD_TMP/"
cd "$BUILD_TMP"

echo "Building container..."
echo "Definition file: RComPlEx.def"
echo "Output: $SCRIPT_DIR/RComPlEx.sif"
echo ""

# Run apptainer build
# Use --fakeroot if available, otherwise use --sandbox first then convert
if apptainer --version | grep -q "Apptainer version"; then
    echo "Starting Apptainer build (this may take 10-20 minutes)..."
    apptainer build --fakeroot "$SCRIPT_DIR/RComPlEx.sif" RComPlEx.def
else
    echo "ERROR: Apptainer not found on this node"
    exit 1
fi

echo ""
echo "======================================"
echo "Build Complete!"
echo "======================================"
echo ""
echo "Container location: $SCRIPT_DIR/RComPlEx.sif"
echo ""

# Test the container
echo "Testing container..."
apptainer exec "$SCRIPT_DIR/RComPlEx.sif" R --version | head -3
echo ""

# Test Rfast installation
echo "Verifying Rfast installation..."
apptainer exec "$SCRIPT_DIR/RComPlEx.sif" Rscript -e 'library(Rfast); cat("✓ Rfast version:", packageVersion("Rfast"), "\n")'
echo ""

# Cleanup
cd /
rm -rf "$BUILD_TMP"
echo "Cleaned up temporary directory"
echo ""
echo "Ready to run pipeline with optimized Rfast::Tcrossprod!"

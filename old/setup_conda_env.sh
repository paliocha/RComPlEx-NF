#!/bin/bash
# ==============================================================================
# RComPlEx Conda Environment Setup
# ==============================================================================
# This script creates a conda environment with all dependencies for RComPlEx
# Use this if Apptainer containerization is not available or preferred
# ==============================================================================

set -e

echo "=========================================="
echo "RComPlEx Conda Environment Setup"
echo "=========================================="
echo ""

# Check if conda/micromamba is available
if ! command -v micromamba &> /dev/null && ! command -v conda &> /dev/null; then
    echo "Error: Neither micromamba nor conda found in PATH"
    echo "Please activate your Nextflow environment first:"
    echo "  source ~/.bashrc"
    echo "  micromamba activate Nextflow"
    exit 1
fi

# Determine which conda tool to use
if command -v micromamba &> /dev/null; then
    CONDA_CMD="micromamba"
    echo "Using micromamba for environment creation"
else
    CONDA_CMD="conda"
    echo "Using conda for environment creation"
fi

echo ""
echo "Creating RComPlEx conda environment..."
echo "This may take a few minutes..."
echo ""

# Create environment from YAML file
$CONDA_CMD env create -f environment.yml --yes

echo ""
echo "=========================================="
echo "✓ Environment created successfully!"
echo ""
echo "To activate the environment, run:"
echo "  micromamba activate rcomplex"
echo ""
echo "Then run the pipeline:"
echo "  nextflow run main.nf -profile slurm --use_ng"
echo ""
echo "=========================================="

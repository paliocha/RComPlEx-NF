#!/bin/bash
#SBATCH --partition=orion
#SBATCH --job-name=nf-test-paths
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=6G
#SBATCH --time=01:00:00
#SBATCH --output=nf-test-paths_%A.out

# ==============================================================================
# RComPlEx Path Fix Test Script
# ==============================================================================
# Tests the pipeline with corrected ${System.getenv('HOME')} paths
# ==============================================================================

echo "=========================================="
echo "RComPlEx Path Fix Test"
echo "=========================================="
echo "Job ID: ${SLURM_JOB_ID}"
echo "Hostname: $(hostname)"
echo "Start time: $(date)"
echo "=========================================="
echo ""

# Setup environment
source ~/.bashrc
eval "$(micromamba shell hook --shell bash)"

# Activate Nextflow for pipeline orchestration
micromamba activate Nextflow
echo "✓ Activated Nextflow environment"

# Load R module
module load R/4.4.2
echo "✓ Loaded R module"
echo ""

# Get working directory
WORK_DIR=$(pwd)
echo "Working directory: ${WORK_DIR}"
cd "${WORK_DIR}"

# Display path resolution test
echo "=========================================="
echo "Path Resolution Test"
echo "=========================================="
echo "HOME environment variable: $HOME"
echo "RComPlEx will resolve to: $HOME/RComPlEx"
echo "Config file path: $HOME/RComPlEx/config/pipeline_config.yaml"
echo ""

# Run pipeline in test mode
echo "Starting Nextflow pipeline test..."
echo "Command: nextflow run main.nf -profile slurm --test_mode true"
echo "=========================================="
echo ""

nextflow run main.nf -profile slurm --test_mode true

# Capture exit status
EXIT_STATUS=$?

echo ""
echo "=========================================="
echo "Test completed with exit code: ${EXIT_STATUS}"
echo "End time: $(date)"
echo "=========================================="

exit ${EXIT_STATUS}

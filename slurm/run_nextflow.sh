#!/bin/bash
#SBATCH --partition=orion
#SBATCH --job-name=nf-complex
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=6G
#SBATCH --time=365-00:00:00
#SBATCH --output=nf-complex_%A.out

# ==============================================================================
# RComPlEx Nextflow Pipeline Submission Script
# ==============================================================================
# This script submits the Nextflow pipeline to SLURM
# Nextflow will then spawn individual jobs for each process
# ==============================================================================
#
# USAGE:
#   sbatch run_nextflow.sh [TISSUE] [TEST_MODE]
#
# ARGUMENTS:
#   TISSUE    : Specific tissue to run (default: all tissues)
#               Options: root, leaf, or leave empty for both
#   TEST_MODE : Run only 3 pairs per tissue (default: false)
#               Options: true, false
#
# EXAMPLES:
#   # Run all tissues (default)
#   sbatch run_nextflow.sh
#
#   # Test mode: 3 pairs (RECOMMENDED for initial testing)
#   sbatch run_nextflow.sh "" true
#
#   # Run only root tissue
#   sbatch run_nextflow.sh root
#
#   # Run only leaf tissue with test mode
#   sbatch run_nextflow.sh leaf true
#
# ==============================================================================

echo "=========================================="
echo "RComPlEx Nextflow Pipeline"
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
module load Anaconda3
micromamba activate Nextflow
echo "✓ Activated Nextflow environment"
echo "✓ R will come from the Apptainer container (RComPlEx.sif)"
echo ""

# Get working directory
WORK_DIR=$(pwd)
echo "Working directory: ${WORK_DIR}"
cd "${WORK_DIR}"

# Parse arguments
TISSUE=${1:-}
TEST_MODE=${2:-false}

echo "Test mode: ${TEST_MODE}"
echo ""

# Container will rely on Apptainer default auto-mounts
echo "✓ Container will use default Apptainer auto-mounts"
echo ""

# Build Nextflow command (always use slurm profile with container)
NF_CMD="nextflow run main.nf -profile slurm"

# Add tissue parameter if specified
if [ -n "${TISSUE}" ]; then
    echo "Tissue: ${TISSUE}"
    NF_CMD="${NF_CMD} --tissues ${TISSUE}"
else
    echo "Running all tissues"
fi

# Add test mode if requested
if [ "${TEST_MODE}" = "true" ]; then
    NF_CMD="${NF_CMD} --test_mode true"
fi

# Resume unless NO_RESUME environment variable is set
if [ "${NO_RESUME}" != "true" ]; then
    NF_CMD="${NF_CMD} -resume"
fi

echo ""
echo "Command: ${NF_CMD}"
echo ""

# Execute Nextflow
eval ${NF_CMD}

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "✓ Pipeline completed successfully"
    echo ""
    echo "Check results in: results/"
    echo "Execution reports:"
    echo "  - results/timeline.html"
    echo "  - results/report.html"
    echo "  - results/trace.txt"
else
    echo "✗ Pipeline failed with exit code ${EXIT_CODE}"
    echo ""
    echo "Check logs:"
    echo "  - .nextflow.log"
    echo "  - nf-complex_${SLURM_JOB_ID}.out"
fi
echo "End time: $(date)"
echo "=========================================="

exit ${EXIT_CODE}

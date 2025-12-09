#!/bin/bash
#SBATCH --partition=orion
#SBATCH --job-name=igraph
#SBATCH --nodes=1
#SBATCH --cpus-per-task=12
#SBATCH --mem=220G
#SBATCH --time=365-00:00:00
#SBATCH --output=logs/igraph_%A.out

# Load R (adjust for your cluster)
module load R/4.4.2

cd /mnt/users/martpali/AnnualPerennial/RComPlEx

mkdir -p logs

echo "Starting clique analysis"
echo "Job ID: ${SLURM_JOB_ID}"
echo "CPUs: ${SLURM_CPUS_PER_TASK}"
echo "Memory: ${SLURM_MEM_PER_NODE}MB"
echo "Start time: $(date)"
echo ""

# Run the analysis
Rscript find_cliques_furrr.R

echo ""
echo "Finished: $(date)"
echo "Check output: cliques.tsv"
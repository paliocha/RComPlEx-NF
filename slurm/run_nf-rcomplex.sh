#!/bin/bash
#SBATCH --partition=orion
#SBATCH --job-name=nf-rcomplex
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=365-00:00:00
#SBATCH --output=nf-complex_%A.out

# Setup environment
source ~/.bashrc
eval "$(micromamba shell hook --shell bash)"

# Load singularity & activate Nextflow environment
module load singularity/rpm
micromamba activate $HOME/micromamba/envs/Nextflow

# Switch primary group to fjellheimlab for correct quota accounting
# This ensures all new files count against the project quota, not personal quota
newgrp fjellheimlab << 'ENDGROUP'
umask 002
nextflow run main.nf -profile slurm -resume
ENDGROUP
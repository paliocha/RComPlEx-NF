#!/bin/bash
#SBATCH --partition=orion
#SBATCH --job-name=RComPlEx
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=200G
#SBATCH --time=365-00:00:00
#SBATCH --output=logs/RComPlEx_%A_%a.out

source ~/.bashrc
eval "$(micromamba shell hook --shell bash)"
micromamba activate pandoc

# Load R (adjust for your cluster)
module load R/4.4.2

cd /mnt/users/martpali/AnnualPerennial/RComPlEx
pwd

# Get absolute path to working directory
WORK_DIR=$(pwd)
BASE_DIR="${WORK_DIR}/rcomplex_data"
PAIR_ID=$(sed -n "${SLURM_ARRAY_TASK_ID}p" ${BASE_DIR}/job_list.txt)
PAIR_DIR="${BASE_DIR}/pairs/${PAIR_ID}"
RESULT_DIR="${BASE_DIR}/results/${PAIR_ID}"

mkdir -p logs ${RESULT_DIR}/RData

echo "Running RComPlEx for ${PAIR_ID}"

# Extract species names from config
SP1=$(grep "species1_name <-" ${PAIR_DIR}/config.R | sed 's/.*"\(.*\)".*/\1/')
SP2=$(grep "species2_name <-" ${PAIR_DIR}/config.R | sed 's/.*"\(.*\)".*/\1/')

# Run RComPlEx
Rscript -e "
source('${PAIR_DIR}/config.R')
rmarkdown::render('${WORK_DIR}/rcomplex-main/RComPlEx.Rmd', 
                  output_file = '${PAIR_ID}_report.html',
                  output_dir = '${RESULT_DIR}',
                  envir = parent.frame())
"

# Move only this pair's RData files from working directory to results
if [ -d "${WORK_DIR}/rcomplex-main/RData" ]; then
    mv ${WORK_DIR}/rcomplex-main/RData/*${SP1}-${SP2}*.RData ${RESULT_DIR}/ 2>/dev/null || true
fi

echo "Done"
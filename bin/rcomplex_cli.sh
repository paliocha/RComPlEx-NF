#!/bin/bash
# ==============================================================================
# RComPlEx CLI Wrapper
# ==============================================================================
# Convenience script for running RComPlEx pipeline steps
# ==============================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_DIR}"

CONFIG="config/pipeline_config.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
RComPlEx Pipeline CLI

Usage: $0 <command> [arguments]

Commands:
    prepare <tissue>              Prepare data for a tissue (root or leaf)
    submit <tissue> [max_jobs]    Submit RComPlEx SLURM array jobs
    cliques <tissue>              Find co-expressolog cliques
    status <tissue>               Check job status
    report                        Generate summary report
    clean <tissue>                Clean intermediate files

Examples:
    $0 prepare root               # Prepare root tissue data
    $0 submit root 20             # Submit up to 20 concurrent jobs
    $0 cliques root               # Find cliques for root tissue
    $0 status root                # Check job status
    $0 report                     # Generate final report

EOF
    exit 1
}

prepare_data() {
    local tissue=$1
    echo -e "${GREEN}Preparing data for tissue: ${tissue}${NC}"

    module load R/4.4.2

    Rscript scripts/prepare_data.R \
        --tissue "${tissue}" \
        --config "${CONFIG}" \
        --workdir "${PROJECT_DIR}"

    echo -e "${GREEN}✓ Data preparation complete${NC}"
    echo ""
    echo "Next step:"
    echo "  $0 submit ${tissue}"
}

submit_jobs() {
    local tissue=$1
    local max_concurrent=${2:-20}

    job_list="rcomplex_data/${tissue}/job_list.txt"

    if [ ! -f "${job_list}" ]; then
        echo -e "${RED}ERROR: Job list not found: ${job_list}${NC}"
        echo "Run: $0 prepare ${tissue}"
        exit 1
    fi

    n_jobs=$(wc -l < "${job_list}")

    echo -e "${GREEN}Submitting RComPlEx jobs for tissue: ${tissue}${NC}"
    echo "  - Total jobs: ${n_jobs}"
    echo "  - Max concurrent: ${max_concurrent}"

    sbatch --array=1-${n_jobs}%${max_concurrent} \
           slurm/run_rcomplex.sh "${tissue}"

    echo -e "${GREEN}✓ Jobs submitted${NC}"
    echo ""
    echo "Monitor with:"
    echo "  squeue -u $(whoami)"
    echo "  $0 status ${tissue}"
}

find_cliques() {
    local tissue=$1

    results_dir="rcomplex_data/${tissue}/results"

    if [ ! -d "${results_dir}" ]; then
        echo -e "${RED}ERROR: Results directory not found: ${results_dir}${NC}"
        echo "Run RComPlEx analyses first!"
        exit 1
    fi

    n_results=$(find "${results_dir}" -name "comparison-*.RData" | wc -l)

    if [ ${n_results} -eq 0 ]; then
        echo -e "${RED}ERROR: No comparison files found in ${results_dir}${NC}"
        exit 1
    fi

    echo -e "${GREEN}Finding co-expressolog cliques for tissue: ${tissue}${NC}"
    echo "  - Comparison files found: ${n_results}"

    module load R/4.4.2

    Rscript scripts/find_coexpressolog_cliques.R \
        --tissue "${tissue}" \
        --config "${CONFIG}" \
        --workdir "${PROJECT_DIR}" \
        --outdir "results"

    echo -e "${GREEN}✓ Clique detection complete${NC}"
}

check_status() {
    local tissue=$1

    job_list="rcomplex_data/${tissue}/job_list.txt"
    results_dir="rcomplex_data/${tissue}/results"

    if [ ! -f "${job_list}" ]; then
        echo -e "${RED}No job list found for ${tissue}${NC}"
        exit 1
    fi

    n_expected=$(wc -l < "${job_list}")
    n_completed=0

    if [ -d "${results_dir}" ]; then
        n_completed=$(find "${results_dir}" -name "comparison-*.RData" | wc -l)
    fi

    echo "Status for tissue: ${tissue}"
    echo "  Expected comparisons: ${n_expected}"
    echo "  Completed: ${n_completed}"
    echo "  Remaining: $((n_expected - n_completed))"
    echo ""

    if [ ${n_completed} -eq ${n_expected} ]; then
        echo -e "${GREEN}✓ All comparisons complete!${NC}"
        echo ""
        echo "Next step:"
        echo "  $0 cliques ${tissue}"
    else
        pct=$((100 * n_completed / n_expected))
        echo "Progress: ${pct}%"

        # Check running jobs
        n_running=$(squeue -u $(whoami) -n RComPlEx -h | wc -l)
        if [ ${n_running} -gt 0 ]; then
            echo "Running jobs: ${n_running}"
        else
            echo -e "${YELLOW}No jobs currently running${NC}"
        fi
    fi
}

generate_report() {
    echo -e "${GREEN}Generating summary report${NC}"

    module load R/4.4.2

    if [ -f "scripts/summary_report.Rmd" ]; then
        Rscript -e "rmarkdown::render('scripts/summary_report.Rmd', output_dir='results')"
        echo -e "${GREEN}✓ Report generated: results/summary_report.html${NC}"
    else
        echo -e "${YELLOW}Warning: summary_report.Rmd not found${NC}"
        echo "Skipping report generation"
    fi
}

clean_intermediate() {
    local tissue=$1

    echo -e "${YELLOW}Cleaning intermediate files for ${tissue}${NC}"
    echo "This will remove HTML reports but keep comparison RData files"
    read -p "Continue? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        find "rcomplex_data/${tissue}/results" -name "*_report.html" -delete
        find "rcomplex_data/${tissue}/results" -name "RData" -type d -exec rm -rf {} + 2>/dev/null || true
        echo -e "${GREEN}✓ Cleanup complete${NC}"
    else
        echo "Cancelled"
    fi
}

# Main command dispatcher
case "${1:-}" in
    prepare)
        [ -z "$2" ] && usage
        prepare_data "$2"
        ;;
    submit)
        [ -z "$2" ] && usage
        submit_jobs "$2" "${3:-20}"
        ;;
    cliques)
        [ -z "$2" ] && usage
        find_cliques "$2"
        ;;
    status)
        [ -z "$2" ] && usage
        check_status "$2"
        ;;
    report)
        generate_report
        ;;
    clean)
        [ -z "$2" ] && usage
        clean_intermediate "$2"
        ;;
    *)
        usage
        ;;
esac

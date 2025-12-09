# Archived Files

This directory contains scripts and documentation that have been superseded by the refactored Nextflow pipeline (as of December 2025).

## Contents

### Obsolete Prototype Scripts

- **find_cliques_furrr.R**: Early parallel clique detection using furrr (superseded by current find_coexpressolog_cliques.R)
- **find_conserved_genes.R**: Alternative clique-finding approach (experimental)
- **prepare_data.R**: Old monolithic data preparation script (replaced by inline Nextflow logic)
- **run_igraph.sh**: Standalone igraph testing script (no longer used)

### Obsolete Root-Level Scripts

- **run_rcomplex.sh**: Old SLURM array job wrapper (superseded by `slurm/run_nextflow.sh`)
- **test_pipeline.sh**: Quick test harness (replaced by `nextflow run main.nf --test_mode true`)
- **setup_conda_env.sh**: Conda environment setup (conda environment still valid, but script is archived)

### Obsolete Documentation

- **RComPlEx-NG.md**: Historical documentation about the parallelized version (now standard)
- **REFACTORING_SUMMARY.md**: Summary of earlier refactoring work (superseded by REFACTORING_COMPLETED.md)
- **READY_TO_RUN.md**: Status report from earlier phase
- **USAGE_MODULAR.md**: Outdated usage guide (see main README.md for current instructions)
- **SETUP_GUIDE.md**: Old setup guide (setup already complete)
- **.plan_containerization.md**: Historical planning document for containerization

## Why These Files Are Archived

The pipeline underwent a major simplification in December 2025 to:
1. Remove algorithm version toggles (committed to parallelized version)
2. Eliminate metadata file I/O (pair generation now inline in Nextflow)
3. Use comparison RData files directly in clique detection
4. Consolidate to a single orchestration path (Nextflow only)

Result: ~30% code reduction while maintaining 100% functionality.

## If You Need These Files

For historical context or to review earlier approaches:
- **Development history**: Check git log
- **Algorithm details**: See main RComPlEx.Rmd in rcomplex-main/ (original algorithm reference)
- **Current approach**: See main README.md and REFACTORING_COMPLETED.md

## Contact

If you have questions about why something was archived, see REFACTORING_COMPLETED.md or contact the pipeline maintainers.

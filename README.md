# RComPlEx-NF: Co-expressolog discovery using Nexflow

A modern Nextflow implementation for identifying conserved co-expressologs (co-expressed orthologs) across species with different life habits (annual vs perennial) in tissue-specific contexts.

## Documentation

- **[METHOD.md](METHOD.md)** - Detailed explanation of the RComPlEx algorithm, hypergeometric testing, and clique detection
- **[INPUT_FORMAT.md](INPUT_FORMAT.md)** - Data structure requirements, file formats, and validation
- **[INSTALLATION.md](INSTALLATION.md)** - Setup instructions for local, HPC, and Docker environments

## Overview

This pipeline identifies multi-species gene cliques where orthologous genes are **all pairwise co-expressed** across species. Unlike simple conservation tests, the clique-based approach ensures that every gene pair in a clique shows significant co-expression, forming complete subgraphs in the co-expression network.

### Key Features

- **Tissue-specific analysis**: Separate processing for root and leaf tissues
- **Life habit stratification**: Identifies annual-specific, perennial-specific, and shared cliques
- **Multi-copy ortholog handling**: Clique detection naturally handles many-to-many orthology
- **Modular design**: Can be run via convenient CLI or SLURM array jobs
- **Centralized configuration**: All parameters in a single YAML file

## Quick Start

### 1. Build Container (One-Time Setup)

```bash
# Start interactive session on login node with persistent tmux
qlogin
tmux new-session -s rcomplex_build

# Navigate and activate environment
cd /net/fs-2/scale/OrionStore/Home/martpali/AnnualPerennial/RComPlEx
source ~/.bashrc
eval "$(micromamba shell hook --shell bash)"
micromamba activate Nextflow

# Build container (15-30 minutes, builds in /tmp)
bash apptainer/build_container.sh
```

After build completes, verify: `ls -lh RComPlEx.sif` (should be ~1-1.5 GB)

### 2. Run Pipeline

```bash
# Test with 3 pairs per tissue (quick validation)
nextflow run main.nf --tissues root --test_mode true

# Full pipeline - all tissues
nextflow run main.nf

# Submit to SLURM with container
sbatch slurm/run_nextflow.sh "slurm,singularity_hpc" "" false
```

## Advanced Usage

Submit via SLURM with specific parameters:

```bash
# Run only root tissue
sbatch slurm/run_nextflow.sh slurm root false

# Test mode with 3 pairs per tissue
sbatch slurm/run_nextflow.sh slurm "" true

# Run with Apptainer container
sbatch slurm/run_nextflow.sh "slurm,singularity_hpc" "" false
```

## Configuration

Edit `config/pipeline_config.yaml` to customize:

- **Species lists**: Annual and perennial species
- **Tissues**: Which tissues to analyze
- **RComPlEx parameters**: Correlation method, network density, p-value threshold
- **Resource allocation**: CPUs, memory, time limits

## Output Files

### Per-tissue Clique Files

Located in `results/{tissue}/`:

- `coexpressolog_cliques_{tissue}_all.tsv` - All cliques with full metadata
- `coexpressolog_cliques_{tissue}_annual.tsv` - Annual-specific cliques
- `coexpressolog_cliques_{tissue}_perennial.tsv` - Perennial-specific cliques
- `coexpressolog_cliques_{tissue}_shared.tsv` - Mixed annual/perennial cliques
- `genes_{tissue}_annual.txt` - Gene lists for downstream analysis
- `genes_{tissue}_perennial.txt`
- `genes_{tissue}_mixed.txt`

### Clique File Columns

- `CliqueID`: Unique identifier (HOG_CliqueNumber)
- `HOG`: Hierarchical ortholog group
- `CliqueSize`: Number of genes in clique
- `Genes`: Comma-separated gene IDs
- `Species`: Species represented in clique
- `LifeHabit`: Annual, Perennial, or Mixed
- `n_annual_species`: Number of annual species
- `n_perennial_species`: Number of perennial species
- `n_species`: Total species count
- `Mean_pval`: Average p-value across all gene pairs
- `Median_pval`: Median p-value
- `Mean_effect_size`: Average effect size (enrichment)
- `n_edges`: Number of co-expressed gene pairs

## Pipeline Architecture

```
RComPlEx/
├── main.nf                          # Nextflow workflow (7 processes)
├── nextflow.config                  # Nextflow execution config
├── config/
│   └── pipeline_config.yaml         # Central analysis parameters
├── R/
│   └── config_parser.R              # Config utilities
├── scripts/
│   ├── prepare_single_pair.R        # Pair data preparation
│   ├── rcomplex_01_load_filter.R    # Step 1: Load & filter data
│   ├── rcomplex_02_compute_networks.R   # Step 2: Correlation networks
│   ├── rcomplex_03_network_comparison.R # Step 3: Network comparison
│   ├── rcomplex_04_summary_stats.R  # Step 4: Summary statistics
│   └── find_coexpressolog_cliques.R # Clique detection from comparisons
├── slurm/
│   └── run_nextflow.sh              # SLURM submission script for Nextflow
├── rcomplex_data/                   # Working directories
│   ├── root/                        # Root tissue analysis
│   └── leaf/                        # Leaf tissue analysis
└── results/                         # Final pipeline outputs
    ├── root/                        # Root cliques & gene lists
    └── leaf/                        # Leaf cliques & gene lists
```

## Algorithm Overview

### Workflow Steps (Nextflow Pipeline)

**PREPARE_PAIR**: Per-pair data extraction
- Loads variance-stabilized expression data (vst_hog.RDS, tissue-filtered)
- Extracts ortholog pairs from hierarchical orthogroups (N1_clean.RDS)
- Creates working directories with expression matrices and ortholog mappings

**RCOMPLEX_01**: Load & filter data for species pair
- Extract orthologs present in both species' expression datasets
- Output: `01_filtered_data.RData`

**RCOMPLEX_02**: Compute co-expression networks
- Correlations: Spearman (configurable: Pearson, Kendall)
- Normalization: Mutual Rank (configurable: CLR)
- Density threshold: Top 3% of correlations (configurable)
- Parallel across species (2 workers for both species simultaneously)
- Output: `02_networks.RData` (correlation matrices + thresholds)

**RCOMPLEX_03**: Network comparison (conservation testing)
- For each ortholog pair: Test if neighborhood co-expression is conserved
- Method: Hypergeometric test on co-expressed neighbors
- Bidirectional testing: Species1→Species2 AND Species2→Species1
- FDR correction for multiple testing
- Parallel across ortholog pairs
- Output: `03_comparison.RData` (p-values + effect sizes)

**RCOMPLEX_04**: Summary statistics & visualization
- Aggregate results into TSV format (per-gene, per-HOG stats)
- Generate p-value correlation and effect size plots
- Output: `04_summary_statistics.tsv` + PNG plots

**FIND_CLIQUES**: Clique detection (aggregated per tissue)

**Key Innovation**: Identifies multi-species cliques where ALL gene pairs are co-expressed

Algorithm:
1. Load all pairwise comparison results for a tissue
2. Extract conserved gene pairs (Max.p.val < 0.05)
3. For each hierarchical orthogroup (HOG):
   - Build undirected graph: nodes = genes, edges = conserved co-expression
   - Find maximal cliques using `igraph::max_cliques()`
   - Each clique represents genes that are ALL pairwise co-expressed
4. Annotate cliques with species and life cycle information
5. Classify as Annual, Perennial, or Mixed based on species composition
6. Export stratified results

**Why Cliques?**
- Handles many-to-many orthology naturally
- Multiple cliques can exist per HOG (different co-expression modules)
- Ensures ALL genes in a clique are mutually co-expressed
- Example: If clique has 4 genes, all 6 possible pairs must be co-expressed (p < 0.05)

## Data Requirements

### Input Files

1. **vst_hog.RDS** (253 MB): Variance-stabilized expression data
   - Columns: species, tissue, GeneID, sample_id, vst.count, life_cycle, HOG
   - Tissues: "root" and "leaf"
   - 13 grass species (5 annual, 8 perennial)

2. **N1_clean.RDS** (6 MB): Hierarchical ortholog groups
   - Columns: HOG, OG, species, GeneID, life_cycle, is_core
   - Format: One row per gene-HOG association

### Species List

**Annual (5 species):**
- Brachypodium distachyon
- Hordeum vulgare
- Vulpia bromoides
- Briza maxima
- Poa annua

**Perennial (8 species):**
- Brachypodium sylvaticum
- Hordeum jubatum
- Poa supina
- Briza media
- Festuca pratensis
- Melica nutans
- Nassella pubiflora
- Oloptum miliaceum

## Computational Requirements

### Per RComPlEx Job
- CPUs: 24
- Memory: 200 GB
- Time: Up to 7 days
- Typical runtime: 30-60 minutes per pair

### Clique Detection
- CPUs: 12
- Memory: 220 GB
- Time: Up to 2 days
- Typical runtime: 2-4 hours

### Total Pipeline
- 78 pairwise comparisons per tissue
- 2 tissues = 156 total comparisons
- With 20 concurrent jobs: ~4-6 hours wall time per tissue

## Troubleshooting

### Container Build Issues

```bash
# Verify container exists
test -f RComPlEx.sif && echo "✓ Container ready" || echo "✗ Not built"

# Check container size
du -sh RComPlEx.sif  # Should be ~1-1.5 GB

# Test container packages
apptainer exec RComPlEx.sif R --slave -e "
  pkgs <- c('igraph', 'furrr', 'future', 'yaml', 'optparse', 'glue')
  for (p in pkgs) cat(p, ':', require(p, quietly=TRUE), '\n')
"
```

### Jobs Failing with Memory Errors

Increase memory in `config/pipeline_config.yaml`:

```yaml
resources:
  rcomplex:
    memory: "250GB"  # Increase from 200GB
```

### Missing Comparison Files

Check SLURM logs in `logs/` directory:

```bash
# Find failed jobs
grep -l "failed" logs/RComPlEx_*.err

# Check specific job log
tail -50 logs/RComPlEx_JOBID_ARRAYID.out
```

### No Cliques Found

- Check p-value threshold in config (default: 0.05)
- Verify RComPlEx analyses completed successfully
- Check that comparison files exist: `find rcomplex_data/*/results -name "comparison-*.RData"`

## Citation

If you use this pipeline, please cite:

- ComPlEx method: Netotea *et al.* (2014) *BMC Genomics*. doi:[10.1186/1471-2164-15-106](https://doi.org/10.1186/1471-2164-15-106)
- R implementation: Torgeir R. Hvidsten
- Nextflow pipeline & parallelization: Martin Paliocha
- Pipeline repository: [paliocha/RComPlEx-NF](https://github.com/paliocha/RComPlEx-NF)

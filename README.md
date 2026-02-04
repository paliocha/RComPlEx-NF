# Comparative Analysis of Plant Co-Expression Networks in R

**Comparative Analysis of Plant Co-Expression Networks in R (RComPlEx)** is a Nextflow pipeline that identifies **conserved co-expressologs** which are orthologous genes that maintain coordinated expression patterns across evolutionarily divergent species.

## What Makes RComPlEx Different?

Unlike traditional comparative genomics approaches that focus on sequence conservation alone, RComPlEx discovers genes that are:

1. **Orthologous** - Share common evolutionary ancestry
2. **Co-expressed** - Show correlated expression patterns within each species  
3. **Functionally conserved** - Maintain similar regulatory relationships across species
4. **Module members** - Part of complete functional networks (cliques), not just pairwise connections

### The Clique Advantage

RComPlEx finds **multi-species gene cliques** where **all** pairwise relationships are conserved:

- **Traditional approach**: "Gene A and Gene B are co-expressed in both species"
- **RComPlEx cliques**: "Genes A, B, C, and D are all mutually co-expressed across all species" (6 pairwise relationships for 4 genes, all significant)

This ensures discovery of **complete functional modules** with tight coordination, providing stronger evidence of conserved biological function than pairwise comparisons alone.

## Documentation

- **[METHOD.md](METHOD.md)** - Detailed algorithm explanation, statistical methods, hypergeometric testing
- **[INPUT_FORMAT.md](INPUT_FORMAT.md)** - Data requirements, file formats, and validation
- **[INSTALLATION.md](INSTALLATION.md)** - Setup instructions for local, HPC, and container environments
- **[PROCESS_FLOW.txt](PROCESS_FLOW.txt)** - Step-by-step execution flow with biological context (includes unsigned and polarity analysis)

## Scientific Background

### Biological Question

**Do genes that are co-expressed in one species maintain those co-expression relationships in related species?**

Conserved co-expression suggests:
- **Shared regulatory mechanisms** (transcription factors, enhancers)
- **Functional coordination** (pathway components, protein complexes)
- **Evolutionary constraint** (selection maintains co-regulation)
- **Biological importance** (essential processes preserved across species)

### Life Habit Stratification

This implementation focuses on comparing **annual vs. perennial grasses**:

- **Annual plants**: Complete life cycle in one growing season (rapid growth, high reproduction)
- **Perennial plants**: Live multiple years (resource storage, stress tolerance, dormancy)

By stratifying cliques by life habit, RComPlEx identifies:
- **Annual-specific modules**: Genes coordinated uniquely in annual species
- **Perennial-specific modules**: Genes coordinated uniquely in perennial species  
- **Shared modules**: Core processes conserved across all plants

### Tissue Specificity

Analyzes **root** and **leaf** tissues independently:
- **Root**: Nutrient uptake, water transport, stress response, storage
- **Leaf**: Photosynthesis, gas exchange, defense, transpiration

Tissue-specific cliques reveal organ-specialized regulatory networks.

### Key Features

- **Tissue-specific analysis**: Separate processing for root and leaf tissues
- **Life habit stratification**: Identifies annual-specific, perennial-specific, and shared cliques
- **Multi-copy ortholog handling**: Clique detection naturally handles many-to-many orthology
- **Modular design**: Can be run via convenient CLI or SLURM array jobs
- **Centralized configuration**: All parameters in a single YAML file
- **Polarity divergence analysis**: Compares signed vs. unsigned support to flag potential regulatory polarity changes

## Quick Start

### Run Pipeline

```bash
# Test with 3 pairs per tissue (15-30 min - recommended first!)
nextflow run main.nf -profile slurm --test_mode true

# Full pipeline - signed networks only (default, faster)
nextflow run main.nf -profile slurm

# Full pipeline with unsigned analysis + polarity divergence
nextflow run main.nf -profile slurm --run_unsigned

# Single tissue only
nextflow run main.nf -profile slurm --tissues root

# Resume from interruption
nextflow run main.nf -profile slurm -resume
```

### SLURM Submission (Recommended)

```bash
# Submit long-running pipeline via SLURM (includes --run_unsigned by default)
sbatch slurm/run_nf-rcomplex.sh
```

### Directory Configuration

Default paths (edit `nextflow.config` to change):
- Working directory: `/mnt/users/martpali/AnnualPerennial/RComPlEx`
- Output directory: `/mnt/users/martpali/AnnualPerennial/RComPlEx/results`
- Nextflow work: `/mnt/users/martpali/AnnualPerennial/RComPlEx/work`

Override at runtime:
```bash
nextflow run main.nf -profile slurm \
  --workdir /custom/path \
  --outdir /custom/results \
  -w /custom/work
```

## Configuration

Edit `config/pipeline_config.yaml` to customize:
- Species lists (annual vs perennial)
- Tissues to analyze
- RComPlEx parameters (correlation method, network density, p-value threshold)

Edit `nextflow.config` for:
- Resource allocation (CPUs, memory, time limits)
- Directory paths
- SLURM settings

## Output Files

### Per-tissue Clique Files

Located in `results/{tissue}/`:

- `cliques.qs2` - All cliques in fast qs2 format (for R analysis)
- `cliques.csv` - All cliques in CSV format
- `cliques_annual.csv` - Annual-specific cliques
- `cliques_perennial.csv` - Perennial-specific cliques
- `cliques_shared.csv` - Mixed annual/perennial cliques

### Unsigned Clique Files (when `--run_unsigned` enabled)

Located in `results/{tissue}/`:

- `cliques_unsigned.qs2` - Unsigned cliques in qs2 format
- `cliques_unsigned.csv` - Unsigned cliques in CSV format
- `cliques_unsigned_annual.csv`, `cliques_unsigned_perennial.csv`, `cliques_unsigned_shared.csv`

### Polarity Divergence Outputs (when `--run_unsigned` enabled)

Located in `results/{tissue}/polarity/`:

- `polarity_divergence_<pair_id>.tsv` – Columns: `tissue, pair_id, gene1, gene2, score_signed, score_unsigned, polarity_divergent`
   - `polarity_divergent = TRUE` when sign differs and unsigned strength > 75th percentile

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
├── main.nf                          # Nextflow workflow (10 processes)
├── nextflow.config                  # Nextflow execution config
├── config/
│   └── pipeline_config.yaml         # Central analysis parameters
├── R/
│   ├── config_parser.R              # Config utilities
│   └── orion_hpc_utils.R            # Orion HPC path resolution
├── scripts/
│   ├── prepare_single_pair.R        # Pair data preparation
│   ├── rcomplex_01_load_filter.R    # Step 1: Load & filter data
│   ├── rcomplex_02_compute_species_network.R  # Step 2: Per-species networks (reusable)
│   ├── rcomplex_03_load_and_filter_networks.R # Step 3: Filter networks to pair
│   ├── rcomplex_03_network_comparison.R       # Step 4: Network comparison
│   ├── rcomplex_04_summary_stats.R            # Step 5: Summary statistics
│   ├── find_cliques_streaming.R               # Streaming clique detection
│   ├── polarity_divergence_report.R           # Polarity divergence analysis
│   └── validate_inputs.R                      # Input validation
├── slurm/
│   └── run_nf-rcomplex.sh           # SLURM submission script
├── rcomplex_data/                   # Working directories
│   ├── root/                        # Root tissue analysis
│   └── leaf/                        # Leaf tissue analysis
└── results/                         # Final pipeline outputs
    ├── root/                        # Root cliques & gene lists
    │   └── polarity/                # Polarity divergence reports
    └── leaf/                        # Leaf cliques & gene lists
        └── polarity/                # Polarity divergence reports
```

## Algorithm Overview

### Pipeline Workflow (10 Processes)

The pipeline has two modes:
- **Default (signed only)**: 7 processes - faster, analyzes signed correlation networks
- **With `--run_unsigned`**: 10 processes - adds unsigned network analysis + polarity divergence

#### Step 0: PREPARE_PAIR (Data Preparation)

**Purpose**: Extract tissue-specific expression data for each species pair

- Loads variance-stabilized expression matrix (vst_hog.RDS)
- Filters to focal tissue (root or leaf)
- Extracts ortholog mappings from hierarchical ortholog groups (N1_clean.RDS)
- Creates species pair working directories
- **Output**: Expression files + ortholog table per pair

---

#### Step 1: RCOMPLEX_01_LOAD_FILTER (Quality Control)

**Purpose**: Validate data and filter to analyzable gene sets

- Loads expression matrices for both species
- Filters orthologs to genes present in BOTH species' expression data
- Removes genes with missing values or low expression
- **Output**: `01_filtered_data.RData` (clean, aligned ortholog pairs)

---

#### Step 2: RCOMPLEX_02_COMPUTE_SPECIES_NETWORKS (Per-Species Networks)

**Purpose**: Build gene co-expression networks for each species (computed once, reused across pairs)

**Method**:

1. **Correlation calculation**: 
   - Spearman correlation (default) - robust to outliers, detects monotonic relationships
   - Computes all pairwise gene correlations (gene × gene matrix)
   - Gene universe is limited to genes that have an ortholog in any other species

2. **Mutual Rank normalization**:
   - Ranks correlations bidirectionally: gene_i → gene_j AND gene_j → gene_i  
   - Combines ranks: MR = √(rank_ij × rank_ji)
   - **Why?** Reduces spurious correlations, makes strengths comparable across species

3. **Density thresholding**:
   - Keep top 3% of correlations (configurable)
   - Creates sparse network of strongest co-expression

**Key Optimization**: Networks computed per species-tissue combination (not per pair), enabling massive reuse.

**Output**: `02_network_signed.qs2`, `02_network_unsigned.qs2` (fast qs2 serialization)

---

#### Step 3: RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS (Pair-Specific Filtering)

**Purpose**: Filter precomputed species networks to pair-specific ortholog genes

- Loads precomputed species networks for both species in the pair
- Subsets matrices to the pair's shared ortholog genes
- Recalibrates density thresholds if needed for consistent network sparsity
- **Output**: `02_networks_signed.qs2` (and `02_networks_unsigned.qs2` if `--run_unsigned`)

---

#### Step 4: RCOMPLEX_04_NETWORK_COMPARISON (Conservation Testing)

**Purpose**: Test whether co-expression relationships are conserved between species

**For each ortholog pair (geneA_sp1, geneB_sp2)**:

1. **Extract co-expression neighborhoods**:
   - Sp1_neighbors: All genes significantly co-expressed with geneA in Species 1
   - Sp2_neighbors: All genes significantly co-expressed with geneB in Species 2

2. **Test conservation bidirectionally**:
   
   **Direction 1 (Sp1 → Sp2)**:
   - Question: "Do geneA's neighbors in Sp1 have orthologs that are geneB's neighbors in Sp2?"
   - Count overlap of conserved co-expression relationships
   - Hypergeometric test: P(overlap ≥ observed | random expectation)
   
   **Direction 2 (Sp2 → Sp1)**:
   - Question: "Do geneB's neighbors in Sp2 have orthologs that are geneA's neighbors in Sp1?"
   - Ensures bidirectional conservation (not just one-way)
   - Use minimum p-value (most conservative estimate)

3. **Multiple testing correction**:
   - Benjamini-Hochberg FDR correction
   - Controls false discovery rate at 5% (adjustable)

**Output**: `03_comparison.RData` (p-values, effect sizes, neighborhood statistics)

---

#### Step 5: RCOMPLEX_05_SUMMARY_STATS (Aggregation)

**Purpose**: Aggregate conservation statistics and generate diagnostic plots

- Computes per-gene conservation metrics (mean/median p-values)
- Generates diagnostic visualizations
- **Output**: `04_summary_statistics.tsv` + PNG plots

---

#### Step 6: FIND_CLIQUES_STREAMING (Complete Module Discovery)

**Purpose**: Identify multi-species gene cliques where ALL pairwise co-expression is conserved

**Algorithm** (Two-Pass Streaming):

1. **Pass 1: Index HOG → files** (lightweight scan of all comparison files)
2. **Pass 2: Process per-HOG** (load only relevant data for each HOG)

**For each Hierarchical Ortholog Group (HOG)**:

a. **Build graph**:
   - Nodes = genes from all species in HOG
   - Edges = conserved co-expression relationships (p < 0.05)

b. **Find maximal cliques** using `igraph::max_cliques()`:
   - **Clique** = complete subgraph where all nodes are connected
   - **Maximal** = cannot add more genes without losing completeness

c. **Annotate cliques**:
   - Species composition
   - Life habit classification (Annual/Perennial/Mixed)
   - Statistical properties (mean p-values, effect sizes)

**Memory Efficiency**: Only one HOG's data in memory at a time.

**Output**: 
- `cliques.qs2`, `cliques.csv` (all cliques)
- `cliques_annual.csv`, `cliques_perennial.csv`, `cliques_shared.csv`

---

#### Optional: POLARITY_DIVERGENCE (Regulatory Direction Analysis)

**Enabled with**: `--run_unsigned`

**Purpose**: Flag edges where signed and unsigned support diverge (potential regulatory polarity changes)

- Compares signed vs unsigned network comparison results
- Identifies gene pairs with strong unsigned support but weak/opposite signed support
- **Output**: `polarity_divergence_<pair_id>.tsv`

---

### Why This Approach Works

**Statistical Rigor**:

- Hypergeometric test models drawing without replacement (appropriate for networks)
- Bidirectional testing ensures mutual conservation
- FDR correction controls false discoveries in large-scale testing

**Biological Relevance**:

- Cliques represent tightly coordinated gene modules
- Conservation across species indicates functional importance
- Life habit stratification reveals adaptation-specific networks
- Tissue specificity captures organ-specialized regulation

**Computational Efficiency**:

- Parallelization across species pairs and ortholog pairs
- Sparse networks reduce memory and computation
- Nextflow enables resumable, scalable execution

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

## Performance

### Optimized for NMBU Orion HPC:
- **Test mode**: 15-30 minutes (3 pairs per tissue)
- **Full pipeline (signed only)**: 2-6 hours
- **Full pipeline (with unsigned)**: 4-12 hours
- **Parallel execution**: Up to 30 jobs simultaneously (label-dependent)
- **Resources per job**: Adaptive (8 GB → 800 GB depending on step)

### Resource Allocation Summary:

| Process | CPUs | Memory | Time | MaxForks |
|---------|------|--------|------|----------|
| PREPARE_PAIR | 2 | 8 GB | 15m | 20 |
| RCOMPLEX_01_LOAD_FILTER | 2 | 8 GB | 15m | 20 |
| RCOMPLEX_02_COMPUTE_SPECIES_NETWORKS | 24→36 | 800 GB | 144h | 13 |
| RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS | 2 | 300 GB | 2h | 20 |
| RCOMPLEX_04_NETWORK_COMPARISON | 12→24 | 200→600 GB | 72h | 10 |
| RCOMPLEX_05_SUMMARY_STATS | 4 | 16 GB | 24h | 10 |
| FIND_CLIQUES_STREAMING | 4 | 64→256 GB | 24h | 4 |
| POLARITY_DIVERGENCE | 4 | 200→600 GB | 72h | - |

### Disk Space Requirements:
- Intermediate files: 10-50 GB
- Final results: 1-5 GB
- Nextflow work: 50-200 GB (can be cleaned after successful run)

## Troubleshooting

### Check Pipeline Progress
```bash
# Watch SLURM queue
watch -n 10 'squeue -u $USER'

# View logs
tail -f .nextflow.log

# Check disk space
df -h /mnt/users/martpali/AnnualPerennial/
```

### Common Issues

**No cliques found**: Check p-value threshold in `config/pipeline_config.yaml` (default: 0.05)

**Memory errors**: Pipeline automatically retries with increased memory (200 GB → 400 GB)

**Jobs stuck in queue**: Check SLURM partition limits with `scontrol show partition orion`

## Citation

If you use this pipeline, please cite:

- ComPlEx method: Netotea *et al.* (2014) *BMC Genomics*. doi:[10.1186/1471-2164-15-106](https://doi.org/10.1186/1471-2164-15-106)
- R implementation: [Torgeir R. Hvidsten](https://gitlab.com/hvidsten-lab/rcomplex)
- Nextflow pipeline & parallelization: [Martin Paliocha](https://www.nmbu.no/en/about/employees/martin-paliocha)
- Pipeline repository: [paliocha/RComPlEx-NF](https://github.com/paliocha/RComPlEx-NF)

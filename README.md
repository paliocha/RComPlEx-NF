# RComPlEx-NF: Comparative Analysis of Plant Co-Expression Networks in R

**RComPlEx** is a Nextflow pipeline that identifies **conserved co-expressologs** which are orthologous genes that maintain coordinated expression patterns across evolutionarily divergent species.

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
- **[PROCESS_FLOW.txt](PROCESS_FLOW.txt)** - Step-by-step execution flow with biological context

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

### Pipeline Workflow (5 Main Steps)

#### Step 0: PREPARE_PAIR (Data Preparation)

**Purpose**: Extract tissue-specific expression data for each species pair

- Loads variance-stabilized expression matrix (vst_hog.RDS)
- Filters to focal tissue (root or leaf)
- Extracts ortholog mappings from hierarchical ortholog groups (N1_clean.RDS)
- Creates species pair working directories
- **Output**: Expression files + ortholog table per pair

---

#### Step 1: LOAD_FILTER (Quality Control)

**Purpose**: Validate data and filter to analyzable gene sets

- Loads expression matrices for both species
- Filters orthologs to genes present in BOTH species' expression data
- Removes genes with missing values or low expression
- **Output**: `01_filtered_data.RData` (clean, aligned ortholog pairs)

---

#### Step 2: COMPUTE_NETWORKS (Co-Expression Discovery)

**Purpose**: Build gene co-expression networks for each species

**Method**:

1. **Correlation calculation**: 
   - Spearman correlation (default) - robust to outliers, detects monotonic relationships
   - Computes all pairwise gene correlations (gene × gene matrix)

2. **Mutual Rank normalization**:
   - Ranks correlations bidirectionally: gene_i → gene_j AND gene_j → gene_i  
   - Combines ranks: MR = √(rank_ij × rank_ji)
   - **Why?** Reduces spurious correlations, makes strengths comparable across species

3. **Density thresholding**:
   - Keep top 3% of correlations (configurable)
   - Creates sparse network of strongest co-expression
   - Reduces noise and computational complexity

**Parallelization**: 2 species computed simultaneously (24 cores total)

**Output**: `02_networks.RData` (correlation matrices + thresholds)

---

#### Step 3: NETWORK_COMPARISON (Conservation Testing)

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

3. **Statistical testing**:

   ```text
   Hypergeometric test: P(X ≥ k) where:
     k = observed overlap of conserved co-expression
     m = neighborhood size in species 1
     n = non-neighbors in species 1  
     k = neighborhood size in species 2
   ```

   - Tests if overlap is greater than random chance
   - Accounts for network structure and gene set sizes

4. **Multiple testing correction**:
   - Benjamini-Hochberg FDR correction
   - Controls false discovery rate at 5% (adjustable)
   - Testing ~10,000 ortholog pairs requires stringent correction

**Parallelization**: Processes ortholog pairs in parallel (24 cores)

**Output**: `03_comparison.RData` (p-values, effect sizes, neighborhood statistics)

---

#### Step 4: SUMMARY_STATS (Aggregation & Visualization)

**Purpose**: Aggregate conservation statistics and generate diagnostic plots

- Computes per-gene conservation metrics (mean/median p-values)
- Computes per-HOG statistics (family-level conservation)
- Generates diagnostic visualizations:
  - P-value correlation plot (bidirectional agreement)
  - Effect size distribution (conservation signal strength)

**Output**: `04_summary_statistics.tsv` + PNG plots

---

#### Step 5: FIND_CLIQUES (Complete Module Discovery) ⭐ KEY BIOLOGICAL OUTPUT

**Purpose**: Identify multi-species gene cliques where ALL pairwise co-expression is conserved

**Algorithm**:

1. **Aggregate all pairwise comparisons** for tissue:
   - Combine results from ALL species pair analyses
   - Filter to significantly conserved pairs (p < 0.05 after FDR)

2. **For each Hierarchical Ortholog Group (HOG)**:
   
   a. **Build graph**:
      - Nodes = genes from all species in HOG
      - Edges = conserved co-expression relationships
   
   b. **Find maximal cliques** using `igraph::max_cliques()`:
      - **Clique** = complete subgraph where all nodes are connected to all others
      - **Maximal** = cannot add more genes without losing completeness
      - Example: 4-gene clique requires 6 conserved edges (all pairs)
   
   c. **Why cliques?**
      - Handles many-to-many orthology (paralogs → separate cliques)
      - Ensures COMPLETE coordination (not partial)
      - Stronger functional evidence than pairwise connections
      - Multiple cliques per HOG = different functional modules

3. **Annotate cliques**:
   - Species composition (which species represented)
   - Life habit classification:
     - **Annual**: All genes from annual species only
     - **Perennial**: All genes from perennial species only  
     - **Mixed**: Contains both annual and perennial genes
   - Statistical properties (mean p-values, effect sizes, edge counts)

4. **Export stratified results**:
   - Separate files for annual, perennial, and mixed cliques
   - Gene lists for downstream enrichment analysis

**Output**: 

- `coexpressolog_cliques_{tissue}_{habit}.tsv` (4 files: all, annual, perennial, shared)
- `genes_{tissue}_{habit}.txt` (gene lists for GO/pathway enrichment)

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
- R implementation: [Torgeir R. Hvidsten](https://gitlab.com/hvidsten-lab/rcomplex)
- Nextflow pipeline & parallelization: [Martin Paliocha](https://www.nmbu.no/en/about/employees/martin-paliocha)
- Pipeline repository: [paliocha/RComPlEx-NF](https://github.com/paliocha/RComPlEx-NF)

# Using the Modular RComPlEx Pipeline

## Quick Start

Run the full pipeline as normal:

```bash
nextflow run main.nf \
    -profile slurm \
    --tissues root,leaf \
    --use_ng
```

The pipeline will automatically execute all four RComPlEx steps for each species pair.

## Modular Scripts Structure

The RComPlEx analysis has been split into 4 independent scripts:

### Step 1: Load and Filter Data
```bash
module load R/4.4.2
Rscript scripts/rcomplex_01_load_filter.R \
    --tissue root \
    --pair_id Species1_Species2 \
    --config config/pipeline_config.yaml \
    --workdir . \
    --outdir results/
```

**Input**: Pair configuration files, expression data, ortholog groups
**Output**: `01_filtered_data.RData`

### Step 2: Compute Co-Expression Networks
```bash
module load R/4.4.2
Rscript scripts/rcomplex_02_compute_networks.R \
    --tissue root \
    --pair_id Species1_Species2 \
    --config config/pipeline_config.yaml \
    --workdir . \
    --indir results/ \
    --outdir results/ \
    --cores 24
```

**Input**: `01_filtered_data.RData` from step 1
**Output**: `02_networks.RData`

### Step 3: Network Comparison
```bash
module load R/4.4.2
Rscript scripts/rcomplex_03_network_comparison.R \
    --tissue root \
    --pair_id Species1_Species2 \
    --config config/pipeline_config.yaml \
    --workdir . \
    --indir results/ \
    --outdir results/ \
    --cores 24
```

**Input**: `01_filtered_data.RData`, `02_networks.RData`
**Output**: `03_comparison.RData`

### Step 4: Summary Statistics
```bash
module load R/4.4.2
Rscript scripts/rcomplex_04_summary_stats.R \
    --tissue root \
    --pair_id Species1_Species2 \
    --workdir . \
    --indir results/ \
    --outdir results/
```

**Input**: `03_comparison.RData`
**Output**:
- `04_summary_statistics.tsv`
- `04_pvalue_correlation.png`
- `04_effect_size_plot.png`

## Manual Workflow Example

To manually run all steps for a single pair:

```bash
# Set variables
TISSUE="root"
PAIR="Brachypodium_distachyon_Hordeum_vulgare"
WORKDIR="/net/fs-2/scale/OrionStore/Home/martpali/AnnualPerennial/RComPlEx"
OUTDIR="${WORKDIR}/test_results/${TISSUE}/${PAIR}"

# Create output directory
mkdir -p "$OUTDIR"
cd "$OUTDIR"

# Step 1: Load and filter
echo "Step 1: Load and filter data..."
Rscript ${WORKDIR}/scripts/rcomplex_01_load_filter.R \
    --tissue "$TISSUE" \
    --pair_id "$PAIR" \
    --config "${WORKDIR}/config/pipeline_config.yaml" \
    --workdir "$WORKDIR" \
    --outdir .

# Step 2: Compute networks
echo "Step 2: Compute networks..."
Rscript ${WORKDIR}/scripts/rcomplex_02_compute_networks.R \
    --tissue "$TISSUE" \
    --pair_id "$PAIR" \
    --config "${WORKDIR}/config/pipeline_config.yaml" \
    --workdir "$WORKDIR" \
    --indir . \
    --outdir . \
    --cores 24

# Step 3: Network comparison
echo "Step 3: Compare networks..."
Rscript ${WORKDIR}/scripts/rcomplex_03_network_comparison.R \
    --tissue "$TISSUE" \
    --pair_id "$PAIR" \
    --config "${WORKDIR}/config/pipeline_config.yaml" \
    --workdir "$WORKDIR" \
    --indir . \
    --outdir . \
    --cores 24

# Step 4: Summary statistics
echo "Step 4: Generate summary..."
Rscript ${WORKDIR}/scripts/rcomplex_04_summary_stats.R \
    --tissue "$TISSUE" \
    --pair_id "$PAIR" \
    --workdir "$WORKDIR" \
    --indir . \
    --outdir .

echo "Complete! Results in $OUTDIR"
```

## Debugging Individual Steps

Each step saves its output as an RData file. To inspect intermediate results:

```r
# Load the filtered data
load("01_filtered_data.RData")
head(ortho)
dim(species1_expr)
dim(species2_expr)

# Load the networks
load("02_networks.RData")
dim(species1_net)
summary(species1_thr)

# Load the comparison results
load("03_comparison.RData")
head(comparison)
sum(comparison$Species1.p.val < 0.05)
```

## If a Step Fails

1. **Identify the failing step** from the Nextflow error message
2. **Check the log** in the Nextflow work directory or results folder
3. **Fix the issue** (if it's a data problem, check the intermediate RData files)
4. **Re-run just that step** and Nextflow will automatically re-execute downstream steps

Example: If step 3 fails, you can:
```bash
# Copy the work directory from failed job
cp -r .nextflow/work/XX/YYYYYY ~/debug_pair

cd ~/debug_pair

# Re-run step 3 directly
module load R/4.4.2
Rscript scripts/rcomplex_03_network_comparison.R \
    --tissue root \
    --pair_id Species1_Species2 \
    --config config/pipeline_config.yaml \
    --workdir . \
    --indir . \
    --outdir . \
    --cores 24
```

## Performance Tuning

### Memory and CPU Allocation

Edit `main.nf` to adjust resources for each step:

```nextflow
process RCOMPLEX_02_COMPUTE_NETWORKS {
    cpus 32          // Increase for faster MR normalization
    memory '150 GB'  // Increase for larger datasets
    time '8h'        // Increase if timeout occurs
}
```

### Parallel Workers

Each script respects the `--cores` parameter and automatically:
- Uses SLURM_CPUS_PER_TASK if not explicitly set
- Falls back to detectCores() if neither is available
- Never uses fewer than 1 core

### Intermediate File Storage

RData files are stored in the Nextflow work directory and copied to results. To save disk space:
- Delete intermediate RData files after verification
- Keep only final `04_summary_statistics.tsv` and plots if space is critical

## Configuration

All scripts use the same configuration file defined in `config/pipeline_config.yaml`:

```yaml
rcomplex:
  cor_method: "spearman"    # Method for correlation: pearson, spearman
  cor_sign: ""              # "" for signed, "abs" for absolute correlation
  norm_method: "MR"         # Normalization: "MR" (mutual rank) or "CLR" (centered log ratio)
  density_thr: 0.03         # Network density threshold: 0.01-0.1 (default 3%)
```

To use different parameters for specific runs:
1. Create a modified config file
2. Pass it with `--config /path/to/custom_config.yaml`

## Advantages of Modular Architecture

| Feature | Benefit |
|---------|---------|
| **Separate scripts** | Easier to understand, modify, test |
| **Intermediate files** | Debug data, resume from failures |
| **Per-step resources** | Optimize CPU/memory for each stage |
| **Independent caching** | Nextflow caches each step separately |
| **Error isolation** | One step's failure doesn't affect others |
| **Custom analyses** | Use intermediate files for additional downstream work |

## Comparing to Original Single-File Version

The original `RComPlEx-NG.Rmd` performed all steps in one Rmarkdown document. The modular version:

- **Splits into 4 clear stages** instead of one monolithic file
- **Saves intermediate results** for inspection and debugging
- **Uses native R scripts** instead of Rmarkdown (faster execution)
- **Integrates cleanly with Nextflow** as separate processes
- **Maintains identical analysis logic** (all algorithms unchanged)
- **Adds better error messages** and progress tracking

## Troubleshooting

### "Step X output not found"
The previous step may have failed. Check the Nextflow logs for that step.

### "Pair directory not found"
Ensure PREPARE_PAIR process completed successfully. Check:
```bash
ls rcomplex_data/tissue/pairs/PairID/
```

### "Ortholog file not found"
Verify the ortholog file path in pair configuration:
```bash
cat rcomplex_data/tissue/pairs/PairID/config.R | grep ortholog_group_file
```

### Out of memory
Increase memory in main.nf for the failing step:
```nextflow
memory '200 GB'  // or higher
```

### Script takes too long
Increase cores and/or time:
```nextflow
cpus 32
time '8h'
```

## Next Steps

1. **Run the full pipeline** with default parameters
2. **Monitor progress** with `nextflow log` and work directory
3. **Check results** in `rcomplex_data/tissue/results/pair_id/`
4. **Inspect plots** generated by step 4
5. **Use FIND_CLIQUES** process for downstream analysis

For questions or issues, check:
- `MODULAR_RCOMPLEX.md` for architecture details
- Individual script help: `Rscript script.R --help`
- Nextflow logs: `.nextflow/logs/`

# RComPlEx-NF Directory Configuration Guide

## 📂 Understanding Pipeline Directories

RComPlEx-NF uses three types of directories that can all be customized:

### 1. **Working Directory** (`--workdir`)
- **Purpose:** Stores intermediate pipeline files and data
- **Default:** `${projectDir}` (where the pipeline is located)
- **Contains:**
  - `rcomplex_data/` - Intermediate R data and network files
  - Organized by tissue and species pairs

### 2. **Output Directory** (`--outdir`)
- **Purpose:** Final results and reports
- **Default:** `${projectDir}/results`
- **Contains:**
  - Network files (SIF format)
  - Expression matrices
  - Comparison results
  - HTML reports

### 3. **Nextflow Work Directory** (`-w` or `workDir`)
- **Purpose:** Temporary execution files and task staging
- **Default:** `./work` (in current directory)
- **Contains:**
  - Task execution directories
  - Cached process outputs
  - Temporary staging files

---

## 🎯 Quick Configuration Examples

### Example 1: Keep Everything Local (Default)
```bash
nextflow run main.nf -profile slurm
```
- Working dir: `./` (project directory)
- Output dir: `./results`
- Work dir: `./work`

### Example 2: Use Scratch Space for Work Directory
```bash
nextflow run main.nf -profile slurm \
  -w /scratch/$USER/rcomplex_work
```
- Working dir: `./` (project directory)
- Output dir: `./results`
- Work dir: `/scratch/$USER/rcomplex_work` ✅ Faster I/O!

### Example 3: Full Custom Configuration
```bash
nextflow run main.nf -profile slurm \
  --workdir /scratch/$USER/rcomplex_data \
  --outdir /project/results/rcomplex_run1 \
  -w /scratch/$USER/rcomplex_work
```
- Working dir: `/scratch/$USER/rcomplex_data` (intermediate files)
- Output dir: `/project/results/rcomplex_run1` (final results)
- Work dir: `/scratch/$USER/rcomplex_work` (Nextflow temp files)

### Example 4: Separate Data Processing Location
```bash
nextflow run main.nf -profile slurm \
  --workdir /local/data/rcomplex \
  --outdir ~/results/$(date +%Y%m%d)_rcomplex
```
- Working dir: `/local/data/rcomplex` (fast local disk)
- Output dir: `~/results/20251211_rcomplex` (timestamped results)
- Work dir: `./work` (default)

---

## ⚙️ Configuration Methods

### Method 1: Command Line (Recommended for Flexibility)
```bash
nextflow run main.nf \
  --workdir /path/to/work \
  --outdir /path/to/output \
  -w /path/to/nextflow/work
```

### Method 2: Edit nextflow.config (Recommended for Consistency)
Edit `nextflow.config` and modify:

```groovy
params {
    workdir = "/scratch/$USER/rcomplex_data"
    outdir = "/project/results/rcomplex"
}

// Uncomment and set Nextflow work directory
workDir = "/scratch/$USER/rcomplex_work"
```

### Method 3: Environment Variable
```bash
export NXF_WORK=/scratch/$USER/rcomplex_work
nextflow run main.nf --workdir /scratch/$USER/data --outdir ~/results
```

### Method 4: Custom Config File
Create `custom.config`:
```groovy
params {
    workdir = "/scratch/$USER/rcomplex_data"
    outdir = "/project/results/rcomplex"
}
workDir = "/scratch/$USER/rcomplex_work"
```

Run with:
```bash
nextflow run main.nf -c custom.config
```

---

## 💡 Best Practices for Orion HPC

### Recommended Setup for Orion:
```bash
# Set up directories
SCRATCH_BASE="/scratch/$USER/rcomplex"
PROJECT_BASE="/path/to/your/project"

# Create directories
mkdir -p $SCRATCH_BASE/{data,work}
mkdir -p $PROJECT_BASE/results

# Run pipeline
nextflow run main.nf -profile slurm \
  --workdir $SCRATCH_BASE/data \
  --outdir $PROJECT_BASE/results \
  -w $SCRATCH_BASE/work \
  -resume
```

### Why This Configuration?
1. **Scratch space** (`/scratch`) for intermediate and temporary files
   - ✅ Faster I/O performance
   - ✅ More space available
   - ✅ Automatically cleaned after job completion

2. **Project space** for final results
   - ✅ Permanent storage
   - ✅ Backed up
   - ✅ Easy to access later

---

## 📊 Directory Structure with Custom Paths

### With Default Settings:
```
RComPlEx-NF/
├── main.nf
├── nextflow.config
├── work/                    # Nextflow temp files
├── rcomplex_data/           # Intermediate files (workdir)
│   ├── root/
│   └── leaf/
└── results/                 # Final outputs (outdir)
    ├── root/
    ├── leaf/
    └── reports/
```

### With Custom Configuration:
```
/scratch/$USER/rcomplex/
├── work/                    # Nextflow temp files (-w)
└── data/                    # Intermediate files (--workdir)
    ├── rcomplex_data/
    │   ├── root/
    │   └── leaf/

/project/results/
└── rcomplex_run1/           # Final outputs (--outdir)
    ├── root/
    ├── leaf/
    └── reports/

/path/to/RComPlEx-NF/        # Pipeline code only
├── main.nf
├── nextflow.config
└── scripts/
```

---

## 🔍 What Goes Where?

### Working Directory (`--workdir`)
Files created:
```
rcomplex_data/
├── root/
│   ├── pairs/
│   │   ├── sp1_sp2/
│   │   │   ├── *.RData           # Prepared data for each pair
│   │   └── ...
│   └── results/
│       ├── sp1_sp2/
│       │   ├── filtered_*.RData  # Filtered expression data
│       │   └── ...
└── leaf/
    └── (same structure)
```

**Size:** ~10-50 GB depending on data
**Access pattern:** Read/write intensive during processing
**Lifespan:** Can be deleted after successful run (use `-resume` to keep)

### Output Directory (`--outdir`)
Files created:
```
results/
├── root/
│   ├── RComPlEx_expression_matrix_root.csv
│   ├── RComPlEx_sif_top_interactions_root.csv
│   └── ...
├── leaf/
│   └── (same structure)
├── EdgeR_comparison_*.csv
├── shared_interactions_*.csv
├── report.html
└── timeline.html
```

**Size:** ~1-5 GB (final results only)
**Access pattern:** Write once, read many
**Lifespan:** Permanent (these are your results!)

### Nextflow Work Directory (`-w`)
Files created:
```
work/
├── 12/
│   └── 34abc5def...          # Task execution directory
│       ├── .command.sh       # Task script
│       ├── .command.log      # Task log
│       └── [task outputs]    # Cached outputs
└── ...
```

**Size:** Can grow large (100+ GB with full caching)
**Access pattern:** Frequent reads for `-resume`
**Lifespan:** Clean up after successful runs (keep for `-resume`)

---

## 🧹 Cleanup Strategies

### After Successful Run (Save Space):
```bash
# Keep results, remove intermediate and temp files
rm -rf work/
rm -rf $WORKDIR/rcomplex_data/

# Or if you might need to resume:
# Keep work directory for 30 days, then clean
find work/ -type d -mtime +30 -exec rm -rf {} +
```

### For Resume Capability:
```bash
# Keep work/ and workdir, only remove specific failed tasks
nextflow clean -f -k  # Keep only successful task work directories
```

### Complete Cleanup:
```bash
# Remove everything except final results
rm -rf work/
rm -rf rcomplex_data/
rm -f .nextflow.log*
rm -rf .nextflow/

# Keep only results directory
```

---

## 🎯 Common Use Cases

### 1. Multiple Runs with Different Parameters
```bash
# Run 1: All tissues
nextflow run main.nf -profile slurm \
  --outdir results/run1_all_tissues \
  -w work_run1

# Run 2: Root only
nextflow run main.nf -profile slurm \
  --tissues root \
  --outdir results/run2_root_only \
  -w work_run2
```

### 2. Test Run on Fast Storage, Production on Permanent Storage
```bash
# Test run (fast, temporary)
nextflow run main.nf -profile test \
  --workdir /local/scratch \
  --outdir /local/scratch/results \
  -w /local/scratch/work

# Production run (permanent storage)
nextflow run main.nf -profile slurm \
  --workdir /scratch/$USER/data \
  --outdir /project/permanent/results \
  -w /scratch/$USER/work
```

### 3. Shared Project, Individual Work Directories
```bash
# Each user runs with their own scratch space
nextflow run main.nf -profile slurm \
  --workdir /scratch/$USER/rcomplex_data \
  --outdir /project/shared/results/$USER \
  -w /scratch/$USER/work
```

---

## ⚠️ Important Notes

1. **Create directories first:**
   ```bash
   mkdir -p /path/to/workdir /path/to/outdir /path/to/work
   ```

2. **Absolute paths recommended:**
   Use full paths (`/scratch/...`) instead of relative (`../scratch`) for clarity

3. **Check disk space:**
   ```bash
   df -h /scratch/$USER  # Check available space
   ```

4. **Permissions:**
   Ensure you have write access to all directories:
   ```bash
   touch /path/to/workdir/test && rm /path/to/workdir/test
   ```

5. **Resume after directory changes:**
   Changing directories breaks `-resume` capability. If you change paths, it's a fresh run.

---

## 📞 Quick Reference

| Directory Type | Parameter | Default | Purpose |
|---------------|-----------|---------|---------|
| **Working Dir** | `--workdir` | `${projectDir}` | Intermediate pipeline files |
| **Output Dir** | `--outdir` | `${projectDir}/results` | Final results |
| **Nextflow Work** | `-w` or `workDir` | `./work` | Temporary execution files |

### Quick Command Template:
```bash
nextflow run main.nf -profile slurm \
  --workdir /path/to/intermediate/files \
  --outdir /path/to/final/results \
  -w /path/to/nextflow/temp
```

---

## 🚀 Ready to Configure?

Choose your setup based on your needs:
- **Simple:** Use defaults (all local)
- **Optimized:** Use scratch for work/workdir, project for outdir
- **Flexible:** Use command-line parameters for each run
- **Consistent:** Edit nextflow.config for permanent settings

**Happy computing!** 🧬

---

*For more information, see: OPTIMIZATION_SUMMARY.md, DEPLOYMENT_CHECKLIST.md*

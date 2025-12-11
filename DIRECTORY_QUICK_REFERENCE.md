# 📂 RComPlEx Directory Configuration - Quick Reference

## Three Types of Directories

| Type | Parameter | Default | What It Stores |
|------|-----------|---------|----------------|
| **Working** | `--workdir` | `./` | Intermediate R data files |
| **Output** | `--outdir` | `./results` | Final results & reports |
| **Nextflow Work** | `-w` | `./work` | Temporary execution files |

---

## 🚀 Quick Start Examples

### Default (Everything Local)
```bash
nextflow run main.nf -profile slurm
```

### Recommended for Orion HPC
```bash
# Use scratch space for speed
nextflow run main.nf -profile slurm \
  --workdir /scratch/$USER/rcomplex \
  --outdir ~/results/rcomplex \
  -w /scratch/$USER/work
```

### Custom All Directories
```bash
nextflow run main.nf -profile slurm \
  --workdir /path/to/intermediate \
  --outdir /path/to/results \
  -w /path/to/nextflow_work
```

### Test Mode with Custom Directories
```bash
nextflow run main.nf -profile test \
  --workdir /tmp/test \
  --outdir /tmp/results \
  -w /tmp/work
```

---

## ⚙️ Configuration Methods

### 1. Command Line (Most Flexible)
```bash
nextflow run main.nf --workdir /path --outdir /path -w /path
```

### 2. Edit nextflow.config (Most Consistent)
```groovy
params {
    workdir = "/scratch/$USER/rcomplex"
    outdir = "/project/results"
}

// Uncomment to set Nextflow work directory:
workDir = "/scratch/$USER/work"
```

### 3. Custom Config File
Create `my_dirs.config`:
```groovy
params.workdir = "/scratch/data"
params.outdir = "/project/results"
workDir = "/scratch/work"
```

Run with: `nextflow run main.nf -c my_dirs.config`

---

## 💾 Disk Space Estimates

| Directory | Typical Size | Can Delete After? |
|-----------|--------------|-------------------|
| `workdir` | 10-50 GB | ✅ Yes (after successful run) |
| `outdir` | 1-5 GB | ❌ No (these are your results!) |
| `-w` (work) | 50-200 GB | ✅ Yes (unless using -resume) |

---

## 🧹 Cleanup After Run

### Safe Cleanup (Keep Results)
```bash
rm -rf work/                    # Remove Nextflow temp
rm -rf rcomplex_data/           # Remove intermediate files
# Keep results/ directory!
```

### Full Cleanup
```bash
rm -rf work/ rcomplex_data/ .nextflow* results/
```

### Keep Resume Capability
```bash
nextflow clean -f -k  # Keep successful task work dirs
```

---

## 📍 Where Files Actually Go

### `--workdir` Creates:
```
/your/workdir/
└── rcomplex_data/
    ├── root/
    │   ├── pairs/sp1_sp2/*.RData
    │   └── results/sp1_sp2/*.RData
    └── leaf/
        └── (same structure)
```

### `--outdir` Creates:
```
/your/outdir/
├── root/
│   ├── RComPlEx_expression_matrix_root.csv
│   ├── RComPlEx_sif_top_interactions_root.csv
├── leaf/
│   └── (similar files)
├── EdgeR_comparison_*.csv
├── report.html
└── timeline.html
```

### `-w` Creates:
```
/your/work/
├── ab/
│   └── 123abc.../ (task directory)
├── cd/
│   └── 456def.../ (task directory)
└── ...
```

---

## ⚠️ Important Tips

1. **Create directories first:**
   ```bash
   mkdir -p /path/to/workdir /path/to/outdir /path/to/work
   ```

2. **Use absolute paths:**
   ```bash
   --workdir /scratch/data  ✅
   --workdir ../data        ❌ (can cause issues)
   ```

3. **Check disk space:**
   ```bash
   df -h /scratch/$USER
   ```

4. **Test permissions:**
   ```bash
   touch /path/test && rm /path/test
   ```

---

## 🎯 Common Scenarios

### Scenario 1: Multiple Runs, Separate Results
```bash
# Run 1
nextflow run main.nf --outdir results/run1 -w work1

# Run 2
nextflow run main.nf --outdir results/run2 -w work2
```

### Scenario 2: Share Results, Private Work
```bash
nextflow run main.nf \
  --workdir /scratch/$USER/work \
  --outdir /project/shared/results \
  -w /scratch/$USER/nextflow_work
```

### Scenario 3: Fast Scratch, Permanent Results
```bash
nextflow run main.nf \
  --workdir /local/fast_scratch \
  --outdir /network/permanent/storage \
  -w /local/fast_scratch/work
```

---

## 📖 Full Documentation

For detailed information, see: **DIRECTORY_CONFIGURATION.md**

---

**Questions? Check the help:**
```bash
nextflow run main.nf --help
```

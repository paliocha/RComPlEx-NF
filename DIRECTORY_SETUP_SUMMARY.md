# RComPlEx-NF Directory Configuration

## 📂 Current Directory Settings

Your pipeline is now configured with the following default directories:

### **Working Directory**
```
/mnt/users/martpali/AnnualPerennial/RComPlEx
```
- **Purpose:** Stores intermediate pipeline files and data
- **Contains:** `rcomplex_data/` with tissue-specific intermediate files
- **Parameter:** `params.workdir`

### **Output Directory**
```
/mnt/users/martpali/AnnualPerennial/RComPlEx/results
```
- **Purpose:** Final results, reports, and published outputs
- **Contains:** Network files, expression matrices, comparison results, HTML reports
- **Parameter:** `params.outdir`

### **Nextflow Work Directory**
```
/mnt/users/martpali/AnnualPerennial/RComPlEx/work
```
- **Purpose:** Temporary execution files and task staging
- **Contains:** Task directories, cached outputs, execution logs
- **Setting:** `workDir` (Nextflow global)

---

## 🚀 Running the Pipeline

### Basic Run (Uses Configured Directories)
```bash
cd /path/to/RComPlEx-NF
nextflow run main.nf -profile slurm
```

### With Resume (Uses Cached Results)
```bash
nextflow run main.nf -profile slurm -resume
```

### Test Mode
```bash
nextflow run main.nf -profile slurm --test_mode true
```

### Single Tissue
```bash
nextflow run main.nf -profile slurm --tissues root
```

---

## 📊 Directory Structure (What Gets Created)

After running the pipeline, you'll see:

```
/mnt/users/martpali/AnnualPerennial/RComPlEx/
├── rcomplex_data/              # Intermediate files (workdir)
│   ├── root/
│   │   ├── pairs/
│   │   │   ├── sp1_sp2/
│   │   │   │   └── *.RData
│   │   │   └── ...
│   │   └── results/
│   │       └── sp1_sp2/
│   │           └── *.RData
│   └── leaf/
│       └── (same structure)
│
├── results/                     # Final outputs (outdir)
│   ├── root/
│   │   ├── RComPlEx_expression_matrix_root.csv
│   │   ├── RComPlEx_sif_top_interactions_root.csv
│   │   └── ...
│   ├── leaf/
│   │   └── (similar files)
│   ├── EdgeR_comparison_*.csv
│   ├── shared_interactions_*.csv
│   ├── report.html
│   └── timeline.html
│
└── work/                        # Nextflow temp files (workDir)
    ├── 12/
    │   └── 34abc5def.../
    │       ├── .command.sh
    │       ├── .command.log
    │       └── [cached outputs]
    └── ...
```

---

## 🔧 Override Directories (If Needed)

Even though directories are configured, you can still override them:

### Override Working Directory
```bash
nextflow run main.nf --workdir /different/path
```

### Override Output Directory
```bash
nextflow run main.nf --outdir /different/path/results
```

### Override Nextflow Work Directory
```bash
nextflow run main.nf -w /different/path/work
```

### Override All
```bash
nextflow run main.nf \
  --workdir /path1 \
  --outdir /path2 \
  -w /path3
```

---

## 💾 Disk Space Requirements

| Directory | Estimated Size | Notes |
|-----------|---------------|-------|
| **workdir** | 10-50 GB | Intermediate R data files |
| **outdir** | 1-5 GB | Final results only |
| **work** | 50-200 GB | Nextflow caching (grows with runs) |

**Total:** Plan for ~60-260 GB depending on data size and number of runs

---

## 🧹 Cleanup After Successful Runs

### Keep Results, Remove Temp Files
```bash
# Remove Nextflow work directory
rm -rf /mnt/users/martpali/AnnualPerennial/RComPlEx/work/*

# Remove intermediate files
rm -rf /mnt/users/martpali/AnnualPerennial/RComPlEx/rcomplex_data/*

# Your results are safe in:
ls /mnt/users/martpali/AnnualPerennial/RComPlEx/results/
```

### Keep Resume Capability
```bash
# Only clean failed tasks
cd /path/to/RComPlEx-NF
nextflow clean -f -k  # Keeps successful task directories
```

### Complete Cleanup (Fresh Start)
```bash
rm -rf /mnt/users/martpali/AnnualPerennial/RComPlEx/work
rm -rf /mnt/users/martpali/AnnualPerennial/RComPlEx/rcomplex_data
rm -rf /mnt/users/martpali/AnnualPerennial/RComPlEx/results
```

---

## ⚠️ Important Notes

### 1. Directories Must Exist and Be Writable
Before running, ensure:
```bash
# Check directories exist (create if needed)
mkdir -p /mnt/users/martpali/AnnualPerennial/RComPlEx/{results,work,rcomplex_data}

# Verify write permissions
touch /mnt/users/martpali/AnnualPerennial/RComPlEx/test && \
  rm /mnt/users/martpali/AnnualPerennial/RComPlEx/test
```

### 2. Check Available Disk Space
```bash
df -h /mnt/users/martpali/AnnualPerennial/
```

Ensure you have at least **100-300 GB free** for a full run.

### 3. Resume Only Works with Same Work Directory
If you change the work directory, `-resume` won't work (it's a fresh run).

### 4. Relative vs Absolute Paths
- ✅ Using absolute paths (as configured) is recommended
- ❌ Avoid relative paths which can cause issues with task execution

---

## 🔍 Verify Configuration

Check your current settings:

```bash
cd /path/to/RComPlEx-NF

# View configured directories
nextflow config | grep -E "workdir|outdir|workDir"

# Should show:
# params.workdir = '/mnt/users/martpali/AnnualPerennial/RComPlEx'
# params.outdir = '/mnt/users/martpali/AnnualPerennial/RComPlEx/results'
# workDir = '/mnt/users/martpali/AnnualPerennial/RComPlEx/work'
```

---

## 📈 Monitoring During Execution

### Check Work Directory Growth
```bash
watch -n 30 'du -sh /mnt/users/martpali/AnnualPerennial/RComPlEx/work'
```

### Check Output Files
```bash
watch -n 60 'ls -lh /mnt/users/martpali/AnnualPerennial/RComPlEx/results/'
```

### Monitor Disk Usage
```bash
watch -n 30 'df -h /mnt/users/martpali/AnnualPerennial/'
```

---

## 🎯 Quick Reference

| What | Where |
|------|-------|
| **Configuration file** | `nextflow.config` |
| **Working directory** | `/mnt/users/martpali/AnnualPerennial/RComPlEx` |
| **Output directory** | `/mnt/users/martpali/AnnualPerennial/RComPlEx/results` |
| **Work directory** | `/mnt/users/martpali/AnnualPerennial/RComPlEx/work` |
| **Run command** | `nextflow run main.nf -profile slurm` |
| **Resume command** | `nextflow run main.nf -profile slurm -resume` |

---

## 📚 Additional Documentation

For more information:
- **DIRECTORY_QUICK_REFERENCE.md** - Quick command examples
- **DIRECTORY_CONFIGURATION.md** - Comprehensive guide
- **OPTIMIZATION_SUMMARY.md** - Performance optimizations
- **DEPLOYMENT_CHECKLIST.md** - Testing procedures

---

## ✅ Ready to Run!

Your directories are now configured. Just run:

```bash
cd /path/to/RComPlEx-NF
nextflow run main.nf -profile slurm
```

All files will automatically go to your configured directories! 🚀

---

*Configuration updated: December 11, 2025*

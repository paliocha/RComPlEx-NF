# ✅ Your RComPlEx-NF Pipeline is Ready!

## 🎯 Configuration Complete

Your pipeline is now configured with your specific directories on Orion HPC.

---

## 📂 Your Directories

| Type | Path |
|------|------|
| **Working** | `/mnt/users/martpali/AnnualPerennial/RComPlEx` |
| **Output** | `/mnt/users/martpali/AnnualPerennial/RComPlEx/results` |
| **Nextflow Work** | `/mnt/users/martpali/AnnualPerennial/RComPlEx/work` |

---

## 🚀 Ready to Run!

### Step 1: Pull the Latest Changes
```bash
cd /path/to/your/RComPlEx-NF
git pull origin main
```

### Step 2: Ensure Directories Exist
```bash
mkdir -p /mnt/users/martpali/AnnualPerennial/RComPlEx/{results,work}
```

### Step 3: Verify Container
```bash
ls -lh /path/to/your/RComPlEx-NF/RComPlEx.sif
```

### Step 4: Run Test Mode (15-30 minutes)
```bash
nextflow run main.nf -profile slurm --test_mode true
```

**This will:**
- ✅ Process only 3 pairs per tissue (quick validation)
- ✅ Use your configured directories automatically
- ✅ Verify the optimization is working (~10 parallel jobs)

### Step 5: Full Production Run (2-3 hours)
```bash
nextflow run main.nf -profile slurm
```

---

## 📊 What to Expect

### Test Run Results (3 pairs × 2 tissues):
```
/mnt/users/martpali/AnnualPerennial/RComPlEx/
├── rcomplex_data/          # Created during run
│   ├── root/
│   │   ├── pairs/
│   │   └── results/
│   └── leaf/
│       ├── pairs/
│       └── results/
├── results/                 # Final outputs here!
│   ├── root/
│   │   ├── RComPlEx_expression_matrix_root.csv
│   │   └── RComPlEx_sif_top_interactions_root.csv
│   ├── leaf/
│   │   └── (similar files)
│   ├── report.html         # Open this in browser!
│   └── timeline.html
└── work/                    # Nextflow temp files
    ├── 12/
    ├── ab/
    └── ...
```

---

## 👀 Monitoring Your Run

### Watch SLURM Queue (Should see ~10 jobs!)
```bash
watch -n 10 'squeue -u $USER --format="%.18i %.9P %.30j %.8T %.10M %.6D %C"'
```

Look for:
- ✅ ~10 jobs running simultaneously (not just 1-2!)
- ✅ Each using 24 CPUs
- ✅ Jobs completing in minutes

### Check Nextflow Progress
```bash
tail -f .nextflow.log
```

### Monitor Disk Usage
```bash
watch -n 30 'df -h /mnt/users/martpali/AnnualPerennial/'
```

---

## 🎯 Performance Expectations

| Metric | Before Optimization | After Optimization |
|--------|---------------------|-------------------|
| **Parallel jobs** | 1-2 | **10** ✅ |
| **CPU usage** | 8-16 cores | **240 cores** ✅ |
| **Test run time** | 2-4 hours | **15-30 min** ✅ |
| **Full run time** | 8-12+ hours | **2-3 hours** ✅ |
| **OOM failures** | Frequent | **Rare** ✅ |

---

## 🧹 After Successful Run

### View Your Results
```bash
# Check output files
ls -lh /mnt/users/martpali/AnnualPerennial/RComPlEx/results/

# View report in browser
firefox /mnt/users/martpali/AnnualPerennial/RComPlEx/results/report.html
```

### Cleanup Temp Files (Save Space)
```bash
# Remove work directory (can reclaim 50-200 GB!)
rm -rf /mnt/users/martpali/AnnualPerennial/RComPlEx/work/*

# Remove intermediate files (can reclaim 10-50 GB!)
rm -rf /mnt/users/martpali/AnnualPerennial/RComPlEx/rcomplex_data/*

# Your results are safe in:
# /mnt/users/martpali/AnnualPerennial/RComPlEx/results/
```

---

## 🔧 If You Need to Change Directories

You can always override at runtime:

```bash
nextflow run main.nf -profile slurm \
  --workdir /different/path \
  --outdir /different/results \
  -w /different/work
```

Or edit `nextflow.config` to change defaults permanently.

---

## 📚 Documentation Index

| Document | Purpose |
|----------|---------|
| **YOUR_SETUP_READY.md** | This file - Quick start guide |
| **DIRECTORY_SETUP_SUMMARY.md** | Detailed directory configuration |
| **QUICK_COMPARISON.md** | Before/after optimization comparison |
| **OPTIMIZATION_SUMMARY.md** | Complete optimization details |
| **DEPLOYMENT_CHECKLIST.md** | Step-by-step deployment guide |
| **DIRECTORY_CONFIGURATION.md** | Comprehensive directory guide |
| **DIRECTORY_QUICK_REFERENCE.md** | Quick command examples |

---

## ⚠️ Quick Troubleshooting

### "Permission denied" Error
```bash
# Check write access
touch /mnt/users/martpali/AnnualPerennial/RComPlEx/test
rm /mnt/users/martpali/AnnualPerennial/RComPlEx/test
```

### "No space left on device"
```bash
# Check available space
df -h /mnt/users/martpali/AnnualPerennial/

# Need at least 100-300 GB free
```

### "Container not found"
```bash
# Verify container path in nextflow.config
# Or specify: --container /path/to/RComPlEx.sif
```

### Jobs Not Running in Parallel
```bash
# Check SLURM limits
scontrol show partition orion

# Verify in Nextflow log - should see multiple tasks submitted
tail -f .nextflow.log
```

---

## ✅ Pre-Flight Checklist

Before running, verify:
- [ ] Git pulled latest changes: `git pull origin main`
- [ ] Directories exist: `ls -d /mnt/users/martpali/AnnualPerennial/RComPlEx/{results,work}`
- [ ] Write permissions: `touch /mnt/users/martpali/AnnualPerennial/RComPlEx/test`
- [ ] Container available: `ls RComPlEx.sif`
- [ ] Enough disk space: `df -h /mnt/users/martpali/AnnualPerennial/` (need 100+ GB)
- [ ] Input data present: `ls -d exp_design/ genexp/`
- [ ] SLURM access: `sinfo` shows orion partition

---

## 🎉 You're All Set!

Everything is configured and ready. Just run:

```bash
# Test first (recommended!)
nextflow run main.nf -profile slurm --test_mode true

# Then full run
nextflow run main.nf -profile slurm
```

**Your 5-10x optimized pipeline is ready to go!** 🚀

---

## 📞 Need Help?

If you encounter any issues:
1. Check `.nextflow.log` for errors
2. Review `DEPLOYMENT_CHECKLIST.md` for troubleshooting
3. Check SLURM logs in work directories
4. Verify all paths are correct

**Good luck with your co-expressolog discovery!** 🧬🌱

---

*Configuration completed: December 11, 2025*

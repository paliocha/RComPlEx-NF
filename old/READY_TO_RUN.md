# RComPlEx Pipeline - Ready to Run

## ✅ Setup Complete

### Conda Environment
- **Status**: ✅ Created and ready
- **Location**: `~/micromamba/envs/rcomplex`
- **Contents**: R 4.4.2 + all required packages (tidyverse, furrr, future, gplots, igraph, etc.)

### Pipeline Configuration
- **Core**: Modular Nextflow pipeline (4 sequential R scripts)
- **Mode**: RComPlEx-NG (parallelized version)
- **Test Mode**: Available (3 pairs per tissue for quick validation)

### SLURM Submission Script
- **Location**: `slurm/run_nextflow.sh`
- **Status**: ✅ Updated and ready to use

### Files Cleaned Up
- ❌ Removed old build logs
- ❌ Removed old documentation
- ❌ Removed Apptainer temporary directories
- ❌ Removed SLURM output files

---

## 🚀 Ready-to-Use Command

### Test Run (Recommended First Step)
```bash
sbatch slurm/run_nextflow.sh slurm "" true true
```

**What this does:**
- Uses SLURM profile (no container)
- Runs all tissues
- Enables RComPlEx-NG (parallelized)
- Runs in test mode (3 pairs per tissue)
- Expected runtime: 30-60 minutes
- Memory usage: Manageable with 6GB SLURM allocation

### Full Run (All Data)
```bash
sbatch slurm/run_nextflow.sh slurm "" true
```

**What this does:**
- Uses SLURM profile with Conda environment
- Runs all tissues
- Enables RComPlEx-NG (parallelized)
- Full dataset execution
- Memory usage: Monitor with `sstat` for SLURM job ID

---

## 📋 Command Arguments Reference

```
sbatch slurm/run_nextflow.sh [PROFILE] [TISSUE] [USE_NG] [TEST_MODE]
```

- **PROFILE**: `slurm` (or `slurm,singularity_hpc` for container - not ready yet)
- **TISSUE**: Empty string for all tissues, or `root`/`leaf` for specific
- **USE_NG**: `true` for parallelized, `false` for original
- **TEST_MODE**: `true` for 3 pairs only, `false` for all

---

## 📊 Expected Outputs

After running, check:
- `results/timeline.html` - Execution timeline
- `results/report.html` - Nextflow report
- `results/trace.txt` - Detailed execution trace
- `.nextflow.log` - Pipeline logs

---

## ⚙️ Key Technical Details

### Pipeline Architecture
- **01_load_filter.R**: Load and filter expression matrices, orthologs
- **02_compute_networks.R**: Calculate correlation networks (parallelized)
- **03_network_comparison.R**: Compare networks, hypergeometric testing
- **04_summary_stats.R**: Generate conservation statistics and plots

### Resource Configuration
- **SLURM Job**: 4 CPUs, 6GB RAM
- **R Parallel**: 2 workers (furrr/future)
- **Memory Limit**: Inf (SLURM enforces job limit)

### Data Sources
- Expression matrices: `rcomplex_data/`
- Orthologs: Configured in `config/pipeline_config.yaml`
- Species pairs: Configured in pipeline parameters

---

## 🔧 Advanced Options

### Run Only Root Tissue with Full Data
```bash
sbatch slurm/run_nextflow.sh slurm root true
```

### Run with Original RComPlEx (Non-parallelized)
```bash
sbatch slurm/run_nextflow.sh slurm "" false
```

### Monitor Running Job
```bash
# Check job status
squeue -j [JOB_ID]

# Monitor resource usage
sstat -j [JOB_ID]

# View output logs
tail -f nf-complex_[JOB_ID].out
tail -f .nextflow.log
```

---

## 📝 Notes

- Conda environment uses pre-compiled binaries (no source compilation)
- Pipeline automatically resumes from last checkpoint with `-resume` flag
- Test mode is ideal for validating setup before full runs
- Apptainer containerization available as future alternative (if container build succeeds with SLURM allocation)

---

## 🎯 Quick Start Checklist

- [x] Conda environment created (`rcomplex`)
- [x] Nextflow pipeline configured
- [x] SLURM submission script ready
- [x] Test data accessible
- [x] R scripts modular and refactored
- [ ] Submit test run: `sbatch slurm/run_nextflow.sh slurm "" true true`
- [ ] Verify results in `results/` directory
- [ ] Monitor with: `tail -f .nextflow.log`

---

**You are ready to run the pipeline!**

Execute the test command above and monitor progress.

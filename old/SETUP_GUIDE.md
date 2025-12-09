# RComPlEx Pipeline Setup Guide

## Overview

This guide provides two approaches for setting up the RComPlEx pipeline environment:

1. **Apptainer Container (Recommended)** - Complete reproducibility
2. **Conda Environment (Fallback)** - Faster setup

---

## Option 1: Apptainer Container (Recommended)

### Status: In Development

The Apptainer container provides complete environmental isolation and reproducibility. However, due to `/tmp` memory limitations on the HPC system, the full container build requires additional setup.

### Quick Start

```bash
# Build the container (one-time)
bash apptainer/build_container.sh

# Run pipeline with container
nextflow run main.nf -profile slurm,singularity_hpc --use_ng
```

### Submit via SLURM

```bash
# With container
sbatch slurm/run_nextflow.sh "slurm,singularity_hpc" root true

# Without container (fallback)
sbatch slurm/run_nextflow.sh slurm root true
```

### Troubleshooting

**Issue:** Build fails with "Killed" message
- **Cause:** `/tmp` RAM disk (16 GB) is too small for large package compilation
- **Solution:** Use conda environment (Option 2) or submit build job to SLURM with more memory

**Issue:** "no space left on device"
- **Cause:** `/work` filesystem is full
- **Solution:** Already handled by using `/tmp` for temporary files

---

## Option 2: Conda Environment (Quick Setup)

### Setup

```bash
# Load conda
source ~/.bashrc
eval "$(micromamba shell hook --shell bash)"

# Create environment from YAML
bash setup_conda_env.sh

# OR manually
micromamba env create -f environment.yml --yes
```

### Usage

```bash
# Activate environment
micromamba activate rcomplex

# Run pipeline
nextflow run main.nf -profile slurm --use_ng
```

### Submit via SLURM

```bash
sbatch slurm/run_nextflow.sh slurm root true
```

---

## Comparison

| Feature | Apptainer | Conda |
|---------|-----------|-------|
| Reproducibility | ⭐⭐⭐ (Perfect) | ⭐⭐ (Good) |
| Setup time | ~1-2 hours | ~5-10 minutes |
| Size | 2 GB | <1 GB |
| Portability | ⭐⭐⭐ (Shareable) | ⭐⭐ (Per-system) |
| System dependency | Independent | Depends on conda |

---

## Recommended Workflow

### Short-term (Testing)
Use **Conda** for quick iteration:
```bash
micromamba activate rcomplex
nextflow run main.nf -profile slurm,test --use_ng
```

### Production (Full Analysis)
Either:
- Use **Apptainer** if you need maximum reproducibility and sharing
- Use **Conda** if you need faster setup and don't need portability

---

## Files

- `environment.yml` - Conda environment specification
- `setup_conda_env.sh` - Automated conda setup script
- `apptainer/build_container.sh` - Apptainer container build script
- `RComPlEx.def` - Apptainer container definition
- `slurm/run_nextflow.sh` - SLURM submission script (supports both options)

---

## Notes

- Both options work with the containerized SLURM profile (`slurm,singularity_hpc` for Apptainer only)
- Without containerization, use `-profile slurm` only
- The `--use_ng` flag activates the parallelized RComPlEx-NG version
- Check results in `results/timeline.html` and `results/report.html` after completion

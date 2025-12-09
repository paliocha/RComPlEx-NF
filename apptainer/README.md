# RComPlEx Apptainer Container

This directory contains the Apptainer (Singularity) container definition for the RComPlEx pipeline.

## Quick Start

### 1. Build the Container

```bash
cd /net/fs-2/scale/OrionStore/Home/martpali/AnnualPerennial/RComPlEx
bash apptainer/build_container.sh
```

**Expected output**: `RComPlEx.sif` (~1.5-2 GB)
**Build time**: 20-30 minutes

### 2. Run with Nextflow (Recommended)

```bash
module load R/4.4.2
micromamba activate Nextflow

nextflow run main.nf -profile slurm,singularity-hpc --use_ng
```

### 3. Run Individual Scripts in Container

```bash
apptainer exec RComPlEx.sif Rscript scripts/rcomplex_01_load_filter.R \
    --tissue root \
    --pair_id Species1_Species2 \
    --config config/pipeline_config.yaml \
    --workdir . \
    --outdir results
```

---

## Container Contents

### Base Image
- **rocker/tidyverse:4.4.2** - Pre-built R image with tidyverse
- R 4.4.2 compiled and optimized
- System libraries for R development

### Installed Packages

| Package | Purpose |
|---------|---------|
| tidyverse | Data manipulation and visualization |
| furrr | Parallel functional programming |
| future | Future evaluation framework |
| parallel | Parallel processing utilities |
| matrixStats | Efficient matrix operations |
| ggplot2 | Advanced graphics |
| RColorBrewer | Color palettes |
| cowplot | Plot composition |
| gplots | Extended plotting |
| DT | Interactive tables |
| optparse | Command-line argument parsing |
| yaml | YAML configuration files |

### System Utilities
- curl, git, wget for data access and reproducibility
- OpenSSL, libcurl for secure connections
- Locales configured for reproducibility

---

## Building the Container

### Prerequisites
- Apptainer 1.4.5+ installed and in PATH
- ~30 GB free disk space during build
- ~2 GB final container file
- Network access for downloading packages

### Build Process

```bash
# Automated build
bash apptainer/build_container.sh

# Manual build (if needed)
apptainer build RComPlEx.sif RComPlEx.def

# Build with sandbox (for debugging)
apptainer build --sandbox RComPlEx_sandbox RComPlEx.def
```

### Build Output
- **RComPlEx.sif**: Final container file (1.5-2 GB)
- **RComPlEx_sandbox/** (optional): Writable sandbox for debugging

### Troubleshooting Build

**Issue**: "Permission denied" error
```bash
# Need sudo for building containers
sudo apptainer build RComPlEx.sif RComPlEx.def

# Or use fakeroot (if available)
apptainer build --fakeroot RComPlEx.sif RComPlEx.def
```

**Issue**: "Could not retrieve image"
```bash
# Check internet connectivity
# Verify Docker Hub access (rocker images are on Docker Hub)
curl -I https://hub.docker.com/v2/
```

**Issue**: "Package X failed to install"
```bash
# Check the %post section in RComPlEx.def
# May need to add system dependencies via apt-get
# See "Customizing the Container" section below
```

---

## Using the Container

### With Nextflow (Recommended)

The container is automatically used when running with the `singularity-hpc` profile:

```bash
nextflow run main.nf -profile slurm,singularity-hpc --use_ng
```

**What happens**:
1. Nextflow detects container specification in config
2. Automatically runs each process in the container
3. Data directories bind-mounted automatically
4. Results written to host filesystem

### Direct Execution

Run R scripts directly in the container:

```bash
# Single script
apptainer exec RComPlEx.sif \
  Rscript scripts/rcomplex_01_load_filter.R \
  --tissue root --pair_id Test_Test \
  --config config/pipeline_config.yaml \
  --workdir . --outdir /tmp/test

# R interactive
apptainer exec RComPlEx.sif R

# Bash shell
apptainer shell RComPlEx.sif
```

### SLURM Integration

The container works seamlessly with SLURM:

```bash
#!/bin/bash
#SBATCH --job-name=rcomplex
#SBATCH --cpus-per-task=24
#SBATCH --mem=280G
#SBATCH --time=04:00:00
#SBATCH --qos=normal

module load R/4.4.2
micromamba activate Nextflow

nextflow run main.nf -profile slurm,singularity-hpc --use_ng
```

---

## Container Configuration

### Environment Variables

The container automatically sets:

```bash
R_HOME=/usr/local/lib/R
R_LIBS_USER=/usr/local/lib/R/site-library
LC_ALL=C
LANG=C
OMP_NUM_THREADS=1
DEBIAN_FRONTEND=noninteractive
```

These ensure:
- Consistent R library paths
- Reproducible locale settings
- Single-threaded base R (parallelization via furrr/future)
- Non-interactive environment

### Bind Mounts

With `singularity.autoMounts = true` in Nextflow config:

**Automatically mounted**:
- Current working directory → `/mnt/pwd`
- Home directory → `/mnt/home`
- Temp directories → `/tmp`, `/var/tmp`
- SLURM job directories → preserved

**Manual mount** (if needed):

```bash
apptainer exec \
  --bind /path/to/data:/data \
  --bind /path/to/output:/output \
  RComPlEx.sif Rscript script.R
```

---

## Customizing the Container

### Adding Packages

Edit `RComPlEx.def` and add to the `%post` section:

```singularity
%post
    R --slave -e "
        install.packages('new_package_name')
    "
```

Then rebuild:
```bash
bash apptainer/build_container.sh
```

### Adding System Dependencies

Edit `%post` section:

```singularity
%post
    apt-get update
    apt-get install -y package-name
```

### Using Different Base Image

Change the `From:` line in `RComPlEx.def`:

```singularity
Bootstrap: docker
From: rocker/tidyverse:4.3.0  # Different version
```

---

## Troubleshooting

### Container Won't Run

**Issue**: "exec format error"
- Check container file integrity: `file RComPlEx.sif`
- Rebuild if corrupted: `bash apptainer/build_container.sh`

**Issue**: "no such file or directory"
- Ensure working directory is correct
- Check mount paths with: `apptainer inspect RComPlEx.sif`

### R Package Errors

**Issue**: "package not found"
- Install in container: Edit `RComPlEx.def` and rebuild
- Or use system R (without container)

**Issue**: "library not loaded"
- May be system library issue
- Check container build log for warnings
- Rebuild with: `bash apptainer/build_container.sh`

### Performance Issues

**Issue**: "container startup slow"
- First execution is slower (cache building)
- Subsequent runs use cached container
- Check disk I/O with: `apptainer inspect RComPlEx.sif`

**Issue**: "out of memory"
- Increase SLURM memory allocation
- Check ulimits: `ulimit -a`
- Container doesn't add overhead; issue is likely job-size

### Nextflow Integration Issues

**Issue**: "can't find container"
- Verify container path in nextflow.config
- Check: `ls -lh RComPlEx.sif`
- Container must be in project directory or absolute path

**Issue**: "bind mount failed"
- Enable autoMounts: `singularity.autoMounts = true`
- Check file permissions
- Verify paths exist

---

## Performance & Resources

### Build Resources
- **CPU**: 4+ cores recommended
- **Memory**: 8+ GB
- **Disk**: 30+ GB free (30 GB build + 2 GB final)
- **Time**: 20-30 minutes

### Runtime Resources
- **Container startup**: 1-2 seconds
- **Memory overhead**: < 100 MB (negligible)
- **Disk overhead**: 1.5-2 GB (one-time)
- **Performance impact**: None (near-native speed)

### SLURM Settings
Recommended for full pipeline:

```bash
#SBATCH --cpus-per-task=24
#SBATCH --mem=280G
#SBATCH --time=04:00:00
```

---

## Reproducibility

The container ensures reproducibility by:

1. **Fixed R version**: 4.4.2 (exact)
2. **Fixed package versions**: CRAN snapshot at build time
3. **Fixed system libraries**: Rocker base includes everything
4. **Fixed locale**: LC_ALL=C for consistent output
5. **Isolated environment**: No system R used

**To guarantee exact reproducibility**:
- Rebuild container with same `RComPlEx.def`
- Document build date in notes
- Container SIF file is portable and shareable

---

## Sharing the Container

The built `RComPlEx.sif` file can be shared:

```bash
# Copy to colleague
scp RComPlEx.sif user@other_system:/path/to/project/

# Upload to archive
tar czf RComPlEx_container.tar.gz RComPlEx.sif
# ... share via file transfer service ...
```

Colleagues can use immediately without rebuilding:
```bash
nextflow run main.nf -profile slurm,singularity-hpc --use_ng
```

---

## Reference

### Apptainer Documentation
- https://apptainer.org/docs/user/latest/
- https://apptainer.org/docs/user/latest/quick_start.html

### Rocker Project
- https://rocker-project.org/
- https://hub.docker.com/r/rocker/tidyverse

### Nextflow & Singularity
- https://www.nextflow.io/docs/latest/singularity.html
- https://seqera.io/blog/container-support-in-nextflow/

---

## Support

For issues with the container:

1. Check the build log: `bash apptainer/build_container.sh 2>&1 | tee build.log`
2. Review this README's troubleshooting section
3. Test individual package: `apptainer exec RComPlEx.sif Rscript -e "library(package_name)"`
4. Check Apptainer logs: `export APPTAINER_DEBUG=1` before building

---

**Last Updated**: December 5, 2025
**Apptainer Version**: 1.4.5+
**R Version**: 4.4.2
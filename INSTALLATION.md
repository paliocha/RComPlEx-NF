# Installation & Setup Guide

This guide covers installing and setting up the RComPlEx-NG pipeline on your system.

## System Requirements

### Minimum Specifications
- **OS**: Linux or macOS (Windows via WSL2)
- **CPU**: 4 cores (8+ recommended for development)
- **RAM**: 16 GB (32+ GB recommended for production runs)
- **Storage**: 50 GB available space (for reference data + results)
- **Disk speed**: SSD preferred for `/tmp` during container builds

### Supported Architectures
- x86_64 (Intel/AMD) - primary
- arm64 (Apple Silicon) - requires ARM-compatible Docker image

---

## Installation Methods

### Option 1: Local Installation (Recommended for Development)

#### Step 1: Install Nextflow

```bash
# Install Nextflow (Java required, version 11+)
wget -qO- https://get.nextflow.io | bash
chmod +x nextflow
sudo mv nextflow /usr/local/bin/

# Verify installation
nextflow -version
```

#### Step 2: Install Required Tools

```bash
# Install Conda/Micromamba (for environments)
curl -L -O https://github.com/conda-forge/miniforge/releases/download/23.11.0-0/Mambaforge-Linux-x86_64.sh
bash Mambaforge-Linux-x86_64.sh -b -p ~/mambaforge
~/mambaforge/bin/mamba init

# Reload shell
source ~/.bashrc
```

#### Step 3: Install Apptainer/Singularity (for containers)

```bash
# Option A: Using package manager (if available)
sudo apt-get install -y apptainer

# Option B: Build from source
git clone https://github.com/apptainer/apptainer.git
cd apptainer
./mconfig
make -C builddir
sudo make -C builddir install
```

#### Step 4: Clone Repository & Install RComPlEx

```bash
# Clone the RComPlEx-NG repository
git clone https://github.com/YOUR_USERNAME/RComPlEx-NG.git
cd RComPlEx-NG

# Create conda environment (optional, for development)
mamba env create -f environment.yml
mamba activate rcomplex-dev

# Or install R packages individually
mamba install -c conda-forge r-igraph r-furrr r-yaml r-optparse r-glue
```

---

### Option 2: HPC Installation (SLURM Cluster)

#### Step 1: Load Environment Modules

```bash
# Load modules on login node
module load nextflow/25.10.2
module load apptainer/1.4.5
module load r/4.4.2
module load gcc/11.4.0  # For compilation if needed
```

#### Step 2: Set Up Conda Environment

```bash
# Create local conda environment
micromamba create -n rcomplex-hpc
micromamba activate rcomplex-hpc
micromamba install -c conda-forge r-igraph r-furrr r-yaml r-optparse r-glue
```

#### Step 3: Configure for Your Cluster

```bash
# Edit nextflow.config with your cluster parameters
vim nextflow.config

# Key settings to customize:
# - queue: Your SLURM queue name (e.g., "gpu", "cpu")
# - executor: Should be "slurm" for HPC
# - memory limits: Per your cluster's max allocation
# - time limits: Per your queue's max walltime
```

---

### Option 3: Docker Container (Development/Testing)

```bash
# Build Docker image
docker build -t rcomplex-ng:latest .

# Run pipeline in Docker
docker run -v $(pwd):/work -w /work \
  -e SLURM_CONF=/etc/slurm/slurm.conf \
  rcomplex-ng:latest \
  nextflow run main.nf --tissues root

# Or use Docker Compose
docker-compose up
```

---

## Building the Apptainer Container Image

The pipeline uses Apptainer to containerize the analysis environment.

### One-Time Build

```bash
# Navigate to project directory
cd /path/to/RComPlEx-NG

# Start interactive session (on login node, not compute node)
qlogin

# Create persistent tmux session
tmux new-session -s rcomplex_build

# Activate environment
source ~/.bashrc
eval "$(micromamba shell hook --shell bash)"
micromamba activate Nextflow

# Build container (15-30 minutes)
bash apptainer/build_container.sh

# Detach from tmux if needed: Ctrl+B then D
# Reattach: tmux attach -t rcomplex_build
```

### After Build

```bash
# Verify container exists
ls -lh RComPlEx.sif  # Should be ~1-1.5 GB

# Test container
apptainer exec RComPlEx.sif Rscript --version

# Inspect container
apptainer inspect RComPlEx.sif
```

### Troubleshooting Container Build

**Problem**: Build fails with "Permission denied"
```bash
# Solution: Ensure running on login node with qlogin
qlogin  # Start interactive session first
```

**Problem**: "No space left on device"
```bash
# Check /tmp space
df -h /tmp

# Clean old builds
rm -rf /tmp/RComPlEx_*.sif /tmp/.apptainer_cache
```

**Problem**: Build takes very long
```bash
# Check if still building (in another terminal)
tail -f /path/to/RComPlEx-NG/.nextflow.log

# Normal build time: 15-30 minutes
```

---

## Testing Installation

### Quick Validation Test

```bash
# 1. Validate input data
module load R/4.4.2
Rscript scripts/validate_inputs.R \
  --config config/pipeline_config.yaml \
  --workdir .

# Expected output:
# ✓ Validation passed
#   Tissues: root, leaf
#   Species: 13 (5 annual, 8 perennial)
```

### Test Pipeline (3 pairs per tissue, ~1 hour)

```bash
# Without container (uses system R)
nextflow run main.nf --tissues root --test_mode true

# With container (recommended)
nextflow run main.nf -profile slurm,singularity_hpc \
  --tissues root --test_mode true
```

### Check Test Results

```bash
# Monitor progress
tail -f .nextflow.log

# Check results directory
ls -la results/root/

# View first clique results
head -5 results/root/coexpressolog_cliques_root_all.tsv
```

---

## Environment Files

### environment.yml (Conda Dependencies)

```yaml
name: rcomplex-dev
channels:
  - conda-forge
  - bioconda
dependencies:
  - r-base=4.4.2
  - r-igraph
  - r-furrr
  - r-future
  - r-tidyverse
  - r-yaml
  - r-optparse
  - r-glue
  - r-gplots
  - r-rcolorbrewer
  - r-cowplot
  - bioconda::bioconductor-wgcna=1.72
```

### RComPlEx.def (Apptainer Container)

```
Bootstrap: docker
From: rocker/tidyverse:4.4.2

%post
    apt-get update && apt-get install -y \
        libgsl-dev \
        gfortran \
        libopenblas-dev \
        liblapack-dev \
        && rm -rf /var/lib/apt/lists/*

    R --slave -e "
        install.packages(c(
            'igraph', 'furrr', 'future', 'yaml', 'optparse', 'glue',
            'gplots', 'RColorBrewer', 'cowplot', 'DT'
        ), repos='https://cran.r-project.org')

        if (!require('WGCNA', quietly=TRUE)) {
            install.packages('WGCNA', repos='https://cran.r-project.org')
        }
    "

%environment
    export LC_ALL=C

%runscript
    exec Rscript "\$@"
```

---

## Configuration

### nextflow.config Customization

```groovy
// Example for local laptop
profiles {
    local {
        process {
            executor = 'local'
            maxForks = 2      // Use 2 parallel jobs
            cpus = 2
            memory = '8GB'
        }
    }
}

// Example for SLURM cluster
profiles {
    slurm {
        process {
            executor = 'slurm'
            queue = 'gpu'     // Your queue name
            maxForks = 10     // Max concurrent jobs

            withName: RCOMPLEX_03_NETWORK_COMPARISON {
                cpus = 24
                memory = '200GB'
                time = '7d'
            }
        }
    }
}
```

### Data Directory Setup

```bash
# Create data directory structure
mkdir -p data config results logs

# Place input files
cp /path/to/vst_hog.RDS .
cp /path/to/N1_clean.RDS .

# Copy/create config
cp config.example.yaml config/pipeline_config.yaml
# Edit config as needed
vim config/pipeline_config.yaml

# Directory structure
RComPlEx-NG/
├── main.nf
├── nextflow.config
├── README.md
├── METHOD.md
├── INPUT_FORMAT.md
├── vst_hog.RDS          # Your data
├── N1_clean.RDS         # Your data
├── RComPlEx.sif         # Built container
├── config/
│   └── pipeline_config.yaml
├── scripts/
│   ├── validate_inputs.R
│   ├── rcomplex_01_load_filter.R
│   ├── ... (other scripts)
├── apptainer/
│   ├── build_container.sh
│   └── RComPlEx.def
├── slurm/
│   └── run_nextflow.sh
└── results/             # Output directory
```

---

## Running the Pipeline

### Command Line Options

```bash
# Basic run (uses system R, no container)
nextflow run main.nf

# With Apptainer container
nextflow run main.nf -profile slurm,singularity_hpc

# Test mode (3 pairs per tissue)
nextflow run main.nf --test_mode true

# Specific tissue only
nextflow run main.nf --tissues root

# Resume after interruption (smart restart)
nextflow run main.nf -resume

# With custom config
nextflow run main.nf -c my_custom.config

# Monitor execution
nextflow run main.nf -with-report report.html \
                     -with-timeline timeline.html \
                     -with-trace trace.txt
```

### Submitting to SLURM

```bash
# Simple submission
sbatch slurm/run_nextflow.sh slurm "" false

# With container
sbatch slurm/run_nextflow.sh "slurm,singularity_hpc" "" false

# Test mode via SLURM
sbatch slurm/run_nextflow.sh slurm root true
```

---

## Troubleshooting

### "command not found: nextflow"
```bash
# Install Nextflow
curl -s https://get.nextflow.io | bash
export PATH=$PWD:$PATH
```

### "No module named 'yaml' (R)"
```bash
# Install R packages
R --slave -e "install.packages(c('yaml', 'igraph', 'furrr', 'optparse'))"

# Or via conda
mamba install -c conda-forge r-yaml r-igraph r-furrr r-optparse
```

### "Apptainer not found"
```bash
# Check installation
which apptainer
apptainer version

# If not installed, see installation section above
```

### "File not found in container"
```bash
# Check that vst_hog.RDS and N1_clean.RDS are in project root
ls -la vst_hog.RDS N1_clean.RDS

# Verify paths in config
cat config/pipeline_config.yaml
```

### "Out of memory" errors
```bash
# Increase memory allocation in nextflow.config
# Or increase system available memory
# Check memory usage during run
htop  # Press 'T' to sort by memory
```

---

## Next Steps

1. **Prepare your data**: See [INPUT_FORMAT.md](INPUT_FORMAT.md)
2. **Understand the method**: See [METHOD.md](METHOD.md)
3. **Run test pipeline**: `nextflow run main.nf --test_mode true`
4. **Customize config**: Edit `config/pipeline_config.yaml` for your analysis
5. **Run full analysis**: `nextflow run main.nf`
6. **Interpret results**: See [README.md](README.md#output-files)

---

## Getting Help

- **Installation issues**: Check troubleshooting section above
- **Data format questions**: See [INPUT_FORMAT.md](INPUT_FORMAT.md)
- **Method questions**: See [METHOD.md](METHOD.md)
- **Pipeline run issues**: Check `.nextflow.log` and stdout
- **Bug reports**: GitHub Issues (when available)

## System-Specific Notes

### macOS
```bash
# Use Homebrew for dependencies
brew install nextflow
brew install --cask apptainer  # May need Docker Desktop
brew install r
```

### Ubuntu/Debian
```bash
# Install via apt
sudo apt-get update
sudo apt-get install -y nextflow apptainer r-base
```

### CentOS/RHEL
```bash
# Install via yum
sudo yum install -y apptainer
# Nextflow and R from conda/mamba recommended
```

## Version Compatibility

| Component | Version | Status |
|-----------|---------|--------|
| Nextflow | 25.10.2+ | Tested |
| R | 4.4.2 | Tested |
| Apptainer | 1.4.5+ | Tested |
| SLURM | 21.08+ | Compatible |
| Docker | 20.10+ | Compatible |

---

## Citation

If you use this pipeline, please cite:
1. **Pipeline**: RComPlEx-NG [GitHub URL when available]
2. **Method**: Netotea et al. (2014) Nature Communications
3. **Tools**: Nextflow, Apptainer, R packages (igraph, furrr, etc.)

See [METHOD.md](METHOD.md#references) for detailed citations.
# Installation & Setup Guide

This guide covers installing and setting up the RComPlEx-NF pipeline on your system.

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
# Clone the RComPlEx-NF repository
git clone https://github.com/paliocha/RComPlEx-NF.git
cd RComPlEx-NF

# Create conda environment (optional, for development)
mamba env create -f environment.yml
mamba activate rcomplex

# Or install R packages individually
mamba install -c conda-forge r-base=4.5.2 r-igraph r-furrr r-yaml r-optparse r-glue r-data.table r-rfast
```

---

### Option 2: HPC Installation (SLURM Cluster)

#### Step 1: Load Environment Modules

```bash
# Load modules on login node
module load nextflow/25.04.7   # Or latest available version
module load apptainer/1.4.5
module load R/4.5.2
module load gcc/11.4.0  # For compilation if needed

# Verify versions
nextflow -version
apptainer --version
R --version
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
cd /path/to/RComPlEx-NF

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
tail -f /path/to/RComPlEx-NF/.nextflow.log

# Normal build time: 15-30 minutes
```

**Problem**: QoS (Quality of Service) configuration issues
```bash
# Check available QoS settings for your account
./check_qos.sh

# Update nextflow.config with correct QoS name
# See QOS_CONFIGURATION_GUIDE.md for details
```

---

## Testing Installation

### Quick Validation Test

```bash
# 1. Check QoS configuration (HPC only)
./check_qos.sh

# 2. Validate installation
bash bin/validate_installation.sh

# 3. Validate input data
module load R/4.5.2
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
name: rcomplex
channels:
  - conda-forge
  - bioconda
  - defaults
dependencies:
  # R version matching RComPlEx.def (rocker/tidyverse:4.5.2)
  - r-base=4.5.2
  
  # Essential packages for RComPlEx
  - r-tidyverse        # Data wrangling and visualization ecosystem
  - r-igraph           # Network/graph analysis (core for RComPlEx)
  - r-future           # Evaluation framework for parallel processing
  - r-furrr            # Parallel functional programming
  
  # Plotting and visualization
  - r-gplots           # Extended plotting functions
  - r-rcolorbrewer     # Color palettes
  - r-cowplot          # Plot composition and alignment
  - r-ggplot2          # Grammar of graphics (included in tidyverse)
  
  # Data manipulation and processing
  - r-data.table       # Fast data manipulation
  - r-matrixstats      # Fast matrix functions
  - r-rfast            # High-performance computations (Tcrossprod)
  - r-matrix           # Sparse and dense matrix classes
  
  # Interactive and reporting
  - r-dt               # Interactive data tables
  - r-rmarkdown        # R Markdown support
  
  # Utility packages
  - r-optparse         # Command line argument parsing
  - r-yaml             # YAML configuration file parsing
  - r-glue             # String interpolation
  - r-conflicted       # Manage function name conflicts
  
  # Optional: Weighted Gene Co-Expression Network Analysis
  # Uncomment if needed for your analysis
  # - bioconda::bioconductor-wgcna
```

### RComPlEx.def (Apptainer Container)

```
Bootstrap: docker
From: rocker/tidyverse:4.5.2

%files
    scripts /opt/rcomplex/scripts
    R /opt/rcomplex/R

%labels
    Author "Martin Paliocha & Torgeir Rhodén Hvidsten"
    Version "1.0.0"
    Description "RComPlEx: Comparative analysis of plant co-expression networks in R"
    HPC "Apptainer 1.4.5+"
    RVersion "4.5.2"

%post
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        ca-certificates curl git wget locales \
        libssl-dev libcurl4-openssl-dev libxml2-dev \
        libssl3 gsl-bin libgsl0-dev gfortran \
        libopenblas-dev liblapack-dev
    
    locale-gen en_US.UTF-8
    
    R --slave -e "
        options(repos = c(CRAN = 'https://cran.r-project.org'))
        
        essential_pkgs <- c(
            'tidyverse', 'furrr', 'future', 'igraph', 'gplots', 
            'RColorBrewer', 'conflicted', 'cowplot', 'DT', 
            'data.table', 'optparse', 'yaml', 'glue', 
            'matrixStats', 'Rfast'
        )
        
        install.packages(essential_pkgs, dependencies=TRUE, clean=TRUE, quiet=TRUE)
        
        # Optional WGCNA
        tryCatch({
            install.packages('WGCNA', dependencies=TRUE, clean=TRUE, quiet=TRUE)
        }, error = function(e) {
            cat('Warning: Could not install WGCNA (optional)\n')
        })
    "
    
    apt-get clean
    rm -rf /var/lib/apt/lists/*

%environment
    export R_HOME=/usr/local/lib/R
    export R_LIBS_USER="/usr/local/lib/R/site-library"
    export RCOMPLEX_HOME=/opt/rcomplex
    export LC_ALL=C
    export LANG=C
    export OMP_NUM_THREADS=1
    export DEBIAN_FRONTEND=noninteractive

%runscript
    exec R "${@}"
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
RComPlEx-NF/
├── main.nf
├── nextflow.config
├── README.md
├── METHOD.md
├── INPUT_FORMAT.md
├── INSTALLATION.md
├── QOS_CONFIGURATION_GUIDE.md
├── VERIFICATION_REPORT.md
├── check_qos.sh         # QoS validation script
├── environment.yml      # Conda environment (R 4.5.2)
├── vst_hog.RDS          # Your data
├── N1_clean.RDS         # Your data
├── RComPlEx.sif         # Built container
├── RComPlEx.def         # Container definition (R 4.5.2)
├── bin/
│   └── validate_installation.sh
├── config/
│   └── pipeline_config.yaml
├── scripts/
│   ├── validate_inputs.R
│   ├── rcomplex_01_load_filter.R
│   └── ... (other scripts)
├── R/
│   └── config_parser.R
├── apptainer/
│   └── build_container.sh
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
| Nextflow | 25.04.7+ | Tested ✅ |
| R | 4.5.2 | Tested ✅ |
| Apptainer | 1.4.5+ | Tested ✅ |
| SLURM | 21.08+ | Compatible ✅ |
| Docker | 20.10+ | Compatible ✅ |
| rocker/tidyverse | 4.5.2 | Base Image ✅ |

---

## Additional Resources

- **QoS Configuration**: See [QOS_CONFIGURATION_GUIDE.md](QOS_CONFIGURATION_GUIDE.md) for SLURM QoS setup
- **Verification Report**: See [VERIFICATION_REPORT.md](VERIFICATION_REPORT.md) for system validation details
- **Check QoS Script**: Run `./check_qos.sh` to verify your SLURM QoS settings

---

## Citation

If you use this pipeline, please cite:
1. **Pipeline**: RComPlEx-NF (https://github.com/paliocha/RComPlEx-NF)
2. **Method**: Netotea et al. (2014) Nature Communications
3. **Tools**: Nextflow, Apptainer, R packages (igraph, furrr, etc.)

See [METHOD.md](METHOD.md#references) for detailed citations.
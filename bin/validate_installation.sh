#!/bin/bash
# ==============================================================================
# RComPlEx Pipeline Installation Validator
# ==============================================================================
# Checks that all required files and dependencies are in place
# ==============================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_DIR}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo "=========================================="
echo "RComPlEx Pipeline Installation Validation"
echo "=========================================="
echo ""

# Check required files
echo "Checking required files..."

REQUIRED_FILES=(
    "config/pipeline_config.yaml"
    "R/config_parser.R"
    "scripts/prepare_data.R"
    "scripts/run_rcomplex_single.R"
    "scripts/find_coexpressolog_cliques.R"
    "slurm/run_rcomplex.sh"
    "bin/rcomplex_cli.sh"
    "rcomplex-main/RComPlEx.Rmd"
    "README.md"
    "QUICKSTART.md"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}✓${NC} $file"
    else
        echo -e "  ${RED}✗${NC} $file - MISSING"
        ((ERRORS++))
    fi
done

# Check data files
echo ""
echo "Checking data files..."

if [ -f "vst_hog.RDS" ]; then
    size=$(du -h vst_hog.RDS | cut -f1)
    echo -e "  ${GREEN}✓${NC} vst_hog.RDS ($size)"
else
    echo -e "  ${RED}✗${NC} vst_hog.RDS - MISSING"
    ((ERRORS++))
fi

if [ -f "N1_clean.RDS" ]; then
    size=$(du -h N1_clean.RDS | cut -f1)
    echo -e "  ${GREEN}✓${NC} N1_clean.RDS ($size)"
else
    echo -e "  ${RED}✗${NC} N1_clean.RDS - MISSING"
    ((ERRORS++))
fi

# Check executability
echo ""
echo "Checking script permissions..."

EXECUTABLES=(
    "bin/rcomplex_cli.sh"
    "bin/validate_installation.sh"
)

for script in "${EXECUTABLES[@]}"; do
    if [ -x "$script" ]; then
        echo -e "  ${GREEN}✓${NC} $script is executable"
    else
        echo -e "  ${YELLOW}⚠${NC} $script is not executable (fixing...)"
        chmod +x "$script"
        ((WARNINGS++))
    fi
done

# Check R installation
echo ""
echo "Checking R installation..."

if command -v Rscript &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Rscript found"
else
    echo -e "  ${RED}✗${NC} Rscript not found"
    echo "    Run: module load R/4.4.2"
    ((ERRORS++))
fi

# Check R packages (if R is available)
if command -v Rscript &> /dev/null; then
    echo ""
    echo "Checking R packages..."

    REQUIRED_PACKAGES=(
        "tidyverse"
        "yaml"
        "igraph"
        "furrr"
        "optparse"
        "glue"
        "rmarkdown"
    )

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if Rscript -e "library($pkg)" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $pkg"
        else
            echo -e "  ${RED}✗${NC} $pkg - NOT INSTALLED"
            echo "    Install: install.packages('$pkg')"
            ((ERRORS++))
        fi
    done
fi

# Check SLURM
echo ""
echo "Checking SLURM..."

if command -v sbatch &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} sbatch found"
else
    echo -e "  ${YELLOW}⚠${NC} sbatch not found (SLURM may not be available)"
    ((WARNINGS++))
fi

# Check directory structure
echo ""
echo "Checking directory structure..."

REQUIRED_DIRS=(
    "config"
    "R"
    "scripts"
    "slurm"
    "bin"
    "rcomplex-main"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "  ${GREEN}✓${NC} $dir/"
    else
        echo -e "  ${RED}✗${NC} $dir/ - MISSING"
        ((ERRORS++))
    fi
done

# Create runtime directories if they don't exist
echo ""
echo "Checking/creating runtime directories..."

RUNTIME_DIRS=(
    "logs"
    "results"
)

for dir in "${RUNTIME_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "  ${GREEN}✓${NC} $dir/ exists"
    else
        mkdir -p "$dir"
        echo -e "  ${YELLOW}⚠${NC} $dir/ created"
        ((WARNINGS++))
    fi
done

# Check configuration
echo ""
echo "Checking configuration..."

if [ -f "config/pipeline_config.yaml" ]; then
    # Check if config is valid YAML (basic check)
    if grep -q "data:" config/pipeline_config.yaml && \
       grep -q "species:" config/pipeline_config.yaml && \
       grep -q "tissues:" config/pipeline_config.yaml; then
        echo -e "  ${GREEN}✓${NC} Configuration appears valid"
    else
        echo -e "  ${RED}✗${NC} Configuration may be malformed"
        ((ERRORS++))
    fi
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Installation is complete and valid${NC}"
    echo ""
    echo "Ready to run!"
    echo "  ./bin/rcomplex_cli.sh prepare root"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Installation complete with ${WARNINGS} warning(s)${NC}"
    echo ""
    echo "Pipeline should work, but review warnings above"
    exit 0
else
    echo -e "${RED}✗ Installation has ${ERRORS} error(s) and ${WARNINGS} warning(s)${NC}"
    echo ""
    echo "Fix errors above before running pipeline"
    exit 1
fi

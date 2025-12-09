# Input Format Documentation

This document describes the required structure and format of input files for the RComPlEx pipeline.

## Overview

RComPlEx requires two main data files and one configuration file:

| File | Type | Size | Description |
|------|------|------|-------------|
| `vst_hog.RDS` | R serialized data | ~250 MB | Variance-stabilized expression matrix |
| `N1_clean.RDS` | R serialized data | ~6 MB | Hierarchical ortholog groups |
| `config/pipeline_config.yaml` | YAML config | < 1 KB | Pipeline parameters and species list |

---

## 1. Expression Data: `vst_hog.RDS`

### Purpose
Variance-stabilized transcriptome expression data for all species and tissues.

### Data Type
- **R format**: RDS (R Serialized Data, binary format)
- **R class**: Long-format data.frame
- **Rows**: Individual gene-sample observations
- **Size**: Typically 250-400 MB for 13 species with ~20,000 genes

### Required Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `species` | character | Species name | "Brachypodium distachyon" |
| `tissue` | character | Tissue type | "root" or "leaf" |
| `GeneID` | character | Gene identifier | "BRADI1G00010.1" |
| `sample_id` | character | Unique sample identifier | "BdRoot_1" |
| `vst.count` | numeric | Variance-stabilized expression value | 5.2, 8.9, ... |
| `life_cycle` | character | Life habit annotation | "annual" or "perennial" |
| `HOG` | character | Hierarchical ortholog group | "HOG:0000001" |

### Structure Example

```r
# Load and inspect
vst <- readRDS("vst_hog.RDS")
head(vst)
#     species             tissue      GeneID   sample_id vst.count    life_cycle        HOG
# 1   Brachypodium_distachyon   root  BRADI1G00010.1  BdRoot_1      5.2      annual  HOG:0000001
# 2   Brachypodium_distachyon   root  BRADI1G00020.1  BdRoot_1      7.8      annual  HOG:0000002
# 3   Hordeum_vulgare          root  HORVU1H000010.1  HvRoot_1      6.1      annual  HOG:0000001
# ...

# Summary statistics
dim(vst)  # Should be ~millions of rows x 7 columns
unique(vst$species)  # All species you want to analyze
unique(vst$tissue)   # Should include "root" and "leaf"
unique(vst$life_cycle)  # Should be "annual" and "perennial"
```

### Data Quality Requirements

1. **Expression values**
   - Should be variance-stabilized (VST, DESeq2) or log-transformed
   - Not raw counts or RPKM values
   - Range: Typically 0-15 for VST-transformed data

2. **Samples per tissue per species**
   - Minimum: 10 samples (very low statistical power)
   - Recommended: 30+ samples per tissue per species
   - Our dataset: ~50-100 samples per tissue per species

3. **Gene coverage**
   - All genes in the same species should have the same set of samples
   - Missing values: Should be either removed or filled with 0 (not NA)
   - Consistency: Same GeneID format across all species

4. **Species names**
   - Must exactly match species names in config
   - Can use underscores: "Brachypodium_distachyon"
   - Or spaces: "Brachypodium distachyon" (will be auto-converted)

### Creating vst_hog.RDS from Raw Data

```r
# Pseudocode for preparing VST data
library(DESeq2)

# Load expression counts and metadata
counts <- read.csv("raw_expression_counts.csv", row.names=1)
metadata <- read.csv("sample_metadata.csv", row.names=1)

# Create DESeqDataSet
dds <- DESeqDataSetFromMatrix(
  countData = counts,
  colData = metadata,
  design = ~ species + tissue
)

# Variance stabilization
vst <- assay(vst(dds))

# Convert to long format
library(tidyr)
vst_long <- vst %>%
  as.data.frame() %>%
  rownames_to_column("GeneID") %>%
  pivot_longer(-GeneID, names_to="sample_id", values_to="vst.count") %>%
  left_join(metadata, by="sample_id") %>%
  mutate(HOG = get_hog(GeneID))  # Assign HOGs

# Save
saveRDS(vst_long, "vst_hog.RDS")
```

---

## 2. Ortholog Groups: `N1_clean.RDS`

### Purpose
Hierarchical ortholog group assignments mapping genes across species.

### Data Type
- **R format**: RDS (binary)
- **R class**: data.frame or tibble
- **Rows**: Individual gene-HOG associations
- **Size**: Typically 6-20 MB for comprehensive orthology

### Required Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `HOG` | character | Hierarchical ortholog group | "HOG:0000001" |
| `OG` | character | Ortholog group (lower level) | "OG001234" |
| `species` | character | Species name (MUST match vst_hog.RDS) | "Brachypodium_distachyon" |
| `GeneID` | character | Gene identifier (MUST match vst_hog.RDS) | "BRADI1G00010.1" |
| `life_cycle` | character | Life habit annotation | "annual" or "perennial" |
| `is_core` | logical | TRUE if gene is in core conserved set | TRUE, FALSE |

### Structure Example

```r
# Load and inspect
n1 <- readRDS("N1_clean.RDS")
head(n1)
#        HOG      OG                species        GeneID life_cycle is_core
# 1  HOG:0000001  OG001234  Brachypodium_distachyon  BRADI1G00010.1  annual   TRUE
# 2  HOG:0000001  OG001234  Hordeum_vulgare         HORVU1H000010.1  annual   TRUE
# 3  HOG:0000001  OG001234  Brachypodium_sylvaticum BRASY1G000010.1  perennial TRUE
# ...

# Summary statistics
dim(n1)  # Should be 50,000-200,000 rows x 6 columns
length(unique(n1$HOG))  # Number of HOGs (typically 10,000-30,000)
table(n1$life_cycle)    # Distribution: annual vs. perennial
```

### Data Quality Requirements

1. **Ortholog mappings**
   - One row per gene-HOG association (one gene can be in one HOG)
   - All genes in vst_hog.RDS should have HOG assignments
   - If a gene lacks a HOG, it will be filtered out

2. **Species consistency**
   - Species names MUST exactly match vst_hog.RDS
   - All species in config must be in this file
   - At least 2 species required for pairwise comparison

3. **Gene ID consistency**
   - GeneIDs must match exactly with vst_hog.RDS
   - Case-sensitive matching: "BRADI1G00010.1" ≠ "bradi1g00010.1"

4. **Coverage**
   - Ideally: Each HOG contains genes from multiple species
   - Minimum: Some HOGs must have genes from ≥2 species (otherwise no pairs to compare)
   - is_core flag: Can indicate which genes are in highly conserved groups

### Creating N1_clean.RDS from OrthoFinder/EggNOG Output

```r
# Pseudocode for preparing ortholog data

# If using OrthoFinder
orthofinder_output <- read.csv("orthogroups.csv")
n1 <- orthofinder_output %>%
  pivot_longer(-c(HOG, OG), names_to="species", values_to="GeneID") %>%
  filter(!is.na(GeneID)) %>%
  mutate(GeneID = trimws(GeneID)) %>%  # Remove spaces (multiple genes per cell)
  separate_rows(GeneID, sep=",") %>%   # Split if multiple genes
  left_join(species_metadata, by="species") %>%
  mutate(is_core = TRUE)  # Or based on species representation

# Clean up species names to match vst file
n1 <- n1 %>%
  mutate(species = case_when(
    species == "Brachypodium.distachyon" ~ "Brachypodium_distachyon",
    species == "Hordeum.vulgare" ~ "Hordeum_vulgare",
    TRUE ~ species
  ))

# Save
saveRDS(n1, "N1_clean.RDS")
```

---

## 3. Configuration: `config/pipeline_config.yaml`

### Purpose
Central configuration file specifying pipeline parameters and species list.

### Format
YAML (YAML Ain't Markup Language) - Human-readable data serialization.

### Required Structure

```yaml
# Data files (relative to project root)
data:
  vst_file: "vst_hog.RDS"
  n1_file: "N1_clean.RDS"
  output_dir: "rcomplex_data"

# Tissues to analyze
tissues:
  - root
  - leaf

# Species classification (names must match vst_hog.RDS and N1_clean.RDS exactly)
species:
  annual:
    - Brachypodium distachyon
    - Hordeum vulgare
    - Vulpia bromoides
    - Briza maxima
    - Poa annua
  perennial:
    - Brachypodium sylvaticum
    - Hordeum jubatum
    - Poa supina
    - Briza media
    - Festuca pratensis
    - Melica nutans
    - Nassella pubiflora
    - Oloptum miliaceum

# RComPlEx algorithm parameters
rcomplex:
  # Correlation method: "spearman" (default), "pearson", or "kendall"
  correlation_method: "spearman"

  # Network density: Keep top N% of correlations
  # Higher = more genes per network, lower = sparser networks
  density_threshold: 0.03  # Keep top 3%

  # Clique detection p-value threshold
  p_value_threshold: 0.05

  # FDR method: "BH" (Benjamini-Hochberg, default) or "bonferroni"
  fdr_method: "BH"

# Resource allocation for SLURM
resources:
  rcomplex:
    cpus: 24
    memory: "200GB"
    time: "7-00:00:00"  # 7 days

  find_cliques:
    cpus: 12
    memory: "220GB"
    time: "2-00:00:00"  # 2 days

# Optional: Advanced parameters
advanced:
  # Mutual rank normalization (recommended: true)
  use_mutual_rank: true

  # Minimum genes per tissue per species to include in analysis
  min_genes_threshold: 1000

  # Include multi-copy orthologs in clique detection
  include_paralogs: true
```

### Configuration Options

#### Tissues
- **Format**: List of tissue names (strings)
- **Must match**: Exact values in `vst_hog.RDS` tissue column
- **Common values**: "root", "leaf", "flower", "stem"
- **Validation**: Pipeline validates that requested tissues exist in data

#### Species
- **Format**: Lists under `annual` and `perennial`
- **Naming**: Can use spaces ("Brachypodium distachyon") or underscores
- **Automatic conversion**: Spaces converted to underscores in code
- **Validation**: Pipeline validates that all species exist in data

#### Correlation Method
- **"spearman"** (recommended): Rank-based, robust to outliers
- **"pearson"**: Parametric, assumes linear relationships
- **"kendall"**: Rank-based, very robust, slower computation

#### Density Threshold
- **0.01** (top 1%): Very sparse networks, only strongest correlations
- **0.03** (top 3%): Balanced, recommended for most analyses
- **0.05** (top 5%): More inclusive, may include weak correlations
- **Higher values**: More genes per network, slower computation

#### P-Value Threshold
- **0.05**: Standard significance level (5% false positive rate after FDR)
- **0.01**: Conservative, stricter requirement for conservation
- **0.10**: Liberal, more cliques detected (use with caution)

---

## Data Validation

### Automatic Checks (validate_inputs.R)

The pipeline automatically validates input data:

```bash
# Validation runs at workflow start
Rscript scripts/validate_inputs.R \
  --config config/pipeline_config.yaml \
  --workdir /path/to/project
```

**Checks performed**:
1. Data files exist and are readable
2. All columns present in both files
3. No missing values in critical columns
4. Species in config exist in data
5. Tissues in config exist in data
6. GeneID and species names match between files

**Output**:
```
✓ Validation passed
  Tissues: root, leaf
  Species: 13 (5 annual, 8 perennial)
```

### Manual Data Quality Inspection

```r
# Load and inspect your data
vst <- readRDS("vst_hog.RDS")
n1 <- readRDS("N1_clean.RDS")

# Check dimensions
dim(vst)  # Should have millions of rows
dim(n1)   # Should have 50,000+ rows

# Check for missing values
sum(is.na(vst$vst.count))  # Should be 0
sum(is.na(n1$GeneID))      # Should be 0

# Check species coverage
table(vst$species)
table(n1$species)

# Check that HOGs have multi-species representation
hog_species <- n1 %>%
  group_by(HOG) %>%
  summarize(n_species = n_distinct(species))
table(hog_species$n_species)  # Most should be 2+

# Check species names match
vst_species <- unique(vst$species)
n1_species <- unique(n1$species)
setdiff(vst_species, n1_species)  # Should be empty

# Check expression value ranges
summary(vst$vst.count)  # Should typically be 0-15 for VST
```

---

## Example Data Structure

### vst_hog.RDS (first 20 rows)
```
         species          tissue      GeneID   sample_id vst.count life_cycle        HOG
1  Brachypodium_distachyon  root  BRADI1G00010  BdRoot_1      5.2    annual   HOG:0000001
2  Brachypodium_distachyon  root  BRADI1G00020  BdRoot_1      0.0    annual   HOG:0000002
3  Brachypodium_distachyon  root  BRADI1G00030  BdRoot_1      8.9    annual   HOG:0000003
...
1000  Hordeum_vulgare       root  HORVU1H00001  HvRoot_1      6.1    annual   HOG:0000001
1001  Hordeum_vulgare       root  HORVU1H00002  HvRoot_1      3.2    annual   HOG:0000002
```

### N1_clean.RDS
```
       HOG        OG             species        GeneID life_cycle is_core
1  HOG:0000001  OG001234  Brachypodium_distachyon  BRADI1G00010  annual     TRUE
2  HOG:0000001  OG001234  Hordeum_vulgare         HORVU1H00001  annual     TRUE
3  HOG:0000001  OG001234  Brachypodium_sylvaticum  BRASY1G00010  perennial  TRUE
4  HOG:0000002  OG001235  Brachypodium_distachyon  BRADI1G00020  annual     FALSE
5  HOG:0000002  OG001235  Hordeum_vulgare         HORVU1H00002  annual     FALSE
```

### config/pipeline_config.yaml
```yaml
data:
  vst_file: "vst_hog.RDS"
  n1_file: "N1_clean.RDS"
  output_dir: "rcomplex_data"

tissues:
  - root
  - leaf

species:
  annual:
    - Brachypodium distachyon
    - Hordeum vulgare
    - Vulpia bromoides
    - Briza maxima
    - Poa annua
  perennial:
    - Brachypodium sylvaticum
    - Hordeum jubatum
    - Poa supina
    - Briza media
    - Festuca pratensis
    - Melica nutans
    - Nassella pubiflora
    - Oloptum miliaceum

rcomplex:
  correlation_method: "spearman"
  density_threshold: 0.03
  p_value_threshold: 0.05
  fdr_method: "BH"

resources:
  rcomplex:
    cpus: 24
    memory: "200GB"
    time: "7-00:00:00"
```

---

## Troubleshooting

### "Invalid species in config"
- Check: Do your species names in config exactly match vst_hog.RDS?
- Check: Spaces vs. underscores (both are automatically handled, but check for typos)
- Solution: Run validation script to see which species are available in data

### "Invalid tissues in config"
- Check: Do tissue names match the tissue column in vst_hog.RDS?
- Check: Case sensitivity (must be exact match)
- Solution: Validate script will list available tissues

### Missing validation output
- Check: Are data files in the correct location (project root)?
- Check: Are filenames exactly as specified in config?
- Solution: Run validation script manually to see specific error

### Gene count mismatch
- Check: Ensure all genes in vst_hog.RDS have HOG assignments in N1_clean.RDS
- Expected: Most genes will have HOGs, a few orphans are OK
- Check: Gene IDs must match exactly between files

---

## Data Citation

If using this pipeline with your own data, please cite:
1. The orthology resource (OrthoFinder, eggNOG, etc.)
2. The gene expression dataset source
3. The RComPlEx-NG pipeline (GitHub repo when available)

See [METHOD.md](METHOD.md) for citations to the RComPlEx methodology.
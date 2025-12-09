# RComPlEx Method: Co-Expressolog Discovery

## Overview

RComPlEx identifies **conserved co-expressed orthologs (co-expressologs)** across multiple species. Unlike simple orthology, this method finds genes that are not only orthologous but also **co-expressed in functionally similar networks** across species.

The key innovation is detecting multi-species **cliques** where all orthologous gene pairs show significant co-expression, ensuring functional conservation of entire gene modules.

## Key Concepts

### Co-Expressolog
A co-expressolog is an orthologous gene pair where the genes are:
1. **Orthologous**: Derived from a common ancestor (mapped via HOGs)
2. **Co-expressed**: Show significant correlation in expression across samples
3. **Reciprocally conserved**: The co-expression relationship is bidirectional between species

### What is a Clique?
A clique is a maximal subset of genes where:
- **ALL pairwise co-expression relationships are significant** (p < 0.05)
- Genes form a complete subgraph in the co-expression network
- Example: A 4-gene clique has all 6 possible pairwise relationships significant

This ensures we capture complete functional modules, not just pairwise connections.

## Pipeline Workflow

### Step 1: Data Preparation (PREPARE_PAIR)
**Input**: Variance-stabilized expression matrix (vst_hog.RDS), hierarchical orthogroups (N1_clean.RDS)

**Process**:
- Load expression data for two species
- Extract ortholog pairs from HOGs (Hierarchical Ortholog Groups)
- Filter to genes present in both species for the focal tissue
- Create working directories with aligned expression matrices

**Output**: Expression matrices for species pair, ortholog mappings

---

### Step 2: Load & Filter (RCOMPLEX_01_LOAD_FILTER)
**Input**: Expression matrices and ortholog mappings

**Process**:
- Load ortholog pair expression data
- Filter out genes with low variance or missing values
- Ensure expression values are on the same scale
- Create filtered dataset for network analysis

**Output**: `01_filtered_data.RData` - Cleaned expression matrices for both species

---

### Step 3: Compute Co-Expression Networks (RCOMPLEX_02_COMPUTE_NETWORKS)

**Input**: Filtered expression data

**Process** (for each species):

1. **Calculate Correlations**
   - Method: Spearman correlation (default; Pearson/Kendall available)
   - Why Spearman: Robust to outliers, preserves monotonic relationships

2. **Normalize Using Mutual Rank (MR)**
   - Each gene's correlations ranked from strongest to weakest
   - Bidirectional ranking: If geneA ranks geneB highly, and geneB ranks geneA highly, they're likely truly correlated
   - Reduces spurious correlations from noise

3. **Apply Density Threshold**
   - Keep top 3% of gene-pair correlations (configurable)
   - Creates sparse network of most important relationships
   - Reduces computational burden and improves signal

**Output**: `02_networks.RData` - Correlation matrices and thresholds for both species

---

### Step 4: Network Comparison (RCOMPLEX_03_NETWORK_COMPARISON)

**Input**: Co-expression networks for two species

**Process** (for each ortholog pair):

This is the core innovation - testing whether co-expression relationships are **conserved** between species.

#### The Hypergeometric Test

For ortholog pair (geneA_Sp1, geneB_Sp2):

1. **Extract neighborhoods**
   - Sp1_neighbors: All genes co-expressed with geneA in Species1
   - Sp2_neighbors: All genes co-expressed with geneB in Species2

2. **Count overlap**
   - How many neighbors in Sp1 have orthologs that are neighbors in Sp2?
   - This is the intersection of conserved co-expression

3. **Hypergeometric test**
   - Null hypothesis: Overlap is random
   - Formula: P(X ≥ k) where k = observed overlap
   - Population size: All possible ortholog pairs
   - Success states: Pairs both co-expressed in focal species
   - Sample size: Neighbors in focal species

4. **Bidirectional testing**
   - Test Sp1 → Sp2: Do Sp1 neighbors have Sp2 orthologs as neighbors?
   - Test Sp2 → Sp1: Do Sp2 neighbors have Sp1 orthologs as neighbors?
   - Use minimum p-value for conservative estimate

#### Multiple Testing Correction

- **Problem**: Testing thousands of ortholog pairs inflates false positive rate
- **Solution**: Benjamini-Hochberg FDR correction
- **Threshold**: p < 0.05 after FDR correction

**Output**: `03_comparison.RData` - p-values and effect sizes for each ortholog pair

---

### Step 5: Summary Statistics (RCOMPLEX_04_SUMMARY_STATS)

**Input**: Comparison results

**Process**:
- Aggregate p-values and effect sizes per gene and HOG
- Calculate mean/median p-values across all gene pairs
- Generate visualization plots (p-value distributions, effect size distributions)
- Create summary table for downstream analysis

**Output**: `04_summary_statistics.tsv` + PNG plots

---

### Step 6: Clique Detection (FIND_CLIQUES)

**Input**: All pairwise comparison results for a tissue

**Process**:

1. **Extract conserved gene pairs**
   - Filter to pairs with p < 0.05 (after FDR correction)
   - These represent significant co-expression conservation

2. **For each HOG (Hierarchical Ortholog Group)**:

   a. **Build undirected graph**
      - Nodes = genes in the HOG
      - Edges = conserved co-expression pairs

   b. **Find maximal cliques**
      - Use `igraph::max_cliques()` algorithm
      - Maximal: Cannot add more genes without losing all-pairs significance

   c. **Extract clique properties**
      - Clique size (number of genes)
      - Gene IDs
      - Species composition
      - Life habit (annual/perennial)

3. **Classify cliques**
   - **Annual**: All genes from annual species
   - **Perennial**: All genes from perennial species
   - **Mixed**: Both annual and perennial species

4. **Export results**
   - Stratified TSV files by clique type
   - Gene lists for downstream analysis (pathway enrichment, etc.)

**Output**: `coexpressolog_cliques_*.tsv`, `genes_*.txt`

---

## Why Cliques Matter

### Biological Relevance
- **Complete modules**: Cliques represent tightly coordinated gene expression
- **Functional conservation**: All genes are mutually co-expressed = coordinated evolution
- **Robustness**: Requires multiple co-expression relationships, not just one strong pair

### Handling Multi-Copy Orthologs
- Grasses have whole-genome duplications → many-to-many orthology
- A single HOG may contain multiple copies per species
- Cliques naturally partition paralogous copies into separate functional modules
- Example: HOG with 2 genes in Sp1 and 3 in Sp2 → could produce multiple cliques

### Example

**Before clique detection** (after Step 5):
- Gene pairs with significant co-expression conservation identified
- Could have isolated connections

**After clique detection**:
- Genes grouped into complete subgraphs
- Module 1 clique: [Sp1_geneA, Sp1_geneB, Sp2_geneX, Sp2_geneY]
  - All 6 pairwise relationships significant
  - Represents conserved 4-gene module

- Module 2 clique: [Sp1_geneA, Sp2_geneZ]
  - Different paralog of Sp1_geneA
  - Different functional context

## Statistical Foundation

### Why Hypergeometric Test?
- Models drawing without replacement (appropriate for biological networks)
- Accounts for network structure (not all genes equally connected)
- Provides exact p-values (no distributional assumptions)

### Why Mutual Rank Normalization?
- Correlation magnitude varies due to:
  - Biological effect size differences
  - Technical noise differences between species
  - Different numbers of samples

- Mutual Rank approach:
  - Makes correlations comparable across species
  - Focuses on consistency of relationship ranking
  - Reduces spurious correlations from single outliers

### Why FDR Correction?
- Testing ~10,000 ortholog pairs per species pair
- False discovery rate (FDR): Expected proportion of false positives among significant tests
- Benjamini-Hochberg at FDR=0.05: Expected ~5% false positives (more power than Bonferroni)

## Tissue-Specific Analysis

- **Root tissue**: Belowground functions (nutrient uptake, stress response)
- **Leaf tissue**: Aboveground functions (photosynthesis, defense)
- Run independently → tissue-specific modules (different genes active in each tissue)
- Can compare tissue-specific cliques across life habits (annual vs. perennial adaptations)

## Input Requirements

See [INPUT_FORMAT.md](INPUT_FORMAT.md) for detailed data structure documentation.

**Minimum requirements**:
- Variance-stabilized expression matrix (≥ 100 samples per tissue per species)
- Hierarchical ortholog groups (≥ 2 species pairs)
- Configurable parameters (correlation method, density threshold, p-value cutoff)

## References

- **Original RComPlEx**: Netotea et al. (2014). "Comparative genomics approach to identify conserved co-expressed genes." *Nature Communications*.
- **Method update**: Current implementation with Nextflow, tissue stratification, and multi-copy handling.
- **Hypergeometric testing**: Uses `phyper()` from R base::stats
- **Clique detection**: Uses `igraph::max_cliques()` for exact maximal clique enumeration

## Output Interpretation

See main [README.md](README.md) for output file descriptions and column definitions.

Key insight: A clique represents a **conserved, coordinated gene module** where all genes are mutually co-expressed across species. This is stronger evidence of functional conservation than pairwise co-expression alone.
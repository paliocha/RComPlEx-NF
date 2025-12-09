---
title: "Conservation and divergence of co-expression networks in R (RComPlEx-NG)"
author: "Torgeir Rhodén Hvidsten & Martin Paliocha"
date: '05.12.2025'
output:
  html_document:
    theme: yeti
    code_folding: hide
    number_sections: false
editor_options:
  chunk_output_type: console
---



### Set up species and input files

Using PLAZA ortholog groups from PlantGenIE inferred using OrthoMCL:
ftp://plantgenie.org/Data/Cross-Species/Orthologs/PLAZA/orthologs.ORTHO.plantgenie.txt.gz

Species names: from PLAZA e.g. "potri" and "piabi"

Expression files: tab-separated file where the first column contains gene names and is called "Genes". Here we use data from [AspWood](https://doi.org/10.1105/tpc.17.00153) and [NorWood](https://doi.org/10.1111/nph.14458).


``` r
# Set defaults only if not already defined (e.g., from sourced config)
if (!exists("species1_name")) species1_name <- "potri"
if (!exists("species2_name")) species2_name <- "piabi"
if (!exists("species1_expr_file")) species1_expr_file <- "Data/AspWood_expression.txt"
if (!exists("species2_expr_file")) species2_expr_file <- "Data/NorWood_expression.txt"
if (!exists("ortholog_group_file")) ortholog_group_file <- "Data/orthologs.ORTHO.plantgenie.txt.gz"

# Parallelization settings
if (!exists("n_cores")) {
  n_cores <- availableCores() - 1  # Leave one core free
  if (n_cores < 1) n_cores <- 1
}
cat("Will use", n_cores, "CPU cores for parallel processing\n\n")
```

```
## Will use 15 CPU cores for parallel processing
```

### Read in ortholog groups and expression data










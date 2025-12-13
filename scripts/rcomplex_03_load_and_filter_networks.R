#!/usr/bin/env Rscript
# ==============================================================================
# RComPlEx Step 3: Load and Filter Pre-Computed Networks
# ==============================================================================
# Loads species co-expression networks computed in Step 2, filters to genes
# present in the ortholog set for this specific pair
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(optparse)
})

# Source Orion HPC utilities for path resolution
orion_utils_candidates <- c(
  "R/orion_hpc_utils.R",
  file.path(Sys.getenv("PROJECT_DIR", ""), "R/orion_hpc_utils.R"),
  file.path(Sys.getenv("HOME", ""), "AnnualPerennial/RComPlEx/R/orion_hpc_utils.R"),
  "/opt/rcomplex/R/orion_hpc_utils.R"
)
orion_utils_path <- orion_utils_candidates[file.exists(orion_utils_candidates)][1]
if (is.na(orion_utils_path)) {
  stop("Cannot locate R/orion_hpc_utils.R; checked: ",
       paste(orion_utils_candidates, collapse = ", "))
}
source(orion_utils_path)

# Parse command-line arguments
option_list <- list(
  make_option(c("-t", "--tissue"), type = "character", default = NULL,
              help = "Tissue being analyzed", metavar = "character"),
  make_option(c("-p", "--pair_id"), type = "character", default = NULL,
              help = "Species pair ID (e.g., 'Species1_Species2')", metavar = "character"),
  make_option(c("--species1"), type = "character", default = NULL,
              help = "First species name", metavar = "character"),
  make_option(c("--species2"), type = "character", default = NULL,
              help = "Second species name", metavar = "character"),
  make_option(c("--net1_signed"), type = "character", default = NULL,
              help = "Path to species1 signed network RData file", metavar = "character"),
  make_option(c("--net2_signed"), type = "character", default = NULL,
              help = "Path to species2 signed network RData file", metavar = "character"),
  make_option(c("--net1_unsigned"), type = "character", default = NULL,
              help = "Path to species1 unsigned network RData file", metavar = "character"),
  make_option(c("--net2_unsigned"), type = "character", default = NULL,
              help = "Path to species2 unsigned network RData file", metavar = "character"),
  make_option(c("-i", "--indir"), type = "character", default = NULL,
              help = "Input directory with step 1 pair data (for orthologs)", metavar = "character"),
  make_option(c("-o", "--outdir"), type = "character", default = NULL,
              help = "Output directory for results", metavar = "character")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Resolve Orion HPC paths
opt$indir <- resolve_orion_path(opt$indir)
opt$outdir <- resolve_orion_path(opt$outdir)
opt$net1_signed <- resolve_orion_path(opt$net1_signed)
opt$net2_signed <- resolve_orion_path(opt$net2_signed)
opt$net1_unsigned <- resolve_orion_path(opt$net1_unsigned)
opt$net2_unsigned <- resolve_orion_path(opt$net2_unsigned)

# Validate required arguments
required_args <- c("tissue", "pair_id", "species1", "species2",
                   "net1_signed", "net2_signed", "indir", "outdir")
for (arg in required_args) {
  if (is.null(opt[[arg]])) {
    print_help(opt_parser)
    stop("--", arg, " argument is required", call. = FALSE)
  }
}

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("RComPlEx Step 3: Load and Filter Pre-Computed Networks\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Pair ID:", opt$pair_id, "\n")
cat("Species 1:", opt$species1, "\n")
cat("Species 2:", opt$species2, "\n")
cat(rep("=", 80), "\n\n")

# ==============================================================================
# LOAD ORTHOLOG SET FOR THIS PAIR
# ==============================================================================

cat("Loading ortholog data for this pair...\n")
input_file <- file.path(opt$indir, "01_filtered_data.RData")
if (!file.exists(input_file)) {
  stop("Step 1 output not found: ", input_file)
}

load(input_file)  # loads: species1_expr, species2_expr, shared_ortho_hogs

# Extract gene IDs from ortholog table
species1_genes_in_pair <- unique(shared_ortho_hogs[[opt$species1]])
species2_genes_in_pair <- unique(shared_ortho_hogs[[opt$species2]])

cat("  Orthologs in this pair:\n")
cat("    ", opt$species1, ":", length(species1_genes_in_pair), "genes\n", sep = "")
cat("    ", opt$species2, ":", length(species2_genes_in_pair), "genes\n\n", sep = "")

# Clean up pair expression data (not needed)
rm(species1_expr, species2_expr)
gc(verbose = FALSE)

# ==============================================================================
# LOAD SIGNED NETWORKS
# ==============================================================================

cat(rep("=", 60), "\n", sep = "")
cat("LOADING SIGNED NETWORKS\n")
cat(rep("=", 60), "\n\n", sep = "")

# Load species 1 signed network
cat("Loading", opt$species1, "signed network from:", opt$net1_signed, "\n")
if (!file.exists(opt$net1_signed)) {
  stop("Species 1 signed network not found: ", opt$net1_signed)
}
load(opt$net1_signed)  # loads: species_net, species_thr, species_genes
species1_net_signed <- species_net
species1_thr_signed <- species_thr
species1_genes_full <- species_genes
cat("  Loaded:", nrow(species1_net_signed), "×", ncol(species1_net_signed), "matrix\n")
cat("  Threshold:", format(species1_thr_signed, digits = 3), "\n\n")
rm(species_net, species_thr, species_genes)
gc(verbose = FALSE)

# Load species 2 signed network
cat("Loading", opt$species2, "signed network from:", opt$net2_signed, "\n")
if (!file.exists(opt$net2_signed)) {
  stop("Species 2 signed network not found: ", opt$net2_signed)
}
load(opt$net2_signed)  # loads: species_net, species_thr, species_genes
species2_net_signed <- species_net
species2_thr_signed <- species_thr
species2_genes_full <- species_genes
cat("  Loaded:", nrow(species2_net_signed), "×", ncol(species2_net_signed), "matrix\n")
cat("  Threshold:", format(species2_thr_signed, digits = 3), "\n\n")
rm(species_net, species_thr, species_genes)
gc(verbose = FALSE)

# ==============================================================================
# FILTER NETWORKS TO PAIR ORTHOLOGS
# ==============================================================================

cat("Filtering signed networks to pair orthologs...\n")

# Filter species1 network
genes_to_keep_1 <- intersect(species1_genes_full, species1_genes_in_pair)
cat("  ", opt$species1, ": keeping", length(genes_to_keep_1), "of", length(species1_genes_full), "genes\n", sep = "")
species1_net_signed <- species1_net_signed[genes_to_keep_1, genes_to_keep_1, drop = FALSE]

# Filter species2 network
genes_to_keep_2 <- intersect(species2_genes_full, species2_genes_in_pair)
cat("  ", opt$species2, ": keeping", length(genes_to_keep_2), "of", length(species2_genes_full), "genes\n\n", sep = "")
species2_net_signed <- species2_net_signed[genes_to_keep_2, genes_to_keep_2, drop = FALSE]

# Clean up
rm(species1_genes_full, species2_genes_full, genes_to_keep_1, genes_to_keep_2)
gc(verbose = FALSE)

# ==============================================================================
# LOAD UNSIGNED NETWORKS (if provided)
# ==============================================================================

have_unsigned <- !is.null(opt$net1_unsigned) && !is.null(opt$net2_unsigned) &&
                 file.exists(opt$net1_unsigned) && file.exists(opt$net2_unsigned)

if (have_unsigned) {
  cat(rep("=", 60), "\n", sep = "")
  cat("LOADING UNSIGNED NETWORKS\n")
  cat(rep("=", 60), "\n\n", sep = "")

  # Load species 1 unsigned network
  cat("Loading", opt$species1, "unsigned network from:", opt$net1_unsigned, "\n")
  load(opt$net1_unsigned)  # loads: species_net_unsigned, species_thr_unsigned, species_genes
  species1_net_unsigned <- species_net_unsigned
  species1_thr_unsigned <- species_thr_unsigned
  species1_genes_full_u <- species_genes
  cat("  Loaded:", nrow(species1_net_unsigned), "×", ncol(species1_net_unsigned), "matrix\n")
  cat("  Threshold:", format(species1_thr_unsigned, digits = 3), "\n\n")
  rm(species_net_unsigned, species_thr_unsigned, species_genes)
  gc(verbose = FALSE)

  # Load species 2 unsigned network
  cat("Loading", opt$species2, "unsigned network from:", opt$net2_unsigned, "\n")
  load(opt$net2_unsigned)  # loads: species_net_unsigned, species_thr_unsigned, species_genes
  species2_net_unsigned <- species_net_unsigned
  species2_thr_unsigned <- species_thr_unsigned
  species2_genes_full_u <- species_genes
  cat("  Loaded:", nrow(species2_net_unsigned), "×", ncol(species2_net_unsigned), "matrix\n")
  cat("  Threshold:", format(species2_thr_unsigned, digits = 3), "\n\n")
  rm(species_net_unsigned, species_thr_unsigned, species_genes)
  gc(verbose = FALSE)

  # Filter unsigned networks to pair orthologs
  cat("Filtering unsigned networks to pair orthologs...\n")

  genes_to_keep_1u <- intersect(species1_genes_full_u, species1_genes_in_pair)
  cat("  ", opt$species1, ": keeping", length(genes_to_keep_1u), "of", length(species1_genes_full_u), "genes\n", sep = "")
  species1_net_unsigned <- species1_net_unsigned[genes_to_keep_1u, genes_to_keep_1u, drop = FALSE]

  genes_to_keep_2u <- intersect(species2_genes_full_u, species2_genes_in_pair)
  cat("  ", opt$species2, ": keeping", length(genes_to_keep_2u), "of", length(species2_genes_full_u), "genes\n\n", sep = "")
  species2_net_unsigned <- species2_net_unsigned[genes_to_keep_2u, genes_to_keep_2u, drop = FALSE]

  # Clean up
  rm(species1_genes_full_u, species2_genes_full_u, genes_to_keep_1u, genes_to_keep_2u)
  gc(verbose = FALSE)
}

# ==============================================================================
# SAVE FILTERED NETWORKS
# ==============================================================================

cat(rep("=", 60), "\n", sep = "")
cat("SAVING FILTERED NETWORKS\n")
cat(rep("=", 60), "\n\n", sep = "")

dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# Save signed networks
output_file_signed <- file.path(opt$outdir, "02_networks_signed.RData")
cat("Saving signed networks to:", output_file_signed, "\n")
species1_name <- opt$species1
species2_name <- opt$species2
save(species1_net_signed, species2_net_signed,
     species1_thr_signed, species2_thr_signed,
     species1_name, species2_name, shared_ortho_hogs,
     file = output_file_signed)

# Save unsigned networks if available
if (have_unsigned) {
  output_file_unsigned <- file.path(opt$outdir, "02_networks_unsigned.RData")
  cat("Saving unsigned networks to:", output_file_unsigned, "\n")
  save(species1_net_unsigned, species2_net_unsigned,
       species1_thr_unsigned, species2_thr_unsigned,
       species1_name, species2_name, shared_ortho_hogs,
       file = output_file_unsigned)
}

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Step 3 COMPLETE\n")
cat(rep("=", 80), "\n")

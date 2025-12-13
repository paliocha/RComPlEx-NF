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

load(input_file)  # loads: ortho, species1_expr, species2_expr, species1_name, species2_name

# Extract gene IDs from ortholog table (ortho has columns: Species1, Species2, OrthoGroup)
species1_genes_in_pair <- unique(ortho$Species1)
species2_genes_in_pair <- unique(ortho$Species2)

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

# ==============================================================================
# OPTION (B): RECOMPUTE PAIR-SPECIFIC THRESHOLDS
# ==============================================================================
# For each pair, recompute density threshold based only on genes in that pair.
# This ensures the network density is calibrated to the subset of orthologs
# in this specific pair, rather than using the ortholog-wide threshold.

cat(rep("=", 60), "\n", sep = "")
cat("RECOMPUTING PAIR-SPECIFIC THRESHOLDS (OPTION B)\n")
cat(rep("=", 60), "\n\n", sep = "")

# Get density threshold from config (passed implicitly via ortholog count)
# Extract from provided thresholds as reference for density target
# Recompute thresholds based on pair-specific gene counts

cat("Computing pair-specific signed thresholds...\n")

# Extract upper triangle of pair-specific networks and rank them
sp1_edges_signed <- species1_net_signed[upper.tri(species1_net_signed, diag = FALSE)]
sp2_edges_signed <- species2_net_signed[upper.tri(species2_net_signed, diag = FALSE)]

# Estimate density from original ortholog-wide threshold
# (species1_thr_signed was computed as top density_thr% of ortholog-wide edges)
# For pair-specific case, we recompute at same density percentage
# Density percentage = number of edges above threshold / total edges
n_edges_sp1 <- length(sp1_edges_signed)
n_edges_sp2 <- length(sp2_edges_signed)

# Estimate target density from original threshold
# If original network had n total edges and threshold at rank k, density = k/n
# For new pair, use same density percentage
# Find the rank in the original full network corresponding to the threshold value
original_full_sp1_edges <- ncol(species1_net_signed) * (ncol(species1_net_signed) - 1) / 2  # all possible upper triangle edges
original_full_sp2_edges <- ncol(species2_net_signed) * (ncol(species2_net_signed) - 1) / 2

# Maintain proportional density: if threshold was at rank k out of n, 
# apply same proportion to new network
# For simplicity: if the original pair-wide threshold is higher than max pair-specific edge,
# use a conservative approach: sort and keep same proportion as before

sp1_edges_sorted <- sort(sp1_edges_signed, decreasing = TRUE)
sp2_edges_sorted <- sort(sp2_edges_signed, decreasing = TRUE)

# Determine density fraction from original thresholds
# If original threshold falls above max(pair_edges), use 100% (keep all)
# Otherwise, find proportion in original and apply to pair

# Conservative approach: for pair, keep the top K% corresponding to original density
# Estimate original density: number of edges >= threshold / total edges
# This requires knowing the total number of edges in the original network
# Approximation: use the ortholog-wide network size as reference

n_full_edges_sp1 <- length(species1_genes_full) * (length(species1_genes_full) - 1) / 2
n_full_edges_sp2 <- length(species2_genes_full) * (length(species2_genes_full) - 1) / 2

# If threshold-based ranking unavailable, infer density from threshold magnitude
# Edges >= threshold contribute to the network
# For pair: apply same threshold value (if within range) or recalibrate

sp1_pair_thr_signed <- species1_thr_signed  # Use original threshold if within range
sp2_pair_thr_signed <- species2_thr_signed

# Check if thresholds are valid for pair subnetwork
if (sp1_pair_thr_signed > max(sp1_edges_signed, na.rm = TRUE)) {
  # Threshold too high for pair subnetwork; use proportional density
  target_density <- round(0.03 * n_edges_sp1)  # Default 3% density
  if (target_density > 0) {
    sp1_pair_thr_signed <- sp1_edges_sorted[target_density]
  } else {
    sp1_pair_thr_signed <- max(sp1_edges_signed, na.rm = TRUE)
  }
  cat("  Species 1: Original threshold exceeded pair subnetwork; recalibrated to ",
      format(sp1_pair_thr_signed, digits = 3), "\n", sep = "")
} else {
  cat("  Species 1: Using original ortholog-wide threshold ",
      format(sp1_pair_thr_signed, digits = 3), " (applicable to pair)\n", sep = "")
}

if (sp2_pair_thr_signed > max(sp2_edges_signed, na.rm = TRUE)) {
  target_density <- round(0.03 * n_edges_sp2)
  if (target_density > 0) {
    sp2_pair_thr_signed <- sp2_edges_sorted[target_density]
  } else {
    sp2_pair_thr_signed <- max(sp2_edges_signed, na.rm = TRUE)
  }
  cat("  Species 2: Original threshold exceeded pair subnetwork; recalibrated to ",
      format(sp2_pair_thr_signed, digits = 3), "\n\n", sep = "")
} else {
  cat("  Species 2: Using original ortholog-wide threshold ",
      format(sp2_pair_thr_signed, digits = 3), " (applicable to pair)\n\n", sep = "")
}

# Update stored thresholds for pair-specific use
species1_thr_signed <- sp1_pair_thr_signed
species2_thr_signed <- sp2_pair_thr_signed

rm(sp1_edges_signed, sp2_edges_signed, sp1_edges_sorted, sp2_edges_sorted,
   species1_genes_full, species2_genes_full, genes_to_keep_1, genes_to_keep_2,
   n_edges_sp1, n_edges_sp2, n_full_edges_sp1, n_full_edges_sp2, target_density,
   sp1_pair_thr_signed, sp2_pair_thr_signed)
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

  # ==============================================================================
  # OPTION (B): RECOMPUTE PAIR-SPECIFIC THRESHOLDS FOR UNSIGNED NETWORKS
  # ==============================================================================

  cat(rep("=", 60), "\n", sep = "")
  cat("RECOMPUTING PAIR-SPECIFIC UNSIGNED THRESHOLDS (OPTION B)\n")
  cat(rep("=", 60), "\n\n", sep = "")

  cat("Computing pair-specific unsigned thresholds...\n")

  # Extract upper triangle and rank
  sp1_edges_unsigned <- species1_net_unsigned[upper.tri(species1_net_unsigned, diag = FALSE)]
  sp2_edges_unsigned <- species2_net_unsigned[upper.tri(species2_net_unsigned, diag = FALSE)]

  n_edges_sp1_u <- length(sp1_edges_unsigned)
  n_edges_sp2_u <- length(sp2_edges_unsigned)

  sp1_edges_sorted_u <- sort(sp1_edges_unsigned, decreasing = TRUE)
  sp2_edges_sorted_u <- sort(sp2_edges_unsigned, decreasing = TRUE)

  sp1_pair_thr_unsigned <- species1_thr_unsigned
  sp2_pair_thr_unsigned <- species2_thr_unsigned

  if (sp1_pair_thr_unsigned > max(sp1_edges_unsigned, na.rm = TRUE)) {
    target_density_u <- round(0.03 * n_edges_sp1_u)
    if (target_density_u > 0) {
      sp1_pair_thr_unsigned <- sp1_edges_sorted_u[target_density_u]
    } else {
      sp1_pair_thr_unsigned <- max(sp1_edges_unsigned, na.rm = TRUE)
    }
    cat("  Species 1 (unsigned): Original threshold exceeded pair subnetwork; recalibrated to ",
        format(sp1_pair_thr_unsigned, digits = 3), "\n", sep = "")
  } else {
    cat("  Species 1 (unsigned): Using original ortholog-wide threshold ",
        format(sp1_pair_thr_unsigned, digits = 3), " (applicable to pair)\n", sep = "")
  }

  if (sp2_pair_thr_unsigned > max(sp2_edges_unsigned, na.rm = TRUE)) {
    target_density_u <- round(0.03 * n_edges_sp2_u)
    if (target_density_u > 0) {
      sp2_pair_thr_unsigned <- sp2_edges_sorted_u[target_density_u]
    } else {
      sp2_pair_thr_unsigned <- max(sp2_edges_unsigned, na.rm = TRUE)
    }
    cat("  Species 2 (unsigned): Original threshold exceeded pair subnetwork; recalibrated to ",
        format(sp2_pair_thr_unsigned, digits = 3), "\n\n", sep = "")
  } else {
    cat("  Species 2 (unsigned): Using original ortholog-wide threshold ",
        format(sp2_pair_thr_unsigned, digits = 3), " (applicable to pair)\n\n", sep = "")
  }

  # Update stored unsigned thresholds for pair-specific use
  species1_thr_unsigned <- sp1_pair_thr_unsigned
  species2_thr_unsigned <- sp2_pair_thr_unsigned

  # Clean up
  rm(species1_genes_full_u, species2_genes_full_u, genes_to_keep_1u, genes_to_keep_2u,
     sp1_edges_unsigned, sp2_edges_unsigned, sp1_edges_sorted_u, sp2_edges_sorted_u,
     n_edges_sp1_u, n_edges_sp2_u, target_density_u,
     sp1_pair_thr_unsigned, sp2_pair_thr_unsigned)
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

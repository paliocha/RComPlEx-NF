#!/usr/bin/env Rscript
# ==============================================================================
# RComPlEx Step 3: Network Comparison
# ==============================================================================
# Performs parallel pairwise network comparisons using hypergeometric testing
# and computes p-values for neighborhood conservation
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(optparse)
  library(furrr)
  library(future)
  library(parallel)
})

# Source Orion HPC utilities for path resolution (resolve across work and home mounts)
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
  make_option(c("-c", "--config"), type = "character", default = "config/pipeline_config.yaml",
              help = "Path to configuration file [default= %default]", metavar = "character"),
  make_option(c("-w", "--workdir"), type = "character", default = ".",
              help = "Working directory [default= %default]", metavar = "character"),
  make_option(c("-i", "--indir"), type = "character", default = NULL,
              help = "Input directory with previous step outputs", metavar = "character"),
  make_option(c("-o", "--outdir"), type = "character", default = NULL,
              help = "Output directory for results", metavar = "character"),
  make_option(c("--cores"), type = "integer", default = NULL,
              help = "Number of CPU cores to use", metavar = "integer")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Resolve Orion HPC paths
opt$config <- resolve_orion_path(opt$config)
opt$workdir <- resolve_orion_path(opt$workdir)
opt$indir <- resolve_orion_path(opt$indir)
opt$outdir <- resolve_orion_path(opt$outdir)

# Validate required arguments
required_args <- c("tissue", "pair_id", "indir", "outdir")
for (arg in required_args) {
  if (is.null(opt[[arg]])) {
    print_help(opt_parser)
    stop("--", arg, " argument is required", call. = FALSE)
  }
}

# Setup parallel processing
if (is.null(opt$cores)) {
  slurm_cpus <- Sys.getenv("SLURM_CPUS_PER_TASK", unset = "")
  if (slurm_cpus != "") {
    n_cores <- as.integer(slurm_cpus) - 1
  } else {
    n_cores <- parallel::detectCores() - 1
  }
} else {
  n_cores <- opt$cores - 1
}
if (n_cores < 1) n_cores <- 1

# Increase future.globals.maxSize for large matrices
options(future.globals.maxSize = Inf)

# Store working directory for path resolution
workdir <- opt$workdir

# Source config parser using path resolution (Orion HPC multi-mount issue)
config_parser_candidates <- c(
  "R/config_parser.R",
  file.path(workdir, "R/config_parser.R"),
  file.path(Sys.getenv("HOME", ""), "AnnualPerennial/RComPlEx/R/config_parser.R"),
  "/opt/rcomplex/R/config_parser.R"
)
config_parser_path <- config_parser_candidates[file.exists(config_parser_candidates)][1]
if (is.na(config_parser_path)) {
  stop("Cannot locate R/config_parser.R; checked: ",
       paste(config_parser_candidates, collapse = ", "))
}
source(config_parser_path)

# Load configuration
config <- load_config(opt$config, workdir = workdir)

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("RComPlEx Step 3: Network Comparison\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Pair ID:", opt$pair_id, "\n")
cat("Cores available:", n_cores, "\n")
cat(rep("=", 80), "\n\n")

# Create output directory
dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# LOAD DATA FROM PREVIOUS STEPS
# ==============================================================================

cat("Loading data from previous steps...\n")

# Load networks from step 3 (includes ortho table, species names, networks, and thresholds)
# Check for both signed and unsigned versions
input_file_signed <- file.path(opt$indir, "02_networks_signed.RData")
input_file_unsigned <- file.path(opt$indir, "02_networks_unsigned.RData")

if (file.exists(input_file_signed)) {
  cat("  Loading signed networks from:", input_file_signed, "\n")
  load(input_file_signed)
  # Rename for consistency with downstream code
  species1_net <- species1_net_signed
  species2_net <- species2_net_signed
  species1_thr <- species1_thr_signed
  species2_thr <- species2_thr_signed
} else if (file.exists(input_file_unsigned)) {
  cat("  Loading unsigned networks from:", input_file_unsigned, "\n")
  load(input_file_unsigned)
  # Rename for consistency with downstream code
  species1_net <- species1_net_unsigned
  species2_net <- species2_net_unsigned
  species1_thr <- species1_thr_unsigned
  species2_thr <- species2_thr_unsigned
} else {
  stop("Networks file not found. Expected either:\n  ", 
       input_file_signed, "\n  or\n  ", input_file_unsigned)
}

cat("✓ Data loaded successfully\n\n")

# ==============================================================================
# VALIDATE ORTHOLOGS EXIST IN NETWORKS
# ==============================================================================

cat("Validating that all orthologs have genes in the networks...\n")

species1_net_genes <- rownames(species1_net)
species2_net_genes <- rownames(species2_net)

# Find orthologs with genes that exist in both networks
valid_orthos <- ortho %>%
  filter(Species1 %in% species1_net_genes & Species2 %in% species2_net_genes)

# If any orthologs were filtered out, update the ortho table
if (nrow(valid_orthos) < nrow(ortho)) {
  filtered_count <- nrow(ortho) - nrow(valid_orthos)
  cat("  Filtered out", filtered_count, "orthologs missing from networks\n")
  ortho <- valid_orthos
}

cat("  Processing", nrow(ortho), "ortholog pairs\n\n")

# ==============================================================================
# PARALLEL NETWORK COMPARISON
# ==============================================================================

cat(rep("=", 60), "\n", sep = "")
cat("PARALLEL NETWORK NEIGHBORHOOD COMPARISON\n")
cat(rep("=", 60), "\n\n", sep = "")

comparison_start <- Sys.time()

# Set up parallel processing
plan(multisession, workers = n_cores)

# Pre-compute network dimensions for efficiency (total genes per species)
N1 <- nrow(species1_net)
N2 <- nrow(species2_net)

cat("Processing", nrow(ortho), "ortholog pairs using", n_cores, "cores\n\n")

# PARALLEL NETWORK COMPARISON LOOP
# ================================
# Suppress warnings and disable progress bar (progress to stderr causes Nextflow issues)
comparison <- suppressWarnings({
  ortho %>%
    mutate(row_id = row_number()) %>%
    group_split(row_id) %>%
    future_map_dfr(function(row_data) {

    i <- row_data$row_id

    # Species 1 -> Species 2
    # ======================

    neigh <- species1_net[ortho$Species1[i], ]
    neigh <- names(neigh[neigh >= species1_thr])

    ortho_neigh <- species2_net[ortho$Species2[i], ]
    ortho_neigh <- names(ortho_neigh[ortho_neigh >= species2_thr])
    ortho_neigh <- unique(ortho$Species1[ortho$Species2 %in% ortho_neigh])

    m <- length(neigh)
    n <- N1 - m
    k <- length(ortho_neigh)
    x <- length(intersect(neigh, ortho_neigh))
    p_val_1 <- 1
    effect_size_1 <- 1
    if (x > 1) {
      p_val_1 <- phyper(x - 1, m, n, k, lower.tail = FALSE)
      effect_size_1 <- (x / k) / (m / N1)
    }

    # Species 2 -> Species 1
    # ======================

    neigh <- species2_net[ortho$Species2[i], ]
    neigh <- names(neigh[neigh >= species2_thr])

    ortho_neigh <- species1_net[ortho$Species1[i], ]
    ortho_neigh <- names(ortho_neigh[ortho_neigh >= species1_thr])
    ortho_neigh <- unique(ortho$Species2[ortho$Species1 %in% ortho_neigh])

    m2 <- length(neigh)
    n2 <- N2 - m2
    k2 <- length(ortho_neigh)
    x2 <- length(intersect(neigh, ortho_neigh))
    p_val_2 <- 1
    effect_size_2 <- 1
    if (x2 > 1) {
      p_val_2 <- phyper(x2 - 1, m2, n2, k2, lower.tail = FALSE)
      effect_size_2 <- (x2 / k2) / (m2 / N2)
    }

    # Return results as single row tibble
    tibble(
      OrthoGroup = ortho$OrthoGroup[i],
      Species1 = ortho$Species1[i],
      Species2 = ortho$Species2[i],
      Species1.neigh = m,
      Species1.ortho.neigh = k,
      Species1.neigh.overlap = x,
      Species1.p.val = p_val_1,
      Species1.effect.size = effect_size_1,
      Species2.neigh = m2,
      Species2.ortho.neigh = k2,
      Species2.neigh.overlap = x2,
      Species2.p.val = p_val_2,
      Species2.effect.size = effect_size_2
    )

  }, .progress = FALSE, .options = furrr_options(seed = TRUE))
})

comparison_elapsed <- as.numeric(difftime(Sys.time(), comparison_start, units = "mins"))
cat("\n✓ Network comparison completed in", round(comparison_elapsed, 2), "minutes\n")
cat("  Average:", round(comparison_elapsed * 60 / nrow(ortho), 3), "seconds per ortholog pair\n\n")

# ==============================================================================
# POST-PROCESSING AND STATISTICS
# ==============================================================================

cat("Post-processing results...\n\n")

# Filter orthologs not in the networks
comparison <- comparison %>%
  filter(Species1.neigh.overlap > 0 & Species2.neigh.overlap > 0)

# FDR correction
comparison$Species1.p.val <- p.adjust(comparison$Species1.p.val, method = "fdr")
comparison$Species2.p.val <- p.adjust(comparison$Species2.p.val, method = "fdr")

cat("After filtering:\n")
cat("  Ortholog groups:", length(unique(comparison$OrthoGroup)), "\n")
cat("    -", species1_name, "genes:", length(unique(comparison$Species1)), "\n")
cat("    -", species2_name, "genes:", length(unique(comparison$Species2)), "\n\n")

# ==============================================================================
# SAVE RESULTS
# ==============================================================================

output_file <- file.path(opt$outdir, paste0("03_", opt$pair_id, ".RData"))
cat("Saving comparison results to:", output_file, "\n")
save(comparison, species1_thr, species2_thr,
     species1_name, species2_name,
     file = output_file)

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Step 3 COMPLETE\n")
cat(rep("=", 80), "\n")

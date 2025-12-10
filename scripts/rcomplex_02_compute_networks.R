#!/usr/bin/env Rscript
# ==============================================================================
# RComPlEx Step 2: Compute Co-Expression Networks
# ==============================================================================
# Computes correlation matrices with parallelization, applies normalization
# (CLR or MR), and determines density thresholds
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(optparse)
  library(furrr)
  library(future)
  library(parallel)
  library(matrixStats)
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
              help = "Input directory with step 1 output", metavar = "character"),
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

# Source config parser
source(file.path(workdir, "R/config_parser.R"))

# Load configuration
config <- load_config(opt$config, workdir = workdir)

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("RComPlEx Step 2: Compute Co-Expression Networks\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Pair ID:", opt$pair_id, "\n")
cat("Cores available:", n_cores, "\n")
cat(rep("=", 80), "\n\n")

# ==============================================================================
# LOAD FILTERED DATA FROM STEP 1
# ==============================================================================

input_file <- file.path(opt$indir, "01_filtered_data.RData")
if (!file.exists(input_file)) {
  stop("Step 1 output not found: ", input_file)
}

cat("Loading filtered data from step 1...\n")
load(input_file)

# Get parameters from config
cor_method <- config$rcomplex$cor_method
cor_sign <- config$rcomplex$cor_sign
norm_method <- config$rcomplex$norm_method
density_thr <- config$rcomplex$density_thr
randomize <- ""  # Never randomize in production

cat("\nParameters:\n")
cat("  Correlation method:", cor_method, "\n")
cat("  Correlation sign:", ifelse(cor_sign == "", "signed", cor_sign), "\n")
cat("  Normalization method:", norm_method, "\n")
cat("  Network density threshold:", density_thr, "\n")
cat("  Randomization:", ifelse(randomize == "", "none", randomize), "\n\n")

# Create output directory
dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# COMPUTE CO-EXPRESSION NETWORKS
# ==============================================================================

cat(rep("=", 60), "\n", sep = "")
cat("COMPUTING CO-EXPRESSION NETWORKS\n")
cat(rep("=", 60), "\n\n", sep = "")

start_time <- Sys.time()

if (randomize == "rand") {
  cat("Randomizing gene names for null model...\n")
  species1_expr$Genes <- sample(species1_expr$Genes, nrow(species1_expr), FALSE)
  species2_expr$Genes <- sample(species2_expr$Genes, nrow(species2_expr), FALSE)
}

# PARALLEL CORRELATION COMPUTATION
# ================================
# Strategy: Parallelizes across species (2 workers: one for each species)
# Each correlation matrix is computed within R's base cor() function
# 
# NOTE: R's base cor() uses native compiled code and is already quite fast.
# For very large matrices, you could alternatively use:
#   - WGCNA::cor(): Uses threaded computation (faster for huge matrices)
#     However, WGCNA only supports Pearson and Spearman (which we need)
#     Install: uncomment 'bioconductor-wgcna' in environment.yml
#   - FastCorr or other optimized implementations
# 
# Current approach balances memory efficiency (separate processes) with
# computation speed (parallelizes across species, not within)

cat("Computing correlation matrices in parallel...\n")
cat("  Matrix size: ~", nrow(species1_expr), "×", nrow(species1_expr),
    " and ~", nrow(species2_expr), "×", nrow(species2_expr), "\n")
cat("  Using", min(2, n_cores), "workers for species-level parallelization\n\n")

cor_start <- Sys.time()

# Set up parallel processing
plan(multisession, workers = min(2, n_cores))

# Parallel computation of both correlation matrices
correlation_results <- future_map(
  list(
    list(expr = species1_expr, name = species1_name),
    list(expr = species2_expr, name = species2_name)
  ),
  function(sp) {
    expr_matrix <- t(sp$expr[, -1])
    net <- cor(expr_matrix, method = cor_method)
    dimnames(net) <- list(sp$expr$Genes, sp$expr$Genes)
    return(net)
  },
  .options = furrr_options(seed = TRUE)
)

species1_net <- correlation_results[[1]]
species2_net <- correlation_results[[2]]

# Clean up memory
rm(correlation_results)
gc(verbose = FALSE)

cor_elapsed <- as.numeric(difftime(Sys.time(), cor_start, units = "secs"))
cat("✓ Correlation computation completed in", round(cor_elapsed, 1), "seconds\n\n")

# Apply sign correction
if (cor_sign == "abs") {
  cat("Applying absolute value to correlations...\n")
  species1_net <- abs(species1_net)
  species2_net <- abs(species2_net)
}

# NORMALIZATION
# =============

if (norm_method == "CLR") {
  cat("\nApplying CLR (Centered Log Ratio) normalization...\n")
  norm_start <- Sys.time()

  # Preserve gene names before CLR normalization
  species1_genes <- rownames(species1_net)
  species2_genes <- rownames(species2_net)

  # Species 1: Vectorized CLR with Rfast
  z <- scale(species1_net)
  z[z < 0] <- 0
  species1_net <- sqrt(Rfast::Tcrossprod(t(z)) + Rfast::Tcrossprod(z))
  rownames(species1_net) <- species1_genes
  colnames(species1_net) <- species1_genes

  # Species 2: Vectorized CLR with Rfast
  z <- scale(species2_net)
  z[z < 0] <- 0
  species2_net <- sqrt(Rfast::Tcrossprod(t(z)) + Rfast::Tcrossprod(z))
  rownames(species2_net) <- species2_genes
  colnames(species2_net) <- species2_genes

  norm_elapsed <- as.numeric(difftime(Sys.time(), norm_start, units = "secs"))
  cat("✓ CLR normalization completed in", round(norm_elapsed, 1), "seconds\n\n")

} else if (norm_method == "MR") {
  cat("\nApplying Mutual Rank (MR) normalization with Rfast...\n")
  norm_start <- Sys.time()

  # Preserve gene names before MR normalization (matrices lose dimnames during computation)
  species1_genes <- rownames(species1_net)
  species2_genes <- rownames(species2_net)

  # Species 1: Fast ranking + vectorized MR with Rfast
  cat("Ranking and computing MR for", species1_name, "...\n")
  R1 <- matrixStats::rowRanks(species1_net, ties.method = "average")
  species1_net <- sqrt(Rfast::Tcrossprod(R1, R1))
  rownames(species1_net) <- species1_genes
  colnames(species1_net) <- species1_genes
  rm(R1)
  gc(verbose = FALSE)

  # Species 2: Fast ranking + vectorized MR with Rfast
  cat("Ranking and computing MR for", species2_name, "...\n")
  R2 <- matrixStats::rowRanks(species2_net, ties.method = "average")
  species2_net <- sqrt(Rfast::Tcrossprod(R2, R2))
  rownames(species2_net) <- species2_genes
  colnames(species2_net) <- species2_genes
  rm(R2)
  gc(verbose = FALSE)

  norm_elapsed <- as.numeric(difftime(Sys.time(), norm_start, units = "secs"))
  cat("\n✓ MR normalization completed in", round(norm_elapsed, 1), "seconds\n\n")
}

# Remove diagonals and set to 0
diag(species1_net) <- 0
diag(species2_net) <- 0

# Compute network density thresholds
# ==================================

cat("Computing network density thresholds...\n")
R <- sort(species1_net[upper.tri(species1_net, diag = FALSE)], decreasing = TRUE)
species1_thr <- R[round(density_thr * length(R))]
cat("  ", species1_name, "threshold at", format(density_thr * 100), "% density:",
    format(species1_thr, digits = 3), "\n", sep = "")

R <- sort(species2_net[upper.tri(species2_net, diag = FALSE)], decreasing = TRUE)
species2_thr <- R[round(density_thr * length(R))]
cat("  ", species2_name, "threshold at", format(density_thr * 100), "% density:",
    format(species2_thr, digits = 3), "\n", sep = "")

rm(R)
gc(verbose = FALSE)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
cat("\n✓ Network computation completed in", round(elapsed, 2), "minutes\n\n")

# ==============================================================================
# SAVE NETWORKS
# ==============================================================================

output_file <- file.path(opt$outdir, "02_networks.RData")
cat("Saving networks to:", output_file, "\n")
save(species1_net, species2_net, species1_thr, species2_thr,
     species1_name, species2_name,
     file = output_file)

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Step 2 COMPLETE\n")
cat(rep("=", 80), "\n")

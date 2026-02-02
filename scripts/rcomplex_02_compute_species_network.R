#!/usr/bin/env Rscript
# ==============================================================================
# RComPlEx Step 2: Compute Species Co-Expression Network
# ==============================================================================
# Computes correlation matrix for a SINGLE species-tissue combination
# This network is reused across all pairwise comparisons involving this species
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(optparse)
  library(parallel)
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
  make_option(c("-s", "--species"), type = "character", default = NULL,
              help = "Species name", metavar = "character"),
  make_option(c("-c", "--config"), type = "character", default = "config/pipeline_config.yaml",
              help = "Path to configuration file [default= %default]", metavar = "character"),
  make_option(c("-w", "--workdir"), type = "character", default = ".",
              help = "Working directory [default= %default]", metavar = "character"),
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
opt$outdir <- resolve_orion_path(opt$outdir)

# Validate required arguments
required_args <- c("tissue", "species", "outdir")
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
    n_cores <- as.integer(slurm_cpus)
  } else {
    n_cores <- parallel::detectCores()
  }
} else {
  n_cores <- opt$cores
}
if (n_cores < 1) n_cores <- 1

# Store working directory for path resolution
workdir <- opt$workdir

# Source config parser
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
cat("RComPlEx Step 2: Compute Species Co-Expression Network\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Species:", opt$species, "\n")
cat("Cores available:", n_cores, "\n")
cat(rep("=", 80), "\n\n")

# ==============================================================================
# LOAD EXPRESSION DATA
# ==============================================================================

# Load VST expression data
vst_file <- file.path(workdir, "vst_hog.RDS")
if (!file.exists(vst_file)) {
  stop("Expression file not found: ", vst_file)
}

cat("Loading expression data from:", vst_file, "\n")
vst <- readRDS(vst_file)

# Normalize species names to underscores to match pipeline inputs
vst <- vst %>% mutate(species = str_replace(species, " ", "_"))

# Filter to this species and tissue
cat("Filtering to species:", opt$species, "and tissue:", opt$tissue, "\n")
species_expr <- vst %>%
  filter(species == opt$species, tissue == opt$tissue) %>%
  select(GeneID, sample_id, vst.count) %>%
  pivot_wider(names_from = sample_id, values_from = vst.count) %>%
  rename(Genes = GeneID)

cat("  Expression matrix:", nrow(species_expr), "genes ×", ncol(species_expr) - 1, "samples\n")

# Restrict to genes that have an ortholog in any other species (closer to original RComPlEx logic)
n1_file <- config$data$n1_file
if (!file.exists(n1_file)) {
  stop("Ortholog file not found: ", n1_file)
}

n1 <- readRDS(n1_file)
# Normalize species names in ortholog table for consistent matching
n1 <- n1 %>% mutate(species = str_replace(species, " ", "_"))
genes_with_ortholog <- unique(n1$GeneID[n1$species == opt$species])

cat("  Genes with orthologs for", opt$species, ":", length(genes_with_ortholog), "\n")
species_expr <- species_expr %>% filter(Genes %in% genes_with_ortholog)
cat("  After ortholog filter:", nrow(species_expr), "genes ×", ncol(species_expr) - 1, "samples\n\n")

if (nrow(species_expr) == 0) {
  stop("No ortholog-filtered expression data for species ", opt$species, " in tissue ", opt$tissue)
}

# Get parameters from config
cor_method <- config$rcomplex$cor_method
cor_sign <- config$rcomplex$cor_sign
norm_method <- config$rcomplex$norm_method
density_thr <- config$rcomplex$density_thr

cat("Parameters:\n")
cat("  Correlation method:", cor_method, "\n")
cat("  Correlation sign:", ifelse(cor_sign == "", "signed", cor_sign), "\n")
cat("  Normalization method:", norm_method, "\n")
cat("  Network density threshold:", density_thr, "\n\n")

# Create output directory
dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# COMPUTE CO-EXPRESSION NETWORK
# ==============================================================================

cat(rep("=", 60), "\n", sep = "")
cat("COMPUTING CO-EXPRESSION NETWORK\n")
cat(rep("=", 60), "\n\n", sep = "")

start_time <- Sys.time()

# Compute correlation matrix
cat("Computing correlation matrix...\n")
cat("  Matrix size:", nrow(species_expr), "×", nrow(species_expr), "\n\n")

cor_start <- Sys.time()

expr_matrix <- t(species_expr[, -1])
species_net <- cor(expr_matrix, method = cor_method)
dimnames(species_net) <- list(species_expr$Genes, species_expr$Genes)
rm(expr_matrix)
gc(verbose = FALSE)

cor_elapsed <- as.numeric(difftime(Sys.time(), cor_start, units = "secs"))
cat("✓ Correlation computation completed in", round(cor_elapsed, 1), "seconds\n\n")

# Apply sign correction
if (cor_sign == "abs") {
  cat("Applying absolute value to correlations...\n")
  species_net <- abs(species_net)
}

# NORMALIZATION
# =============

if (norm_method == "CLR") {
  cat("\nApplying CLR (Centered Log Ratio) normalization...\n")
  norm_start <- Sys.time()

  # Preserve gene names before CLR normalization
  species_genes <- rownames(species_net)

  # Vectorized CLR with Rfast
  library(Rfast)
  z <- scale(species_net)
  z[z < 0] <- 0
  species_net <- sqrt(Rfast::Tcrossprod(t(z)) + Rfast::Tcrossprod(z))
  rownames(species_net) <- species_genes
  colnames(species_net) <- species_genes

  norm_elapsed <- as.numeric(difftime(Sys.time(), norm_start, units = "secs"))
  cat("✓ CLR normalization completed in", round(norm_elapsed, 1), "seconds\n\n")

} else if (norm_method == "MR") {
  cat("\nApplying Mutual Rank (MR) normalization with Rfast...\n")
  norm_start <- Sys.time()

  # Preserve gene names before MR normalization
  species_genes <- rownames(species_net)

  # Store original correlations for unsigned MR computation
  species_cor_original <- species_net

  # Signed MR
  cat("Ranking and computing MR for", opt$species, "...\n")
  library(Rfast)
  R1 <- Rfast::rowRanks(species_net, method = "average", parallel = TRUE, cores = n_cores)
  species_net <- sqrt(Rfast::Tcrossprod(R1, R1))
  rownames(species_net) <- species_genes
  colnames(species_net) <- species_genes
  rm(R1)
  gc(verbose = FALSE)

  # Remove diagonals from signed network
  diag(species_net) <- 0

  # Compute thresholds for signed network
  cat("\nComputing density thresholds for signed network...\n")
  R <- sort(species_net[upper.tri(species_net, diag = FALSE)], decreasing = TRUE)
  species_thr <- R[round(density_thr * length(R))]
  cat("  ", opt$species, "threshold at", format(density_thr * 100), "% density:",
      format(species_thr, digits = 3), "\n", sep = "")
  rm(R)
  gc(verbose = FALSE)

  # Save signed network
  cat("\nSaving signed MR network...\n")
  output_file_signed <- file.path(opt$outdir, "02_network_signed.RData")
  save(species_net, species_thr, species_genes,
       file = output_file_signed, compress = FALSE)

  # Clean up signed network to free memory
  rm(species_net, species_thr)
  gc(verbose = FALSE)

  # Also compute UNSIGNED MR for polarity analysis
  cat("\nComputing UNSIGNED MR for polarity divergence analysis...\n")

  # Create unsigned network from absolute correlations before MR transformation
  species_net_unsigned <- abs(species_cor_original)

  R1u <- Rfast::rowRanks(species_net_unsigned, method = "average", parallel = TRUE, cores = n_cores)
  species_net_unsigned <- sqrt(Rfast::Tcrossprod(R1u, R1u))
  rownames(species_net_unsigned) <- species_genes
  colnames(species_net_unsigned) <- species_genes
  rm(R1u)
  gc(verbose = FALSE)

  # Remove diagonals from unsigned network
  diag(species_net_unsigned) <- 0

  # Compute thresholds for unsigned network
  cat("\nComputing density thresholds for unsigned network...\n")
  R <- sort(species_net_unsigned[upper.tri(species_net_unsigned, diag = FALSE)], decreasing = TRUE)
  species_thr_unsigned <- R[round(density_thr * length(R))]
  cat("  ", opt$species, "(unsigned) threshold at", format(density_thr * 100), "% density:",
      format(species_thr_unsigned, digits = 3), "\n", sep = "")
  rm(R)
  gc(verbose = FALSE)

  # Save unsigned MR network
  cat("\nSaving unsigned MR network...\n")
  output_file_unsigned <- file.path(opt$outdir, "02_network_unsigned.RData")
  save(species_net_unsigned, species_thr_unsigned, species_genes,
       file = output_file_unsigned, compress = FALSE)

  # Clean up
  rm(species_cor_original, species_net_unsigned, species_thr_unsigned)
  gc(verbose = FALSE)

  norm_elapsed <- as.numeric(difftime(Sys.time(), norm_start, units = "secs"))
  cat("\n✓ MR normalization completed in", round(norm_elapsed, 1), "seconds\n\n")
}

# For CLR normalization, compute thresholds and save
if (norm_method == "CLR") {
  # Remove diagonals
  diag(species_net) <- 0

  # Compute network density thresholds
  cat("Computing network density thresholds...\n")
  R <- sort(species_net[upper.tri(species_net, diag = FALSE)], decreasing = TRUE)
  species_thr <- R[round(density_thr * length(R))]
  cat("  ", opt$species, "threshold at", format(density_thr * 100), "% density:",
      format(species_thr, digits = 3), "\n", sep = "")
  rm(R)
  gc(verbose = FALSE)

  # Save CLR network
  output_file <- file.path(opt$outdir, "02_network_signed.RData")
  cat("Saving CLR network to:", output_file, "\n")
  species_genes <- rownames(species_net)
  save(species_net, species_thr, species_genes,
       file = output_file, compress = FALSE)
}

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
cat("\n✓ Network computation completed in", round(elapsed, 2), "minutes\n\n")

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Step 2 COMPLETE\n")
cat(rep("=", 80), "\n")

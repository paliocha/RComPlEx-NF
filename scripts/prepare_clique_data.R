#!/usr/bin/env Rscript
# ==============================================================================
# Prepare Clique Data - Step 1 of Batched Clique Detection
# ==============================================================================
# Loads all comparison files, extracts conserved gene pairs, groups by HOG,
# and saves intermediate data for batched processing.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(optparse)
  library(glue)
  library(qs2)
})

# Configure qs2 to use available threads (SLURM or detected cores)
qs2_threads <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", parallel::detectCores(logical = FALSE)))
if (is.na(qs2_threads) || qs2_threads < 1L) qs2_threads <- 1L
qopt(nthreads = qs2_threads)
message(sprintf("qs2 configured with %d threads", qs2_threads))

# Source Orion HPC utilities for path resolution
orion_utils_candidates <- c(
  "R/orion_hpc_utils.R",
  file.path(Sys.getenv("PROJECT_DIR", ""), "R/orion_hpc_utils.R"),
  file.path(Sys.getenv("HOME", ""), "AnnualPerennial/RComPlEx/R/orion_hpc_utils.R"),
  "/opt/rcomplex/R/orion_hpc_utils.R"
)
orion_utils_path <- orion_utils_candidates[file.exists(orion_utils_candidates)][1]
if (is.na(orion_utils_path)) {
  stop("Cannot locate R/orion_hpc_utils.R")
}
source(orion_utils_path)

# Parse command-line arguments
option_list <- list(
  make_option(c("-t", "--tissue"), type = "character", default = NULL,
              help = "Tissue to analyze", metavar = "character"),
  make_option(c("-c", "--config"), type = "character", default = "config/pipeline_config.yaml",
              help = "Path to configuration file", metavar = "character"),
  make_option(c("-w", "--workdir"), type = "character", default = ".",
              help = "Working directory", metavar = "character"),
  make_option(c("-o", "--outdir"), type = "character", default = ".",
              help = "Output directory for intermediate files", metavar = "character"),
  make_option(c("-r", "--results_dir"), type = "character", default = NULL,
              help = "Path to results directory with comparison RData files", metavar = "character"),
  make_option(c("-b", "--batch_size"), type = "integer", default = 500,
              help = "Number of HOGs per batch [default= %default]", metavar = "integer")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Resolve paths
opt$config <- resolve_orion_path(opt$config)
opt$workdir <- resolve_orion_path(opt$workdir)
opt$outdir <- resolve_orion_path(opt$outdir)
if (!is.null(opt$results_dir)) {
  opt$results_dir <- resolve_orion_path(opt$results_dir)
}

if (is.null(opt$tissue)) {
  stop("--tissue argument is required", call. = FALSE)
}

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
  stop("Cannot locate R/config_parser.R")
}
source(config_parser_path)

config <- load_config(opt$config, workdir = workdir)

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Prepare Clique Data - Batched Processing Step 1\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Batch size:", opt$batch_size, "HOGs per batch\n")
cat("Output directory:", opt$outdir, "\n")
cat(rep("=", 80), "\n\n", sep = "")

# Create output directory
dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# FIND COMPARISON FILES ========================================================
if (!is.null(opt$results_dir)) {
  results_dir <- opt$results_dir
} else {
  results_dir <- file.path(config$data$output_dir, opt$tissue, "results")
}

if (!dir.exists(results_dir)) {
  stop("Results directory not found: ", results_dir)
}

comparison_files <- list.files(results_dir,
                               pattern = "03_comparison(_unsigned)?\\.RData$",
                               recursive = TRUE,
                               full.names = TRUE)

if (length(comparison_files) == 0) {
  comparison_files <- list.files(results_dir,
                                 pattern = "comparison-.*\\.RData$",
                                 recursive = TRUE,
                                 full.names = TRUE)
}

if (length(comparison_files) == 0) {
  stop("No comparison files found in: ", results_dir)
}

cat("Found", length(comparison_files), "comparison files\n\n")

# LOAD CONSERVED PAIRS =========================================================
cat("Loading conserved gene pairs...\n")
cat("  (This may take a few minutes...)\n")

p_threshold <- config$rcomplex$p_threshold

conserved_pairs <- map_dfr(comparison_files, function(file) {
  load(file, envir = tmp_env <- new.env())
  comp <- tmp_env$comparison
  pair_id <- basename(dirname(file))
  
  comp %>%
    rowwise() %>%
    mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
    filter(Max.p.val < p_threshold) %>%
    ungroup() %>%
    mutate(
      PairID = pair_id,
      HOG = str_remove(OrthoGroup, "^HOG_")
    ) %>%
    select(Species1, Species2, HOG, OrthoGroup, Max.p.val,
           Species1.effect.size, Species2.effect.size, PairID)
}, .progress = TRUE)

cat("\n  ✓ Loaded", nrow(conserved_pairs), "conserved gene pairs\n")
cat("    - From", length(unique(conserved_pairs$PairID)), "species pair comparisons\n")
cat("    - Across", length(unique(conserved_pairs$HOG)), "unique HOGs\n")
cat("    - P-value threshold:", p_threshold, "\n\n")

if (nrow(conserved_pairs) == 0) {
  stop("No conserved gene pairs found with p <", p_threshold)
}

# CREATE HOG BATCHES ===========================================================
cat("Creating HOG batches...\n")

unique_hogs <- sort(unique(conserved_pairs$HOG))
n_hogs <- length(unique_hogs)
n_batches <- ceiling(n_hogs / opt$batch_size)

cat("  Total HOGs:", n_hogs, "\n")
cat("  Batch size:", opt$batch_size, "\n")
cat("  Number of batches:", n_batches, "\n\n")

# Create batch assignments
batch_assignments <- tibble(
  HOG = unique_hogs,
  batch_id = rep(1:n_batches, each = opt$batch_size, length.out = n_hogs)
)

# Save batch info
batch_info <- batch_assignments %>%
  group_by(batch_id) %>%
  summarise(
    n_hogs = n(),
    first_hog = first(HOG),
    last_hog = last(HOG),
    .groups = "drop"
  )

cat("Batch summary:\n")
print(batch_info, n = min(10, nrow(batch_info)))
if (nrow(batch_info) > 10) {
  cat("  ... and", nrow(batch_info) - 10, "more batches\n")
}
cat("\n")

# SAVE INTERMEDIATE DATA =======================================================
cat("Saving intermediate data...\n")

# Save conserved pairs (main data) using qs2 for fast I/O
pairs_file <- file.path(opt$outdir, glue("conserved_pairs_{opt$tissue}.qs2"))
qs_save(conserved_pairs, pairs_file)
cat("  ✓ Conserved pairs:", pairs_file, "\n")
cat("    Size:", round(file.size(pairs_file) / 1024^2, 1), "MB\n")

# Save batch assignments using qs2
batch_file <- file.path(opt$outdir, glue("batch_assignments_{opt$tissue}.qs2"))
qs_save(batch_assignments, batch_file)
cat("  ✓ Batch assignments:", batch_file, "\n")

# Save batch info for Nextflow to read
batch_info_file <- file.path(opt$outdir, glue("batch_info_{opt$tissue}.tsv"))
write_tsv(batch_info, batch_info_file)
cat("  ✓ Batch info:", batch_info_file, "\n")

# Save list of batch IDs (one per line for Nextflow)
batch_ids_file <- file.path(opt$outdir, glue("batch_ids_{opt$tissue}.txt"))
writeLines(as.character(1:n_batches), batch_ids_file)
cat("  ✓ Batch IDs:", batch_ids_file, "\n")

# SUMMARY ======================================================================
cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("PREPARATION COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Total conserved pairs:", nrow(conserved_pairs), "\n")
cat("Total HOGs:", n_hogs, "\n")
cat("Number of batches:", n_batches, "\n")
cat("Ready for parallel batch processing\n")
cat(rep("=", 80), "\n", sep = "")

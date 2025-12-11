#!/usr/bin/env Rscript
# ==============================================================================
# RComPlEx Step 1: Load and Filter Data
# ==============================================================================
# Loads ortholog groups and expression data, filters orthologs to those
# present in expression data for both species
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(optparse)
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
  make_option(c("-o", "--outdir"), type = "character", default = NULL,
              help = "Output directory for results", metavar = "character")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Resolve Orion HPC paths
opt$config <- resolve_orion_path(opt$config)
opt$workdir <- resolve_orion_path(opt$workdir)
opt$outdir <- resolve_orion_path(opt$outdir)

# Validate required arguments
if (is.null(opt$tissue)) {
  print_help(opt_parser)
  stop("--tissue argument is required", call. = FALSE)
}

if (is.null(opt$pair_id)) {
  print_help(opt_parser)
  stop("--pair_id argument is required", call. = FALSE)
}

if (is.null(opt$outdir)) {
  print_help(opt_parser)
  stop("--outdir argument is required", call. = FALSE)
}

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

# Extract species names from pair_id using config species list (handles underscores in names)
all_species <- c(config$species$annual, config$species$perennial) %>%
  str_replace_all(" ", "_")

pair_combos <- combn(all_species, 2, simplify = FALSE)
match_idx <- which(vapply(pair_combos, function(p) paste(p, collapse = "_") == opt$pair_id,
                          logical(1)))

if (length(match_idx) != 1) {
  stop("Invalid pair_id format or species not in config: ", opt$pair_id)
}

species1_name <- pair_combos[[match_idx]][1]
species2_name <- pair_combos[[match_idx]][2]

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("RComPlEx Step 1: Load and Filter Data\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Pair ID:", opt$pair_id, "\n")
cat("Species 1:", species1_name, "\n")
cat("Species 2:", species2_name, "\n")
cat("Output directory:", opt$outdir, "\n")
cat(rep("=", 80), "\n\n")

# Load pair configuration (config$data$output_dir is already absolute)
pair_dir <- file.path(config$data$output_dir, opt$tissue, "pairs", opt$pair_id)
config_file <- file.path(pair_dir, "config.R")

if (!file.exists(config_file)) {
  stop("Pair configuration not found: ", config_file)
}

source(config_file)

# Create output directory
dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# LOAD DATA
# ==============================================================================

cat("Loading expression data and orthologs...\n\n")

# Load ortholog groups
cat("Loading ortholog groups from:", ortholog_group_file, "\n")
load(file = ortholog_group_file)

# Load expression data
cat("Loading expression data for", species1_name, "from:", basename(species1_expr_file), "\n")
species1_expr <- read.delim(species1_expr_file, sep = "\t", header = TRUE, stringsAsFactors = FALSE)

cat("Loading expression data for", species2_name, "from:", basename(species2_expr_file), "\n")
species2_expr <- read.delim(species2_expr_file, sep = "\t", header = TRUE, stringsAsFactors = FALSE)

# ==============================================================================
# SUMMARIZE BEFORE FILTERING
# ==============================================================================

cat("\n")
cat("Before filtering:\n")
cat("  Ortholog groups:", length(unique(ortho$OrthoGroup)), "\n")
cat("    -", species1_name, "genes:", length(unique(ortho$Species1)), "\n")
cat("    -", species2_name, "genes:", length(unique(ortho$Species2)), "\n")
cat("  Expressed genes:\n")
cat("    -", species1_name, ":", nrow(species1_expr), "\n")
cat("    -", species2_name, ":", nrow(species2_expr), "\n\n")

# ==============================================================================
# FILTER ORTHOLOGS
# ==============================================================================

cat("Filtering orthologs to those present in expression data...\n")

# Keep only orthologs where BOTH species genes are in expression data
ortho_before_filter <- nrow(ortho)
ortho <- ortho %>%
  filter(Species1 %in% species1_expr$Genes & Species2 %in% species2_expr$Genes)

# Filter expression data to match orthologs
species1_expr <- species1_expr[species1_expr$Genes %in% ortho$Species1, ]
species2_expr <- species2_expr[species2_expr$Genes %in% ortho$Species2, ]

filtered_count <- ortho_before_filter - nrow(ortho)

cat("\nAfter filtering:\n")
cat("  Ortholog groups:", length(unique(ortho$OrthoGroup)), "\n")
cat("    -", species1_name, "genes:", length(unique(ortho$Species1)), "\n")
cat("    -", species2_name, "genes:", length(unique(ortho$Species2)), "\n")
cat("  Expression data retained:\n")
cat("    -", species1_name, ":", nrow(species1_expr), "genes\n")
cat("    -", species2_name, ":", nrow(species2_expr), "genes\n")
cat("  Removed:", filtered_count, "orthologs with missing genes\n\n")

# ==============================================================================
# SAVE INTERMEDIATE DATA
# ==============================================================================

output_file <- file.path(opt$outdir, "01_filtered_data.RData")
cat("Saving filtered data to:", output_file, "\n")
save(ortho, species1_expr, species2_expr,
     species1_name, species2_name,
     file = output_file)

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Step 1 COMPLETE\n")
cat(rep("=", 80), "\n")

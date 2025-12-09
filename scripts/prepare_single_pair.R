#!/usr/bin/env Rscript
# ==============================================================================
# Prepare Single Species Pair for RComPlEx Analysis
# ==============================================================================
# Processes ONE tissue/species1/species2 combination
# Outputs expression files, ortholog data, and config for RComPlEx
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(optparse)
})

# Parse command-line arguments (before sourcing utility)
option_list <- list(
  make_option(c("-t", "--tissue"), type = "character", default = NULL,
              help = "Tissue to analyze", metavar = "character"),
  make_option(c("-s", "--sp1"), type = "character", default = NULL,
              help = "First species name", metavar = "character"),
  make_option(c("-p", "--sp2"), type = "character", default = NULL,
              help = "Second species name", metavar = "character"),
  make_option(c("-c", "--config"), type = "character", default = "config/pipeline_config.yaml",
              help = "Path to configuration file [default= %default]", metavar = "character"),
  make_option(c("-w", "--workdir"), type = "character", default = ".",
              help = "Working directory [default= %default]", metavar = "character")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

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

# Validate required arguments
required_args <- c("tissue", "sp1", "sp2")
missing_args <- required_args[sapply(required_args, function(x) is.null(opt[[x]]))]
if (length(missing_args) > 0) {
  print_help(opt_parser)
  stop("Missing required arguments: ", paste(missing_args, collapse = ", "), call. = FALSE)
}

# Store working directory for absolute paths, but DON'T change directory
# Nextflow expects outputs in the current work directory, not workdir
workdir <- opt$workdir

# Source config parser using absolute path
source(file.path(workdir, "R/config_parser.R"))

# Load configuration with workdir for path resolution
config <- load_config(opt$config, workdir = workdir)

# Validate tissue
if (!is_valid_tissue(config, opt$tissue)) {
  stop("Invalid tissue: ", opt$tissue, ". Valid tissues: ",
       paste(config$tissues, collapse = ", "))
}

sp1 <- opt$sp1
sp2 <- opt$sp2
tissue <- opt$tissue
pair_id <- paste0(sp1, "_", sp2)

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("RComPlEx Single Pair Preparation\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", tissue, "\n")
cat("Species 1:", sp1, "\n")
cat("Species 2:", sp2, "\n")
cat("Pair ID:", pair_id, "\n")
cat("Working directory:", getwd(), "\n")
cat(rep("=", 80), "\n\n", sep = "")

# LOAD DATA ====================================================================
cat("Loading data...\n")

# Load N1 clean
n1 <- readRDS(config$data$n1_file)

# Load VST expression data
vst.hog <- readRDS(config$data$vst_file)
cat("  ✓ Loaded expression data\n")

# Filter by tissue
vst.hog <- vst.hog %>% filter(tissue == tissue)

# Replace spaces in species names
vst.hog <- vst.hog %>% mutate(species = str_replace(species, " ", "_"))
n1 <- n1 %>% mutate(species = str_replace(species, " ", "_"))

# CREATE OUTPUT DIRECTORIES ====================================================
cat("Creating output directories...\n")
# Write outputs directly to current directory (Nextflow work dir)
# Nextflow publishDir will handle organizing into proper directory structure
pair_dir <- "."
cat("  ✓ Output directory:", getwd(), "\n")

# PROCESS PAIR =================================================================
cat("\nProcessing pair...\n")

# 1. Create ortholog pairs from N1 HOGs
# ======================================
cat("  - Extracting ortholog pairs...\n")

ortho <- n1 %>%
  filter(species %in% c(sp1, sp2)) %>%
  select(HOG, species, GeneID) %>%
  pivot_wider(names_from = species, values_from = GeneID, values_fn = list) %>%
  filter(!is.na(.data[[sp1]]) & !is.na(.data[[sp2]])) %>%
  # Use crossing to create all pairwise combinations (cartesian product)
  mutate(
    pairs = map2(.data[[sp1]], .data[[sp2]], ~crossing(Species1 = .x, Species2 = .y))
  ) %>%
  select(HOG, pairs) %>%
  unnest(pairs) %>%
  transmute(
    Species1 = Species1,
    Species2 = Species2,
    OrthoGroup = paste0("HOG_", HOG)
  )

# Apply gene count filters if specified
if (config$rcomplex$min_genes > 1 || is.finite(config$rcomplex$max_genes)) {
  hog_counts <- ortho %>%
    group_by(OrthoGroup) %>%
    summarise(
      n_sp1 = n_distinct(Species1),
      n_sp2 = n_distinct(Species2),
      .groups = "drop"
    ) %>%
    filter(
      n_sp1 >= config$rcomplex$min_genes & n_sp1 <= config$rcomplex$max_genes,
      n_sp2 >= config$rcomplex$min_genes & n_sp2 <= config$rcomplex$max_genes
    )

  ortho <- ortho %>%
    filter(OrthoGroup %in% hog_counts$OrthoGroup)
}

cat("    - Found", length(unique(ortho$OrthoGroup)), "HOGs\n")
cat("    - Total ortholog pairs:", nrow(ortho), "\n")

# Save ortholog pairs
ortho_file <- file.path(pair_dir, paste0("orthologs-", sp1, "-", sp2, ".RData"))
save(ortho, file = ortho_file)
cat("    - Saved orthologs to:", ortho_file, "\n")

# 2. Convert species 1 expression to wide format
# ==============================================
cat("  - Preparing expression data for", sp1, "...\n")

sp1_expr <- vst.hog %>%
  filter(species == sp1) %>%
  select(GeneID, sample_id, vst.count) %>%
  pivot_wider(names_from = sample_id, values_from = vst.count) %>%
  rename(Genes = GeneID)

# Filter to genes with orthologs
sp1_expr <- sp1_expr %>% filter(Genes %in% ortho$Species1)

write.table(sp1_expr,
            file.path(pair_dir, paste0(sp1, "_expression.txt")),
            sep = "\t", row.names = FALSE, quote = FALSE)

cat("    -", nrow(sp1_expr), "genes saved\n")

# 3. Convert species 2 expression to wide format
# ==============================================
cat("  - Preparing expression data for", sp2, "...\n")

sp2_expr <- vst.hog %>%
  filter(species == sp2) %>%
  select(GeneID, sample_id, vst.count) %>%
  pivot_wider(names_from = sample_id, values_from = vst.count) %>%
  rename(Genes = GeneID)

# Filter to genes with orthologs
sp2_expr <- sp2_expr %>% filter(Genes %in% ortho$Species2)

write.table(sp2_expr,
            file.path(pair_dir, paste0(sp2, "_expression.txt")),
            sep = "\t", row.names = FALSE, quote = FALSE)

cat("    -", nrow(sp2_expr), "genes saved\n")

# 4. Create RComPlEx config
# =========================
cat("  - Creating config file...\n")

# Build absolute paths for config.R (config$data$output_dir is already absolute)
# Files will be published to output_dir/tissue/pairs/pair_id/
published_pair_dir <- resolve_orion_path(
  file.path(config$data$output_dir, tissue, "pairs", pair_id)
)

config_content <- sprintf('species1_name <- "%s"
species2_name <- "%s"
species1_expr_file <- "%s"
species2_expr_file <- "%s"
ortholog_group_file <- "%s"
',
                          sp1, sp2,
                          file.path(published_pair_dir, paste0(sp1, "_expression.txt")),
                          file.path(published_pair_dir, paste0(sp2, "_expression.txt")),
                          file.path(published_pair_dir, paste0("orthologs-", sp1, "-", sp2, ".RData"))
)

writeLines(config_content, file.path(pair_dir, "config.R"))
cat("    - Config saved\n")

# SAVE PAIR STATISTICS =========================================================
cat("\n")
pair_stats <- tibble(
  pair_id = pair_id,
  species1 = sp1,
  species2 = sp2,
  tissue = tissue,
  n_hogs = length(unique(ortho$OrthoGroup)),
  n_ortho_pairs = nrow(ortho),
  n_genes_sp1 = nrow(sp1_expr),
  n_genes_sp2 = nrow(sp2_expr)
)

stats_file <- file.path(pair_dir, "pair_stats.tsv")
write_tsv(pair_stats, stats_file)

# SUMMARY ======================================================================
cat(rep("=", 80), "\n", sep = "")
cat("PAIR PREPARATION COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", tissue, "\n")
cat("Pair:", pair_id, "\n")
cat("HOGs:", pair_stats$n_hogs, "\n")
cat("Ortholog pairs:", pair_stats$n_ortho_pairs, "\n")
cat("Output directory:", pair_dir, "\n")
cat(rep("=", 80), "\n")

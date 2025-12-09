#!/usr/bin/env Rscript
# ==============================================================================
# Tissue-Specific RComPlEx Data Preparation
# ==============================================================================
# Prepares pairwise species comparisons for a specific tissue
# Filters expression data by tissue before creating comparison matrices
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(optparse)
})

# Parse command-line arguments
option_list <- list(
  make_option(c("-t", "--tissue"), type = "character", default = NULL,
              help = "Tissue to analyze (e.g., 'root' or 'leaf')", metavar = "character"),
  make_option(c("-c", "--config"), type = "character", default = "config/pipeline_config.yaml",
              help = "Path to configuration file [default= %default]", metavar = "character"),
  make_option(c("-w", "--workdir"), type = "character", default = ".",
              help = "Working directory [default= %default]", metavar = "character")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Validate required arguments
if (is.null(opt$tissue)) {
  print_help(opt_parser)
  stop("--tissue argument is required", call. = FALSE)
}

# Store working directory for path resolution
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

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("RComPlEx Data Preparation\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Working directory:", getwd(), "\n")
cat("Configuration:", opt$config, "\n")
cat(rep("=", 80), "\n\n", sep = "")

# LOAD DATA ====================================================================
cat("Loading data...\n")

# Load N1 clean (already in long format with life_cycle column)
n1 <- readRDS(config$data$n1_file)
cat("  ✓ Loaded N1 orthogroups:", nrow(n1), "gene-HOG pairs\n")
cat("    -", length(unique(n1$HOG)), "unique HOGs\n")
cat("    -", length(unique(n1$GeneID)), "unique genes\n")
cat("    -", length(unique(n1$species)), "species\n")

# Load VST expression data
vst.hog <- readRDS(config$data$vst_file)
cat("  ✓ Loaded expression data:", nrow(vst.hog), "observations\n")
cat("    - Tissues:", paste(unique(vst.hog$tissue), collapse = ", "), "\n")

# Filter by tissue FIRST
cat("\n")
cat("Filtering expression data for tissue:", opt$tissue, "\n")
vst.hog <- vst.hog %>% filter(tissue == opt$tissue)
cat("  ✓ Retained", nrow(vst.hog), "observations for", opt$tissue, "\n")

# Replace spaces in species names for compatibility
vst.hog <- vst.hog %>% mutate(species = str_replace(species, " ", "_"))
n1 <- n1 %>% mutate(species = str_replace(species, " ", "_"))

# Get species list from filtered data
species_list <- vst.hog %>% distinct(species) %>% pull()
cat("  ✓ Found", length(species_list), "species in", opt$tissue, "tissue:\n")
for (sp in sort(species_list)) {
  cat("    -", sp, "\n")
}

# CREATE OUTPUT DIRECTORIES ====================================================
cat("\n")
output_dirs <- create_output_dirs(config, opt$tissue)

# GENERATE PAIRWISE COMBINATIONS ===============================================
cat("\n")
pairs <- combn(species_list, 2, simplify = FALSE)
cat("Creating", length(pairs), "unique pairwise combinations\n")
cat("(", length(species_list), "species →", length(pairs), "pairs )\n\n")

job_list <- c()
pair_stats <- tibble(
  pair_id = character(),
  species1 = character(),
  species2 = character(),
  n_hogs = integer(),
  n_ortho_pairs = integer(),
  n_genes_sp1 = integer(),
  n_genes_sp2 = integer()
)

# PROCESS EACH PAIR ============================================================
cat("Processing species pairs...\n")
pb <- txtProgressBar(min = 0, max = length(pairs), style = 3)

for (i in seq_along(pairs)) {

  sp1 <- pairs[[i]][1]
  sp2 <- pairs[[i]][2]
  pair_id <- paste0(sp1, "_", sp2)

  setTxtProgressBar(pb, i)

  pair_dir <- file.path(output_dirs$pairs, pair_id)
  dir.create(pair_dir, showWarnings = FALSE, recursive = TRUE)

  # 1. Create ortholog pairs from N1 HOGs
  # ======================================

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

  # Save ortholog pairs
  ortho_file <- file.path(pair_dir, paste0("orthologs-", sp1, "-", sp2, ".RData"))
  save(ortho, file = ortho_file)

  # 2. Convert species 1 expression to wide format
  # ==============================================

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

  # 3. Convert species 2 expression to wide format
  # ==============================================

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

  # 4. Create RComPlEx config
  # =========================

  config_content <- sprintf('species1_name <- "%s"
species2_name <- "%s"
species1_expr_file <- "%s"
species2_expr_file <- "%s"
ortholog_group_file <- "%s"
',
                            sp1, sp2,
                            file.path(pair_dir, paste0(sp1, "_expression.txt")),
                            file.path(pair_dir, paste0(sp2, "_expression.txt")),
                            ortho_file
  )

  writeLines(config_content, file.path(pair_dir, "config.R"))

  # Track statistics
  job_list <- c(job_list, pair_id)

  pair_stats <- pair_stats %>%
    add_row(
      pair_id = pair_id,
      species1 = sp1,
      species2 = sp2,
      n_hogs = length(unique(ortho$OrthoGroup)),
      n_ortho_pairs = nrow(ortho),
      n_genes_sp1 = nrow(sp1_expr),
      n_genes_sp2 = nrow(sp2_expr)
    )
}

close(pb)
cat("\n\n")

# SAVE JOB LIST ================================================================
job_list_file <- file.path(output_dirs$base, "job_list.txt")
writeLines(job_list, job_list_file)

# SAVE STATISTICS ==============================================================
stats_file <- file.path(output_dirs$base, "preparation_stats.tsv")
write_tsv(pair_stats, stats_file)

# SUMMARY ======================================================================
cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("PREPARATION COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Species pairs created:", length(job_list), "\n")
cat("\n")
cat("Statistics:\n")
cat("  - Total HOGs across all pairs:", sum(pair_stats$n_hogs), "\n")
cat("  - Total ortholog pairs:", sum(pair_stats$n_ortho_pairs), "\n")
cat("  - Average HOGs per pair:", round(mean(pair_stats$n_hogs), 1), "\n")
cat("  - Average ortholog pairs per comparison:", round(mean(pair_stats$n_ortho_pairs), 1), "\n")
cat("\n")
cat("Output files:\n")
cat("  - Job list:", job_list_file, "\n")
cat("  - Statistics:", stats_file, "\n")
cat("  - Pair data:", output_dirs$pairs, "\n")
cat("\n")
cat("Next step:\n")
cat("  sbatch --array=1-", length(job_list), " slurm/run_rcomplex.sh ", opt$tissue, "\n", sep = "")
cat(rep("=", 80), "\n", sep = "")

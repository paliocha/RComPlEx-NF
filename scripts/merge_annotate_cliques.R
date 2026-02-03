#!/usr/bin/env Rscript
# ==============================================================================
# Merge and Annotate Cliques - Step 3 of Batched Clique Detection
# ==============================================================================
# Merges clique results from all batches, annotates with species/lifecycle info,
# and produces final output files.
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
  make_option(c("-i", "--input_dir"), type = "character", default = NULL,
              help = "Directory containing batch clique RDS files", metavar = "character"),
  make_option(c("-o", "--outdir"), type = "character", default = ".",
              help = "Output directory for final results", metavar = "character"),
  make_option(c("-s", "--signed"), type = "logical", default = TRUE,
              help = "Processing signed (TRUE) or unsigned (FALSE) results [default= %default]",
              metavar = "logical"),
  make_option(c("-n", "--n1_file"), type = "character", default = NULL,
              help = "Path to N1 annotation file (RDS or RData)", metavar = "character")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Resolve paths
opt$config <- resolve_orion_path(opt$config)
opt$workdir <- resolve_orion_path(opt$workdir)
if (!is.null(opt$input_dir)) {
  opt$input_dir <- resolve_orion_path(opt$input_dir)
}
opt$outdir <- resolve_orion_path(opt$outdir)

if (is.null(opt$tissue)) {
  stop("--tissue argument is required", call. = FALSE)
}

if (is.null(opt$input_dir)) {
  stop("--input_dir argument is required", call. = FALSE)
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

mode_suffix <- ifelse(opt$signed, "signed", "unsigned")

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Merge and Annotate Cliques\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Mode:", ifelse(opt$signed, "Signed correlation", "Unsigned (absolute) correlation"), "\n")
cat("Input directory:", opt$input_dir, "\n")
cat("Output directory:", opt$outdir, "\n")
cat(rep("=", 80), "\n\n", sep = "")

# Create output directory
dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# FIND AND LOAD BATCH FILES ====================================================
cat("Finding batch files...\n")

pattern <- glue("cliques_{opt$tissue}_{mode_suffix}_batch.*\\.qs2$")
batch_files <- list.files(opt$input_dir, pattern = pattern, full.names = TRUE)

if (length(batch_files) == 0) {
  stop("No batch files found matching pattern: ", pattern)
}

cat("  Found", length(batch_files), "batch files\n\n")

cat("Loading and merging batch results...\n")
all_cliques <- map_dfr(batch_files, function(file) {
  cat("  Loading:", basename(file), "\n")
  qs_read(file)
}, .progress = FALSE)

cat("\n  ✓ Merged", nrow(all_cliques), "cliques from", length(batch_files), "batches\n")

if (nrow(all_cliques) == 0) {
  cat("\nWarning: No cliques found. Creating empty output files.\n")
  
  # Save empty results
  output_prefix <- ifelse(opt$signed, "cliques", "cliques_unsigned")
  qs_save(tibble(), file.path(opt$outdir, glue("{output_prefix}.qs2")))
  write_csv(tibble(), file.path(opt$outdir, glue("{output_prefix}.csv")))
  
  cat("Created empty output files.\n")
  quit(save = "no", status = 0)
}

cat("\nClique statistics:\n")
cat("  Total cliques:", nrow(all_cliques), "\n")
cat("  Unique HOGs:", n_distinct(all_cliques$HOG), "\n")
cat("  Min clique size:", min(all_cliques$clique_size), "\n")
cat("  Max clique size:", max(all_cliques$clique_size), "\n")
cat("  Mean clique size:", round(mean(all_cliques$clique_size), 2), "\n")

# LOAD ANNOTATIONS =============================================================
cat("\nLoading species annotations...\n")

# Try to find N1 file
n1_file <- opt$n1_file
if (is.null(n1_file)) {
  n1_candidates <- c(
    config$data$n1_clean,
    file.path(workdir, "N1_clean.RDS"),
    file.path(workdir, "rcomplex-main/RData/N1_clean.RDS"),
    "/opt/rcomplex/data/N1_clean.RDS"
  )
  n1_file <- n1_candidates[file.exists(n1_candidates)][1]
}

if (is.na(n1_file) || !file.exists(n1_file)) {
  warning("N1 annotation file not found. Skipping species annotation.")
  N1 <- NULL
} else {
  cat("  Loading from:", n1_file, "\n")
  if (grepl("\\.rds$", n1_file, ignore.case = TRUE)) {
    N1 <- readRDS(n1_file)
  } else {
    load(n1_file, envir = tmp_env <- new.env())
    N1 <- tmp_env$N1 %||% tmp_env$N1_clean
  }
  cat("  ✓ Loaded annotations for", nrow(N1), "genes\n")
}

# ANNOTATE CLIQUES =============================================================
cat("\nAnnotating cliques with species information...\n")

if (!is.null(N1)) {
  # Create gene annotation lookup
  gene_info <- N1 %>%
    select(GeneID = Gene_ID, Species, Life_habit) %>%
    distinct()
  
  # Extract species info for each clique
  all_cliques_annotated <- all_cliques %>%
    rowwise() %>%
    mutate(
      # Get species for each gene in clique
      species_list = list({
        gene_info %>%
          filter(GeneID %in% genes) %>%
          pull(Species) %>%
          unique() %>%
          sort()
      }),
      n_species = length(species_list),
      
      # Get life habits
      life_habits = list({
        gene_info %>%
          filter(GeneID %in% genes) %>%
          pull(Life_habit) %>%
          unique() %>%
          sort()
      }),
      
      # Classify clique by life habit composition
      life_habit_class = {
        habits <- unlist(life_habits)
        if (all(habits == "Annual")) {
          "Annual"
        } else if (all(habits == "Perennial")) {
          "Perennial"
        } else {
          "Mixed"
        }
      }
    ) %>%
    ungroup()
} else {
  # Without annotations, just pass through
  all_cliques_annotated <- all_cliques %>%
    mutate(
      species_list = list(character()),
      n_species = NA_integer_,
      life_habits = list(character()),
      life_habit_class = "Unknown"
    )
}

# SAVE RESULTS =================================================================
cat("\nSaving results...\n")

output_prefix <- ifelse(opt$signed, "cliques", "cliques_unsigned")

# Save full data with qs2 for fast I/O
full_qs2 <- file.path(opt$outdir, glue("{output_prefix}.qs2"))
qs_save(all_cliques_annotated, full_qs2)
cat("  ✓ Full data (qs2):", full_qs2, "\n")
cat("    Size:", round(file.size(full_qs2) / 1024^2, 1), "MB\n")

# Create flat CSV for easier viewing
all_cliques_flat <- all_cliques_annotated %>%
  mutate(
    genes_str = map_chr(genes, ~ paste(., collapse = ";")),
    species_str = map_chr(species_list, ~ paste(., collapse = ";")),
    life_habits_str = map_chr(life_habits, ~ paste(., collapse = ";"))
  ) %>%
  select(HOG, OrthoGroup, clique_id, clique_size, n_species, 
         life_habit_class, genes = genes_str, species = species_str, 
         life_habits = life_habits_str)

flat_csv <- file.path(opt$outdir, glue("{output_prefix}.csv"))
write_csv(all_cliques_flat, flat_csv)
cat("  ✓ Flat format (CSV):", flat_csv, "\n")

# Save by life habit class
if (!is.null(N1)) {
  for (lh_class in unique(all_cliques_annotated$life_habit_class)) {
    class_data <- all_cliques_flat %>%
      filter(all_cliques_annotated$life_habit_class == lh_class)
    
    class_file <- file.path(opt$outdir, glue("{output_prefix}_{tolower(lh_class)}.csv"))
    write_csv(class_data, class_file)
    cat("  ✓", lh_class, "cliques:", class_file, "(", nrow(class_data), "cliques)\n")
  }
}

# SUMMARY ======================================================================
cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("MERGE COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Mode:", ifelse(opt$signed, "Signed", "Unsigned"), "\n")
cat("Total cliques:", nrow(all_cliques_annotated), "\n")
cat("Unique HOGs:", n_distinct(all_cliques_annotated$HOG), "\n")
if (!is.null(N1)) {
  cat("\nCliques by life habit:\n")
  print(table(all_cliques_annotated$life_habit_class))
}
cat(rep("=", 80), "\n", sep = "")

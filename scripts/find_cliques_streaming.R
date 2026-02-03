#!/usr/bin/env Rscript
# ==============================================================================
# Find Cliques - Two-Pass Streaming Approach
# ==============================================================================
# Replaces the 3-step batched clique detection with a simpler two-pass approach:
#   Pass 1: Index - scan files to build HOG -> files mapping (lightweight)
#   Pass 2: Process - for each HOG, load only relevant data and find cliques
#
# Memory efficient: only one HOG's data in memory at a time.
# Works for both signed and unsigned modes via --mode flag.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(igraph)
  library(optparse)
  library(glue)
  library(qs2)
})

# Configure qs2 to use available threads (SLURM or detected cores)
qs2_threads <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", parallel::detectCores(logical = FALSE)))
if (is.na(qs2_threads) || qs2_threads < 1L) qs2_threads <- 1L
qopt("nthreads", qs2_threads)
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
  make_option(c("-m", "--mode"), type = "character", default = "signed",
              help = "Mode: 'signed' or 'unsigned' [default= %default]", metavar = "character"),
  make_option(c("-c", "--config"), type = "character", default = "config/pipeline_config.yaml",
              help = "Path to configuration file", metavar = "character"),
  make_option(c("-w", "--workdir"), type = "character", default = ".",
              help = "Working directory", metavar = "character"),
  make_option(c("-r", "--results_dir"), type = "character", default = NULL,
              help = "Path to results directory with comparison RData files", metavar = "character"),
  make_option(c("-n", "--n1_file"), type = "character", default = NULL,
              help = "Path to N1 annotation file (RDS)", metavar = "character"),
  make_option(c("-o", "--outdir"), type = "character", default = ".",
              help = "Output directory", metavar = "character"),
  make_option(c("-p", "--p_threshold"), type = "double", default = NULL,
              help = "P-value threshold (overrides config)", metavar = "double")
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
if (!is.null(opt$n1_file)) {
  opt$n1_file <- resolve_orion_path(opt$n1_file)
}

# Validate arguments
if (is.null(opt$tissue)) {
  stop("--tissue argument is required", call. = FALSE)
}

if (!opt$mode %in% c("signed", "unsigned")) {
  stop("--mode must be 'signed' or 'unsigned'", call. = FALSE)
}

signed_mode <- opt$mode == "signed"
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

# P-value threshold
p_threshold <- opt$p_threshold %||% config$rcomplex$p_threshold

# Print memory usage helper
print_memory <- function(prefix = "") {
  mem_mb <- as.numeric(system("ps -o rss= -p $$", intern = TRUE)) / 1024
  cat(sprintf("%s[Memory: %.1f GB]\n", prefix, mem_mb / 1024))
}

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Find Cliques - Two-Pass Streaming Approach\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Mode:", opt$mode, "\n")
cat("P-value threshold:", p_threshold, "\n")
cat("Output directory:", opt$outdir, "\n")
cat(rep("=", 80), "\n\n", sep = "")

print_memory("Initial ")

# Create output directory
dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# FIND COMPARISON FILES
# ==============================================================================

if (!is.null(opt$results_dir)) {
  results_dir <- opt$results_dir
} else {
  results_dir <- file.path(config$data$output_dir, opt$tissue, "results")
}

if (!dir.exists(results_dir)) {
  stop("Results directory not found: ", results_dir)
}

# Pattern depends on mode
if (signed_mode) {
  comparison_files <- list.files(results_dir,
                                 pattern = "03_comparison\\.RData$",
                                 recursive = TRUE,
                                 full.names = TRUE)
} else {
  comparison_files <- list.files(results_dir,
                                 pattern = "03_comparison_unsigned\\.RData$",
                                 recursive = TRUE,
                                 full.names = TRUE)
}

if (length(comparison_files) == 0) {
  stop("No comparison files found in: ", results_dir, 
       "\nPattern: ", ifelse(signed_mode, "03_comparison.RData", "03_comparison_unsigned.RData"))
}

cat("Found", length(comparison_files), "comparison files\n\n")

# ==============================================================================
# LOAD N1 ANNOTATIONS (once at start - small enough to keep in memory)
# ==============================================================================

cat("Loading species annotations...\n")

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
  gene_info <- NULL
} else {
  cat("  Loading from:", n1_file, "\n")
  if (grepl("\\.rds$", n1_file, ignore.case = TRUE)) {
    N1 <- readRDS(n1_file)
  } else {
    load(n1_file, envir = tmp_env <- new.env())
    N1 <- tmp_env$N1 %||% tmp_env$N1_clean
  }
  
  # Create compact gene info lookup
  gene_info <- N1 %>%
    select(GeneID = Gene_ID, Species, Life_habit) %>%
    distinct()
  
  cat("  ✓ Loaded annotations for", nrow(gene_info), "genes\n")
  rm(N1)
  gc(verbose = FALSE)
}

print_memory("After loading annotations ")

# ==============================================================================
# CLIQUE FINDING FUNCTION
# ==============================================================================

find_cliques_for_hog <- function(hog_pairs, signed = TRUE, max_edges = 10000) {
  if (nrow(hog_pairs) < 3) {
    return(tibble())
  }
  
  # Apply sign filter for signed mode
  if (signed) {
    hog_pairs <- hog_pairs %>%
      filter(sign(Species1.effect.size) == sign(Species2.effect.size))
  }
  
  if (nrow(hog_pairs) < 3) {
    return(tibble())
  }
  
  # Build edge list
  edges <- hog_pairs %>%
    mutate(
      gene1 = pmin(Species1, Species2),
      gene2 = pmax(Species1, Species2)
    ) %>%
    distinct(gene1, gene2) %>%
    filter(gene1 != gene2)
  
  if (nrow(edges) < 3) {
    return(tibble())
  }
  
  # Protect against exponential blowup on dense HOGs
  if (nrow(edges) > max_edges) {
    warning(sprintf("HOG %s has %d edges (> %d), skipping to avoid exponential runtime",
                    unique(hog_pairs$HOG), nrow(edges), max_edges))
    return(tibble())
  }
  
  # Create igraph object
  g <- graph_from_data_frame(edges, directed = FALSE)
  
  # Find all maximal cliques (minimum size 3)
  cliques <- tryCatch({
    max_cliques(g, min = 3)
  }, error = function(e) {
    warning(sprintf("Error finding cliques for HOG %s: %s", 
                    unique(hog_pairs$HOG), conditionMessage(e)))
    list()
  })
  
  if (length(cliques) == 0) {
    return(tibble())
  }
  
  # Convert to tibble
  map_dfr(seq_along(cliques), function(i) {
    genes <- names(cliques[[i]])
    tibble(
      HOG = unique(hog_pairs$HOG),
      OrthoGroup = unique(hog_pairs$OrthoGroup),
      clique_id = i,
      clique_size = length(genes),
      genes = list(sort(genes))
    )
  })
}

# ==============================================================================
# ANNOTATE CLIQUES FUNCTION
# ==============================================================================

annotate_clique <- function(clique_row, gene_info) {
  if (is.null(gene_info)) {
    return(clique_row %>%
             mutate(
               species_list = list(character()),
               n_species = NA_integer_,
               life_habits = list(character()),
               life_habit_class = "Unknown"
             ))
  }
  
  genes <- unlist(clique_row$genes)
  
  clique_gene_info <- gene_info %>%
    filter(GeneID %in% genes)
  
  species_list <- sort(unique(clique_gene_info$Species))
  life_habits <- sort(unique(clique_gene_info$Life_habit))
  
  life_habit_class <- if (all(life_habits == "Annual")) {
    "Annual"
  } else if (all(life_habits == "Perennial")) {
    "Perennial"
  } else {
    "Mixed"
  }
  
  clique_row %>%
    mutate(
      species_list = list(species_list),
      n_species = length(species_list),
      life_habits = list(life_habits),
      life_habit_class = life_habit_class
    )
}

# ==============================================================================
# PASS 1: BUILD HOG -> FILES INDEX
# ==============================================================================

cat("=" , rep("=", 59), "\n", sep = "")
cat("PASS 1: Building HOG -> files index\n")
cat(rep("=", 60), "\n\n", sep = "")

start_pass1 <- Sys.time()

# HOG -> list of files containing that HOG
hog_file_index <- list()

# Also track HOG -> OrthoGroup mapping
hog_orthogroup <- list()

for (i in seq_along(comparison_files)) {
  file <- comparison_files[i]
  
  if (i %% 10 == 0 || i == length(comparison_files)) {
    cat(sprintf("  Scanning file %d/%d: %s\n", i, length(comparison_files), basename(dirname(file))))
  }
  
  # Load comparison data
  load(file, envir = tmp_env <- new.env())
  comp <- tmp_env$comparison
  rm(tmp_env)
  
  # Filter to conserved pairs and get unique HOGs
  conserved <- comp %>%
    rowwise() %>%
    mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
    ungroup() %>%
    filter(Max.p.val < p_threshold)
  
  if (nrow(conserved) == 0) {
    next
  }
  
  # Index HOGs to files
  hog_data <- conserved %>%
    mutate(HOG = str_remove(OrthoGroup, "^HOG_")) %>%
    select(HOG, OrthoGroup) %>%
    distinct()
  
  for (j in seq_len(nrow(hog_data))) {
    hog <- hog_data$HOG[j]
    og <- hog_data$OrthoGroup[j]
    
    hog_file_index[[hog]] <- c(hog_file_index[[hog]], file)
    hog_orthogroup[[hog]] <- og
  }
  
  rm(comp, conserved, hog_data)
}

gc(verbose = FALSE)

n_hogs <- length(hog_file_index)
elapsed_pass1 <- as.numeric(difftime(Sys.time(), start_pass1, units = "secs"))

cat("\n✓ Pass 1 complete in", round(elapsed_pass1, 1), "seconds\n")
cat("  Indexed", n_hogs, "unique HOGs\n")
cat("  Average files per HOG:", round(mean(sapply(hog_file_index, length)), 1), "\n")
print_memory("  ")

if (n_hogs == 0) {
  cat("\nNo conserved HOGs found. Creating empty output files.\n")
  
  output_prefix <- ifelse(signed_mode, "cliques", "cliques_unsigned")
  qs_save(tibble(), file.path(opt$outdir, glue("{output_prefix}.qs2")))
  write_csv(tibble(), file.path(opt$outdir, glue("{output_prefix}.csv")))
  
  cat("Created empty output files.\n")
  quit(save = "no", status = 0)
}

# ==============================================================================
# PASS 2: PROCESS EACH HOG
# ==============================================================================

cat("\n")
cat(rep("=", 60), "\n", sep = "")
cat("PASS 2: Processing", n_hogs, "HOGs\n")
cat(rep("=", 60), "\n\n", sep = "")

start_pass2 <- Sys.time()

# Initialize output file
output_prefix <- ifelse(signed_mode, "cliques", "cliques_unsigned")
output_qs2 <- file.path(opt$outdir, glue("{output_prefix}.qs2"))
output_csv <- file.path(opt$outdir, glue("{output_prefix}.csv"))

# Collect all cliques (we'll annotate and save at end - memory efficient enough for cliques)
all_cliques <- tibble()

hog_names <- names(hog_file_index)
processed <- 0
cliques_found <- 0

for (hog in hog_names) {
  processed <- processed + 1
  
  # Progress every 500 HOGs
  if (processed %% 500 == 0 || processed == n_hogs) {
    elapsed <- as.numeric(difftime(Sys.time(), start_pass2, units = "secs"))
    rate <- processed / elapsed
    remaining <- (n_hogs - processed) / rate
    
    cat(sprintf("  [%d/%d] %.1f HOGs/sec | %d cliques | ETA: %.0fs\n",
                processed, n_hogs, rate, cliques_found, remaining))
  }
  
  # Get files for this HOG
  files_for_hog <- hog_file_index[[hog]]
  orthogroup <- hog_orthogroup[[hog]]
  
  # Load and combine conserved pairs for this HOG from all relevant files
  hog_pairs <- map_dfr(files_for_hog, function(file) {
    load(file, envir = tmp_env <- new.env())
    comp <- tmp_env$comparison
    rm(tmp_env)
    
    pair_id <- basename(dirname(file))
    
    comp %>%
      rowwise() %>%
      mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
      ungroup() %>%
      filter(Max.p.val < p_threshold) %>%
      mutate(HOG = str_remove(OrthoGroup, "^HOG_")) %>%
      filter(HOG == hog) %>%
      select(Species1, Species2, HOG, OrthoGroup, Max.p.val,
             Species1.effect.size, Species2.effect.size) %>%
      mutate(PairID = pair_id)
  })
  
  if (nrow(hog_pairs) < 3) {
    next
  }
  
  # Find cliques for this HOG
  hog_cliques <- find_cliques_for_hog(hog_pairs, signed = signed_mode)
  
  if (nrow(hog_cliques) > 0) {
    all_cliques <- bind_rows(all_cliques, hog_cliques)
    cliques_found <- cliques_found + nrow(hog_cliques)
  }
  
  rm(hog_pairs, hog_cliques)
  
  # Periodic garbage collection
  if (processed %% 1000 == 0) {
    gc(verbose = FALSE)
  }
}

elapsed_pass2 <- as.numeric(difftime(Sys.time(), start_pass2, units = "secs"))

cat("\n✓ Pass 2 complete in", round(elapsed_pass2 / 60, 1), "minutes\n")
cat("  Processed", n_hogs, "HOGs\n")
cat("  Found", nrow(all_cliques), "cliques\n")
print_memory("  ")

# ==============================================================================
# ANNOTATE CLIQUES
# ==============================================================================

if (nrow(all_cliques) > 0) {
  cat("\nAnnotating cliques with species information...\n")
  
  all_cliques_annotated <- all_cliques %>%
    rowwise() %>%
    do(annotate_clique(., gene_info)) %>%
    ungroup()
  
  cat("  ✓ Annotated", nrow(all_cliques_annotated), "cliques\n")
} else {
  all_cliques_annotated <- tibble(
    HOG = character(),
    OrthoGroup = character(),
    clique_id = integer(),
    clique_size = integer(),
    genes = list(),
    species_list = list(),
    n_species = integer(),
    life_habits = list(),
    life_habit_class = character()
  )
}

# ==============================================================================
# SAVE RESULTS
# ==============================================================================

cat("\nSaving results...\n")

# Save full data with qs2
qs_save(all_cliques_annotated, output_qs2)
cat("  ✓ Full data (qs2):", output_qs2, "\n")
if (file.exists(output_qs2)) {
  cat("    Size:", round(file.size(output_qs2) / 1024^2, 1), "MB\n")
}

# Create flat CSV
if (nrow(all_cliques_annotated) > 0) {
  all_cliques_flat <- all_cliques_annotated %>%
    mutate(
      genes_str = map_chr(genes, ~ paste(., collapse = ";")),
      species_str = map_chr(species_list, ~ paste(., collapse = ";")),
      life_habits_str = map_chr(life_habits, ~ paste(., collapse = ";"))
    ) %>%
    select(HOG, OrthoGroup, clique_id, clique_size, n_species,
           life_habit_class, genes = genes_str, species = species_str,
           life_habits = life_habits_str)
} else {
  all_cliques_flat <- tibble(
    HOG = character(),
    OrthoGroup = character(),
    clique_id = integer(),
    clique_size = integer(),
    n_species = integer(),
    life_habit_class = character(),
    genes = character(),
    species = character(),
    life_habits = character()
  )
}

write_csv(all_cliques_flat, output_csv)
cat("  ✓ Flat format (CSV):", output_csv, "\n")

# Save by life habit class
if (nrow(all_cliques_annotated) > 0 && !is.null(gene_info)) {
  for (lh_class in unique(all_cliques_annotated$life_habit_class)) {
    class_data <- all_cliques_flat %>%
      filter(all_cliques_annotated$life_habit_class == lh_class)
    
    class_file <- file.path(opt$outdir, glue("{output_prefix}_{tolower(lh_class)}.csv"))
    write_csv(class_data, class_file)
    cat("  ✓", lh_class, "cliques:", basename(class_file), "(", nrow(class_data), ")\n")
  }
}

# ==============================================================================
# SUMMARY
# ==============================================================================

total_elapsed <- as.numeric(difftime(Sys.time(), start_pass1, units = "secs"))

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("CLIQUE DETECTION COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Mode:", opt$mode, "\n")
cat("Total HOGs processed:", n_hogs, "\n")
cat("Total cliques found:", nrow(all_cliques_annotated), "\n")

if (nrow(all_cliques_annotated) > 0) {
  cat("Unique HOGs with cliques:", n_distinct(all_cliques_annotated$HOG), "\n")
  cat("Average clique size:", round(mean(all_cliques_annotated$clique_size), 2), "\n")
  cat("Max clique size:", max(all_cliques_annotated$clique_size), "\n")
  
  if (!is.null(gene_info)) {
    cat("\nCliques by life habit:\n")
    print(table(all_cliques_annotated$life_habit_class))
  }
}

cat("\nTotal runtime:", round(total_elapsed / 60, 1), "minutes\n")
print_memory("Final ")
cat(rep("=", 80), "\n", sep = "")

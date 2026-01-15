#!/usr/bin/env Rscript
# ==============================================================================
# Co-Expressolog Clique Detection
# ==============================================================================
# Finds multi-species cliques where orthologous genes are ALL pairwise
# co-expressed (complete graph = clique)
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(igraph)
  library(furrr)
  library(optparse)
  library(glue)
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
              help = "Tissue to analyze", metavar = "character"),
  make_option(c("-c", "--config"), type = "character", default = "config/pipeline_config.yaml",
              help = "Path to configuration file [default= %default]", metavar = "character"),
  make_option(c("-w", "--workdir"), type = "character", default = ".",
              help = "Working directory [default= %default]", metavar = "character"),
  make_option(c("-o", "--outdir"), type = "character", default = "results",
              help = "Output directory [default= %default]", metavar = "character"),
  make_option(c("-r", "--results_dir"), type = "character", default = NULL,
              help = "Optional: Path to results directory with comparison RData files [default uses config path]", metavar = "character")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Resolve Orion HPC paths
opt$config <- resolve_orion_path(opt$config)
opt$workdir <- resolve_orion_path(opt$workdir)
opt$outdir <- resolve_orion_path(opt$outdir)
if (!is.null(opt$results_dir)) {
  opt$results_dir <- resolve_orion_path(opt$results_dir)
}

# Validate required arguments
if (is.null(opt$tissue)) {
  print_help(opt_parser)
  stop("--tissue argument is required", call. = FALSE)
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

# Load configuration with workdir for path resolution
config <- load_config(opt$config, workdir = workdir)

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Co-Expressolog Clique Detection\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Working directory:", getwd(), "\n")
cat("Configuration:", opt$config, "\n")
cat(rep("=", 80), "\n\n", sep = "")

# SETUP PARALLEL PROCESSING ====================================================
cat("Setting up parallel processing...\n")
plan(multisession, workers = config$cliques$parallel_workers)
cat("  ✓ Using", nbrOfWorkers(), "parallel workers\n\n")

# LOAD N1 CLEAN FOR GENE ANNOTATIONS ===========================================
cat("Loading gene annotations...\n")
n1 <- readRDS(config$data$n1_file)

# Replace spaces in species names
n1 <- n1 %>% mutate(species = str_replace(species, " ", "_"))

cat("  ✓ Loaded", nrow(n1), "gene-HOG associations\n")
cat("    -", length(unique(n1$HOG)), "unique HOGs\n")
cat("    -", length(unique(n1$GeneID)), "unique genes\n")
cat("    -", length(unique(n1$species)), "species\n\n")

# FIND COMPARISON FILES ========================================================
# Allow override of results directory for Nextflow execution
if (!is.null(opt$results_dir)) {
  results_dir <- opt$results_dir
} else {
  results_dir <- file.path(config$data$output_dir, opt$tissue, "results")
}

if (!dir.exists(results_dir)) {
  stop("Results directory not found: ", results_dir,
       "\nRun RComPlEx analyses first!")
}

# Look for 03_comparison.RData or 03_comparison_unsigned.RData files (new format from Nextflow)
comparison_files <- list.files(results_dir,
                               pattern = "03_comparison(_unsigned)?\\.RData$",
                               recursive = TRUE,
                               full.names = TRUE)

# Fallback to old format if needed
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

# LOAD ALL CONSERVED PAIRS =====================================================
cat("Loading conserved gene pairs...\n")
cat("  (This may take a few minutes...)\n")

p_threshold <- config$rcomplex$p_threshold

conserved_pairs <- map_dfr(comparison_files, function(file) {

  # Load comparison
  load(file, envir = tmp_env <- new.env())
  comp <- tmp_env$comparison

  # Extract pair info from filename
  pair_id <- basename(dirname(file))

  # Filter for conserved pairs
  comp %>%
    rowwise() %>%
    mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
    filter(Max.p.val < p_threshold) %>%
    ungroup() %>%
    mutate(
      PairID = pair_id,
      # Remove "HOG_" prefix to match N1_clean format
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

# FIND CLIQUES PER HOG =========================================================
cat("Finding co-expressolog cliques...\n")
cat("  (This will take some time, progress bar below)\n\n")

hog_cliques <- conserved_pairs %>%
  group_by(HOG) %>%
  group_split() %>%
  future_map_dfr(function(hog_data) {

    hog_id <- hog_data$HOG[1]

    # Build undirected graph: nodes = genes, edges = co-expression
    edges <- hog_data %>%
      select(Species1, Species2) %>%
      distinct()

    genes_in_network <- unique(c(edges$Species1, edges$Species2))

    if (length(genes_in_network) < config$cliques$min_clique_size) {
      return(NULL)
    }

    # Create graph
    g <- graph_from_data_frame(edges, directed = FALSE)

    # Find maximal cliques
    cliques <- max_cliques(g)

    if (length(cliques) == 0) {
      return(NULL)
    }

    # Convert to tibble
    tibble(
      HOG = hog_id,
      CliqueSize = map_int(cliques, length),
      Genes = map_chr(cliques, ~ paste(sort(names(.x)), collapse = ",")),
      CliqueID = paste0(hog_id, "_C", seq_along(cliques))
    ) %>%
      filter(CliqueSize >= config$cliques$min_clique_size)

  }, .progress = TRUE, .options = furrr_options(seed = TRUE))

cat("\n  ✓ Found", nrow(hog_cliques), "cliques across",
    length(unique(hog_cliques$HOG)), "HOGs\n")

if (nrow(hog_cliques) == 0) {
  stop("No cliques found with minimum size ", config$cliques$min_clique_size)
}

cat("  Clique size distribution:\n")
size_dist <- table(hog_cliques$CliqueSize)
for (size in names(size_dist)) {
  cat("    - Size", size, ":", size_dist[size], "cliques\n")
}
cat("\n")

# ANNOTATE CLIQUES WITH SPECIES AND LIFE CYCLE INFO ===========================
cat("Annotating cliques with species and life cycle information...\n")
cat("  (Optimized vectorized implementation)\n")

# STEP 1: Pre-create gene info lookup table (single operation)
cat("  - Building gene info lookup...\n")
gene_info_lookup <- n1 %>%
  select(GeneID, species, life_cycle) %>%
  distinct()

# STEP 2: Pre-index conserved_pairs edges for fast lookup
cat("  - Indexing conserved pair edges...\n")
edge_lookup <- conserved_pairs %>%
  mutate(
    # Create canonical edge key (sorted species pair + HOG)
    edge_key = paste(pmin(Species1, Species2), pmax(Species1, Species2), HOG, sep = "___")
  ) %>%
  select(edge_key, HOG, Max.p.val, Species1.effect.size, Species2.effect.size)

# STEP 3: Expand cliques to gene-level (vectorized string split + unnest)
cat("  - Expanding cliques to gene level...\n")
cliques_expanded <- hog_cliques %>%
  mutate(
    CliqueID = row_number(),
    gene_list = str_split(Genes, ",")
  ) %>%
  unnest(gene_list) %>%
  rename(GeneID = gene_list)

# STEP 4: Join gene info (single vectorized join instead of per-row filter)
cat("  - Joining gene annotations...\n")
cliques_with_info <- cliques_expanded %>%
  left_join(gene_info_lookup, by = "GeneID")

# STEP 5: Aggregate species/lifecycle stats per clique (vectorized group_by)
cat("  - Computing species and life cycle statistics...\n")
clique_species_stats <- cliques_with_info %>%
  group_by(CliqueID, HOG, CliqueSize, Genes) %>%
  summarise(
    n_annual_species = n_distinct(species[life_cycle == "annual"], na.rm = TRUE),
    n_perennial_species = n_distinct(species[life_cycle == "perennial"], na.rm = TRUE),
    Species = paste(sort(unique(na.omit(species))), collapse = "; "),
    .groups = "drop"
  ) %>%
  mutate(
    n_species = n_annual_species + n_perennial_species,
    LifeHabit = case_when(
      n_perennial_species == 0 ~ "Annual",
      n_annual_species == 0 ~ "Perennial",
      TRUE ~ "Mixed"
    )
  )

# STEP 6: Generate all clique edges and compute stats (vectorized)
cat("  - Computing edge statistics...\n")

# Get unique genes per clique for edge generation
clique_genes <- cliques_expanded %>%
  group_by(CliqueID, HOG) %>%
  summarise(genes = list(GeneID), .groups = "drop")

# Generate all edges per clique using parallel processing
clique_edges <- future_map_dfr(seq_len(nrow(clique_genes)), function(i) {
  row <- clique_genes[i, ]
  genes <- row$genes[[1]]
  
  if (length(genes) < 2) {
    return(tibble(CliqueID = row$CliqueID, edge_key = character(0)))
  }
  
  # Generate all pairs
  pairs <- combn(genes, 2, simplify = FALSE)
  edge_keys <- map_chr(pairs, ~ paste(sort(.x), collapse = "___"))
  edge_keys <- paste(edge_keys, row$HOG, sep = "___")
  
  tibble(CliqueID = row$CliqueID, edge_key = edge_keys)
}, .progress = FALSE, .options = furrr_options(seed = TRUE))

# Join with edge lookup to get statistics
clique_edge_stats <- clique_edges %>%
  left_join(edge_lookup, by = "edge_key") %>%
  group_by(CliqueID) %>%
  summarise(
    Mean_pval = mean(Max.p.val, na.rm = TRUE),
    Median_pval = median(Max.p.val, na.rm = TRUE),
    Mean_effect_size = mean(c(Species1.effect.size, Species2.effect.size), na.rm = TRUE),
    n_edges = sum(!is.na(Max.p.val)),
    .groups = "drop"
  )

# STEP 7: Combine all annotations
cat("  - Finalizing clique annotations...\n")
cliques_annotated <- clique_species_stats %>%
  left_join(clique_edge_stats, by = "CliqueID") %>%
  select(-CliqueID) %>%
  arrange(desc(CliqueSize), Mean_pval)

cat("  ✓ Annotation complete\n\n")

# SPLIT BY LIFE HABIT ==========================================================
cat("Splitting cliques by life habit...\n")

annual_cliques <- cliques_annotated %>% filter(LifeHabit == "Annual")
perennial_cliques <- cliques_annotated %>% filter(LifeHabit == "Perennial")
mixed_cliques <- cliques_annotated %>% filter(LifeHabit == "Mixed")

cat("  - Annual cliques:", nrow(annual_cliques), "\n")
cat("  - Perennial cliques:", nrow(perennial_cliques), "\n")
cat("  - Mixed cliques:", nrow(mixed_cliques), "\n\n")

# CREATE OUTPUT DIRECTORY ======================================================
tissue_outdir <- file.path(opt$outdir, opt$tissue)
dir.create(tissue_outdir, showWarnings = FALSE, recursive = TRUE)

# EXPORT RESULTS ===============================================================
cat("Exporting results...\n")

# All cliques
all_file <- file.path(tissue_outdir, glue("coexpressolog_cliques_{opt$tissue}_all.tsv"))
write_tsv(cliques_annotated, all_file)
cat("  ✓", all_file, "\n")

# Annual cliques
annual_file <- file.path(tissue_outdir, glue("coexpressolog_cliques_{opt$tissue}_annual.tsv"))
write_tsv(annual_cliques, annual_file)
cat("  ✓", annual_file, "\n")

# Perennial cliques
perennial_file <- file.path(tissue_outdir, glue("coexpressolog_cliques_{opt$tissue}_perennial.tsv"))
write_tsv(perennial_cliques, perennial_file)
cat("  ✓", perennial_file, "\n")

# Mixed cliques
mixed_file <- file.path(tissue_outdir, glue("coexpressolog_cliques_{opt$tissue}_shared.tsv"))
write_tsv(mixed_cliques, mixed_file)
cat("  ✓", mixed_file, "\n")

# Export gene lists
cat("\nExporting gene lists...\n")

for (habit in c("annual", "perennial", "mixed")) {

  clique_data <- switch(habit,
                       "annual" = annual_cliques,
                       "perennial" = perennial_cliques,
                       "mixed" = mixed_cliques)

  if (nrow(clique_data) > 0) {
    genes <- clique_data %>%
      pull(Genes) %>%
      str_split(",") %>%
      unlist() %>%
      unique() %>%
      sort()

    gene_file <- file.path(tissue_outdir,
                           glue("genes_{opt$tissue}_{habit}.txt"))
    writeLines(genes, gene_file)
    cat("  ✓", gene_file, "(", length(genes), "genes )\n")
  }
}

# SUMMARY ======================================================================
cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("CLIQUE DETECTION COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Total cliques:", nrow(cliques_annotated), "\n")
cat("  - Annual:", nrow(annual_cliques), "\n")
cat("  - Perennial:", nrow(perennial_cliques), "\n")
cat("  - Mixed:", nrow(mixed_cliques), "\n")
cat("\n")
cat("Clique size range:", min(cliques_annotated$CliqueSize), "-",
    max(cliques_annotated$CliqueSize), "genes\n")
cat("Species representation:", min(cliques_annotated$n_species), "-",
    max(cliques_annotated$n_species), "species\n")
cat("\n")
cat("Output directory:", tissue_outdir, "\n")
cat(rep("=", 80), "\n", sep = "")

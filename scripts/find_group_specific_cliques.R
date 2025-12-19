#!/usr/bin/env Rscript
# ==============================================================================
# Group-Specific Co-Expressolog Clique Detection
# ==============================================================================
# Finds cliques of co-expressologues where ALL edges come from comparisons
# within a specified group (e.g., annual-only or perennial-only comparisons).
# Outputs include species coverage information for each clique.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(igraph)
  library(furrr)
  library(optparse)
  library(glue)
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
              help = "Tissue to analyze", metavar = "character"),
  make_option(c("-g", "--group"), type = "character", default = NULL,
              help = "Group to filter for (e.g., 'annual', 'perennial')", metavar = "character"),
  make_option(c("--group_column"), type = "character", default = "life_cycle",
              help = "Column in N1 that defines groups [default= %default]", metavar = "character"),
  make_option(c("-c", "--config"), type = "character", default = "config/pipeline_config.yaml",
              help = "Path to configuration file [default= %default]", metavar = "character"),
  make_option(c("-w", "--workdir"), type = "character", default = ".",
              help = "Working directory [default= %default]", metavar = "character"),
  make_option(c("-o", "--outdir"), type = "character", default = "results",
              help = "Output directory [default= %default]", metavar = "character"),
  make_option(c("-r", "--results_dir"), type = "character", default = NULL,
              help = "Path to results directory with comparison RData files", metavar = "character")
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
if (is.null(opt$group)) {
  print_help(opt_parser)
  stop("--group argument is required", call. = FALSE)
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
  stop("Cannot locate R/config_parser.R; checked: ",
       paste(config_parser_candidates, collapse = ", "))
}
source(config_parser_path)

# Load configuration
config <- load_config(opt$config, workdir = workdir)

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Group-Specific Co-Expressolog Clique Detection\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Group:", opt$group, "\n")
cat("Group column:", opt$group_column, "\n")
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

# Validate group column exists
if (!opt$group_column %in% colnames(n1)) {
  stop("Group column '", opt$group_column, "' not found in N1 data. ",
       "Available columns: ", paste(colnames(n1), collapse = ", "))
}

# Get species-to-group mapping
species_group <- n1 %>%
  select(species, !!sym(opt$group_column)) %>%
  distinct() %>%
  rename(group = !!sym(opt$group_column))

# Get all species in the target group
group_species <- species_group %>%
  filter(group == opt$group) %>%
  pull(species)

n_total_group_species <- length(group_species)

cat("  ✓ Loaded", nrow(n1), "gene-HOG associations\n")
cat("    -", length(unique(n1$HOG)), "unique HOGs\n")
cat("    -", length(unique(n1$GeneID)), "unique genes\n")
cat("    -", length(unique(n1$species)), "total species\n")
cat("    -", n_total_group_species, "species in group '", opt$group, "':\n", sep = "")
cat("      ", paste(group_species, collapse = ", "), "\n\n")

if (n_total_group_species < 2) {
  stop("Need at least 2 species in group '", opt$group, "' for clique detection")
}

# FIND COMPARISON FILES ========================================================
if (!is.null(opt$results_dir)) {
  results_dir <- opt$results_dir
} else {
  results_dir <- file.path(config$data$output_dir, opt$tissue, "results")
}

if (!dir.exists(results_dir)) {
  stop("Results directory not found: ", results_dir,
       "\nRun RComPlEx analyses first!")
}

# Look for comparison files
comparison_files <- list.files(results_dir,
                               pattern = "03_comparison\\.RData$",
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

# LOAD ALL CONSERVED PAIRS =====================================================
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

# FILTER TO GROUP-SPECIFIC EDGES ===============================================
cat("Filtering to", opt$group, "-only edges...\n")

# Get species for each gene in conserved_pairs
gene_species <- n1 %>%
  select(GeneID, species) %>%
  distinct()

# Add species info for both genes in each pair
conserved_pairs_annotated <- conserved_pairs %>%
  left_join(gene_species, by = c("Species1" = "GeneID")) %>%
  rename(Species1_species = species) %>%
  left_join(gene_species, by = c("Species2" = "GeneID")) %>%
  rename(Species2_species = species)

# Filter to edges where BOTH genes are from species in the target group
group_only_pairs <- conserved_pairs_annotated %>%
  filter(Species1_species %in% group_species & Species2_species %in% group_species)

cat("  ✓ Filtered from", nrow(conserved_pairs), "to", nrow(group_only_pairs), "group-specific edges\n")
cat("    - Reduction:", round((1 - nrow(group_only_pairs)/nrow(conserved_pairs)) * 100, 1), "%\n\n")

if (nrow(group_only_pairs) == 0) {
  cat("WARNING: No edges found for group '", opt$group, "'. Creating empty output.\n", sep = "")
  
  # Create empty output
  empty_output <- tibble(
    HOG = character(),
    CliqueID = character(),
    CliqueSize = integer(),
    Genes = character(),
    Species = character(),
    n_species_in_clique = integer(),
    n_total_group_species = integer(),
    coverage_fraction = numeric(),
    Mean_pval = numeric(),
    Median_pval = numeric(),
    Mean_effect_size = numeric(),
    n_edges = integer()
  )
  
  output_file <- file.path(opt$outdir, glue("{opt$group}_cliques_{opt$tissue}.csv"))
  dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)
  write_csv(empty_output, output_file)
  cat("\n  ✓ Empty output written to:", output_file, "\n")
  quit(save = "no", status = 0)
}

# FIND CLIQUES PER HOG =========================================================
cat("Finding", opt$group, "-specific cliques...\n")
cat("  (This will take some time, progress bar below)\n\n")

hog_cliques <- group_only_pairs %>%
  group_by(HOG) %>%
  group_split() %>%
  future_map_dfr(function(hog_data) {
    
    hog_id <- hog_data$HOG[1]
    
    # Build undirected graph: nodes = genes, edges = co-expression
    edges <- hog_data %>%
      select(Species1, Species2) %>%
      distinct()
    
    genes_in_network <- unique(c(edges$Species1, edges$Species2))
    
    # Need at least 2 genes for a clique
    if (length(genes_in_network) < 2) {
      return(NULL)
    }
    
    # Create graph
    g <- graph_from_data_frame(edges, directed = FALSE)
    
    # Find maximal cliques (minimum size 2)
    cliques <- max_cliques(g, min = 2)
    
    if (length(cliques) == 0) {
      return(NULL)
    }
    
    # Convert to tibble
    tibble(
      HOG = hog_id,
      CliqueSize = map_int(cliques, length),
      Genes = map_chr(cliques, ~ paste(sort(names(.x)), collapse = ",")),
      CliqueID = paste0(hog_id, "_C", seq_along(cliques))
    )
    
  }, .progress = TRUE, .options = furrr_options(seed = TRUE))

if (nrow(hog_cliques) == 0) {
  cat("\nWARNING: No cliques found for group '", opt$group, "'. Creating empty output.\n", sep = "")
  
  empty_output <- tibble(
    HOG = character(),
    CliqueID = character(),
    CliqueSize = integer(),
    Genes = character(),
    Species = character(),
    n_species_in_clique = integer(),
    n_total_group_species = integer(),
    coverage_fraction = numeric(),
    Mean_pval = numeric(),
    Median_pval = numeric(),
    Mean_effect_size = numeric(),
    n_edges = integer()
  )
  
  output_file <- file.path(opt$outdir, glue("{opt$group}_cliques_{opt$tissue}.csv"))
  dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)
  write_csv(empty_output, output_file)
  cat("\n  ✓ Empty output written to:", output_file, "\n")
  quit(save = "no", status = 0)
}

cat("\n  ✓ Found", nrow(hog_cliques), "cliques across",
    length(unique(hog_cliques$HOG)), "HOGs\n")

cat("  Clique size distribution:\n")
size_dist <- table(hog_cliques$CliqueSize)
for (size in names(size_dist)) {
  cat("    - Size", size, ":", size_dist[size], "cliques\n")
}
cat("\n")

# ANNOTATE CLIQUES WITH SPECIES COVERAGE =======================================
cat("Annotating cliques with species coverage...\n")

cliques_annotated <- hog_cliques %>%
  rowwise() %>%
  mutate(
    gene_list = list(str_split(Genes, ",")[[1]]),
    gene_info = list({
      n1 %>%
        filter(GeneID %in% gene_list) %>%
        select(GeneID, species) %>%
        distinct()
    })
  ) %>%
  ungroup() %>%
  mutate(
    # Get species list for this clique
    Species = map_chr(gene_info, ~ paste(sort(unique(.x$species)), collapse = "; ")),
    
    # Count unique species in clique
    n_species_in_clique = map_int(gene_info, ~ n_distinct(.x$species)),
    
    # Total species in group (constant)
    n_total_group_species = n_total_group_species,
    
    # Coverage fraction
    coverage_fraction = n_species_in_clique / n_total_group_species,
    
    # Get statistics from group_only_pairs
    clique_stats = pmap(list(gene_list, HOG), function(genes, hog_id) {
      if (length(genes) < 2) {
        return(tibble(Mean_pval = NA, Median_pval = NA, Mean_effect_size = NA, n_edges = 0))
      }
      
      gene_pairs <- combn(genes, 2, simplify = FALSE)
      edge_stats <- map_dfr(gene_pairs, function(pair) {
        group_only_pairs %>%
          filter(HOG == hog_id,
                 ((Species1 == pair[1] & Species2 == pair[2]) |
                    (Species1 == pair[2] & Species2 == pair[1]))) %>%
          select(Max.p.val, Species1.effect.size, Species2.effect.size)
      })
      
      if (nrow(edge_stats) > 0) {
        tibble(
          Mean_pval = mean(edge_stats$Max.p.val, na.rm = TRUE),
          Median_pval = median(edge_stats$Max.p.val, na.rm = TRUE),
          Mean_effect_size = mean(c(edge_stats$Species1.effect.size,
                                    edge_stats$Species2.effect.size), na.rm = TRUE),
          n_edges = nrow(edge_stats)
        )
      } else {
        tibble(Mean_pval = NA, Median_pval = NA, Mean_effect_size = NA, n_edges = 0)
      }
    })
  ) %>%
  unnest(clique_stats) %>%
  select(-gene_list, -gene_info) %>%
  arrange(desc(n_species_in_clique), desc(CliqueSize), Mean_pval)

cat("  ✓ Annotation complete\n\n")

# SPECIES COVERAGE SUMMARY =====================================================
cat("Species coverage summary:\n")
coverage_summary <- cliques_annotated %>%
  group_by(n_species_in_clique) %>%
  summarise(n_cliques = n(), .groups = "drop") %>%
  arrange(desc(n_species_in_clique))

for (i in seq_len(nrow(coverage_summary))) {
  row <- coverage_summary[i, ]
  cat("    -", row$n_species_in_clique, "of", n_total_group_species, "species:",
      row$n_cliques, "cliques\n")
}
cat("\n")

# EXPORT RESULTS ===============================================================
cat("Exporting results...\n")

output_file <- file.path(opt$outdir, glue("{opt$group}_cliques_{opt$tissue}.csv"))
dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)
write_csv(cliques_annotated, output_file)
cat("  ✓", output_file, "\n")

# SUMMARY ======================================================================
cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("GROUP-SPECIFIC CLIQUE DETECTION COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Group:", opt$group, "\n")
cat("Total cliques:", nrow(cliques_annotated), "\n")
cat("Clique size range:", min(cliques_annotated$CliqueSize), "-",
    max(cliques_annotated$CliqueSize), "genes\n")
cat("Species coverage range:", min(cliques_annotated$n_species_in_clique), "-",
    max(cliques_annotated$n_species_in_clique), "of", n_total_group_species, "species\n")
cat("\nOutput file:", output_file, "\n")
cat(rep("=", 80), "\n", sep = "")

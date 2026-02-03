#!/usr/bin/env Rscript
# ==============================================================================
# Find Cliques Batch - Step 2 of Batched Clique Detection
# ==============================================================================
# Processes a batch of HOGs to find coexpressolog cliques.
# Designed to run in parallel with other batches.
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
qopt(nthreads = qs2_threads)
message(sprintf("qs2 configured with %d threads", qs2_threads))

# Parse command-line arguments
option_list <- list(
  make_option(c("-t", "--tissue"), type = "character", default = NULL,
              help = "Tissue to analyze", metavar = "character"),
  make_option(c("-b", "--batch_id"), type = "integer", default = NULL,
              help = "Batch ID to process", metavar = "integer"),
  make_option(c("-p", "--pairs_file"), type = "character", default = NULL,
              help = "Path to conserved_pairs RDS file", metavar = "character"),
  make_option(c("-a", "--batch_assignments"), type = "character", default = NULL,
              help = "Path to batch_assignments RDS file", metavar = "character"),
  make_option(c("-o", "--outdir"), type = "character", default = ".",
              help = "Output directory for batch results", metavar = "character"),
  make_option(c("-s", "--signed"), type = "logical", default = TRUE,
              help = "Use signed correlation (TRUE) or absolute (FALSE) [default= %default]",
              metavar = "logical")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Validate required arguments
if (is.null(opt$tissue) || is.null(opt$batch_id) || 
    is.null(opt$pairs_file) || is.null(opt$batch_assignments)) {
  stop("Required arguments: --tissue, --batch_id, --pairs_file, --batch_assignments", 
       call. = FALSE)
}

# Print memory usage helper
print_memory <- function(prefix = "") {
  mem_mb <- as.numeric(system("ps -o rss= -p $$", intern = TRUE)) / 1024
  cat(sprintf("%s[Memory: %.1f GB]\n", prefix, mem_mb / 1024))
}

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Find Cliques - Batch Processing\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Batch ID:", opt$batch_id, "\n")
cat("Mode:", ifelse(opt$signed, "Signed correlation", "Unsigned (absolute) correlation"), "\n")
cat(rep("=", 80), "\n\n", sep = "")

print_memory("Initial ")

# Create output directory
dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# LOAD BATCH DATA ==============================================================
cat("Loading batch data...\n")

# Load conserved pairs
cat("  Loading conserved pairs from:", opt$pairs_file, "\n")
all_pairs <- qs_read(opt$pairs_file)
print_memory("  After loading pairs ")

# Load batch assignments
cat("  Loading batch assignments from:", opt$batch_assignments, "\n")
batch_assignments <- qs_read(opt$batch_assignments)

# Get HOGs for this batch
batch_hogs <- batch_assignments %>%
  filter(batch_id == opt$batch_id) %>%
  pull(HOG)

cat("  This batch contains", length(batch_hogs), "HOGs\n\n")

# Filter pairs to only this batch's HOGs
batch_pairs <- all_pairs %>%
  filter(HOG %in% batch_hogs)

cat("  Filtered to", nrow(batch_pairs), "conserved pairs for this batch\n")
print_memory("  After filtering ")

# Clean up memory
rm(all_pairs)
gc()
print_memory("  After cleanup ")

cat("\n")

# CLIQUE FINDING FUNCTION ======================================================
find_cliques_for_hog <- function(hog_data, signed = TRUE) {
  if (nrow(hog_data) < 3) {
    # Need at least 3 edges to form a clique
    return(tibble())
  }
  
  # Create gene pairs based on signed/unsigned mode
  if (signed) {
    # For signed: only connect genes with same sign correlation
    gene_pairs <- hog_data %>%
      mutate(
        # Sign agreement: both positive or both negative
        sign_agreement = sign(Species1.effect.size) == sign(Species2.effect.size)
      ) %>%
      filter(sign_agreement) %>%
      select(Species1, Species2, HOG, OrthoGroup, PairID)
  } else {
    # For unsigned: use all pairs (absolute correlation)
    gene_pairs <- hog_data %>%
      select(Species1, Species2, HOG, OrthoGroup, PairID)
  }
  
  if (nrow(gene_pairs) < 3) {
    return(tibble())
  }
  
  # Build graph
  # Each unique gene pair creates an edge in the graph
  edges <- gene_pairs %>%
    mutate(
      gene1 = pmin(Species1, Species2),
      gene2 = pmax(Species1, Species2)
    ) %>%
    distinct(gene1, gene2) %>%
    filter(gene1 != gene2)
  
  if (nrow(edges) < 3) {
    return(tibble())
  }
  
  # Create igraph object
  g <- graph_from_data_frame(edges, directed = FALSE)
  
  # Find all maximal cliques (minimum size 3)
  cliques <- max_cliques(g, min = 3)
  
  if (length(cliques) == 0) {
    return(tibble())
  }
  
  # Convert cliques to tibble
  clique_results <- map_dfr(seq_along(cliques), function(i) {
    genes <- names(cliques[[i]])
    tibble(
      HOG = unique(hog_data$HOG),
      OrthoGroup = unique(hog_data$OrthoGroup),
      clique_id = i,
      clique_size = length(genes),
      genes = list(sort(genes))
    )
  })
  
  return(clique_results)
}

# PROCESS HOGS =================================================================
cat("Processing", length(batch_hogs), "HOGs in batch", opt$batch_id, "...\n")

start_time <- Sys.time()
processed <- 0

# Pre-split data by HOG for efficiency
hog_data_list <- split(batch_pairs, batch_pairs$HOG)

all_cliques <- map_dfr(batch_hogs, function(hog) {
  processed <<- processed + 1
  
  # Progress every 100 HOGs
  if (processed %% 100 == 0 || processed == length(batch_hogs)) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    rate <- processed / elapsed
    remaining <- (length(batch_hogs) - processed) / rate
    
    cat(sprintf("  [%d/%d] HOG %s | %.1f HOGs/sec | ETA: %.0fs\n",
                processed, length(batch_hogs), hog, rate, remaining))
    
    if (processed %% 500 == 0) {
      print_memory("    ")
    }
  }
  
  hog_data <- hog_data_list[[hog]]
  
  if (is.null(hog_data) || nrow(hog_data) == 0) {
    return(tibble())
  }
  
  tryCatch({
    find_cliques_for_hog(hog_data, signed = opt$signed)
  }, error = function(e) {
    cat("    Warning: Error processing HOG", hog, ":", conditionMessage(e), "\n")
    return(tibble())
  })
})

elapsed_total <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
cat("\n")
cat("Processing complete in", round(elapsed_total / 60, 1), "minutes\n")
print_memory("Final ")

# SAVE RESULTS =================================================================
cat("\nSaving results...\n")

# Create output filename
mode_suffix <- ifelse(opt$signed, "signed", "unsigned")
output_file <- file.path(opt$outdir, 
                         glue("cliques_{opt$tissue}_{mode_suffix}_batch{sprintf('%03d', opt$batch_id)}.qs2"))

qs_save(all_cliques, output_file)
cat("  ✓ Saved:", output_file, "\n")
cat("    Size:", round(file.size(output_file) / 1024^2, 1), "MB\n")

# SUMMARY ======================================================================
cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("BATCH COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")
cat("Batch ID:", opt$batch_id, "\n")
cat("Mode:", ifelse(opt$signed, "Signed", "Unsigned"), "\n")
cat("HOGs processed:", length(batch_hogs), "\n")
cat("Cliques found:", nrow(all_cliques), "\n")
if (nrow(all_cliques) > 0) {
  cat("Unique HOGs with cliques:", n_distinct(all_cliques$HOG), "\n")
  cat("Average clique size:", round(mean(all_cliques$clique_size), 2), "\n")
  cat("Max clique size:", max(all_cliques$clique_size), "\n")
}
cat("Processing time:", round(elapsed_total / 60, 1), "minutes\n")
cat(rep("=", 80), "\n", sep = "")

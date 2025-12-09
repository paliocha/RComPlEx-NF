#!/usr/bin/env Rscript
# ==============================================================================
# RComPlEx Step 4: Generate Summary Statistics
# ==============================================================================
# Computes summary statistics from network comparison results
# Generates p-value correlation analysis, effect size analysis, and summary tables
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(optparse)
  library(ggplot2)
})

# Source Orion HPC utilities for path resolution
source("R/orion_hpc_utils.R")

# Parse command-line arguments
option_list <- list(
  make_option(c("-t", "--tissue"), type = "character", default = NULL,
              help = "Tissue being analyzed", metavar = "character"),
  make_option(c("-p", "--pair_id"), type = "character", default = NULL,
              help = "Species pair ID (e.g., 'Species1_Species2')", metavar = "character"),
  make_option(c("-w", "--workdir"), type = "character", default = ".",
              help = "Working directory [default= %default]", metavar = "character"),
  make_option(c("-i", "--indir"), type = "character", default = NULL,
              help = "Input directory with step 3 output", metavar = "character"),
  make_option(c("-o", "--outdir"), type = "character", default = NULL,
              help = "Output directory for results", metavar = "character")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Resolve Orion HPC paths
opt$workdir <- resolve_orion_path(opt$workdir)
opt$indir <- resolve_orion_path(opt$indir)
opt$outdir <- resolve_orion_path(opt$outdir)

# Validate required arguments
required_args <- c("tissue", "pair_id", "indir", "outdir")
for (arg in required_args) {
  if (is.null(opt[[arg]])) {
    print_help(opt_parser)
    stop("--", arg, " argument is required", call. = FALSE)
  }
}

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("RComPlEx Step 4: Generate Summary Statistics\n")
cat(rep("=", 80), "\n", sep = "")
cat("Tissue:", opt$tissue, "\n")
cat("Pair ID:", opt$pair_id, "\n")
cat(rep("=", 80), "\n\n")

# Create output directory
dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# LOAD COMPARISON DATA FROM STEP 3
# ==============================================================================

input_file <- file.path(opt$indir, "03_comparison.RData")
if (!file.exists(input_file)) {
  stop("Step 3 output not found: ", input_file)
}

cat("Loading comparison data from step 3...\n")
load(input_file)

cat("✓ Data loaded successfully\n\n")

# ==============================================================================
# SUMMARY STATISTICS - GENE PAIRS
# ==============================================================================

cat("Computing summary statistics...\n\n")

cat("GENE PAIRS:\n")
conserved_sp1_pairs <- sum(comparison$Species1.p.val < 0.05)
conserved_sp2_pairs <- sum(comparison$Species2.p.val < 0.05)
reciprocal_pairs <- sum(comparison$Species1.p.val < 0.05 & comparison$Species2.p.val < 0.05)

cat("  Conserved", species1_name, "gene pairs:",
    conserved_sp1_pairs, "/", nrow(comparison),
    " (", format(conserved_sp1_pairs / nrow(comparison), digits = 3), ")\n", sep = "")
cat("  Conserved", species2_name, "gene pairs:",
    conserved_sp2_pairs, "/", nrow(comparison),
    " (", format(conserved_sp2_pairs / nrow(comparison), digits = 3), ")\n", sep = "")
cat("  Reciprocally conserved gene pairs:",
    reciprocal_pairs, "/", nrow(comparison),
    " (", format(reciprocal_pairs / nrow(comparison), digits = 3), ")\n\n", sep = "")

# ==============================================================================
# SUMMARY STATISTICS - GENES
# ==============================================================================

cat("GENES:\n")

# Get best p-value per species1 gene
comparison_species1 <- comparison %>%
  group_by(Species1) %>%
  arrange(Species1.p.val) %>%
  slice(1)

conserved_sp1_genes <- sum(comparison_species1$Species1.p.val < 0.05)
cat("  Conserved", species1_name, "genes:",
    conserved_sp1_genes, "/", nrow(comparison_species1),
    " (", format(conserved_sp1_genes / nrow(comparison_species1), digits = 3), ")\n", sep = "")

# Get best p-value per species2 gene
comparison_species2 <- comparison %>%
  group_by(Species2) %>%
  arrange(Species2.p.val) %>%
  slice(1)

conserved_sp2_genes <- sum(comparison_species2$Species2.p.val < 0.05)
cat("  Conserved", species2_name, "genes:",
    conserved_sp2_genes, "/", nrow(comparison_species2),
    " (", format(conserved_sp2_genes / nrow(comparison_species2), digits = 3), ")\n", sep = "")

# Get best reciprocal p-value per species1 gene
comparison_species1_12 <- comparison %>%
  rowwise() %>%
  mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
  group_by(Species1) %>%
  arrange(Max.p.val) %>%
  slice(1)

reciprocal_sp1_genes <- sum(comparison_species1_12$Max.p.val < 0.05)
cat("  Reciprocally conserved", species1_name, "genes:",
    reciprocal_sp1_genes, "/", nrow(comparison_species1_12),
    " (", format(reciprocal_sp1_genes / nrow(comparison_species1_12), digits = 3), ")\n", sep = "")

# Get best reciprocal p-value per species2 gene
comparison_species2_12 <- comparison %>%
  rowwise() %>%
  mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
  group_by(Species2) %>%
  arrange(Max.p.val) %>%
  slice(1)

reciprocal_sp2_genes <- sum(comparison_species2_12$Max.p.val < 0.05)
cat("  Reciprocally conserved", species2_name, "genes:",
    reciprocal_sp2_genes, "/", nrow(comparison_species2_12),
    " (", format(reciprocal_sp2_genes / nrow(comparison_species2_12), digits = 3), ")\n\n", sep = "")

# ==============================================================================
# SUMMARY STATISTICS - ORTHOGROUPS
# ==============================================================================

cat("ORTHOLOG GROUPS:\n")

# Get best p-value per orthogroup (species1 perspective)
comparison_og1 <- comparison %>%
  group_by(OrthoGroup) %>%
  arrange(Species1.p.val) %>%
  slice(1)

conserved_og_sp1 <- sum(comparison_og1$Species1.p.val < 0.05)
cat("  Conserved", species1_name, "orthogroups:",
    conserved_og_sp1, "/", nrow(comparison_og1),
    " (", format(conserved_og_sp1 / nrow(comparison_og1), digits = 3), ")\n", sep = "")

# Get best p-value per orthogroup (species2 perspective)
comparison_og2 <- comparison %>%
  group_by(OrthoGroup) %>%
  arrange(Species2.p.val) %>%
  slice(1)

conserved_og_sp2 <- sum(comparison_og2$Species2.p.val < 0.05)
cat("  Conserved", species2_name, "orthogroups:",
    conserved_og_sp2, "/", nrow(comparison_og2),
    " (", format(conserved_og_sp2 / nrow(comparison_og2), digits = 3), ")\n", sep = "")

# Get reciprocally conserved orthogroups
comparison_og12 <- comparison %>%
  rowwise() %>%
  mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
  group_by(OrthoGroup) %>%
  arrange(Max.p.val) %>%
  slice(1)

reciprocal_og <- sum(comparison_og12$Max.p.val < 0.05)
cat("  Reciprocally conserved orthogroups:",
    reciprocal_og, "/", nrow(comparison_og12),
    " (", format(reciprocal_og / nrow(comparison_og12), digits = 3), ")\n\n", sep = "")

# ==============================================================================
# SAVE SUMMARY TABLE
# ==============================================================================

cat("Creating summary table...\n")

comparison_table <- comparison %>%
  rowwise() %>%
  mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
  mutate(Min.effect.size = min(Species1.effect.size, Species2.effect.size)) %>%
  select(-c("Species1.neigh", "Species1.ortho.neigh", "Species2.neigh", "Species2.ortho.neigh")) %>%
  arrange(Max.p.val)

# Create output TSV file
summary_file <- file.path(opt$outdir, "04_summary_statistics.tsv")
write_tsv(comparison_table, summary_file)
cat("✓ Summary table saved to:", summary_file, "\n\n")

# ==============================================================================
# CREATE PLOTS (PNG FORMAT, NO INTERACTIVE DISPLAY)
# ==============================================================================

cat("Generating plots...\n")

# Set theme for plots
theme_set(theme_classic())
theme_update(plot.title = element_text(face = "bold"))

# Plot 1: P-value correlation
plot_data <- data.frame(
  s1 = -log10(comparison$Species1.p.val + 1e-100),
  s2 = -log10(comparison$Species2.p.val + 1e-100)
)

R <- cor.test(plot_data$s1, plot_data$s2, method = "spearman", continuity = TRUE)

p1 <- ggplot(plot_data, aes(x = s1, y = s2)) +
  geom_point(alpha = 0.5) +
  geom_smooth(method = lm, formula = y ~ x, fill = "gainsboro", se = TRUE) +
  xlab(paste0(species1_name, " p-value (-log10)")) +
  ylab(paste0(species2_name, " p-value (-log10)")) +
  ggtitle(paste0("P-value Correlation (rho = ", format(R$estimate, digits = 3), ")")) +
  theme(plot.title = element_text(face = "bold", hjust = 0.5))

p1_file <- file.path(opt$outdir, "04_pvalue_correlation.png")
ggsave(p1_file, plot = p1, width = 8, height = 6, dpi = 150)
cat("✓ P-value correlation plot saved to:", p1_file, "\n")

# Plot 2: Effect size vs p-value
p2_data <- comparison %>%
  rowwise() %>%
  mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
  mutate(Min.effect.size = min(Species1.effect.size, Species2.effect.size)) %>%
  mutate(NeighborhoodSize = mean(c(Species1.neigh, Species2.neigh))) %>%
  filter(Max.p.val < 0.05)

if (nrow(p2_data) > 0) {
  p2 <- ggplot(p2_data, aes(x = -log10(Max.p.val), y = Min.effect.size, col = NeighborhoodSize)) +
    geom_point(alpha = 0.6) +
    scale_color_gradient(low = "blue", high = "red") +
    xlab("P-value (-log10)") +
    ylab("Effect size") +
    ggtitle("Effect Size vs P-value (FDR < 0.05)") +
    theme(plot.title = element_text(face = "bold", hjust = 0.5)) +
    labs(color = "Neighborhood Size")

  p2_file <- file.path(opt$outdir, "04_effect_size_plot.png")
  ggsave(p2_file, plot = p2, width = 8, height = 6, dpi = 150)
  cat("✓ Effect size plot saved to:", p2_file, "\n")
} else {
  cat("⚠ Skipping effect size plot (no orthologs with FDR < 0.05)\n")
}

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("Step 4 COMPLETE\n")
cat(rep("=", 80), "\n")

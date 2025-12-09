#!/usr/bin/env Rscript
# ==============================================================================
# Find Reciprocally Conserved HOGs Across All Pairwise Comparisons (Clique-Based)
# ==============================================================================
# Loads all RComPlEx comparison results and identifies HOGs that are 
# reciprocally conserved (Max.p.val < 0.05) in ALL pairwise comparisons
#
# CLIQUE-BASED APPROACH:
# - A "clique" is defined as a specific focal gene + orthogroup combination
# - For a clique to be conserved, the SAME focal gene from the SAME orthogroup
#   must appear in ALL pairwise comparisons
# - Example: If Brachypodium gene Bradi1g12345 from HOG N001234 is conserved
#   with Hordeum in comparison 1, it must be the same Bradi1g12345 + N001234
#   pair conserved with Briza in comparison 2, etc.
# - This ensures we identify the same gene relationships across all species
# ==============================================================================

setwd("~/AnnualPerennial/RComPlEx")
library(tidyverse)

# CONFIGURATION ================================================================
RESULTS_DIR <- "rcomplex_data/results"
P_THRESHOLD <- 0.05
OUTPUT_FILE <- "conserved_hogs_all_pairs.tsv"

# FIND ALL COMPARISON FILES ====================================================
files <- list.files(RESULTS_DIR, pattern = "comparison-.*\\.RData$", 
                    recursive = TRUE, full.names = TRUE)

cat("Found", length(files), "comparison files\n")

# LOAD ALL COMPARISONS =========================================================
cat("Loading comparisons...\n")

all_comparisons <- list()

for (i in seq_along(files)) {
  pair_name <- basename(dirname(files[i]))
  
  load(files[i], envir = tmp <- new.env())
  comp <- tmp$comparison
  
  # Add comparison info and filter for conserved pairs
  comp_filtered <- comp %>%
    rowwise() %>%
    mutate(Max.p.val = max(Species1.p.val, Species2.p.val)) %>%
    filter(Max.p.val < P_THRESHOLD) %>%
    ungroup() %>%
    mutate(
      Comparison = pair_name,
      # Extract species names from comparison name
      Sp1 = paste(str_split(pair_name, "_")[[1]][1], str_split(pair_name, "_")[[1]][2]),
      Sp2 = paste(str_split(pair_name, "_")[[1]][3], str_split(pair_name, "_")[[1]][4])
    ) %>%
    select(Comparison, Sp1, Sp2, Species1, Species2, OrthoGroup, Max.p.val,
           Species1.p.val, Species2.p.val)
  
  all_comparisons[[pair_name]] <- comp_filtered
  
  cat(sprintf("  [%d/%d] %s: %d conserved pairs\n", 
              i, length(files), pair_name, nrow(comp_filtered)))
}

# Combine all comparisons
all_data <- bind_rows(all_comparisons)

cat("\nTotal conserved gene pairs:", nrow(all_data), "\n\n")

# ANALYZE BY FOCAL SPECIES =====================================================
cat("Analysing conservation by focal species...\n\n")

# Get all species involved
all_species <- unique(c(all_data$Sp1, all_data$Sp2))
cat("Species found:", length(all_species), "\n")

results_by_species <- list()

for (focal_species in all_species) {
  cat("\n", rep("=", 70), "\n", sep = "")
  cat("Focal species:", focal_species, "\n")
  cat(rep("=", 70), "\n", sep = "")
  
  # Get all comparisons involving this species
  focal_data <- all_data %>%
    filter(Sp1 == focal_species | Sp2 == focal_species)
  
  # Normalize so focal species gene is always in "FocalGene" column
  focal_normalized <- focal_data %>%
    mutate(
      FocalGene = ifelse(Sp1 == focal_species, Species1, Species2),
      PartnerSpecies = ifelse(Sp1 == focal_species, Sp2, Sp1),
      PartnerGene = ifelse(Sp1 == focal_species, Species2, Species1)
    )
  
  # Count comparisons per focal gene
  n_comparisons <- length(unique(focal_normalized$PartnerSpecies))
  
  cat("Partner species:", n_comparisons, "\n")
  cat("Unique focal genes with conserved co-expression:", 
      length(unique(focal_normalized$FocalGene)), "\n")
  
  # CLIQUE-BASED APPROACH: Find genes where the SAME focal gene + orthogroup
  # combination appears in ALL comparisons (forms a complete clique)
  gene_summary <- focal_normalized %>%
    # Group by both FocalGene AND OrthoGroup to ensure it's the same gene pair/clique
    group_by(FocalGene, OrthoGroup) %>%
    summarise(
      N_comparisons_conserved = n_distinct(PartnerSpecies),
      Partner_species = paste(sort(unique(PartnerSpecies)), collapse = ", "),
      N_orthologs = n_distinct(PartnerGene),
      Partner_genes = paste(sort(unique(PartnerGene)), collapse = ", "),
      Mean_max_pval = mean(Max.p.val),
      .groups = "drop"
    ) %>%
    mutate(
      Conserved_in_all = N_comparisons_conserved == n_comparisons,
      FocalSpecies = focal_species
    ) %>%
    arrange(desc(N_comparisons_conserved), Mean_max_pval)
  
  # Genes conserved in ALL comparisons
  fully_conserved <- gene_summary %>%
    filter(Conserved_in_all)
  
  cat("Gene cliques conserved in ALL", n_comparisons, "comparisons:", 
      nrow(fully_conserved), "\n")
  cat("Unique focal genes in conserved cliques:", 
      n_distinct(fully_conserved$FocalGene), "\n")
  
  if (nrow(fully_conserved) > 0) {
    cat("\nTop 10 conserved gene cliques:\n")
    print(head(fully_conserved %>% 
                 select(FocalGene, OrthoGroup, N_comparisons_conserved, Mean_max_pval, N_orthologs),
               10))
  }
  
  results_by_species[[focal_species]] <- gene_summary
}

# COMBINE RESULTS ==============================================================
cat("\n\n")
cat(rep("=", 70), "\n", sep = "")
cat("SUMMARY\n")
cat(rep("=", 70), "\n\n", sep = "")

all_results <- bind_rows(results_by_species)

# Overall statistics
overall_summary <- all_results %>%
  group_by(FocalSpecies) %>%
  summarise(
    Total_gene_cliques_analyzed = n(),
    Unique_genes_analyzed = n_distinct(FocalGene),
    Gene_cliques_conserved_in_all = sum(Conserved_in_all),
    Unique_genes_in_conserved_cliques = n_distinct(FocalGene[Conserved_in_all]),
    Percent_cliques_conserved = round(100 * sum(Conserved_in_all) / n(), 2),
    .groups = "drop"
  ) %>%
  arrange(desc(Percent_cliques_conserved))

print(overall_summary)

# SAVE RESULTS =================================================================
cat("\n\nSaving results...\n")

# 1. Full results per gene clique
write_tsv(all_results, "gene_conservation_full.tsv")
cat("  1. Full results (gene cliques): gene_conservation_full.tsv\n")

# 2. Only gene cliques conserved in ALL comparisons
conserved_all <- all_results %>%
  filter(Conserved_in_all) %>%
  arrange(FocalSpecies, Mean_max_pval)

write_tsv(conserved_all, "gene_cliques_conserved_in_all_comparisons.tsv")
cat("  2. Gene cliques conserved in ALL: gene_cliques_conserved_in_all_comparisons.tsv\n")

# 3. Summary by species
write_tsv(overall_summary, "conservation_summary_by_species.tsv")
cat("  3. Summary by species: conservation_summary_by_species.tsv\n")

# 4. Simple list of conserved genes by species (unique genes from conserved cliques)
cat("\n  4. Gene lists by species (unique genes from conserved cliques):\n")
for (sp in unique(conserved_all$FocalSpecies)) {
  genes <- conserved_all %>%
    filter(FocalSpecies == sp) %>%
    pull(FocalGene) %>%
    unique() %>%
    sort()
  
  filename <- paste0("conserved_genes_", sp, ".txt")
  writeLines(genes, filename)
  cat("     -", filename, "(", length(genes), "unique genes )\n")
}

# 5. Detailed gene-orthogroup pairs
cat("\n  5. Gene-orthogroup clique pairs:\n")
for (sp in unique(conserved_all$FocalSpecies)) {
  gene_hog_pairs <- conserved_all %>%
    filter(FocalSpecies == sp) %>%
    select(FocalGene, OrthoGroup, N_comparisons_conserved, Mean_max_pval) %>%
    arrange(FocalGene, OrthoGroup)
  
  filename <- paste0("conserved_gene_cliques_", sp, ".tsv")
  write_tsv(gene_hog_pairs, filename)
  cat("     -", filename, "(", nrow(gene_hog_pairs), "cliques )\n")
}

# 6-8. Gene lists by life history strategy
cat("\n  6-8. Gene lists by life history strategy:\n")

annual_species <- c("Vulpia bromoides", "Hordeum vulgare", "Briza maxima", "Brachypodium distachyon")
perennial_species <- c("Festuca pratensis", "Hordeum jubatum", "Briza media", "Brachypodium sylvaticum")

# Get genes from conserved cliques for each habit
annual_genes <- conserved_all %>%
  filter(FocalSpecies %in% annual_species) %>%
  pull(FocalGene) %>%
  unique() %>%
  sort() |>
  str_replace("Bradi", "BRADI_") %>%           # Add underscore after BRADI
  str_replace("\\.v3\\.2$", "v3")

perennial_genes <- conserved_all %>%
  filter(FocalSpecies %in% perennial_species) %>%
  pull(FocalGene) %>%
  unique() %>%
  sort()

# Find exclusive and shared genes
annual_exclusive <- setdiff(annual_genes, perennial_genes)
perennial_exclusive <- setdiff(perennial_genes, annual_genes)
shared_both <- intersect(annual_genes, perennial_genes)

# Write files
writeLines(annual_exclusive, "conserved_genes_annual_exclusive.txt")
cat("     - conserved_genes_annual_exclusive.txt (", length(annual_exclusive), "unique genes )\n")

writeLines(perennial_exclusive, "conserved_genes_perennial_exclusive.txt")
cat("     - conserved_genes_perennial_exclusive.txt (", length(perennial_exclusive), "unique genes )\n")

writeLines(shared_both, "conserved_genes_shared_annual_perennial.txt")



# DETAILED REPORT ==============================================================
report_file <- "gene_conservation_report.txt"
sink(report_file)

cat("Gene Conservation Analysis Report (Clique-Based)\n")
cat(rep("=", 70), "\n\n", sep = "")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("p-value threshold:", P_THRESHOLD, "\n")
cat("Total comparisons analyzed:", length(files), "\n\n")
cat("Analysis approach: Clique-based\n")
cat("  - A clique is defined as the same focal gene + orthogroup combination\n")
cat("  - Conserved cliques must appear in ALL pairwise comparisons\n")
cat("  - This ensures the same gene pair is conserved across all species\n\n")

cat("Summary by Species:\n")
cat(rep("-", 70), "\n", sep = "")
print(overall_summary, row.names = FALSE)

cat("\n\nDetailed Results:\n")
cat(rep("-", 70), "\n\n", sep = "")

for (sp in sort(unique(all_results$FocalSpecies))) {
  cat("\n", sp, "\n")
  cat(rep("~", nchar(sp)), "\n", sep = "")
  
  sp_data <- all_results %>% filter(FocalSpecies == sp)
  sp_conserved <- sp_data %>% filter(Conserved_in_all)
  
  cat("Total gene cliques analyzed:", nrow(sp_data), "\n")
  cat("Unique genes analyzed:", n_distinct(sp_data$FocalGene), "\n")
  cat("Gene cliques conserved in all comparisons:", nrow(sp_conserved), "\n")
  cat("Unique genes in conserved cliques:", n_distinct(sp_conserved$FocalGene), "\n")
  cat("Percentage of cliques conserved:", round(100 * nrow(sp_conserved) / nrow(sp_data), 2), "%\n")
  
  if (nrow(sp_conserved) > 0) {
    cat("\nTop conserved gene cliques:\n")
    print(head(sp_conserved %>% 
                 select(FocalGene, OrthoGroup, N_comparisons_conserved, Mean_max_pval, Partner_genes), 
               20), row.names = FALSE)
  }
  cat("\n")
}

sink()

cat("  6. Detailed report:", report_file, "\n")

# DONE =========================================================================
cat("\n")
cat(rep("=", 70), "\n", sep = "")
cat("ANALYSIS COMPLETE\n")
cat(rep("=", 70), "\n", sep = "")
cat("\nTotal gene cliques conserved across ALL comparisons:", nrow(conserved_all), "\n")
cat("Unique genes in conserved cliques:", n_distinct(conserved_all$FocalGene), "\n")
cat("Check output files for details.\n\n")


#!/usr/bin/env Rscript
library(tidyverse)
library(igraph)
library(furrr)

# Setup parallel processing
plan(multisession, workers = availableCores())

cat("Using", nbrOfWorkers(), "cores\n")

# Load all conserved pairs
files <- list.files("rcomplex_data/results", pattern = "comparison-.*\\.RData$", 
                    recursive = TRUE, full.names = TRUE)

pairs <- map_dfr(files, ~ {
  load(.x, e <- new.env())
  e$comparison %>% 
    rowwise() %>% 
    filter(max(Species1.p.val, Species2.p.val) < 0.05) %>%
    select(OrthoGroup, Species1, Species2)
})

cat("Processing", length(unique(pairs$OrthoGroup)), "HOGs...\n")

# Find cliques in parallel
cliques <- pairs %>%
  group_by(OrthoGroup) %>%
  group_split() %>%
  future_map_dfr(~ {
    g <- graph_from_data_frame(.x[, c("Species1", "Species2")], directed = FALSE)
    cl <- max_cliques(g)
    tibble(
      OrthoGroup = .x$OrthoGroup[1],
      Size = map_int(cl, length),
      Genes = map_chr(cl, ~ paste(sort(names(.x)), collapse = ","))
    )
  }, .progress = TRUE) %>%
  arrange(desc(Size))

write_tsv(cliques, "cliques.tsv")
cat("\nFound", nrow(cliques), "cliques\n")
cat("Size distribution:\n")
print(table(cliques$Size))
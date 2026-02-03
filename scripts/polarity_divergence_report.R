#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(optparse)
  library(tidyverse)
  library(qs2)
})

# Configure qs2 to use available threads (SLURM or detected cores)
qs2_threads <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", parallel::detectCores(logical = FALSE)))
if (is.na(qs2_threads) || qs2_threads < 1L) qs2_threads <- 1L
qopt(nthreads = qs2_threads)
message(sprintf("qs2 configured with %d threads", qs2_threads))

option_list <- list(
  make_option(c("-t","--tissue"), type="character"),
  make_option(c("-p","--pair_id"), type="character"),
  make_option(c("-s","--signed"), type="character"),
  make_option(c("-u","--unsigned"), type="character"),
  make_option(c("-o","--outdir"), type="character", default=".")
)
opt <- parse_args(OptionParser(option_list=option_list))

if (is.null(opt$tissue) || is.null(opt$pair_id) || is.null(opt$signed) || is.null(opt$unsigned)) {
  stop("Missing required arguments: --tissue --pair_id --signed --unsigned")
}

# Load network objects from qs2 files
signed_data <- qs_read(opt$signed)
unsigned_data <- qs_read(opt$unsigned)

# Extract variables from lists
species1_net_signed <- signed_data$species1_net_signed
species2_net_signed <- signed_data$species2_net_signed
species1_name <- signed_data$species1_name
species2_name <- signed_data$species2_name

species1_net_unsigned <- unsigned_data$species1_net_unsigned
species2_net_unsigned <- unsigned_data$species2_net_unsigned

# Helper function to extract edges from a network matrix
extract_edges <- function(obj, mode, species_name) {
  if (is.matrix(obj)) {
    ut <- upper.tri(obj, diag = FALSE)
    df <- tibble(
      species = species_name,
      gene1 = rownames(obj)[row(obj)[ut]],
      gene2 = rownames(obj)[col(obj)[ut]],
      score = obj[ut],
      mode = mode
    )
    return(df)
  } else if (is.list(obj) && !is.null(obj$matrix)) {
    m <- obj$matrix
    ut <- upper.tri(m, diag = FALSE)
    df <- tibble(
      species = species_name,
      gene1 = rownames(m)[row(m)[ut]],
      gene2 = rownames(m)[col(m)[ut]],
      score = m[ut],
      mode = mode
    )
    return(df)
  } else if (is.data.frame(obj)) {
    obj$species <- species_name
    obj$mode <- mode
    return(as_tibble(obj))
  } else {
    stop("Unsupported comparison object structure in ", mode)
  }
}

# Extract edges from BOTH species' networks
sp1_signed_edges <- extract_edges(species1_net_signed, "signed", species1_name)
sp1_unsigned_edges <- extract_edges(species1_net_unsigned, "unsigned", species1_name)
sp2_signed_edges <- extract_edges(species2_net_signed, "signed", species2_name)
sp2_unsigned_edges <- extract_edges(species2_net_unsigned, "unsigned", species2_name)

# Combine species
signed_edges <- bind_rows(sp1_signed_edges, sp2_signed_edges)
unsigned_edges <- bind_rows(sp1_unsigned_edges, sp2_unsigned_edges)

# Join on species + gene pairs
joined <- signed_edges %>%
  inner_join(unsigned_edges, by = c("species", "gene1", "gene2"), suffix = c("_signed", "_unsigned"))

# Classify polarity divergence: sign differs but unsigned strong
joined <- joined %>%
  group_by(species) %>%
  mutate(
    sign_match = sign(score_signed) == sign(score_unsigned),
    strength_unsigned = abs(score_unsigned),
    polarity_divergent = (!sign_match) & (strength_unsigned > quantile(strength_unsigned, 0.75, na.rm = TRUE))
  ) %>%
  ungroup()

out <- joined %>%
  transmute(
    tissue = opt$tissue,
    pair_id = opt$pair_id,
    species,
    gene1,
    gene2,
    score_signed,
    score_unsigned,
    polarity_divergent
  )

outfile <- file.path(opt$outdir, paste0("polarity_divergence_", opt$pair_id, ".tsv"))
readr::write_tsv(out, outfile)
cat("Saved:", outfile, "with", nrow(out), "edges from", n_distinct(out$species), "species\n")

#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(optparse)
  library(tidyverse)
})

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

# Load network objects from RData files
# Signed networks contain: species1_net_signed, species2_net_signed, species1_thr_signed, species2_thr_signed, species1_name, species2_name, ortho
load(opt$signed)
# Unsigned networks contain: species1_net_unsigned, species2_net_unsigned, species1_thr_unsigned, species2_thr_unsigned, species1_name, species2_name, ortho
load(opt$unsigned)

# Use the network matrices for polarity comparison
signed <- species1_net_signed
unsigned <- species1_net_unsigned

# Heuristic: derive edge lists if matrices; otherwise expect data.frames
extract_edges <- function(obj, mode){
  if (is.matrix(obj)) {
    ut <- upper.tri(obj, diag=FALSE)
    df <- tibble(
      gene1 = rownames(obj)[row(obj)[ut]],
      gene2 = rownames(obj)[col(obj)[ut]],
      score = obj[ut],
      mode = mode
    )
    return(df)
  } else if (is.list(obj) && !is.null(obj$matrix)) {
    m <- obj$matrix
    ut <- upper.tri(m, diag=FALSE)
    df <- tibble(
      gene1 = rownames(m)[row(m)[ut]],
      gene2 = rownames(m)[col(m)[ut]],
      score = m[ut],
      mode = mode
    )
    return(df)
  } else if (is.data.frame(obj)) {
    obj$mode <- mode
    return(as_tibble(obj))
  } else {
    stop("Unsupported comparison object structure in ", mode)
  }
}

signed_edges <- extract_edges(signed, "signed")
unsigned_edges <- extract_edges(unsigned, "unsigned")

# Join on gene pairs
joined <- signed_edges %>% inner_join(unsigned_edges, by=c("gene1","gene2"), suffix=c("_signed","_unsigned"))

# Classify polarity divergence: sign differs but unsigned strong
joined <- joined %>% mutate(
  # Check if signs match between signed and unsigned scores
  sign_match = sign(score_signed) == sign(score_unsigned),
  # unsigned score uses absolute strength
  strength_unsigned = abs(score_unsigned),
  polarity_divergent = (!sign_match) & (strength_unsigned > quantile(strength_unsigned, 0.75, na.rm=TRUE))
)

out <- joined %>% transmute(
  tissue = opt$tissue,
  pair_id = opt$pair_id,
  gene1, gene2,
  score_signed, score_unsigned,
  polarity_divergent
)

outfile <- file.path(opt$outdir, paste0("polarity_divergence_", opt$pair_id, ".tsv"))
readr::write_tsv(out, outfile)
cat("Saved:", outfile, "\n")

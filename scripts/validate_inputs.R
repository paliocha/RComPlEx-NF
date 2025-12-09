#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(yaml)
  library(optparse)
})

#' Resolve paths that may exist at alternative mount points (Orion HPC workaround)
#' On Orion, NFS is mounted at both /net/fs-2/... and /mnt/users/...
#' Nextflow canonicalizes to /net/fs-2/... but compute nodes can only see /mnt/users/...
resolve_path_orion <- function(path) {
  # Try the path as-is first
  if (file.exists(path)) return(path)

  # Try substituting /net/fs-2 with /mnt/users
  alt_path <- sub("^/net/fs-2/scale/OrionStore/Home/", "/mnt/users/", path)
  if (file.exists(alt_path)) return(alt_path)

  # If neither works, return original and let it fail with clear error
  path
}

validate_pipeline_inputs <- function(config_path, workdir) {
  # Resolve paths for Orion HPC multi-mount NFS
  config_path <- resolve_path_orion(config_path)
  workdir <- resolve_path_orion(workdir)

  config <- read_yaml(config_path)

  # Check data files exist
  vst_file <- file.path(workdir, config$data$vst_file)
  n1_file <- file.path(workdir, config$data$n1_file)

  if (!file.exists(vst_file)) stop("Missing: ", vst_file)
  if (!file.exists(n1_file)) stop("Missing: ", n1_file)

  # Load data to infer valid values
  vst <- readRDS(vst_file)
  n1 <- readRDS(n1_file)

  # Infer valid tissues and species from data
  valid_tissues <- sort(unique(vst$tissue))
  valid_species <- sort(unique(n1$species))

  # Get requested values from config
  requested_tissues <- config$tissues
  requested_species <- c(config$species$annual, config$species$perennial)

  # Validate tissues
  invalid_tissues <- setdiff(requested_tissues, valid_tissues)
  if (length(invalid_tissues) > 0) {
    stop("Invalid tissues in config: ", paste(invalid_tissues, collapse=", "),
         "\nAvailable in data: ", paste(valid_tissues, collapse=", "))
  }

  # Validate species
  invalid_species <- setdiff(requested_species, valid_species)
  if (length(invalid_species) > 0) {
    stop("Invalid species in config: ", paste(invalid_species, collapse=", "),
         "\nAvailable in data: ", paste(valid_species, collapse=", "))
  }

  # Warn about missing tissue-species combinations
  for (tissue in requested_tissues) {
    tissue_data <- vst[vst$tissue == tissue, ]
    tissue_species <- unique(tissue_data$species)
    missing <- setdiff(requested_species, tissue_species)
    if (length(missing) > 0) {
      warning("Tissue '", tissue, "' missing ", length(missing), " species: ",
              paste(head(missing, 3), collapse=", "))
    }
  }

  cat("✓ Validation passed\n")
  cat("  Tissues: ", paste(requested_tissues, collapse=", "), "\n")
  cat("  Species: ", length(requested_species), " (",
      length(config$species$annual), " annual, ",
      length(config$species$perennial), " perennial)\n", sep="")
  invisible(TRUE)
}

# Parse command line arguments
opts <- parse_args(OptionParser(option_list=list(
  make_option("--config", default="config/pipeline_config.yaml"),
  make_option("--workdir", default=".")
)))

# Run validation
validate_pipeline_inputs(opts$config, opts$workdir)
#!/usr/bin/env Rscript
# =============================================================================
# RComPlEx Configuration Parser
# =============================================================================
# Reads and validates pipeline configuration from YAML file
# =============================================================================

library(yaml)

#' Load and validate pipeline configuration
#'
#' @param config_file Path to YAML configuration file
#' @param workdir Working directory for resolving relative paths (default: current directory)
#' @return List containing validated configuration parameters
#' @export
load_config <- function(config_file = "config/pipeline_config.yaml", workdir = ".") {

  if (!file.exists(config_file)) {
    stop("Configuration file not found: ", config_file)
  }

  cat("Loading configuration from:", config_file, "\n")
  config <- yaml::read_yaml(config_file)

  # Validate required sections
  required_sections <- c("data", "species", "tissues", "rcomplex", "cliques", "resources")
  missing <- setdiff(required_sections, names(config))
  if (length(missing) > 0) {
    stop("Missing required configuration sections: ", paste(missing, collapse = ", "))
  }

  # Convert relative data file paths to absolute using workdir
  if (!startsWith(config$data$vst_file, "/")) {
    config$data$vst_file <- file.path(workdir, config$data$vst_file)
  }
  if (!startsWith(config$data$n1_file, "/")) {
    config$data$n1_file <- file.path(workdir, config$data$n1_file)
  }
  if (!startsWith(config$data$output_dir, "/")) {
    config$data$output_dir <- file.path(workdir, config$data$output_dir)
  }

  # Validate data files exist (AFTER path resolution)
  if (!file.exists(config$data$vst_file)) {
    stop("VST data file not found: ", config$data$vst_file)
  }
  if (!file.exists(config$data$n1_file)) {
    stop("N1 orthogroup file not found: ", config$data$n1_file)
  }

  # Validate species lists
  if (length(config$species$annual) == 0) {
    stop("No annual species specified in configuration")
  }
  if (length(config$species$perennial) == 0) {
    stop("No perennial species specified in configuration")
  }

  # Check for species overlap
  overlap <- intersect(config$species$annual, config$species$perennial)
  if (length(overlap) > 0) {
    warning("Species appear in both annual and perennial lists: ",
            paste(overlap, collapse = ", "))
  }

  # Validate tissues
  if (length(config$tissues) == 0) {
    stop("No tissues specified in configuration")
  }

  # Validate RComPlEx parameters
  if (!config$rcomplex$cor_method %in% c("spearman", "pearson", "kendall")) {
    stop("Invalid correlation method: ", config$rcomplex$cor_method)
  }
  if (!config$rcomplex$norm_method %in% c("MR", "CLR")) {
    stop("Invalid normalization method: ", config$rcomplex$norm_method)
  }
  if (config$rcomplex$density_thr <= 0 || config$rcomplex$density_thr >= 1) {
    stop("Density threshold must be between 0 and 1, got: ", config$rcomplex$density_thr)
  }
  if (config$rcomplex$p_threshold <= 0 || config$rcomplex$p_threshold > 1) {
    stop("P-value threshold must be between 0 and 1, got: ", config$rcomplex$p_threshold)
  }

  cat("✓ Configuration loaded and validated successfully\n")
  cat("  - Annual species:", length(config$species$annual), "\n")
  cat("  - Perennial species:", length(config$species$perennial), "\n")
  cat("  - Tissues:", paste(config$tissues, collapse = ", "), "\n")
  cat("  - Correlation method:", config$rcomplex$cor_method, "\n")
  cat("  - Normalization method:", config$rcomplex$norm_method, "\n")
  cat("  - Network density:", config$rcomplex$density_thr * 100, "%\n")
  cat("  - P-value threshold:", config$rcomplex$p_threshold, "\n")

  return(config)
}

#' Get species list by life cycle
#'
#' @param config Configuration list from load_config()
#' @param life_cycle "annual" or "perennial"
#' @return Character vector of species names
#' @export
get_species <- function(config, life_cycle = c("annual", "perennial")) {
  life_cycle <- match.arg(life_cycle)
  return(config$species[[life_cycle]])
}

#' Get all species
#'
#' @param config Configuration list from load_config()
#' @return Character vector of all species names
#' @export
get_all_species <- function(config) {
  return(c(config$species$annual, config$species$perennial))
}

#' Check if a tissue is valid
#'
#' @param config Configuration list from load_config()
#' @param tissue Tissue name to validate
#' @return Logical indicating if tissue is valid
#' @export
is_valid_tissue <- function(config, tissue) {
  return(tissue %in% config$tissues)
}

#' Get RComPlEx parameters as named list
#'
#' @param config Configuration list from load_config()
#' @return Named list of RComPlEx parameters
#' @export
get_rcomplex_params <- function(config) {
  return(config$rcomplex)
}

#' Create output directory structure for a tissue
#'
#' @param config Configuration list from load_config()
#' @param tissue Tissue name
#' @export
create_output_dirs <- function(config, tissue) {

  if (!is_valid_tissue(config, tissue)) {
    stop("Invalid tissue: ", tissue)
  }

  base_dir <- file.path(config$data$output_dir, tissue)
  pairs_dir <- file.path(base_dir, "pairs")
  results_dir <- file.path(base_dir, "results")

  dir.create(base_dir, showWarnings = FALSE, recursive = TRUE)
  dir.create(pairs_dir, showWarnings = FALSE, recursive = TRUE)
  dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

  cat("Created output directories for tissue:", tissue, "\n")
  cat("  - Base:", base_dir, "\n")
  cat("  - Pairs:", pairs_dir, "\n")
  cat("  - Results:", results_dir, "\n")

  invisible(list(
    base = base_dir,
    pairs = pairs_dir,
    results = results_dir
  ))
}

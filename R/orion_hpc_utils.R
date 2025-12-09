# Orion HPC Path Resolution Utilities
# ====================================
# Handles dual NFS mount points on Orion HPC cluster
# Maps /net/fs-2/scale/OrionStore/Home/... to /mnt/users/...

#' Resolve Orion HPC Path
#'
#' @description
#' Translates paths from canonical NFS mount (/net/fs-2) to accessible mount (/mnt/users)
#' on Orion HPC compute nodes. This is necessary because Nextflow canonicalizes all paths
#' to /net/fs-2, but compute nodes can only access /mnt/users mount point.
#'
#' @param path Character: Path to resolve. If it uses /net/fs-2 and doesn't exist locally,
#'             tries the /mnt/users alternative.
#'
#' @return Character: The resolved path (original if accessible, translated if alternative exists)
#'
#' @examples
#' \dontrun{
#'   path <- "/net/fs-2/scale/OrionStore/Home/martpali/data/input.RDS"
#'   actual_path <- resolve_orion_path(path)
#'   # Returns: /mnt/users/martpali/data/input.RDS
#' }
#'
#' @export
resolve_orion_path <- function(path) {
  # If path doesn't exist and uses /net/fs-2, try /mnt/users alternative
  if (!file.exists(path) && grepl("^/net/fs-2", path)) {
    alt_path <- sub("^/net/fs-2/scale/OrionStore/Home/", "/mnt/users/", path)
    if (file.exists(alt_path)) {
      return(alt_path)
    }
  }
  # Return original path (either it exists or we can't resolve it)
  path
}

#' Resolve Multiple Orion HPC Paths
#'
#' @description
#' Apply resolve_orion_path to a vector of paths.
#'
#' @param paths Character vector: Paths to resolve
#'
#' @return Character vector: Resolved paths
#'
#' @export
resolve_orion_paths <- function(paths) {
  sapply(paths, resolve_orion_path, USE.NAMES = FALSE)
}

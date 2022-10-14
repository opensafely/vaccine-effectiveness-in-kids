# source another script with arguments
source_with_args <- function(file, ...) {
    system(paste("Rscript", file, ...))
}

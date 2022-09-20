
# # # # # # # # # # # # # # # # # # # # #
# Purpose: To gather level 4 files ("moderately sensitive") place in a single directory for easy review and release
# # # # # # # # # # # # # # # # # # # # #

## Import libraries ----
library('tidyverse')
library('here')
library('glue')
library('survival')



## post-matching ----

for(cohort in c("over12", "under12")){

  input_dir <- ghere("output", cohort, "models", "km", "combined")
  output_dir <- here("output", "release-objects", cohort)
  fs::dir_create(output_dir)


  ## table1 ----

  fs::file_copy(here("output", cohort, "table1", "coverage.csv"), fs::path(output_dir, "coverage.csv"), overwrite = TRUE)
  fs::file_copy(here("output", cohort, "table1", "table1.csv"), fs::path(output_dir, "table1.csv"), overwrite = TRUE)
  # fs::file_copy(here("output", cohort, "table1", "flowchart.csv"), fs::path(output_dir, "match_flowchart.csv"), overwrite = TRUE)

  ## KM ----
  fs::file_copy(fs::file_path(input_dir, "km_estimates_rounded.csv"), fs::path(output_dir, "km_estimates_rounded.csv"), overwrite = TRUE)
  fs::file_copy(fs::file_path(input_dir, "contrasts_cuts_rounded.csv"), fs::path(output_dir, "contrasts_cuts_rounded.csv"), overwrite = TRUE)
  fs::file_copy(fs::file_path(input_dir, "contrasts_overall_rounded.csv"), fs::path(output_dir, "contrasts_overall_rounded.csv"), overwrite = TRUE)
}

## create text for output review issue ----
fs::dir_ls(here("output", "release-objects"), type="file", recurse=TRUE) %>%
  map_chr(~str_remove(., fixed(here()))) %>%
  map_chr(~paste0("- [ ] ", str_remove(.,fixed("/")))) %>%
  paste(collapse="\n") %>%
  writeLines(here("output", "files-for-release.txt"))


## create command for releasing using osrelease ----
fs::dir_ls(here("output", "release-objects"), type="file", recurse=TRUE) %>%
  map_chr(~str_remove(., fixed(here()))) %>%
  #map_chr(~paste0("'",. ,"'")) %>%
  paste(., collapse=" ") %>%
  paste("osrelease", .) %>%
  writeLines(here("output", "osrelease-command.txt"))


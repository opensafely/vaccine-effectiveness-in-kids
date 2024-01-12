# # # # # # # # # # # # # # # # # # # # #
# Purpose: Removes km estimates from different outcomes
#          when there are fewer than 11 events.
#
# # # # # # # # # # # # # # # # # # # # #

# Preliminaries ----

## Import libraries ----
library("tidyverse")
library("here")
library("glue")
library("survival")

## Import custom user functions from lib
source(here("lib", "functions", "utility.R"))

## Import design elements
source(here("analysis", "design.R"))

output_dir <- here("output", "release")
fs::dir_create(here("output", "release", "redacted"))

for (cohort in c("over12", "under12")) {
  for (vaxn in c(1L, 2L)) {
    km_estimate <- read_csv(fs::path(output_dir, glue("{cohort}_{vaxn}_km_estimates_rounded.csv")))

    km_estimate_filter <- km_estimate %>%
      filter(
        time == max(time),
        cml.event < 27
      )

    km_estimate <- km_estimate %>%
      anti_join(km_estimate_filter, by = c("outcome", "subgroup", "subgroup_level", "treated"))

    write_csv(km_estimate, fs::path(output_dir, glue("redacted/{cohort}_{vaxn}_km_estimates_rounded_redacted.csv")))
    write_csv(km_estimate_filter, fs::path(output_dir, glue("redacted/{cohort}_{vaxn}_km_estimates_rounded_endonly.csv")))
  }
}

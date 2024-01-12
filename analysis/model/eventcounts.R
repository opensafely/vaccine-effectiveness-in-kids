# # # # # # # # # # # # # # # # # # # # #
# Purpose: report count of
#  - import matched data
#  - reports rate of tests and positive tests
#  - The script must be accompanied by two arguments:
#    `cohort` - over12s or under12s
#    `outcome` - the dependent variable

# # # # # # # # # # # # # # # # # # # # #

# Preliminaries ----


## Import libraries ----
library("tidyverse")
library("here")
library("glue")
library("survival")


## import local functions and parameters ---

source(here("analysis", "design.R"))
source(here("lib", "functions", "utility.R"))
source(here("lib", "functions", "survival.R"))


# import command-line arguments ----

args <- commandArgs(trailingOnly = TRUE)


if (length(args) == 0) {
  # use for interactive testing
  removeobjects <- FALSE
  cohort <- "over12"
  vaxn <- as.integer("2")
  subgroup <- "all"
} else {
  removeobjects <- TRUE
  cohort <- args[[1]]
  vaxn <- as.integer(args[[2]])
  subgroup <- args[[3]]
}


## get cohort-specific parameters study dates and parameters ----

dates <- map(study_dates[[cohort]], as.Date)
params <- study_params[[cohort]]

# derive symbolic arguments for programming with

cohort_sym <- sym(cohort)
subgroup_sym <- sym(subgroup)

# create output directories ----

output_dir <- ghere("output", cohort, "vax{vaxn}", "models", "eventcounts", subgroup)
fs::dir_create(output_dir)


data_matched <- read_rds(ghere("output", cohort, "vax{vaxn}", "match", "data_matched.rds"))

## import baseline data, restrict to matched individuals and derive time-to-event variables
data_matched <-
  data_matched %>%
  mutate(all = "all") %>%
  select(
    # select only variables needed for models to save space
    patient_id, treated, trial_date, match_id,
    death_date, dereg_date,
    subgroup, ends_with("_count")
  ) %>%
  mutate(
    censor_date = pmin(
      dereg_date,
      # vax2_date-1, # -1 because we assume vax occurs at the start of the day
      death_date,
      dates[[c(glue("followupend_date{vaxn}"))]],
      trial_date + maxfup - 1,
      na.rm = TRUE
    ),
    censor_date = trial_date + maxfup - 1 # use this to overwrite above definition until issue with `patients.minimum_of()` and date arithmetic is fixed
  )

# report number of tests ----


data_counts <- data_matched %>%
  group_by(treated, !!subgroup_sym) %>%
  summarise(
    n = roundmid_any(n(), threshold),
    persontime = roundmid_any(sum(as.numeric(censor_date - (trial_date - 1))), threshold),
    sum_test_count = roundmid_any(sum(test_count), threshold),
    test_rate = sum_test_count / persontime,
    sum_postest_count = roundmid_any(sum(postest_count), threshold),
    postest_rate = sum_postest_count / persontime,
  )

write_rds(data_counts, fs::path(output_dir, "testcounts.rds"))

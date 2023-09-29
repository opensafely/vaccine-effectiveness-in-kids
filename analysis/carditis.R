# # # # # # # # # # # # # # # # # # # # #
# Purpose: Get initial information on severity of carditis events
#  - import matched data

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
  subgroup <- "prior_covid_infection"
  outcome <- "postest"
} else {
  removeobjects <- TRUE
  cohort <- args[[1]]
  vaxn <- as.integer(args[[2]])
}

## get cohort-specific parameters study dates and parameters ----

dates <- map(study_dates[[cohort]], as.Date)
params <- study_params[[cohort]]

# derive symbolic arguments for programming with

# create output directories ----

output_dir <- ghere("output", cohort, "vax{vaxn}", "carditis_severity")
fs::dir_create(output_dir)


data_matched <- read_rds(ghere("output", cohort, "vax{vaxn}", "match", "data_matched.rds"))

data_matched_myocarditis <- data_matched %>%
  filter(!is.na(myocarditis_date)) %>%
  summarise(
    treated,
    myocarditis_date,
    emergency_date,
    admitted_unplanned_date,
    emergencyhosp_date,
    death_date,
  ) %>%
  mutate(across(ends_with("date"), ~ as.integer(!is.na(.)))) %>%
  summarise(myocarditis = sum(myocarditis_date),
    across(
    ends_with("date"),
    ~ sum(.x) / myocarditis * 100
  ))

write_csv(data_matched_myocarditis, fs::path(output_dir, "myocarditis_severity.csv"))

data_matched_pericarditis <- data_matched %>%
  filter(!is.na(pericarditis_date)) %>%
  summarise(
    treated,
    pericarditis_date,
    emergency_date,
    admitted_unplanned_date,
    emergencyhosp_date,
    death_date,
  ) %>%
  mutate(across(ends_with("date"), ~ as.integer(!is.na(.)))) %>%
  summarise(pericarditis =  sum(pericarditis_date),
            across(
    ends_with("date"),
    ~ sum(.x) / pericarditis * 100
  ))

write_csv(data_matched_pericarditis, fs::path(output_dir, "pericarditis_severity.csv"))


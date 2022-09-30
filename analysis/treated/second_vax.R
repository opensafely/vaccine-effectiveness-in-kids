######################################
# This script:
# imports data extracted by the cohort extractor (or dummy data)
# summarises the time to second vaccination in days
#
######################################

# Preliminaries ----

## Import libraries ----
library("tidyverse")
library("lubridate")
library("arrow")
library("here")
library("glue")

## import local functions and parameters ---

source(here("analysis", "design.R"))

source(here("lib", "functions", "utility.R"))


## import command-line arguments ----

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
    # use for interactive testing
    removeobjects <- FALSE
    cohort <- "over12"
} else {
    # FIXME replace with actual eventual action variables
    removeobjects <- TRUE
    cohort <- args[[1]]
}
## create output directory ----
fs::dir_create(here("output", cohort, "treated"))



data_extract <- read_feather(ghere("output", cohort, "extract", "input_treated.feather")) %>%
    # because date types are not returned consistently by cohort extractor
    mutate(across(ends_with("_date"), as.Date))



vax_2_dist <- data_extract %>%
    mutate(
        has_gap_vax12 = (covid_vax_any_2_date >= (covid_vax_any_1_date + 17) & !is.na(covid_vax_any_2_date)), # at least 17 days between first two vaccinations
        vaxgap12 = case_when(has_gap_vax12 ~ covid_vax_any_2_date - covid_vax_any_1_date)
    ) %>%
    summarise(
        n = length(vaxgap12),
        n_nonmiss = sum(!is.na(vaxgap12)),
        pct_nonmiss = sum(!is.na(vaxgap12)) / length(vaxgap12),
        n_miss = sum(is.na(vaxgap12)),
        pct_miss = sum(is.na(vaxgap12)) / length(vaxgap12),
        mean = mean(vaxgap12, na.rm = TRUE),
        sd = sd(vaxgap12, na.rm = TRUE),
        min = min(vaxgap12, na.rm = TRUE),
        p10 = quantile(vaxgap12, p = 0.1, na.rm = TRUE, type = 1),
        p25 = quantile(vaxgap12, p = 0.25, na.rm = TRUE, type = 1),
        p50 = quantile(vaxgap12, p = 0.5, na.rm = TRUE, type = 1),
        p75 = quantile(vaxgap12, p = 0.75, na.rm = TRUE, type = 1),
        p90 = quantile(vaxgap12, p = 0.9, na.rm = TRUE, type = 1),
        max = max(vaxgap12, na.rm = TRUE),
        unique = n_distinct(vaxgap12, na.rm = TRUE),
        n_max = sum(vaxgap12 == max),
        n_min = sum(vaxgap12 == min)
    ) %>%
    mutate(
        min = case_when(n_min >= 5 ~ min),
        max = case_when(n_max >= 5 ~ max),
        n_min = case_when(n_min >= 5 ~ min),
        n_max = case_when(n_max >= 5 ~ max),
    )

write_csv(vax_2_dist, ghere("output", cohort, "treated", "vaxgap12.csv"))

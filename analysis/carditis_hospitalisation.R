# # # # # # # # # # # # # # # # # # # # #
# Purpose: Get information on severity of carditis events
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
library("arrow")
library('reshape2')

## import local functions and parameters ---

source(here("analysis", "design.R"))

source(here("lib", "functions", "utility.R"))

# import command-line arguments ----

args <- commandArgs(trailingOnly = TRUE)


if (length(args) == 0) {
  # use for interactive testing
  removeobjects <- FALSE
  cohort <- "over12"
  vaxn <- as.integer("1")
} else {
  removeobjects <- TRUE
  cohort <- args[[1]]
  vaxn <- as.integer(args[[2]])
}

# create output directories ----

output_dir <- ghere("output", cohort, "vax{vaxn}", "carditis_severity")
fs::dir_create(output_dir)


## myocarditis
myo_data_extract <- read_feather(ghere("output", cohort, "vax{vaxn}", "extract", "input_myocarditis_severity.feather"))

spell_length <- myo_data_extract %>%
  mutate(
    admission_length_1 = difftime(discharge_date_1, admission_date_1, unit = "days"),
    admission_length_2 = difftime(discharge_date_2, admission_date_2, unit = "days"),
    admission_length_3 = difftime(discharge_date_3, admission_date_3, unit = "days")
  ) %>%
  summarise(
    admission_length_1 = range(admission_length_1, na.rm = T),
    admission_length_2 = range(admission_length_2, na.rm = T),
    admission_length_3 = range(admission_length_3, na.rm = T),
    critical_care_days_1 = range(as.numeric(critical_care_days_1), na.rm = T),
    critical_care_days_2 = range(as.numeric(critical_care_days_2), na.rm = T),
    critical_care_days_3 = range(as.numeric(critical_care_days_3), na.rm = T)
  )

write_csv(spell_length, fs::path(output_dir, "myo_spell_length_ranges_tables.csv"))

diagnosis <- myo_data_extract %>%
  select(contains("primary_diagnosis")) %>%
  gather(primary_diagnosis, val) %>%
  group_by(primary_diagnosis, val) %>%
  count()

write_csv(diagnosis, fs::path(output_dir, "myo_diagnosis_tables.csv"))

admitted <- myo_data_extract %>%
  summarise(
    n = n(),
    myocarditis_emergency = sum(myocarditis_emergency) / n * 100,
    admitted_to_hospital = sum(!is.na(admission_date_1)) / n * 100,
    critical_care = sum(!is.na(critical_care_days_1)) / n * 100
  )

write_csv(admitted, fs::path(output_dir, "myo_admitted_tables.csv"))


## pericarditis
peri_data_extract <- read_feather(ghere("output", cohort, "vax{vaxn}", "extract", "input_pericarditis_severity.feather"))

spell_length <- peri_data_extract %>%
  mutate(
    admission_days_1 = as.numeric(difftime(discharge_date_1, admission_date_1, unit = "days")),
    admission_days_2 = as.numeric(difftime(discharge_date_2, admission_date_2, unit = "days")),
    admission_days_3 = as.numeric(difftime(discharge_date_3, admission_date_3, unit = "days"))
  )  %>%
  select(contains("days")) %>%
  mutate_if(is.factor,as.numeric) %>%
  pivot_longer(cols = contains("days"),
               names_to = "length",
            #   names_prefix = "wk",
               values_to = "rank",
               values_drop_na = F) %>%
  group_by(length) %>%
  summarise(across(contains("rank"),.fns = 
                     list(min = ~min(.,na.rm = T),
                          median = ~median(.,na.rm = T),
                          mean = ~mean(.,na.rm = T),
                          stdev = ~sd(.,na.rm = T),
                          q25 = ~quantile(., 0.25,na.rm = T),
                          q75 = ~quantile(., 0.75,na.rm = T),
                          max = ~max(.,na.rm = T))))

write_csv(spell_length, fs::path(output_dir, "peri_spell_length_ranges_tables.csv"))

diagnosis <- peri_data_extract %>%
  select(contains("primary_diagnosis")) %>%
  gather(primary_diagnosis, val) %>%
  group_by(primary_diagnosis, val) %>%
  count()

write_csv(diagnosis, fs::path(output_dir, "peri_diagnosis_tables.csv"))

admitted <- peri_data_extract %>%
  summarise(
    n = n(),
    pericarditis_emergency = sum(pericarditis_emergency) / n * 100,
    admitted_to_hospital = sum(!is.na(admission_date_1)) / n * 100,
    critical_care = sum(!is.na(critical_care_days_1)) / n * 100
  )

write_csv(admitted, fs::path(output_dir, "peri_admitted_tables.csv"))

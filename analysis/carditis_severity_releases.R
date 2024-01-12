## Import libraries ----
library("tidyverse")
library("here")
library("glue")
library("survival")

## Import custom user functions from lib
source(here("lib", "functions", "utility.R"))

## Import design elements
source(here("analysis", "design.R"))

output_dir <- ghere("output", "release_{Sys.Date()}")
fs::dir_create(output_dir)
df <- NULL
for (cohort in c("over12", "under12")) {
  for (vaxn in c(1L, 2L, 3L)) {
    dfappend <- NULL
    input_dir <- ghere("output", cohort, "vax{vaxn}", "carditis_severity")
    if (file.exists(fs::path(input_dir, "peri_admitted_tables.csv"))) {
      peri_admitted <- read_csv(fs::path(input_dir, "peri_admitted_tables.csv"))
      dfappend <- dfappend %>%
        bind_cols(
          cohort = paste0(cohort, "_", vaxn),
          peri_n = peri_admitted$n,
          peri_emergency = peri_admitted$pericarditis_emergency,
          peri_admitted = peri_admitted$admitted_to_hospital,
          peri_critical = peri_admitted$critical_care
        )
      peri_length <- read_csv(fs::path(input_dir, "peri_spell_length_ranges_tables.csv"))
      print(paste0(cohort, vaxn))
      dfappend <- dfappend %>%
        bind_cols(
          peri_length %>%
            filter(stringr::str_detect(length,"critical")) %>%
            summarise(peri_critical_maxlength = max(rank_max))
        )
      dfappend <- dfappend %>%
        bind_cols(
          peri_length %>%
            filter(stringr::str_detect(length,"admission")) %>%
            summarise(peri_admission_maxlength = max(rank_max))
        )
    }

    if (file.exists(fs::path(input_dir, "myo_admitted_tables.csv"))) {
      myo_admitted <- read_csv(fs::path(input_dir, "myo_admitted_tables.csv"))
      dfappend <- dfappend %>%
        bind_cols(
          myo_n = myo_admitted$n,
          myo_emergency = myo_admitted$myocarditis_emergency,
          myo_admitted = myo_admitted$admitted_to_hospital,
          myo_critical = myo_admitted$critical_care
        )
      myo_length <- read_csv(fs::path(input_dir, "myo_spell_length_ranges_tables.csv"))
      print(paste0(cohort, vaxn))
      dfappend <- dfappend %>%
        bind_cols(
          myo_length %>%
            filter(stringr::str_detect(length,"critical")) %>%
            summarise(myo_critical_maxlength = max(rank_max))
        )
      dfappend <- dfappend %>%
        bind_cols(
          myo_length %>%
            filter(stringr::str_detect(length,"admission")) %>%
            summarise(myo_admission_maxlength = max(rank_max))
        )
    }
    df <- df %>% bind_rows(dfappend)
  }
}



df_disclosive <- df %>%
  mutate(
    peri_emergency = peri_n * peri_emergency / 100,
    peri_admitted = peri_n * peri_admitted / 100,
    peri_critical = peri_n * peri_critical / 100,
    myo_emergency = myo_n * myo_emergency / 100,
    myo_admitted = myo_n * myo_admitted / 100,
    myo_critical = myo_n * myo_critical / 100,
  )

write_csv(df_disclosive, fs::path(output_dir, "full_disclosure_carditis_severity.csv"))


df_ig_disc <- df %>%
  mutate(
    peri_n = roundmid_any(peri_n, threshold),
    peri_emergency = case_when(
      peri_emergency == 0 ~ "none",
      peri_emergency < 51 ~ "less than 51%",
      peri_emergency > 51 ~ "52% or more",
      peri_emergency == 100 ~ "all"
    ),
    peri_admitted = case_when(
      peri_admitted == 0 ~ "none",
      peri_admitted < 51 ~ "less than 51%",
      peri_admitted > 51 ~ "52% or more",
      peri_admitted == 100 ~ "all"
    ),
    peri_critical = case_when(
      peri_critical == 0 ~ "none",
      peri_critical < 51 ~ "less than 51%",
      peri_critical > 51 ~ "52% or more",
      peri_critical == 100 ~ "all"
    ),
    myo_n = roundmid_any(myo_n, threshold),
    myo_emergency = case_when(
      myo_emergency == 0 ~ "none",
      myo_emergency < 51 ~ "less than 51%",
      myo_emergency > 51 ~ "52% or more",
      myo_emergency == 100 ~ "all"
    ),
    myo_admitted = case_when(
      myo_admitted == 0 ~ "none",
      myo_admitted < 51 ~ "less than 51%",
      myo_admitted > 51 ~ "52% or more",
      myo_admitted == 100 ~ "all"
    ),
    myo_critical = case_when(
      myo_critical == 0 ~ "none",
      myo_critical < 51 ~ "less than 51%",
      myo_critical > 51 ~ "52% or more",
      myo_critical == 100 ~ "all"
    )
  )

write_csv(df_ig_disc, fs::path(output_dir, "ig_discussion_carditis_severity.csv"))

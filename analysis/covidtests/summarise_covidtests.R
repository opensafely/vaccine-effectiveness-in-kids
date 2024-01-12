library(tidyverse)
library(here)
library(glue)

## import local functions and parameters ---

source(here("analysis", "design.R"))

source(here("lib", "functions", "utility.R"))

## import command-line arguments ----

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  cohort <- "under12"
  vaxn <- 2L
  subgroup <- "all"
} else {
  cohort <- args[[1]]
  vaxn <- args[[2]]
  subgroup <- args[[3]]
}

if (Sys.getenv("OPENSAFELY_BACKEND") %in% c("")) {
  ## Import released data ----
  release_dir <- ""

  output_dir <- here("output", release_dir, "figures")
  fs::dir_create(output_dir)

  raw_stats_redacted <- read_csv(fs::path(release_dir, "covidtest_rates.csv"))
} else {
  output_dir <- ghere("output", cohort, "vax{vaxn}", "covidtests", "summary", subgroup)
  fs::dir_create(output_dir)

  ## import data ---
  data_anytest_sum <- read_rds(ghere("output", cohort, "vax{vaxn}", "covidtests", "process", "data_anytest_sum.rds")) %>%
    mutate(across(treated, as.factor))

  subgroup_sym <- sym(subgroup)

  # calculate rates ----

  data_rates <- data_anytest_sum %>%
    mutate(all = "all") %>%
    group_by(treated, anytest_cut, !!subgroup_sym) %>%
    summarise(
      n = roundmid_any(n(), threshold),
      total_persondays = case_when(n > 6 ~ roundmid_any(sum(persondays), threshold)),
      sum_anytest = case_when(sum(sum_anytest) > 6 ~ roundmid_any(sum(sum_anytest), threshold)),
      anytest_rate = case_when(sum_anytest > 6 ~ sum_anytest / total_persondays),
      sum_symptomatic = case_when(sum(sum_symptomatic) > 6 ~ roundmid_any(sum(sum_symptomatic), threshold)),
      symptomatic_rate = case_when(sum_symptomatic > 6 ~ sum_symptomatic / total_persondays),
      sum_postest = case_when(sum(sum_postest) > 6 ~ roundmid_any(sum(sum_postest), threshold)),
      postest_rate = case_when(sum_postest > 6 ~ sum_postest / total_persondays),
      sum_firstpostest = case_when(sum(sum_firstpostest) > 6 ~ roundmid_any(sum(sum_firstpostest), threshold)),
      firstpostest_rate = case_when(sum_firstpostest > 6 ~ sum_firstpostest / total_persondays),
      sum_lftonly = case_when(sum(sum_lftonly) > 6 ~ roundmid_any(sum(sum_lftonly), threshold)),
      lftonly_rate = case_when(sum_lftonly > 6 ~ sum_lftonly / total_persondays),
      sum_pcronly = case_when(sum(sum_pcronly) > 6 ~ roundmid_any(sum(sum_pcronly), threshold)),
      pcronly_rate = case_when(sum_pcronly > 6 ~ sum_pcronly / total_persondays),
      sum_both = case_when(sum(sum_both) > 6 ~ roundmid_any(sum(sum_both), threshold)),
      both_rate = case_when(sum_both > 6 ~ sum_both / total_persondays),
      .groups = "keep"
    ) %>%
    mutate(n = case_when(n > 6 ~ n))
  write_csv(data_rates, fs::path(output_dir, "covidtest_rates.csv"))
}

# plot covidtest_rates ----

rates <- c(
  "Any SARS-CoV-2 test" = "anytest",
  "SARS-CoV-2 test for symptomatic case" = "symptomatic",
  "Positive SARS-CoV-2 test" = "postest",
  "First positive SARS-CoV-2 test" = "firstpostest",
  "PCR only" = "pcronly",
  "LFT only" = "lftonly",
  "PCR and LFT" = "both"
)

data_rates %>%
  pivot_longer(
    cols = ends_with("rate")
  ) %>%
  mutate(across(name, factor, levels = str_c(rates, "_rate"), labels = str_wrap(names(rates), 20))) %>%
  ggplot(aes(x = anytest_cut, y = value, group = treated, colour = treated)) +
  geom_point() +
  geom_line() +
  facet_wrap(~name, nrow = 2) +
  labs(
    x = "time period (days relative to trial_date)",
    y = "rate per person-day of follow-up"
  ) +
  theme_bw() +
  theme(
    axis.text.x = element_text(angle = 90, vjust = 0.5),
    legend.position = c(0.9, 0.15)
  )
ggsave(
  filename = file.path(output_dir, "rates.png"),
  width = 15, height = 20, units = "cm"
)

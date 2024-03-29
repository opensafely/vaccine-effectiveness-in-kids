# create dummy data for treated and potential control population ----


library("tidyverse")
library("arrow")
library("here")
library("glue")

# remotes::install_github("https://github.com/wjchulme/dd4d")
library("dd4d")

source(here("lib", "functions", "utility.R"))

population_size <- 20000

# get nth largest value from list
nthmax <- function(x, n = 1) {
  dplyr::nth(sort(x, decreasing = TRUE), n)
}

source(here("analysis", "design.R"))


for (cohort in c("over12", "under12")) {
  for (vaxn in c(1L, 2L)) {
    # cohort = "over12"
    # vaxn = 1L

    dates <- map(study_dates[[cohort]], as.Date)
    params <- study_params[[cohort]]

    minage <- params$minage
    maxage <- params$maxage
    start_date <- as.Date(dates$start_date1)
    end_date <- as.Date(dates$end_date2)
    followupend_date <- as.Date(dates$followupend_date2)
    index_date <- as.Date(dates$start_date1)

    first_pfizerA_date <- as.Date(dates$start_date1)
    first_pfizerC_date <- as.Date(dates$start_date1)

    index_day <- 0L
    start_day <- as.integer(start_date - index_date)
    end_day <- as.integer(end_date - index_date)
    first_pfizerA_day <- as.integer(first_pfizerA_date - index_date)
    first_pfizerC_day <- as.integer(first_pfizerC_date - index_date)


    known_variables <- c(
      "cohort", "vaxn",
      "minage", "maxage",
      "index_date", "start_date", "end_date", "first_pfizerA_date", "first_pfizerC_date",
      "index_day", "start_day", "end_day", "first_pfizerA_day", "first_pfizerC_day"
    )

    sim_list_pre <- lst(

      # dereg_day = bn_node(
      #   ~as.integer(runif(n=..n, start_day, start_day+120)),
      #   missing_rate = ~0.99
      # ),
      #
      # has_follow_up_previous_6weeks = bn_node(
      #   ~rbernoulli(n=..n, p=0.999)
      # ),
      #
      age = bn_node(
        ~ as.integer(runif(n = ..n, minage, maxage))
      ),
      prior_covid_test_frequency = bn_node(
        ~ as.integer(runif(n = ..n, 0, 12))
      ),
      age_aug21 = bn_node(
        ~age
      ),
      treated = bn_node(
        ~ rbernoulli(n = ..n, p = 0.3),
      ),
      registered = bn_node(
        ~ rbernoulli(n = ..n, p = 1),
      ),
      has_died = bn_node(
        ~ rbernoulli(n = ..n, p = 0.1),
      ),
      child_atrisk = bn_node(
        ~ rbernoulli(n = ..n, p = 0.1),
      ),
      ethnicity = bn_node(
        ~ rfactor(n = ..n, levels = c("1", "2", "3", "4", "5"), p = c(.8, 0.05, 0.05, 0.05, 0.05)),
        missing_rate = ~0.001 # this is shorthand for ~(rbernoulli(n=..n, p = 0.2))
      ),
      sex = bn_node(
        ~ rfactor(n = ..n, levels = c("F", "M"), p = c(0.51, 0.49)),
        missing_rate = ~0.001 # this is shorthand for ~(rbernoulli(n=..n, p = 0.2))
      ),
      #
      # bmi = bn_node(
      #   ~rfactor(n=..n, levels = c("Not obese", "Obese I (30-34.9)", "Obese II (35-39.9)", "Obese III (40+)"), p = c(0.5, 0.2, 0.2, 0.1)),
      # ),
      #
      practice_id = bn_node(
        ~ as.integer(runif(n = ..n, 1, 200))
      ),
      msoa = bn_node(
        ~ factor(as.integer(runif(n = ..n, 1, 100)), levels = 1:100),
        missing_rate = ~0.005
      ),
      stp = bn_node(
        ~ factor(as.integer(runif(n = ..n, 1, 36)), levels = 1:36)
      ),
      region = bn_node(
        variable_formula = ~ rfactor(n = ..n, levels = c(
          "North East",
          "North West",
          "Yorkshire and The Humber",
          "East Midlands",
          "West Midlands",
          "East",
          "London",
          "South East",
          "South West"
        ), p = c(0.2, 0.2, 0.3, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05))
      ),

      # imd = bn_node(
      #   ~factor(plyr::round_any(runif(n=..n, 1, 32000), 100), levels=seq(0,32000,100)),
      #   missing_rate = ~0.02
      # ),
      #
      # imd_integer = bn_node(
      #   ~as.integer(as.character(imd)),
      #   keep=FALSE
      # ),
      #
      imd_Q5 = bn_node(~ rfactor(
        n = ..n,
        levels = c("1 (most deprived)", "2", "3", "4", "5 (least deprived)", "Unknown"),
        p = c(0.2, 0.2, 0.2, 0.2, 0.19, 0.01)
      )),
      vax_compliant_exl_mmr = bn_node(~ rcat(
        n = ..n,
        levels = c(TRUE, FALSE),
        p = c(0.8, 0.2)
      )),
      type_MMR = bn_node(~ rcat(
        n = ..n,
        levels = c(TRUE, FALSE),
        p = c(0.85, 0.15)
      )),


      # rural_urban = bn_node(
      #   ~rfactor(n=..n, levels = 1:9, p = rep(1/9, 9)),
      #   missing_rate = ~ 0.1
      # ),
      #

      ## vaccination variables

      first_vax_type = bn_node(
        ~ case_when(
          cohort == "over12" ~ "pfizerA",
          cohort == "under12" ~ "pfizerC",
          TRUE ~ NA_character_
        ),
        keep = FALSE
      ),
      covid_vax_pfizerA_1_day = bn_node(
        ~ as.integer(runif(n = ..n, first_pfizerA_day, first_pfizerA_day + 90)),
        missing_rate = ~ 1 - (first_vax_type == "pfizerA")
      ),
      covid_vax_pfizerA_2_day = bn_node(
        ~ as.integer(runif(n = ..n, covid_vax_pfizerA_1_day + 77, covid_vax_pfizerA_1_day + 240)),
        needs = c("covid_vax_pfizerA_1_day"),
      ),
      covid_vax_pfizerA_3_day = bn_node(
        ~ as.integer(runif(n = ..n, covid_vax_pfizerA_2_day + 100, covid_vax_pfizerA_2_day + 240)),
        needs = c("covid_vax_pfizerA_2_day"),
      ),
      covid_vax_pfizerC_1_day = bn_node(
        ~ as.integer(runif(n = ..n, first_pfizerC_day, first_pfizerC_day + 90)),
        missing_rate = ~ 1 - (first_vax_type == "pfizerC")
      ),
      covid_vax_pfizerC_2_day = bn_node(
        ~ as.integer(runif(n = ..n, covid_vax_pfizerC_1_day + 77, covid_vax_pfizerC_1_day + 240)),
        needs = c("covid_vax_pfizerC_1_day"),
      ),
      covid_vax_pfizerC_3_day = bn_node(
        ~ as.integer(runif(n = ..n, covid_vax_pfizerC_2_day + 100, covid_vax_pfizerC_2_day + 240)),
        needs = c("covid_vax_pfizerC_2_day"),
      ),
      covid_vax_any_1_day = bn_node(
        ~ case_when(
          first_vax_type == "pfizerA" ~ covid_vax_pfizerA_1_day,
          first_vax_type == "pfizerC" ~ covid_vax_pfizerC_1_day,
        )
      ),
      covid_vax_any_2_day = bn_node(
        ~ case_when(
          first_vax_type == "pfizerA" ~ covid_vax_pfizerA_2_day,
          first_vax_type == "pfizerC" ~ covid_vax_pfizerC_2_day,
        )
      ),
      covid_vax_any_3_day = bn_node(
        ~ case_when(
          first_vax_type == "pfizerA" ~ covid_vax_pfizerA_3_day,
          first_vax_type == "pfizerC" ~ covid_vax_pfizerC_3_day,
        )
      ),
      vax_day = bn_node(
        ~ case_when(
          vaxn == 1 ~ covid_vax_any_1_day,
          vaxn == 2 ~ covid_vax_any_2_day,
          TRUE ~ NA_integer_
        ),
        keep = FALSE
      ),
      ## baseline clinical variables

      # asthma = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # chronic_neuro_disease = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # chronic_resp_disease = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # sev_obesity = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # diabetes = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # sev_mental = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # chronic_heart_disease = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # chronic_kidney_disease = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # chronic_liver_disease = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # cancer = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # immunosuppressed = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # asplenia = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      # learndis = bn_node( ~rbernoulli(n=..n, p = 0.02)),
      #
      # cev_ever = bn_node( ~rbernoulli(n=..n, p = 0.05)),
      # endoflife = bn_node( ~rbernoulli(n=..n, p = 0.001)),
      # housebound = bn_node( ~rbernoulli(n=..n, p = 0.001)),
      #
      # prior_covid_test_frequency = bn_node(
      #   ~as.integer(rpois(n=..n, lambda=3)),
      #   missing_rate = ~0
      # ),

      # inhospital = bn_node( ~rbernoulli(n=..n, p = 0.01)),

      ## pre-baseline events where event date is relevant
      #
      primary_care_covid_case_0_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day - 100, vax_day - 1)),
        missing_rate = ~0.7
      ),
      #
      # covid_test_0_day = bn_node(
      #   ~as.integer(runif(n=..n, vax1_day-100, vax1_day-1)),
      #   missing_rate = ~0.7
      # ),
      #
      postest_0_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day - 100, vax_day - 1)),
        missing_rate = ~0.9
      ),
      covidemergency_0_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day - 100, vax_day - 1)),
        missing_rate = ~0.99
      ),
      covidadmitted_0_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day - 100, vax_day - 1)),
        missing_rate = ~0.99
      ),
      #
    )

    sim_list_post <- lst(
      # ## post-baseline events (outcomes)
      dereg_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 120)),
        missing_rate = ~0.99
      ),
      primary_care_covid_case_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.7
      ),
      covid_test_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.7
      ),
      postest_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.7
      ),
      emergency_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.8
      ),
      pericarditisemergency_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 200)),
        missing_rate = ~0.8
      ),
      pericarditisadmitted_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 200)),
        missing_rate = ~0.8
      ),
      myocarditisemergency_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 200)),
        missing_rate = ~0.8
      ),
      myocarditisadmitted_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 200)),
        missing_rate = ~0.8
      ),
      emergencyhosp_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.85
      ),
      covidemergency_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.8
      ),
      covidemergencyhosp_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.85
      ),
      # fracture negative control outcomes
      fractureemergency_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.8
      ),
      fractureadmitted_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.8
      ),
      fracturedeath_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.8
      ),

      # respemergency_day = bn_node(
      #   ~as.integer(runif(n=..n, vax_day, vax_day+100)),
      #   missing_rate = ~0.95
      # ),
      #
      # respemergencyhosp_day = bn_node(
      #   ~as.integer(runif(n=..n, vax_day, vax_day+100)),
      #   missing_rate = ~0.95
      # ),

      covidadmitted_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.7
      ),

      # placeholder for single criticalcare variable ---
      covidcritcare_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.8
      ),
      admitted_unplanned_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.7
      ),
      # admitted_planned_day = bn_node(
      #   ~as.integer(runif(n=..n, vax_day, vax_day+100)),
      #   missing_rate = ~0.7
      # ),

      coviddeath_day = bn_node(
        ~death_day,
        missing_rate = ~0.7,
        needs = "death_day"
      ),
      death_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.90
      ),
      test_count = bn_node(
        ~ rpois(n = ..n, 1)
      ),
      postest_count = bn_node(
        ~ rpois(n = ..n, 0.1)
      ),
      outcome_vax_1_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.8
      ),
      outcome_vax_2_day = bn_node(
        ~ as.integer(runif(n = ..n, vax_day, vax_day + 100)),
        missing_rate = ~0.8
      ),
    )


    sim_list <- splice(sim_list_pre, sim_list_post)

    bn <- bn_create(sim_list, known_variables = known_variables)

    bn_plot(bn)
    bn_plot(bn, connected_only = TRUE)

    set.seed(10)

    dummydata <- bn_simulate(bn, pop_size = population_size, keep_all = FALSE, .id = "patient_id")


    dummydata_processed <- dummydata %>%
      mutate(

        # covid vax any
      ) %>%
      # convert logical to integer as study defs output 0/1 not TRUE/FALSE
      # mutate(across(where(is.logical), ~ as.integer(.))) %>%
      # convert integer days to dates since index date and rename vars
      mutate(across(ends_with("_day"), ~ as.Date(as.character(index_date + .)))) %>%
      rename_with(~ str_replace(., "_day", "_date"), ends_with("_day"))


    fs::dir_create(here("lib", "dummydata"))

    dummydata_processed %>%
      filter(treated) %>%
      select(-treated) %>%
      write_feather(sink = ghere("lib", "dummydata", "dummy_treated_{cohort}_{vaxn}.feather"))

    dummydata_processed %>%
      select(-treated) %>%
      select(-all_of(str_replace(names(sim_list_post), "_day", "_date"))) %>%
      write_feather(sink = ghere("lib", "dummydata", "dummy_control_potential1_{cohort}_{vaxn}.feather"))
  }
}

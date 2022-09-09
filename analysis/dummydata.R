#install required versions
#library('devtools')
#install_version("tidyr", version = "1.1.2",lib="C:/Program Files/R/R-4.1.3/library")
#install_version("tidyverse", version = "1.3.0",lib="C:/Program Files/R/R-4.1.3/library")

library('tidyr')#, lib.loc = "C:/Program Files/R/R-4.1.3/library")
library('tidyverse')#, lib.loc = "C:/Program Files/R/R-4.1.3/library")
#library('tidyverse')
library('arrow')
library('here')
library('glue')

#source(here("analysis", "lib", "utility_functions.R"))

# remotes::install_github("https://github.com/wjchulme/dd4d")
library('dd4d')


population_size <- 20000

# get nth largest value from list
nthmax <- function(x, n=1){
  dplyr::nth(sort(x, decreasing=TRUE), n)
}

source(here("lib", "design", "design.R"))


studystart_date <- as.Date(study_dates$over12start_date)
studyend_date <- as.Date(study_dates$over12end_date)
followupend_date <- as.Date(study_dates$over12followupend_date)
index_date <- as.Date(study_dates$over12start_date)

first_pfizerA_date <- as.Date(study_dates$over12start_date)
first_pfizerC_date <- as.Date(study_dates$under12start_date)

index_day <- 0L
studystart_day <- as.integer(studystart_date - index_date)
studyend_day <- as.integer(studyend_date - index_date)
first_pfizerA_day <- as.integer(first_pfizerA_date - index_date)
first_pfizerC_day <- as.integer(first_pfizerC_date - index_date)

known_variables <- c(
  "index_date", "studystart_date", "studyend_date", "first_pfizerA_date", "first_pfizerC_date",
  "index_day",  "studystart_day", "studyend_day", "first_pfizerA_day", "first_pfizerC_day"
)

sim_list_pre = lst(
  
  # dereg_day = bn_node(
  #   ~as.integer(runif(n=..n, studystart_day, studystart_day+120)),
  #   missing_rate = ~0.99
  # ),
  # 
  # has_follow_up_previous_6weeks = bn_node(
  #   ~rbernoulli(n=..n, p=0.999)
  # ),
  # 
  age = bn_node(
    ~as.integer(rnorm(n=..n, mean=10, sd=2))
  ),
  
  age_aug21 = bn_node(
    ~age
  ),
  
  treated = bn_node(
    ~rbernoulli(n=..n, p = 0.3),
  ),
  
  registered = bn_node(
    ~rbernoulli(n=..n, p = 1),
  ),
  
  has_died =  bn_node(
    ~rbernoulli(n=..n, p = 0.1),
  ),
  
  wchild = bn_node(
    ~rbernoulli(n=..n, p = 0.1),
  ),
  
  ethnicity = bn_node(
    ~rfactor(n=..n, levels = c("1", "2","3","4","5"), p = c(.8,0.05,0.05,0.05,0.05)),
    missing_rate = ~0.001 # this is shorthand for ~(rbernoulli(n=..n, p = 0.2))
  ),
  
  
  sex = bn_node(
    ~rfactor(n=..n, levels = c("F", "M"), p = c(0.51, 0.49)),
    missing_rate = ~0.001 # this is shorthand for ~(rbernoulli(n=..n, p = 0.2))
  ),
  # 
  # bmi = bn_node(
  #   ~rfactor(n=..n, levels = c("Not obese", "Obese I (30-34.9)", "Obese II (35-39.9)", "Obese III (40+)"), p = c(0.5, 0.2, 0.2, 0.1)),
  # ),
  # 
  practice_id = bn_node(
    ~as.integer(runif(n=..n, 1, 200))
  ),
  
  msoa = bn_node(
    ~factor(as.integer(runif(n=..n, 1, 100)), levels=1:100),
    missing_rate = ~ 0.005
  ),
  
  stp = bn_node(
    ~factor(as.integer(runif(n=..n, 1, 36)), levels=1:36)
  ),
  
  region = bn_node(
    variable_formula = ~rfactor(n=..n, levels=c(
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
  imd_Q5 = bn_node(~rfactor(n=..n,
      levels= c("1 (most deprived)", "2", "3", "4", "5 (least deprived)", "Unknown"),
     p = c(0.2, 0.2, 0.2, 0.2, 0.19,0.01))
  ),
  
  # rural_urban = bn_node(
  #   ~rfactor(n=..n, levels = 1:9, p = rep(1/9, 9)),
  #   missing_rate = ~ 0.1
  # ),
  # 
  
  ## vaccination variables
  
  first_vax_type = bn_node(~rcat(n=..n, c("pfizerA","pfizerC"), c(0.5,0.5)), keep=FALSE),
  
  covid_vax_pfizerA_1_day = bn_node(
    ~as.integer(runif(n=..n, first_pfizerA_day, first_pfizerA_day+90)),
    missing_rate = ~1-(first_vax_type=="pfizerA")
  ),
  covid_vax_pfizerA_2_day = bn_node(
    ~as.integer(runif(n=..n, covid_vax_pfizerA_1_day+180, covid_vax_pfizerA_1_day+240)),
    needs = c("covid_vax_pfizerA_1_day"),
  ),
  
  covid_vax_pfizerC_1_day = bn_node(
    ~as.integer(runif(n=..n, first_pfizerC_day, first_pfizerC_day+90)),
    missing_rate = ~1-(first_vax_type=="pfizerC")
  ),
  covid_vax_pfizerC_2_day = bn_node(
    ~as.integer(runif(n=..n, covid_vax_pfizerC_1_day+180, covid_vax_pfizerC_1_day+240)),
    needs = c("covid_vax_pfizerC_1_day"),
  ),
  
  vax1_day = bn_node(
    ~pmin(covid_vax_pfizerA_1_day, covid_vax_pfizerC_1_day, na.rm=TRUE),
    keep=FALSE
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
    ~as.integer(runif(n=..n, studystart_day-100, studystart_day-1)),
    missing_rate = ~0.7
  ),
  # 
  # covid_test_0_day = bn_node(
  #   ~as.integer(runif(n=..n, studystart_day-100, studystart_day-1)),
  #   missing_rate = ~0.7
  # ),
  # 
  postest_0_day = bn_node(
    ~as.integer(runif(n=..n, studystart_day-100, studystart_day-1)),
    missing_rate = ~0.9
  ),

  covidemergency_0_day = bn_node(
    ~as.integer(runif(n=..n, studystart_day-100, studystart_day-1)),
    missing_rate = ~0.99
  ),


  covidadmitted_0_day = bn_node(
    ~as.integer(runif(n=..n, studystart_day-100, studystart_day-1)),
    missing_rate = ~0.99
  ),
  # 
  
)

sim_list_post <- lst(
  # ## post-baseline events (outcomes)
  
  dereg_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+120)),
    missing_rate = ~0.99
  ),
  
  primary_care_covid_case_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
    missing_rate = ~0.7
  ),
  
  covid_test_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
    missing_rate = ~0.7
  ),
  
  postest_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
    missing_rate = ~0.7
  ),
  
  emergency_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+200)),
    missing_rate = ~0.8
  ),
  emergencyhosp_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+200)),
    missing_rate = ~0.85
  ),
  
  
  covidemergency_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+200)),
    missing_rate = ~0.8
  ),
  
  covidemergencyhosp_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+200)),
    missing_rate = ~0.85
  ),
  
  # respemergency_day = bn_node(
  #   ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
  #   missing_rate = ~0.95
  # ),
  # 
  # respemergencyhosp_day = bn_node(
  #   ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
  #   missing_rate = ~0.95
  # ),
  
  covidadmitted_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
    missing_rate = ~0.7
  ),
  
  # placeholder for single criticalcare variable ---
  covidcritcare_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
    missing_rate = ~0.8
  ),
  
  admitted_unplanned_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
    missing_rate = ~0.7
  ),
  # admitted_planned_day = bn_node(
  #   ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
  #   missing_rate = ~0.7
  # ),
  
  coviddeath_day = bn_node(
    ~death_day,
    missing_rate = ~0.7,
    needs = "death_day"
  ),
  
  death_day = bn_node(
    ~as.integer(runif(n=..n, vax1_day, vax1_day+100)),
    missing_rate = ~0.90
  ),
  
)


sim_list <- splice(sim_list_pre, sim_list_post)

bn <- bn_create(sim_list, known_variables = known_variables)

bn_plot(bn)
bn_plot(bn, connected_only=TRUE)

set.seed(10)

dummydata <-bn_simulate(bn, pop_size = population_size, keep_all = FALSE, .id="patient_id")


dummydata_processed <- dummydata %>%
  mutate(
    
    # covid vax any
    covid_vax_any_1_day = pmin(covid_vax_pfizerA_1_day, covid_vax_pfizerC_1_day, na.rm=TRUE),
    covid_vax_any_2_day = pmin(covid_vax_pfizerA_2_day, covid_vax_pfizerC_2_day, na.rm=TRUE),
    
  ) %>%
  #convert logical to integer as study defs output 0/1 not TRUE/FALSE
  # mutate(across(where(is.logical), ~ as.integer(.))) %>%
  #convert integer days to dates since index date and rename vars
  mutate(across(ends_with("_day"), ~ as.Date(as.character(index_date + .)))) %>%
  rename_with(~str_replace(., "_day", "_date"), ends_with("_day"))


fs::dir_create(here("lib", "dummydata"))
write_feather(dummydata_processed, sink = here("lib", "dummydata", "dummyinput.feather"))

write_feather(dummydata_processed %>% filter(treated) %>% select(-treated), sink = here("lib", "dummydata", "dummy_treated.feather"))
write_feather(dummydata_processed %>% select(-treated) %>% select(-all_of(str_replace(names(sim_list_post), "_day", "_date"))), sink = here("lib", "dummydata", "dummy_control_potential1.feather"))

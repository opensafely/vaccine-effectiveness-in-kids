from ast import And
# Import codelists from codelists.py
import codelists

# import json module
import json
import re

from cohortextractor import (
  StudyDefinition,
  patients,
  codelist_from_csv,
  codelist,
  filter_codes_by_category,
  combine_codelists,
  params
)

from variables_outcome import vaccination_date_X 

cohort = params["cohort"]
vaxn = int(params["vaxn"])

# import study dates defined in "./analysis/design.R" script
with open("./lib/design/study-dates.json") as f:
  study_dates = json.load(f)

# change these in design.R if necessary
start_date_0 = study_dates[cohort]["start_date1"]
end_date_0 = study_dates[cohort]["end_date1"]
start_date_1 = study_dates[cohort]["start_date1"]
end_date_1 = study_dates[cohort]["end_date1"]
start_date_2 = study_dates[cohort]["start_date2"]
end_date_2 = study_dates[cohort]["end_date2"]
start_date = study_dates[cohort][f"start_date{vaxn}"]
end_date = study_dates[cohort][f"end_date{vaxn}"]

# import study parameters defined in "./analysis/design.R" script  
with open("./lib/design/study-params.json") as f:
  study_params = json.load(f)

minage = study_params[cohort]["minage"]
maxage = study_params[cohort]["maxage"]
treatment = study_params[cohort]["treatment"]



############################################################
## inclusion variables
from variables_inclusion import generate_inclusion_variables 
inclusion_variables = generate_inclusion_variables(index_date=f"covid_vax_any_{vaxn}_date")
############################################################
## matching variables
from variables_matching import generate_matching_variables 
matching_variables = generate_matching_variables(index_date=f"covid_vax_any_{vaxn}_date")
############################################################
## outcome variables
from variables_outcome import generate_outcome_variables 
outcome_variables = generate_outcome_variables(index_date=f"covid_vax_any_{vaxn}_date")
############################################################



# Specify study defeinition
study = StudyDefinition(
  
  # Configure the expectations framework
  default_expectations={
    "date": {"earliest": "2020-01-01", "latest": end_date},
    "rate": "uniform",
    "incidence": 0.2,
    "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
    "float": {"distribution": "normal", "mean": 25, "stddev": 5},
  },
  
  index_date = start_date,
  
  # This line defines the study population

  population=patients.satisfying(
    f"""
      registered
      AND
      age_aug21 >= {minage}
      AND
      age_aug21 <= {maxage}
      AND
      (NOT has_died)
      AND
      NOT child_atrisk
      AND 
      (covid_vax_any_{vaxn}_date >= start_date_{vaxn})
      AND
      (covid_vax_any_{vaxn}_date <= end_date_{vaxn})
      AND 
      (covid_vax_any_{vaxn-1}_date = covid_vax_{treatment}_{vaxn-1}_date)
       AND
      (covid_vax_any_{vaxn}_date = covid_vax_{treatment}_{vaxn}_date)
    """,
    # Not including (covid_vax_any_2_date >= covid_vax_any_1_date + 12 weeks) as specfied in the outcomes variables week_12_vaccination_date_X
    # 
  start_date_0 = patients.fixed_value(start_date_0),
  end_date_0 = patients.fixed_value(end_date_0),  
  start_date_1 = patients.fixed_value(start_date_1),
  end_date_1 = patients.fixed_value(end_date_1),  
  start_date_2 = patients.fixed_value(start_date_2),
  end_date_2 = patients.fixed_value(end_date_2),  
  covid_vax_any_0_date = patients.fixed_value(start_date_0),
  covid_vax_pfizerA_0_date = patients.fixed_value(start_date_0),
  covid_vax_pfizerC_0_date = patients.fixed_value(start_date_0),
  ),
  
  **week_12_vaccination_date_X(
    name = "covid_vax_any",
    index_date = "1900-01-01",
    n = 3,
    target_disease_matches="SARS-2 CORONAVIRUS"
  ),

  # pfizer
  **week_12_vaccination_date_X(
    name = "covid_vax_pfizerA",
    # use 1900 to capture all possible recorded covid vaccinations, including date errors
    # any vaccines occurring before national rollout are later excluded
    index_date = "1900-01-01", 
    n = 3,
    product_name_matches="COVID-19 mRNA Vaccine Comirnaty 30micrograms/0.3ml dose conc for susp for inj MDV (Pfizer)"
  ),
  
  # pfizer approved for use in children (5-11)
  **week_12_vaccination_date_X(
    name = "covid_vax_pfizerC",
    index_date = "1900-01-01",
    n = 3,
    product_name_matches="COVID-19 mRNA Vaccine Comirnaty Children 5-11yrs 10mcg/0.2ml dose conc for disp for inj MDV (Pfizer)"
  ),


  ##############################################################################
  # inclusion
  ##############################################################################
  **inclusion_variables,    
  
  ###############################################################################
  # matching
  ##############################################################################
  **matching_variables,      
  
    ###############################################################################
  # outcomes
  ##############################################################################
  **outcome_variables,      
  
)

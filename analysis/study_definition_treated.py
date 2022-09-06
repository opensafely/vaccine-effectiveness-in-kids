from variables_outcome import vaccination_date_X 
from ast import And
# Import codelists from codelists.py
import codelists

# import json module
import json


############################################################
## inclusion variables
from variables_inclusion import generate_inclusion_variables 
inclusion_variables = generate_inclusion_variables(index_date="covid_vax_any_1_date")
############################################################
## matching variables
from variables_matching import generate_matching_variables 
matching_variables = generate_matching_variables(index_date="covid_vax_any_1_date")
############################################################



from cohortextractor import (
  StudyDefinition,
  patients,
  codelist_from_csv,
  codelist,
  filter_codes_by_category,
  combine_codelists,
)

# import study dates defined in "./lib/design/study-dates.R" script
with open("./lib/design/study-dates.json") as f:
  study_dates = json.load(f)

# change these in design.R if necessary
studystart_date = study_dates["over12start_date"] 
studyend_date = study_dates["over12end_date"]

## Functions for extracting a series of time dependent variables
# These define study defintion variable signatures such that
# variable_1_date is the the first event date on or after the index date
# variable_2_date is the first event date strictly after variable_2_date
# ...
# variable_n_date is the first event date strictly after variable_n-1_date



# Specify study defeinition
study = StudyDefinition(
  
  # Configure the expectations framework
  default_expectations={
    "date": {"earliest": "2020-01-01", "latest": studyend_date},
    "rate": "uniform",
    "incidence": 0.2,
    "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
    "float": {"distribution": "normal", "mean": 25, "stddev": 5},
  },
  
  index_date = studystart_date,
  # This line defines the study population
  population=patients.satisfying(
    f"""
      registered
      AND
      age >= 12
      AND
      age <= 15
      AND
      (
      NOT has_died
      )
      AND
      NOT child_atrisk
      AND 
      covid_vax_any_1_date >= startdate
      AND
      covid_vax_any_1_date <= enddate
      AND 
      (
      covid_vax_any_1_date=covid_vax_pfizerA_1_date
      )
    """,
  startdate = patients.fixed_value(studystart_date),
  enddate = patients.fixed_value(studyend_date),  
  ),
  
  **vaccination_date_X(
    name = "covid_vax_any",
    index_date = "1900-01-01",
    n = 2,
    target_disease_matches="SARS-2 CORONAVIRUS"
  ),

# pfizer
  **vaccination_date_X(
    name = "covid_vax_pfizerA",
    # use 1900 to capture all possible recorded covid vaccinations, including date errors
    # any vaccines occurring before national rollout are later excluded
    index_date = "1900-01-01", 
    n = 2,
    product_name_matches="COVID-19 mRNA Vaccine Comirnaty 30micrograms/0.3ml dose conc for susp for inj MDV (Pfizer)"
  ),
  
  # pfizer approved for use in children (5-11)
  **vaccination_date_X(
    name = "covid_vax_pfizerC",
    index_date = "1900-01-01",
    n = 2,
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
  
)

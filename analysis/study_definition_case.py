
from ast import And


############################################################
## PRIMIS variables
############################################################
from variables_primis import generate_primis_variables 
primis_variables = generate_primis_variables(index_date="index_date -1 days")


from cohortextractor import (
  StudyDefinition,
  patients,
  codelist_from_csv,
  codelist,
  filter_codes_by_category,
  combine_codelists,
)

# Import codelists from codelists.py
import codelists

# import json module
import json


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


def vaccination_date_X(name, index_date, n, product_name_matches=None, target_disease_matches=None):
  # vaccination date, given product_name
  def var_signature(
    name,
    on_or_after,
    product_name_matches,
    target_disease_matches
  ):
    return {
      name: patients.with_tpp_vaccination_record(
        product_name_matches=product_name_matches,
        target_disease_matches=target_disease_matches,
        on_or_after=on_or_after,
        find_first_match_in_period=True,
        returning="date",
        date_format="YYYY-MM-DD"
      ),
    }
    
  variables = var_signature(f"{name}_1_date", index_date, product_name_matches, target_disease_matches)
  for i in range(2, n+1):
    variables.update(var_signature(
      f"{name}_{i}_date", 
      f"{name}_{i-1}_date + 1 days",
      # pick up subsequent vaccines occurring one day or later -- people with unrealistic dosing intervals are later excluded
      product_name_matches,
      target_disease_matches
    ))
  return variables



def critcare_dates(name, on_or_after, n, with_these_diagnoses, with_admission_method):
  
  
  def var_signature_date(
    # variable signature for date of hosp admission
    name,
    on_or_after,
    with_these_diagnoses,
    with_admission_method
  ):
    return {
      name: patients.admitted_to_hospital(
        returning = "date_admitted",
        with_these_diagnoses = with_these_diagnoses,
        with_admission_method = with_admission_method,
        on_or_after = on_or_after,
        date_format = "YYYY-MM-DD",
        find_first_match_in_period = True
      )
    }
    
  
  def var_signature_ccdays(
    # variable signature for days in critical care
    name,
    event_date,
    with_these_diagnoses,
    with_admission_method
  ):
    return {
      name: patients.admitted_to_hospital(
        returning = "days_in_critical_care",
        with_these_diagnoses = with_these_diagnoses,
        with_admission_method = with_admission_method,
        between = [event_date, event_date],
        find_first_match_in_period = True,
        return_expectations = {
          "category":{"ratios": {"0": 0.8, "1": 0.1, "2": 0.1}}
        }
      )
    }
    
  # define a sequence of n variables for date of admission and associated number of days in critical care
  
  # initialise for first date
  variables_date = var_signature_date(f"{name}_1_date", on_or_after, with_these_diagnoses, with_admission_method)
  variables_ccdays = var_signature_ccdays(f"{name}_1_ccdays", f"{name}_1_date", with_these_diagnoses, with_admission_method)
  #isadmission_cc = {"1" : f"{name}_1_date AND ({name}_1_ccdays > 0)"}
  
  # loop for subsequent dates 
  for i in range(2, n+1):
    variables_date.update(
      var_signature_date(
        name = f"{name}_{i}_date", 
        on_or_after = f"{name}_{i-1}_date + 1 days",
        with_these_diagnoses = with_these_diagnoses,
        with_admission_method = with_admission_method
      )
    )
    
    variables_ccdays.update(
      var_signature_ccdays(
        name = f"{name}_{i}_ccdays", 
        event_date = f"{name}_{i}_date",
        with_these_diagnoses = with_these_diagnoses,
        with_admission_method = with_admission_method
      )
    )
    
    # isadmission_cc.update(
    #   {i : f"{name}_{i}_date AND ({name}_{i}_ccdays > 0)"}
    # )
  
  
  # if no critical care admission
  #isadmission_cc.update({"0" : "DEFAULT"})
    
  # collect variables into single dict
  variables = {**variables_date , **variables_ccdays}
  
  ## further logic if study definition functionality improves!
  
  # variable to identify the first admission after "on_or_after", if any, that was a critical care admission
  # critcareindex_signature = {
  #   critcare_index : patients.categorised_as(
  #     isadmission_cc,
  #     **variables
  #   ),
  #   return_expectations={
  #       "category":{"ratios": {"0": 0.8, "1": 0.1, "2": 0.1}}
  #   },
  # }
  
  
  # variable_names = variables.keys() # FIXME and then also make non-critcare dates in this list null or "" on a patient-pby-patient basis
  # # put into single "minimum_of" statement
  # var_signature = {
  #   name : patients.minimum_of(
  #     *variable_names,
  #     **variables
  #   )
  # }
  
  return variables



# Specify study defeinition
study = StudyDefinition(
  
  # Configure the expectations framework
  default_expectations={
    "date": {"earliest": studystart_date, "latest": studyend_date},
    "rate": "uniform",
    "incidence": 0.2,
    "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
    "float": {"distribution": "normal", "mean": 25, "stddev": 5},
  },
  
  index_date = studystart_date,
  
  # This line defines the study population
  population=patients.satisfying(
    """
      registered
      AND
      (NOT has_died)
    """,
    # we define baseline variables on the day _before_ the study date (start date = day of first possible booster vaccination)
    registered=patients.registered_as_of(
    "index_date  - 1 day",
    ),    
    has_died=patients.died_from_any_cause(
      on_or_before="index_date  - 1 day",
      returning="binary_flag",
        return_expectations={
            "incidence": 0.01,
        },
    ),
    ), 
    startdate = patients.fixed_value(studystart_date),
    enddate = patients.fixed_value(studyend_date),

  
  #################################################################
  ## Covid vaccine dates
  #################################################################
  
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
  
  # any covid vaccine
  **vaccination_date_X(
    name = "covid_vax_disease",
    index_date = "1900-01-01",
    n = 2,
    target_disease_matches="SARS-2 CORONAVIRUS"
  ),
  
  
  
  
  ###############################################################################
  ## Admin and demographics
  ###############################################################################
    
  

  ################################################################################################
  ## Pre-baseline events where event date is of interest
  ################################################################################################

  
  ############################################################
  ## Clinical information
  ############################################################
  
  
  **primis_variables,
  
  #####################################
  # JCVI groups
  #####################################
  

  ############################################################
  ## Post-baseline variables (outcomes)
  ############################################################

)
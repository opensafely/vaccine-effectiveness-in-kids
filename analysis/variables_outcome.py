from cohortextractor import patients, combine_codelists
from codelists import *
import codelists



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

def generate_outcome_variables(index_date):
    outcome_variables = dict(

  # Positive case identification after study start date
  primary_care_covid_case_date=patients.with_these_clinical_events(
    combine_codelists(
      codelists.covid_primary_care_code,
      codelists.covid_primary_care_positive_test,
      codelists.covid_primary_care_sequelae,
    ),
    returning="date",
    date_format="YYYY-MM-DD",
    on_or_after=index_date,
    find_first_match_in_period=True,
  ),
  
  
  # covid PCR test dates from SGSS
  covid_test_date=patients.with_test_result_in_sgss(
    pathogen="SARS-CoV-2",
    test_result="any",
    on_or_after=index_date,
    find_first_match_in_period=True,
    restrict_to_earliest_specimen_date=False,
    returning="date",
    date_format="YYYY-MM-DD",
  ),
  
  # positive covid test
  postest_date=patients.with_test_result_in_sgss(
      pathogen="SARS-CoV-2",
      test_result="positive",
      returning="date",
      date_format="YYYY-MM-DD",
      on_or_after=index_date,
      find_first_match_in_period=True,
      restrict_to_earliest_specimen_date=False,
  ),
  
  # emergency attendance for covid, as per discharge diagnosis
  covidemergency_date=patients.attended_emergency_care(
    returning="date_arrived",
    date_format="YYYY-MM-DD",
    on_or_after=index_date,
    with_these_diagnoses = codelists.covid_emergency,
    find_first_match_in_period=True,
  ),
  
  # emergency attendance for covid, as per discharge diagnosis, resulting in discharge to hospital
  covidemergencyhosp_date=patients.attended_emergency_care(
    returning="date_arrived",
    date_format="YYYY-MM-DD",
    on_or_after=index_date,
    find_first_match_in_period=True,
    with_these_diagnoses = codelists.covid_emergency,
    discharged_to = codelists.discharged_to_hospital,
  ),
  
  # emergency attendance for respiratory illness
  # FIXME -- need to define codelist
  # respemergency_date=patients.attended_emergency_care(
  #   returning="date_arrived",
  #   date_format="YYYY-MM-DD",
  #   on_or_after=index_date,
  #   with_these_diagnoses = codelists.resp_emergency,
  #   find_first_match_in_period=True,
  # ),
  
  # emergency attendance for respiratory illness, resulting in discharge to hospital
  # FIXME -- need to define codelist
  # respemergencyhosp_date=patients.attended_emergency_care(
  #   returning="date_arrived",
  #   date_format="YYYY-MM-DD",
  #   on_or_after=index_date,
  #   find_first_match_in_period=True,
  #   with_these_diagnoses = codelists.resp_emergency,
  #   discharged_to = codelists.discharged_to_hospital,
  # ),
  
  # any emergency attendance
  emergency_date=patients.attended_emergency_care(
    returning="date_arrived",
    on_or_after=index_date,
    date_format="YYYY-MM-DD",
    find_first_match_in_period=True,
  ),
  
  # emergency attendance resulting in discharge to hospital
  emergencyhosp_date=patients.attended_emergency_care(
    returning="date_arrived",
    on_or_after=index_date,
    date_format="YYYY-MM-DD",
    find_last_match_in_period=True,
    discharged_to = codelists.discharged_to_hospital,
  ),
  
  
  # unplanned hospital admission
  admitted_unplanned_date=patients.admitted_to_hospital(
    returning="date_admitted",
    on_or_after=index_date,
    # see https://github.com/opensafely-core/cohort-extractor/pull/497 for codes
    # see https://docs.opensafely.org/study-def-variables/#sus for more info
    with_admission_method=["21", "22", "23", "24", "25", "2A", "2B", "2C", "2D", "28"],
    with_patient_classification = ["1"], # ordinary admissions only
    date_format="YYYY-MM-DD",
    find_first_match_in_period=True,
  ),
  
  # planned hospital admission
  admitted_planned_date=patients.admitted_to_hospital(
    returning="date_admitted",
    on_or_after=index_date,
    # see https://github.com/opensafely-core/cohort-extractor/pull/497 for codes
    # see https://docs.opensafely.org/study-def-variables/#sus for more info
    with_admission_method=["11", "12", "13", "81"],
    with_patient_classification = ["1"], # ordinary admissions only 
    date_format="YYYY-MM-DD",
    find_first_match_in_period=True,
  ),
  
  # Positive covid admission prior to study start date
  covidadmitted_date=patients.admitted_to_hospital(
    returning="date_admitted",
    with_admission_method=["21", "22", "23", "24", "25", "2A", "2B", "2C", "2D", "28"],
    with_these_diagnoses=codelists.covid_icd10,
    on_or_after=index_date,
    date_format="YYYY-MM-DD",
    find_first_match_in_period=True,
  ),
  
  **critcare_dates(
    name = "potentialcovidcritcare", 
    on_or_after = index_date, 
    n = 3,
    with_admission_method = ["21", "22", "23", "24", "25", "2A", "2B", "2C", "2D", "28"],
    with_these_diagnoses = codelists.covid_icd10
  ),
  
  # Covid-related death
  coviddeath_date=patients.with_these_codes_on_death_certificate(
    codelists.covid_icd10,
    returning="date_of_death",
    date_format="YYYY-MM-DD",
  ),
  
  # All-cause death
  death_date=patients.died_from_any_cause(
    returning="date_of_death",
    date_format="YYYY-MM-DD",
  ),
  )
    
    return outcome_variables

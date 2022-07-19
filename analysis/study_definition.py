
from ast import And
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
      (
      registered
      OR
      registered_vac
      )
      AND
      age >= 12
      AND
      age <= 15
      AND
      (
      NOT has_died
      OR
      NOT has_died_vac
      )
      AND
      NOT cev
    """,

    cev = patients.satisfying(
    """severely_clinically_vulnerable AND NOT less_vulnerable""",
    ##### The shielded patient list was retired in March/April 2021 when shielding ended
    ##### so it might be worth using that as the end date instead of index_date, as we're not sure
    ##### what has happened to these codes since then, e.g. have doctors still been adding new
    ##### shielding flags or low-risk flags? Depends what you're looking for really. Could investigate separately.

    ### SHIELDED GROUP - first flag all patients with "high risk" codes
    severely_clinically_vulnerable = patients.with_these_clinical_events(
    codelists.shield,
    returning="binary_flag",
    on_or_before = "index_date - 1 day",
    find_last_match_in_period = True,
    ),

    # find date at which the high risk code was added
    date_severely_clinically_vulnerable = patients.date_of(
    "severely_clinically_vulnerable",
    date_format="YYYY-MM-DD",
    ),

    ### NOT SHIELDED GROUP (medium and low risk) - only flag if later than 'shielded'
    less_vulnerable = patients.with_these_clinical_events(
    codelists.nonshield,
    between=["date_severely_clinically_vulnerable + 1 day", "index_date - 1 day",],
    ),

    ),
    # we define baseline variables on the day _before_ the study date (start date = day of first possible booster vaccination)
    registered=patients.registered_as_of(
    "index_date - 1 day",
    ),    
    registered_vac=patients.registered_as_of(
      "covid_vax_disease_1_date - 1 day",
    ),
    has_died_vac=patients.died_from_any_cause(
      on_or_before="covid_vax_disease_1_date - 1 day",
      returning="binary_flag",
    ), 
    has_died=patients.died_from_any_cause(
      on_or_before="covid_vax_disease_1_date - 1 day",
      returning="binary_flag",
    ), 
    startdate = patients.fixed_value(studystart_date),
    enddate = patients.fixed_value(studyend_date),
  ),
  
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
  
  has_follow_up_previous_6weeks=patients.registered_with_one_practice_between(
    start_date="index_date - 42 days",
    end_date="index_date",
  ),
  
  dereg_date=patients.date_deregistered_from_all_supported_practices(
    on_or_after="index_date",
    date_format="YYYY-MM-DD",
  ),

  
  age=patients.age_as_of( 
    "index_date - 1 day",
  ),
  
  ageband=patients.categorised_as(
            {
                "0": "DEFAULT",
                "5-11": """ age >= 5 AND age < 12""",
                "12-15": """ age >= 12 AND age < 16"""
            },
            return_expectations={
                "rate": "universal",
                "category": {
                    "ratios": {
                        "5-11": 0.65,
                        "12-15": 0.35,
                    }
                },
            },
    ),
  
  sex=patients.sex(
    return_expectations={
      "rate": "universal",
      "category": {"ratios": {"M": 0.49, "F": 0.51}},
      "incidence": 1,
    }
  ),
  
  # https://github.com/opensafely/risk-factors-research/issues/51
  bmi=patients.categorised_as(
    {
      "Not obese": "DEFAULT",
      "Obese I (30-34.9)": """ bmi_value >= 30 AND bmi_value < 35""",
      "Obese II (35-39.9)": """ bmi_value >= 35 AND bmi_value < 40""",
      "Obese III (40+)": """ bmi_value >= 40 AND bmi_value < 100""",
      # set maximum to avoid any impossibly extreme values being classified as obese
    },
    bmi_value=patients.most_recent_bmi(
      on_or_after="index_date - 5 years",
      minimum_age_at_measurement=16
    ),
    return_expectations={
      "rate": "universal",
      "category": {
        "ratios": {
          "Not obese": 0.7,
          "Obese I (30-34.9)": 0.1,
          "Obese II (35-39.9)": 0.1,
          "Obese III (40+)": 0.1,
        }
      },
    },
  ),
  

  ################################################################################################
  ## Practice and patient ID variables
  ################################################################################################
  # practice pseudo id
  practice_id_vac=patients.registered_practice_as_of(
    "covid_vax_disease_1_date - 1 day",
    returning="pseudo_id",
    return_expectations={
      "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
      "incidence": 1,
    },
  ),
  
  practice_id=patients.registered_practice_as_of(
    "index_date - 1 day",
    returning="pseudo_id",
    return_expectations={
      "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
      "incidence": 1,
    },
  ),
  
  # msoa
  msoa_vac=patients.address_as_of(
    "covid_vax_disease_1_date - 1 day",
    returning="msoa",
    return_expectations={
      "rate": "universal",
      "category": {"ratios": {"E02000001": 0.0625, "E02000002": 0.0625, "E02000003": 0.0625, "E02000004": 0.0625,
        "E02000005": 0.0625, "E02000007": 0.0625, "E02000008": 0.0625, "E02000009": 0.0625, 
        "E02000010": 0.0625, "E02000011": 0.0625, "E02000012": 0.0625, "E02000013": 0.0625, 
        "E02000014": 0.0625, "E02000015": 0.0625, "E02000016": 0.0625, "E02000017": 0.0625}},
    },
  ),    
  
  msoa=patients.address_as_of(
    "index_date - 1 day",
    returning="msoa",
    return_expectations={
      "rate": "universal",
      "category": {"ratios": {"E02000001": 0.0625, "E02000002": 0.0625, "E02000003": 0.0625, "E02000004": 0.0625,
        "E02000005": 0.0625, "E02000007": 0.0625, "E02000008": 0.0625, "E02000009": 0.0625, 
        "E02000010": 0.0625, "E02000011": 0.0625, "E02000012": 0.0625, "E02000013": 0.0625, 
        "E02000014": 0.0625, "E02000015": 0.0625, "E02000016": 0.0625, "E02000017": 0.0625}},
    },
  ),    
  # stp is an NHS administration region based on geography
  stp_vac=patients.registered_practice_as_of(
    "covid_vax_disease_1_date - 1 day",
    returning="stp_code",
    return_expectations={
      "rate": "universal",
      "category": {
        "ratios": {
          "STP1": 0.1,
          "STP2": 0.1,
          "STP3": 0.1,
          "STP4": 0.1,
          "STP5": 0.1,
          "STP6": 0.1,
          "STP7": 0.1,
          "STP8": 0.1,
          "STP9": 0.1,
          "STP10": 0.1,
        }
      },
    },
  ),
  stp=patients.registered_practice_as_of(
    "index_date - 1 day",
    returning="stp_code",
    return_expectations={
      "rate": "universal",
      "category": {
        "ratios": {
          "STP1": 0.1,
          "STP2": 0.1,
          "STP3": 0.1,
          "STP4": 0.1,
          "STP5": 0.1,
          "STP6": 0.1,
          "STP7": 0.1,
          "STP8": 0.1,
          "STP9": 0.1,
          "STP10": 0.1,
        }
      },
    },
  ),
  # NHS administrative region
  region_vac=patients.registered_practice_as_of(
    "covid_vax_disease_1_date - 1 day",
    returning="nuts1_region_name",
    return_expectations={
      "rate": "universal",
      "category": {
        "ratios": {
          "North East": 0.1,
          "North West": 0.1,
          "Yorkshire and The Humber": 0.2,
          "East Midlands": 0.1,
          "West Midlands": 0.1,
          "East": 0.1,
          "London": 0.1,
          "South East": 0.1,
          "South West": 0.1
          #"" : 0.01
        },
      },
    },
  ),

  region=patients.registered_practice_as_of(
    "index_date - 1 day",
    returning="nuts1_region_name",
    return_expectations={
      "rate": "universal",
      "category": {
        "ratios": {
          "North East": 0.1,
          "North West": 0.1,
          "Yorkshire and The Humber": 0.2,
          "East Midlands": 0.1,
          "West Midlands": 0.1,
          "East": 0.1,
          "London": 0.1,
          "South East": 0.1,
          "South West": 0.1
          #"" : 0.01
        },
      },
    },
  ),
  ## IMD - quintile
  
  imd_Q5_vac=patients.categorised_as(
    {
      "Unknown": "DEFAULT",
      "1 (most deprived)": "imd_vac >= 0 AND imd_vac < 32844*1/5",
      "2": "imd_vac >= 32844*1/5 AND imd_vac < 32844*2/5",
      "3": "imd_vac >= 32844*2/5 AND imd_vac < 32844*3/5",
      "4": "imd_vac >= 32844*3/5 AND imd_vac < 32844*4/5",
      "5 (least deprived)": "imd_vac >= 32844*4/5 AND imd_vac <= 32844",
    },
    return_expectations={
      "rate": "universal",
      "category": {"ratios": {"Unknown": 0.02, "1 (most deprived)": 0.18, "2": 0.2, "3": 0.2, "4": 0.2, "5 (least deprived)": 0.2}},
    },
    imd_vac=patients.address_as_of(
    "covid_vax_disease_1_date - 1 day",
    returning="index_of_multiple_deprivation",
    round_to_nearest=100,
    return_expectations={
      "category": {"ratios": {c: 1/320 for c in range(100, 32100, 100)}}
    }
    ),

  ),

  imd_Q5=patients.categorised_as(
    {
      "Unknown": "DEFAULT",
      "1 (most deprived)": "imd >= 0 AND imd < 32844*1/5",
      "2": "imd >= 32844*1/5 AND imd < 32844*2/5",
      "3": "imd >= 32844*2/5 AND imd < 32844*3/5",
      "4": "imd >= 32844*3/5 AND imd < 32844*4/5",
      "5 (least deprived)": "imd >= 32844*4/5 AND imd <= 32844",
    },
    return_expectations={
      "rate": "universal",
      "category": {"ratios": {"Unknown": 0.02, "1 (most deprived)": 0.18, "2": 0.2, "3": 0.2, "4": 0.2, "5 (least deprived)": 0.2}},
    },
    imd=patients.address_as_of(
    "index_date - 1 day",
    returning="index_of_multiple_deprivation",
    round_to_nearest=100,
    return_expectations={
      "category": {"ratios": {c: 1/320 for c in range(100, 32100, 100)}}
    }
    ),

  ),
  
  #rurality
  rural_urban_vac=patients.address_as_of(
    "covid_vax_disease_1_date - 1 day",
    returning="rural_urban_classification",
    return_expectations={
      "rate": "universal",
      "category": {"ratios": {1: 0.125, 2: 0.125, 3: 0.125, 4: 0.125, 5: 0.125, 6: 0.125, 7: 0.125, 8: 0.125}},
    },
  ),

  rural_urban=patients.address_as_of(
    "index_date - 1 day",
    returning="rural_urban_classification",
    return_expectations={
      "rate": "universal",
      "category": {"ratios": {1: 0.125, 2: 0.125, 3: 0.125, 4: 0.125, 5: 0.125, 6: 0.125, 7: 0.125, 8: 0.125}},
    },
  ),


  ################################################################################################
  ## occupation / residency
  ################################################################################################


  # health or social care worker  
  hscworker = patients.with_healthcare_worker_flag_on_covid_vaccine_record(returning="binary_flag"),
  
  care_home_tpp_vac=patients.satisfying(
    "care_home_vac='1'",
    
    care_home_vac = patients.care_home_status_as_of(
      "covid_vax_disease_1_date - 1 day",
      categorised_as={
          "1": "IsPotentialCareHome",
          "": "DEFAULT",  # use empty string
      },
    ),
  ),
  
  care_home_tpp=patients.satisfying(
    "care_home='1'",
    
    care_home = patients.care_home_status_as_of(
      "index_date - 1 day",
      categorised_as={
          "1": "IsPotentialCareHome",
          "": "DEFAULT",  # use empty string
      },
    ),
  ),
  
  # Patients in long-stay nursing and residential care
  care_home_code=patients.with_these_clinical_events(
      codelists.carehome,
      on_or_before="covid_vax_disease_1_date - 1 day",
      returning="binary_flag",
      return_expectations={"incidence": 0.01},
  ),
  
  

  ################################################################################################
  ## Pre-baseline events where event date is of interest
  ################################################################################################


  # Positive case identification prior to study start date
  primary_care_covid_case_0_date=patients.with_these_clinical_events(
    combine_codelists(
      codelists.covid_primary_care_code,
      codelists.covid_primary_care_positive_test,
      codelists.covid_primary_care_sequelae,
    ),
    returning="date",
    date_format="YYYY-MM-DD",
    on_or_before="covid_vax_disease_1_date - 1 day",
    find_last_match_in_period=True,
  ),
  
  # covid PCR test dates from SGSS
  covid_test_0_date=patients.with_test_result_in_sgss(
    pathogen="SARS-CoV-2",
    test_result="any",
    on_or_before="covid_vax_disease_1_date - 1 day",
    returning="date",
    date_format="YYYY-MM-DD",
    find_last_match_in_period=True,
    restrict_to_earliest_specimen_date=False,
  ),

  
  # positive covid test
  postest_0_date=patients.with_test_result_in_sgss(
      pathogen="SARS-CoV-2",
      test_result="positive",
      returning="date",
      date_format="YYYY-MM-DD",
      on_or_before="covid_vax_disease_1_date - 1 day",
      find_last_match_in_period=True,
      restrict_to_earliest_specimen_date=False,
  ),
  
  # emergency attendance for covid
  covidemergency_0_date=patients.attended_emergency_care(
    returning="date_arrived",
    on_or_before="covid_vax_disease_1_date - 1 day",
    with_these_diagnoses = codelists.covid_emergency,
    date_format="YYYY-MM-DD",
    find_last_match_in_period=True,
  ),
  
    # Positive covid admission prior to study start date
  covidadmitted_0_date=patients.admitted_to_hospital(
    returning="date_admitted",
    with_admission_method=["21", "22", "23", "24", "25", "2A", "2B", "2C", "2D", "28"],
    with_these_diagnoses=codelists.covid_icd10,
    on_or_before="covid_vax_disease_1_date - 1 day",
    date_format="YYYY-MM-DD",
    find_last_match_in_period=True,
  ),
  
  ############################################################
  ## Clinical information as at initial pfizer dose date
  ############################################################
  
  
  # From PRIMIS

  asthma = patients.satisfying(
    """
      astadm OR
      (ast AND astrxm1 AND astrxm2 AND astrxm3)
      """,
    # Asthma Admission codes
    astadm=patients.with_these_clinical_events(
      codelists.astadm,
      returning="binary_flag",
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
    # Asthma Diagnosis code
    ast = patients.with_these_clinical_events(
      codelists.ast,
      returning="binary_flag",
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
    # Asthma systemic steroid prescription code in month 1
    astrxm1=patients.with_these_medications(
      codelists.astrx,
      returning="binary_flag",
      between=["covid_vax_disease_1_date - 30 days", "covid_vax_disease_1_date - 1 day"],
    ),
    # Asthma systemic steroid prescription code in month 2
    astrxm2=patients.with_these_medications(
      codelists.astrx,
      returning="binary_flag",
      between=["covid_vax_disease_1_date - 60 days", "covid_vax_disease_1_date - 31 days"],
    ),
    # Asthma systemic steroid prescription code in month 3
    astrxm3=patients.with_these_medications(
      codelists.astrx,
      returning="binary_flag",
      between= ["covid_vax_disease_1_date - 90 days", "covid_vax_disease_1_date - 61 days"],
    ),

  ),

  # Chronic Neurological Disease including Significant Learning Disorder
  chronic_neuro_disease=patients.with_these_clinical_events(
    codelists.cns_cov,
    returning="binary_flag",
    on_or_before="covid_vax_disease_1_date - 1 day",
  ),

  # Chronic Respiratory Disease
  chronic_resp_disease = patients.satisfying(
    "asthma OR resp_cov",
    resp_cov=patients.with_these_clinical_events(
      codelists.resp_cov,
      returning="binary_flag",
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
  ),

  sev_obesity = patients.satisfying(
    """
      sev_obesity_date > bmi_date OR
      bmi_value1 >= 40
      """,

    bmi_stage_date=patients.with_these_clinical_events(
      codelists.bmi_stage,
      returning="date",
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
      date_format="YYYY-MM-DD",
    ),

    sev_obesity_date=patients.with_these_clinical_events(
      codelists.sev_obesity,
      returning="date",
      find_last_match_in_period=True,
      ignore_missing_values=True,
      between= ["bmi_stage_date", "covid_vax_disease_1_date - 1 day"],
      date_format="YYYY-MM-DD",
    ),

    bmi_date=patients.with_these_clinical_events(
      codelists.bmi,
      returning="date",
      ignore_missing_values=True,
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
      date_format="YYYY-MM-DD",
    ),

    bmi_value1=patients.with_these_clinical_events(
      codelists.bmi,
      returning="numeric_value",
      ignore_missing_values=True,
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),

  ),

  diabetes = patients.satisfying(
    "(dmres_date < diab_date) OR (diab_date AND (NOT dmres_date))",
    
    diab_date=patients.with_these_clinical_events(
      codelists.diab,
      returning="date",
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
      date_format="YYYY-MM-DD",
    ),

    dmres_date=patients.with_these_clinical_events(
      codelists.dmres,
      returning="date",
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
      date_format="YYYY-MM-DD",
    ),
  ),

  sev_mental=patients.satisfying(
    "(smhres_date < sev_mental_date) OR (sev_mental_date AND (NOT smhres_date))",

    # Severe Mental Illness codes
    sev_mental_date=patients.with_these_clinical_events(
      codelists.sev_mental,
      returning="date",
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
      date_format="YYYY-MM-DD",
    ),
    # Remission codes relating to Severe Mental Illness
    smhres_date=patients.with_these_clinical_events(
      codelists.smhres,
      returning="date",
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
      date_format="YYYY-MM-DD",
    ),
  ),


  # Chronic heart disease codes
  chronic_heart_disease=patients.with_these_clinical_events(
    codelists.chd_cov,
    returning="binary_flag",
    on_or_before="covid_vax_disease_1_date - 1 day",
  ),

  chronic_kidney_disease=patients.satisfying(
    """
      ckd OR
      (ckd15_date AND ckd35_date >= ckd15_date)
      """,

    # Chronic kidney disease codes - all stages
    ckd15_date=patients.with_these_clinical_events(
      codelists.ckd15,
      returning="date",
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
      date_format="YYYY-MM-DD",
    ),

    # Chronic kidney disease codes-stages 3 - 5
    ckd35_date=patients.with_these_clinical_events(
      codelists.ckd35,
      returning="date",
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
      date_format="YYYY-MM-DD",
    ),

    # Chronic kidney disease diagnostic codes
    ckd=patients.with_these_clinical_events(
      codelists.ckd_cov,
      returning="binary_flag",
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
  ),


  # Chronic Liver disease codes
  chronic_liver_disease=patients.with_these_clinical_events(
    codelists.cld,
    returning="binary_flag",
    on_or_before="covid_vax_disease_1_date - 1 day",
  ),


  immunosuppressed=patients.satisfying(
    "immrx OR immdx",

    # Immunosuppression diagnosis codes
    immdx=patients.with_these_clinical_events(
      codelists.immdx_cov,
      returning="binary_flag",
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
    # Immunosuppression medication codes
    immrx=patients.with_these_medications(
      codelists.immrx,
      returning="binary_flag",
      between=["covid_vax_disease_1_date - 182 days", "covid_vax_disease_1_date - 1 day"]
    ),
  ),

  # Asplenia or Dysfunction of the Spleen codes
  asplenia=patients.with_these_clinical_events(
    codelists.spln_cov,
    returning="binary_flag",
    on_or_before="covid_vax_disease_1_date - 1 day",
  ),

  # Wider Learning Disability
  learndis=patients.with_these_clinical_events(
    codelists.learndis,
    returning="binary_flag",
    on_or_before="covid_vax_disease_1_date - 1 day",
  ),


  # to represent household contact of shielding individual
  # hhld_imdef_dat=patients.with_these_clinical_events(
  #   codelists.hhld_imdef,
  #   returning="date",
  #   find_last_match_in_period=True,
  #   on_or_before="covid_vax_disease_1_date - 1 day",
  #   date_format="YYYY-MM-DD",
  # ),
  #
 

  cancer = patients.satisfying(
    
    "cancer_primary_care",
    # cancer_hosp=patients.admitted_to_hospital(
    #   with_these_diagnoses=combine_codelists(
    #     codelists.cancer_nonhaem_icd10,
    #     codelists.cancer_haem_icd10,
    #     codelists.cancer_unspec_icd10,
    #   ),
    #   between=["covid_vax_disease_1_date - 3 years", "covid_vax_disease_1_date - 1 day"],
    #   returning="binary_flag",
    # ),
    cancer_primary_care=patients.with_these_clinical_events( 
      combine_codelists(
        codelists.cancer_nonhaem_snomed,
        codelists.cancer_haem_snomed
      ),
      between=["covid_vax_disease_1_date - 3 years", "covid_vax_disease_1_date - 1 day"],
      returning="binary_flag",
    ), 
  ),

  
  
  #####################################
  # JCVI groups
  #####################################
  
  cev_ever = patients.with_these_clinical_events(
    codelists.shield,
    returning="binary_flag",
    on_or_before = "covid_vax_disease_1_date - 1 day",
    find_last_match_in_period = True,
  ),
  
  endoflife = patients.satisfying(
    """
    midazolam OR
    endoflife_coding
    """,
  
    midazolam = patients.with_these_medications(
      codelists.midazolam,
      returning="binary_flag",
      on_or_before = "covid_vax_disease_1_date - 1 day",
    ),
    
    endoflife_coding = patients.with_these_clinical_events(
      codelists.eol,
      returning="binary_flag",
      on_or_before = "covid_vax_disease_1_date - 1 day",
      find_last_match_in_period = True,
    ),
        
  ),
    
  housebound = patients.satisfying(
    """housebound_date
    AND NOT no_longer_housebound
    AND NOT moved_into_care_home
    """,
        
    housebound_date=patients.with_these_clinical_events( 
      codelists.housebound, 
      on_or_before="covid_vax_disease_1_date - 1 day",
      find_last_match_in_period = True,
      returning="date",
      date_format="YYYY-MM-DD",
    ),   
    no_longer_housebound=patients.with_these_clinical_events( 
      codelists.no_longer_housebound, 
      between=["housebound_date", "covid_vax_disease_1_date - 1 day"],
    ),
    moved_into_care_home=patients.with_these_clinical_events(
      codelists.carehome,
      between=["housebound_date", "covid_vax_disease_1_date - 1 day"],
    ),
  ),
  
  prior_covid_test_frequency=patients.with_test_result_in_sgss(
    pathogen="SARS-CoV-2",
    test_result="any",
    between=["covid_vax_disease_1_date - 182 days", "covid_vax_disease_1_date - 1 day"], # 182 days = 26 weeks
    returning="number_of_matches_in_period", 
    date_format="YYYY-MM-DD",
    restrict_to_earliest_specimen_date=False,
  ),
  
  # overnight hospital admission at time of 3rd / booster dose
  inhospital = patients.satisfying(
  
    "discharged_0_date >= covid_vax_disease_1_date",
    
    discharged_0_date=patients.admitted_to_hospital(
      returning="date_discharged",
      on_or_before="covid_vax_disease_1_date", # this is the admission date
      # see https://github.com/opensafely-core/cohort-extractor/pull/497 for codes
      # see https://docs.opensafely.org/study-def-variables/#sus for more info
      with_admission_method = ['11', '12', '13', '21', '2A', '22', '23', '24', '25', '2D', '28', '2B', '81'],
      with_patient_classification = ["1"], # ordinary admissions only
      date_format="YYYY-MM-DD",
      find_last_match_in_period=True,
    ), 
  ),
  
  atrisk_group = patients.satisfying(
    """
    IMMUNOGROUP
    OR
    CKD_GROUP
    OR
    RESP_GROUP
    OR
    DIAB_GROUP 
    OR
    CLD
    OR
    CNS_GROUP
    OR
    CHD_COV
    OR
    SPLN_COV
    OR
    LEARNDIS
    OR
    SEVMENT_GROUP
    """,
  ##### Patients with Immunosuppression
  IMMUNOGROUP = patients.satisfying(
    """
    IMMDX
    OR
    IMMRX
    OR
    DXT_CHEMO
    """,
    ###  any immunosuppressant Read code is recorded
    IMMDX=patients.with_these_clinical_events(
      codelists.IMMDX_COV_COD,
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
    ### any Immunosuppression medication codes is recorded
    IMMRX=patients.with_these_clinical_events(
      codelists.IMMRX_COD,
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
    ### Receiving chemotherapy or radiotherapy
    DXT_CHEMO = patients.with_these_clinical_events(
      codelists.DXT_CHEMO_COD ,
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
  ),
  # Patients with Chronic Kidney Disease
  CKD_GROUP= patients.satisfying(
    """
     CKD_COV
     OR
     (
     CKD15
     AND
     CKD35_DAT>=CKD15_DAT 
     )
    """,
    ### Chronic kidney disease diagnostic codes
    CKD_COV = patients.with_these_clinical_events(
      codelists.CKD_COV_COD,
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
    ### Chronic kidney disease codes - all stages
    CKD15 = patients.with_these_clinical_events(
      codelists.CKD15_COD,
      on_or_before="covid_vax_disease_1_date - 1 day",
    ),
    ### date of Chronic kidney disease codes-stages 3 – 5  
    CKD35_DAT=patients.with_these_clinical_events(
      codelists.CKD35_COD,
    returning="date",
    date_format="YYYY-MM-DD",
    on_or_before="covid_vax_disease_1_date - 1 day",
    find_first_match_in_period=True,
    ),
    ### date of Chronic kidney disease codes - all stages
    CKD15_DAT=patients.with_these_clinical_events(
      codelists.CKD15_COD,
    returning="date",
    date_format="YYYY-MM-DD",
    on_or_before="covid_vax_disease_1_date - 1 day",
    find_first_match_in_period=True,
    ),
  ),
  ### Patients who have Chronic Respiratory Disease
  RESP_GROUP = patients.satisfying(
    """
     AST_GROUP
     OR
     RESP_COV 
    """,
      ### Patients with Asthma 
      AST_GROUP= patients.satisfying(
      """
      ASTADM
      OR
      (
      AST
      AND
      ASTRXM1
      AND
      ASTRXM2
      )
      """,
        ### Asthma Admission codes
        ASTADM = patients.with_these_clinical_events(
            codelists.ASTADM_COD,
            on_or_before="covid_vax_disease_1_date - 1 day",
        ),  
        ### Asthma Diagnosis code
        AST = patients.with_these_clinical_events(
            codelists.AST_COD,
            on_or_before="covid_vax_disease_1_date - 1 day",
        ),  
        ### Asthma - inhalers in last 12 months
        ASTRXM1=patients.with_these_medications(
            codelists.ASTRX_COD,
            returning="binary_flag",
            between=["covid_vax_disease_1_date - 30 days", "covid_vax_disease_1_date - 1 day"],
          ),
        ### Asthma - systemic oral steroid prescription codes in last 24 months
        ASTRXM2=patients.with_these_medications(
            codelists.ASTRX_COD,
            returning="binary_flag",
            between=["covid_vax_disease_1_date - 60 days", "covid_vax_disease_1_date - 31 days"],
          ),
      ),
    ### Chronic Respiratory Disease
    RESP_COV =patients.with_these_clinical_events(
        codelists.RESP_COV_COD,
        returning="binary_flag",
        on_or_before="covid_vax_disease_1_date - 1 day",
    ),
  ),
  ### Patients with Diabetes
  DIAB_GROUP = patients.satisfying(
  """
  DIAB_DAT>DMRES_DAT
  OR
  ADDIS
  OR
  GDIAB_GROUP
  """,
      ### Date any Diabetes diagnosis Read code is recorded
      DIAB_DAT=patients.with_these_clinical_events(
        codelists.DIAB_COD,
        returning="date",
        find_last_match_in_period=True,
        on_or_before="covid_vax_disease_1_date - 1 day",
        date_format="YYYY-MM-DD",
      ),
      ### Date of Diabetes resolved codes
      DMRES_DAT=patients.with_these_clinical_events(
        codelists.DMRES_COD,
        returning="date",
        find_last_match_in_period=True,
        on_or_before="covid_vax_disease_1_date - 1 day",
        date_format="YYYY-MM-DD",
      ),
      ### Addison’s disease & Pan-hypopituitary diagnosis codes
      ADDIS = patients.with_these_clinical_events(
        codelists.ADDIS_COD,
        returning="binary_flag",
        on_or_before="covid_vax_disease_1_date - 1 day",
      ),
      ### Patients who are currently pregnant with gestational diabetes 
      GDIAB_GROUP = patients.satisfying(
      """
      GDAIB
      AND
      PREG1_GROUP
      """,
        ### Gestational Diabetes diagnosis codes
        GDAIB =  patients.with_these_clinical_events(
          codelists.GDAIB_COD,
          returning="binary_flag",
          on_or_before="covid_vax_disease_1_date - 1 day",
        ),
        ### Patients who are currently pregnant 
        PREG1_GROUP = patients.satisfying(
          """
          PREG
          AND
          PREGDEL_DAT < PREG_DAT
          """,
            ### Pregnancy codes recorded
            PREG =  patients.with_these_clinical_events(
            codelists.PREG_COD,
            returning="binary_flag",
            on_or_before="covid_vax_disease_1_date - 1 day",
            ),
            ### Pregnancy or Delivery codes 
            PREGDEL_DAT=patients.with_these_clinical_events(
            codelists.PREGDEL_COD,
            returning="date",
            find_last_match_in_period=True,
            on_or_before="covid_vax_disease_1_date - 1 day",
            date_format="YYYY-MM-DD",
            ),
            ### date of Pregnancy codes recorded
            PREG_DAT=patients.with_these_clinical_events(
            codelists.PREG_COD,
            returning="date",
            find_last_match_in_period=True,
            on_or_before="covid_vax_disease_1_date - 1 day",
            date_format="YYYY-MM-DD",
            ),
        ),
      ),
    ),  
  ### Chronic Liver disease codes
  CLD = patients.with_these_clinical_events(
    codelists.CLD_COD,
    returning="binary_flag",
    on_or_before="covid_vax_disease_1_date - 1 day",
  ),
  ### Patients with CNS Disease (including Stroke/TIA)
  CNS_GROUP= patients.with_these_clinical_events(
    codelists.CNS_COV_COD,
    returning="binary_flag",
    on_or_before="covid_vax_disease_1_date - 1 day",
  ),  
  ### Chronic heart disease codes
  CHD_COV = patients.with_these_clinical_events(
    codelists.CHD_COV_COD,
    returning="binary_flag",
    on_or_before="covid_vax_disease_1_date - 1 day",
  ),  
  ### Asplenia or Dysfunction of the Spleen codes
  SPLN_COV= patients.with_these_clinical_events(
      codelists.SPLN_COV_COD,
      returning="binary_flag",
      on_or_before="covid_vax_disease_1_date - 1 day",
  ),  
  ### Wider Learning Disability
  LEARNDIS = patients.with_these_clinical_events(
      codelists.LEARNDIS_COD,
      returning="binary_flag",
      on_or_before="covid_vax_disease_1_date - 1 day",
  ),
  ### Patients with Severe Mental Health
  SEVMENT_GROUP = patients.satisfying(
  """
  SEV_MENTAL_DAT > SMHRES_DAT
  """,
    ### date of Severe Mental Illness codes
    SEV_MENTAL_DAT=   patients.with_these_clinical_events(
        codelists.SEV_MENTAL_COD,
        returning="date",
        find_last_match_in_period=True,
        on_or_before="covid_vax_disease_1_date - 1 day",
        date_format="YYYY-MM-DD",
    ),
    ### date of Remission codes relating to Severe Mental Illness
    SMHRES_DAT=   patients.with_these_clinical_events(
      codelists.SMHRES_COD,
      returning="date",
      find_last_match_in_period=True,
      on_or_before="covid_vax_disease_1_date - 1 day",
      date_format="YYYY-MM-DD",
    ),
  ),
),

  ############################################################
  ## Post-baseline variables (outcomes)
  ############################################################


  # Positive case identification after study start date
  primary_care_covid_case_date=patients.with_these_clinical_events(
    combine_codelists(
      codelists.covid_primary_care_code,
      codelists.covid_primary_care_positive_test,
      codelists.covid_primary_care_sequelae,
    ),
    returning="date",
    date_format="YYYY-MM-DD",
    on_or_after="covid_vax_disease_1_date",
    find_first_match_in_period=True,
  ),
  
  
  # covid PCR test dates from SGSS
  covid_test_date=patients.with_test_result_in_sgss(
    pathogen="SARS-CoV-2",
    test_result="any",
    on_or_after="covid_vax_disease_1_date",
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
      on_or_after="covid_vax_disease_1_date",
      find_first_match_in_period=True,
      restrict_to_earliest_specimen_date=False,
  ),
  
  # emergency attendance for covid, as per discharge diagnosis
  covidemergency_date=patients.attended_emergency_care(
    returning="date_arrived",
    date_format="YYYY-MM-DD",
    on_or_after="covid_vax_disease_1_date",
    with_these_diagnoses = codelists.covid_emergency,
    find_first_match_in_period=True,
  ),
  
  # emergency attendance for covid, as per discharge diagnosis, resulting in discharge to hospital
  covidemergencyhosp_date=patients.attended_emergency_care(
    returning="date_arrived",
    date_format="YYYY-MM-DD",
    on_or_after="covid_vax_disease_1_date",
    find_first_match_in_period=True,
    with_these_diagnoses = codelists.covid_emergency,
    discharged_to = codelists.discharged_to_hospital,
  ),
  
  # emergency attendance for respiratory illness
  # FIXME -- need to define codelist
  # respemergency_date=patients.attended_emergency_care(
  #   returning="date_arrived",
  #   date_format="YYYY-MM-DD",
  #   on_or_after="covid_vax_disease_1_date",
  #   with_these_diagnoses = codelists.resp_emergency,
  #   find_first_match_in_period=True,
  # ),
  
  # emergency attendance for respiratory illness, resulting in discharge to hospital
  # FIXME -- need to define codelist
  # respemergencyhosp_date=patients.attended_emergency_care(
  #   returning="date_arrived",
  #   date_format="YYYY-MM-DD",
  #   on_or_after="covid_vax_disease_1_date",
  #   find_first_match_in_period=True,
  #   with_these_diagnoses = codelists.resp_emergency,
  #   discharged_to = codelists.discharged_to_hospital,
  # ),
  
  # any emergency attendance
  emergency_date=patients.attended_emergency_care(
    returning="date_arrived",
    on_or_after="covid_vax_disease_1_date",
    date_format="YYYY-MM-DD",
    find_first_match_in_period=True,
  ),
  
  # emergency attendance resulting in discharge to hospital
  emergencyhosp_date=patients.attended_emergency_care(
    returning="date_arrived",
    on_or_after="covid_vax_disease_1_date",
    date_format="YYYY-MM-DD",
    find_last_match_in_period=True,
    discharged_to = codelists.discharged_to_hospital,
  ),
  
  
  # unplanned hospital admission
  admitted_unplanned_date=patients.admitted_to_hospital(
    returning="date_admitted",
    on_or_after="covid_vax_disease_1_date",
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
    on_or_after="covid_vax_disease_1_date",
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
    on_or_after="covid_vax_disease_1_date",
    date_format="YYYY-MM-DD",
    find_first_match_in_period=True,
  ),
  
  **critcare_dates(
    name = "potentialcovidcritcare", 
    on_or_after = "covid_vax_disease_1_date", 
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
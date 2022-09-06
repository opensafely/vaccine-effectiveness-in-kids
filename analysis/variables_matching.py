from cohortextractor import patients, combine_codelists
from codelists import *
import json
import codelists


def generate_matching_variables(index_date):
    matching_variables = dict(

    sex=patients.sex(
    return_expectations={
      "rate": "universal",
      "category": {"ratios": {"M": 0.49, "F": 0.51}},
      "incidence": 1,
    }
  ),

  ethnicity = patients.with_these_clinical_events(
    codelists.ethnicity,
    returning="category",
    find_last_match_in_period=True,
    include_date_of_match=False,
    return_expectations={
      "category": {"ratios": {"1": 0.2, "2": 0.2, "3": 0.2, "4": 0.2, "5": 0.2}},
      "incidence": 0.75,
    },
  ),

  # ethnicity_white=patients.categorised_as(
  #   {
  #   "Unknown": "DEFAULT",
  #   "White": "ethnicity ==1",
  #   "Non_White": "ethnicity == 2",
  #   },
  # ),

  practice_id=patients.registered_practice_as_of(
    f"{index_date} - 1 day",
    returning="pseudo_id",
    return_expectations={
      "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
      "incidence": 1,
    },
  ),
  
  # msoa
  
  msoa=patients.address_as_of(
    f"{index_date} - 1 day",
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

  stp=patients.registered_practice_as_of(
    f"{index_date} - 1 day",
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

  region=patients.registered_practice_as_of(
    f"{index_date} - 1 day",
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
    f"{index_date} - 1 day",
    returning="index_of_multiple_deprivation",
    round_to_nearest=100,
    return_expectations={
      "category": {"ratios": {c: 1/320 for c in range(100, 32100, 100)}}
    }
    ),
  
  ),

  prior_infection= patients.satisfying(
      """
      primary_care_covid_case
      OR
      covid_test
      OR
      covidemergency
      OR
      covidadmitted
      """,
    
    primary_care_covid_case=patients.with_these_clinical_events(
        codelists.covid_primary_care_probable_combined,
      returning="binary_flag",
      on_or_before=f"{index_date} - 1 day",
    ),
    
    # covid PCR test dates from SGSS
    covid_test=patients.with_test_result_in_sgss(
      pathogen="SARS-CoV-2",
      test_result="positive",
      on_or_before=f"{index_date} - 1 day",
      returning="binary_flag",
    ),


    # emergency attendance for covid
    covidemergency=patients.attended_emergency_care(
      returning="binary_flag",
      on_or_before=f"{index_date} - 1 day",
      with_these_diagnoses = codelists.covid_emergency,
    ),
    
      # Positive covid admission prior to study start date
    covidadmitted=patients.admitted_to_hospital(
      returning="binary_flag",
      with_admission_method=["21", "22", "23", "24", "25", "2A", "2B", "2C", "2D", "28"],
      with_these_diagnoses=codelists.covid_icd10,
      on_or_before=f"{index_date} - 1 day",
    ),
  ),


    )
    return matching_variables


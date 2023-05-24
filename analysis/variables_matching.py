from cohortextractor import patients, combine_codelists
from codelists import *
import json
import codelists

############################################################
## childhood vax variables
from variables_childhood_vaccs import childhood_vaccs 
childhood_vacc_variables = childhood_vaccs()

def generate_matching_variables(baseline_date):
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
  
  #   ethnicity_white=patients.categorised_as(
  #     {
  #     "Unknown": "DEFAULT",
  #     "White": "ethnicity >=1 AND ethnicity <2",
  #     "Non_White": "ethnicity >=2",
  #     },
  #   ),
  
    practice_id=patients.registered_practice_as_of(
      f"{baseline_date} - 1 day",
      returning="pseudo_id",
      return_expectations={
        "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
        "incidence": 1,
      },
    ),
    
    # msoa
    
    msoa=patients.address_as_of(
      f"{baseline_date} - 1 day",
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
      f"{baseline_date} - 1 day",
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
      f"{baseline_date} - 1 day",
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
        f"{baseline_date} - 1 day",
        returning="index_of_multiple_deprivation",
        round_to_nearest=100,
        return_expectations={
          "category": {"ratios": {c: 1/320 for c in range(100, 32100, 100)}}
        }
      ),
    
    ),
    
    primary_care_covid_case_0_date=patients.with_these_clinical_events(
      combine_codelists(
        codelists.covid_primary_care_code,
        codelists.covid_primary_care_positive_test,
        codelists.covid_primary_care_sequelae,
      ),
      returning="date",
      date_format="YYYY-MM-DD",
      on_or_before=f"{baseline_date} - 1 day",
      find_last_match_in_period=True,
    ),

    # # covid PCR test dates from SGSS
    # covid_test_0_date=patients.with_test_result_in_sgss(
    #   pathogen="SARS-CoV-2",
    #   test_result="any",
    #   on_or_before=f"{baseline_date} - 1 day",
    #   returning="date",
    #   date_format="YYYY-MM-DD",
    #   find_last_match_in_period=True,
    #   restrict_to_earliest_specimen_date=False,
    # ),
  
    
    # positive covid test
    postest_0_date=patients.with_test_result_in_sgss(
        pathogen="SARS-CoV-2",
        test_result="positive",
        returning="date",
        date_format="YYYY-MM-DD",
        on_or_before=f"{baseline_date} - 1 day",
        find_last_match_in_period=True,
        restrict_to_earliest_specimen_date=False,
    ),
    
  prior_covid_test_frequency=patients.with_test_result_in_sgss(
    pathogen="SARS-CoV-2",
    test_result="any",
    between=[f"{baseline_date} - 182 days", f"{baseline_date} - 1 day"], # 182 days = 26 weeks
    returning="number_of_matches_in_period", 
    date_format="YYYY-MM-DD",
    restrict_to_earliest_specimen_date=False,
  ),


    # emergency attendance for covid
    covidemergency_0_date=patients.attended_emergency_care(
      returning="date_arrived",
      on_or_before=f"{baseline_date} - 1 day",
      with_these_diagnoses = codelists.covid_emergency,
      date_format="YYYY-MM-DD",
      find_last_match_in_period=True,
    ),

      # Positive covid admission prior to study start date
    covidadmitted_0_date=patients.admitted_to_hospital(
      returning="date_admitted",
      with_admission_method=["21", "22", "23", "24", "25", "2A", "2B", "2C", "2D", "28"],
      with_these_diagnoses=codelists.covid_icd10,
      on_or_before=f"{baseline_date} - 1 day",
      date_format="YYYY-MM-DD",
      find_last_match_in_period=True,
    ),
    type_MMR = patients.satisfying(
          """
          Measles_Mumps_Rubella
          OR
          MMR_II
          OR
          MMRvaxPRO
          OR
          Priorix
          """,
          **childhood_vacc_variables
    ),
    vax_compliant_exl_mmr = patients.satisfying(
        """
        type_dTaP_IPV
        AND
        (
        type_DTaP_IPV_Hib_HepB
        OR
        type_DTaP_IPV_Hib
        )
        AND
        type_Hib_MenC
        AND
        type_PCV
        """,
      type_dTaP_IPV = patients.satisfying(
          """
          Boostrix_IPV
          OR
          DTaP_IPV
          OR
          dTP_Polio
          OR
          Infanrix_IPV
          OR
          Repevax
          """,
    ),
    type_DTaP_IPV_Hib = patients.satisfying( # Infanix_Quinta_5 refers to Infanrix Quinta 5. The spelling mistake is made on the TPP backend. 
          """
          dTP_Polio_Hib
          OR
          DTaP_IPV_Hib
          OR
          Infanix_Quinta_5
          OR
          Infanrix_IPV_HIB
          OR
          Pediacel
          """,
    ),
    type_DTaP_IPV_Hib_HepB = patients.satisfying( 
          """
          DTaP_IPV_Hib_HepB
          OR
          Infanrix_Hexa
          OR
          V419_PR51
          OR
          Vaxelis
          """,
    ),
    type_Hib_MenC = patients.satisfying(
          """
          HIB_Meningitis_C
          OR
          Menitorix
          """,
      ),
         
      type_PCV = patients.satisfying(
          """
          Pneumococcal
          OR
          Pneumococcal_polysaccharide_conjugated_vaccine
          OR
          Prevenar
          OR
          Prevenar_13
          """,
      ),
      
      type_Td_IPV = patients.satisfying(
          """
          DT_Polio
          OR
          Td_IPV
          OR
          Tetanus_Diphtheria_LD_and_Polio
          OR
          Revaxis
          """,
          ),
    ), 

  )

  return matching_variables


# Vaccine effectiveness in children
[View on OpenSAFELY](https://jobs.opensafely.org/university-of-bristol/investigating-the-effectiveness-of-the-covid-19-vaccination-programme-in-the-uk/vaccine-effectiveness-in-children/)

Details of the purpose and any published outputs from this project can be found at the link above.

The contents of this repository MUST NOT be considered an accurate or valid representation of the study or its purpose. This repository may reflect an incomplete or incorrect analysis with no further ongoing work. The content has ONLY been made public to support the OpenSAFELY open science and transparency principles and to support the sharing of re-usable code for other subsequent users. No clinical, policy or safety conclusions must be drawn from the contents of this repository.

About the OpenSAFELY framework
The OpenSAFELY framework is a Trusted Research Environment (TRE) for electronic health records research in the NHS, with a focus on public accountability and research quality.

Read more at OpenSAFELY.org.

Licences
As standard, research projects have a MIT license.

## Repository navigation
-   If you are interested in how we defined our codelists, look in the [`codelists/`](./codelists/) directory.

-   Analysis scripts are in the [`analysis/`](./analysis) directory.

    -   The instructions used to extract data from the OpensAFELY-TPP database is specified in the study definitions; these are written in Python, but non-programmers should be able to understand what is going on
        - [`study_definition_controlactual.py`](./analysis/study_definition_controlactual.py)
        - [`study_definition_controlfinal.py`](./analysis/study_definition_controlfinal.py)
        - [`study_definition_controlpotential.py`](./analysis/study_definition_controlpotential.py) 
        - [`study_definition_covidtests.py`](./analysis/study_definition_covidtests.py)
        - [`study_definition_treated.py`](./analysis/study_definition_treated.py)
        
    -   The [`lib/`](./lib) directory contains preliminary (pre data extract) scripts, useful functions, and dummy data.
    -   The remaining folders mostly contain the R scripts that process, describe, and analyse the extracted database data.

-   Non-disclosive model outputs, including tables, figures, etc, will be made available on the [`OpenSAFELY Jobs`](https://jobs.opensafely.org/university-of-bristol/investigating-the-effectiveness-of-the-covid-19-vaccination-programme-in-the-uk/vaccine-effectiveness-in-children/releases/) site.

-   The [`project.yaml`](./project.yaml) defines run-order and dependencies for all the analysis scripts. **This file should *not* be edited directly**. To make changes to the yaml, edit and run the [`create-project.R`](./create-project.R) script instead.

## R scripts
- metadata and dummy data
    -   [`design.R`](analysis/design.R) defines some common design elements used throughout the study, such as follow-up dates, model outcomes, and covariates.
    -   The [`dummy/`](analysis/dummy/) directory contains the scripts `dummydata.R` and `dummydata_controlfinal.R` used to generate dummy data. This is used instead of the usual dummy data specified in the study definition, because it is then possible to impose some more useful structure in the data, such as ensuring nobody has a first dose of both the Pfizer and another vaccine. If the study definition is updated, this script must also be updated to ensure variable names and types match.
- extracting and matching
    -   [`process_treated.R`](analysis/treated/process_treated.R), [`process_controlfinal.R`](analysis/matching/process_controlfinal.R), [`process_controlactual.R`](analysis/matching/process_controlactual.R) and [`process_controlpotential.R`](analysis/matching/process_controlpotential.R) import the extracted database data (or dummy data), standardises some variables and derives some new ones.
    -   [`match_potential.R`](./analysis/matching/match_potential.R) runs the matching algorithm to pair boosted people with unboosted people. It outputs a matched dataset (with unmatched boosts dropped) and other matching diagnostics. The script takes three arguments:
        -  `cohort`, either _under12_ or _over12_, indicating the age group of interest.
        -  `vaxn`, (1,2) indicating the first or second vaccination.
        - `matching_round`, (1,2,3,...) indicating the matching round 
    -   [`table1.R`](analysis/matching/table1.R) summarises Table 1 type cohort characteristics, stratified by study arm and reports on matching coverage and matching flowcharts.
- modelling
    -   [`km.R`](analysis/model/km.R) outputs summary information, unadjusted Kaplan-Meier estimates, effect estimates, incidence rates, and marginalised cumulative incidence estimates for the Cox models. The script uses the `cohort`, `vaxn` arguments and two additonal arguments `outcome` and `subgroup` to pick up the correct models from the modelling script.
        - `outcome` to choose the outcome of interest, for example postest or covidadmitted 
        - `subgroup` to choose which subgroup to run the analysis within. Choose none for no subgroups (i.e., the main analysis). Choose - to select a specific category of a specific variable. 
    -   [`eventcounts.R`](analysis/model/eventcounts.R) reports the event counts within each covariate level.
    -   [`combine.R`](analysis/model/combine.R) combines km estimates from different outcomes. The script uses the `cohort`, `outcome`, and `subgroup` arguments as above 
- covidtests
    - [`process_covidtests.R`](analysis/covidtests/process_covidtests.R) reads in testing data (generates dummy data if not running on real data), processes testing data, performs sense checks and plots the distribution of the testing behaviour variables. The script uses the `cohort`, `vaxn` arguments
    - [`summarise_covidtests.R`](analysis/covidtests/summarise_covidtests.R) calculates and plots the covid testing rate for both study arms. The script uses the `cohort`, `vaxn` arguments.
- moving and releasing files
    - [`release_objects.R`](analysis/release_objects.R) gathers level 4 files ("moderately sensitive") and places them in a single directory for easy review and release

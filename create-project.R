library("tidyverse")
library("yaml")
library("here")
library("glue")
# library("rlang")

source(here("analysis", "design.R"))

# create action functions ----

## create comment function ----
comment <- function(...) {
  list_comments <- list(...)
  comments <- map(list_comments, ~ paste0("## ", ., " ##"))
  comments
}


## create function to convert comment "actions" in a yaml string into proper comments
convert_comment_actions <- function(yaml.txt) {
  yaml.txt %>%
    str_replace_all("\\\n(\\s*)\\'\\'\\:(\\s*)\\'", "\n\\1") %>%
    # str_replace_all("\\\n(\\s*)\\'", "\n\\1") %>%
    str_replace_all("([^\\'])\\\n(\\s*)\\#\\#", "\\1\n\n\\2\\#\\#") %>%
    str_replace_all("\\#\\#\\'\\\n", "\n")
}


## generic action function ----
action <- function(name,
                   run,
                   arguments = NULL,
                   needs = NULL,
                   highly_sensitive = NULL,
                   moderately_sensitive = NULL,
                   ... # other arguments / options for special action types
) {
  outputs <- list(
    highly_sensitive = highly_sensitive,
    moderately_sensitive = moderately_sensitive
  )
  outputs[sapply(outputs, is.null)] <- NULL

  action <- list(
    run = paste(c(run, arguments), collapse = " "),
    needs = needs,
    outputs = outputs,
    ... = ...
  )
  action[sapply(action, is.null)] <- NULL

  action_list <- list(name = action)
  names(action_list) <- name

  action_list
}

namelesslst <- function(...) {
  unname(lst(...))
}

## create a list of actions
lapply_actions <- function(X, FUN) {
  unlist(
    lapply(
      X,
      FUN
    ),
    recursive = FALSE
  )
}


## actions for a single matching round ----




action_1matchround <- function(cohort, vaxn, matching_round) {
  control_extract_date <- study_dates[[cohort]][[glue("control_extract_dates{vaxn}")]][matching_round]

  splice(
    action(
      name = glue("extract_controlpotential_{cohort}_{vaxn}_{matching_round}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_controlpotential",
        " --output-file output/{cohort}/vax{vaxn}/matchround{matching_round}/extract/input_controlpotential.feather",
        " --param cohort={cohort}",
        " --param matching_round={matching_round}",
        " --param index_date={control_extract_date}",
        " --param vaxn={vaxn}"
      ),
      needs = c(
        if (matching_round > 1) {
          glue("process_controlactual_{cohort}_{vaxn}_{matching_round-1}")
        } else {
          NULL
        }
      ) %>% as.list(),
      highly_sensitive = lst(
        cohort = glue("output/{cohort}/vax{vaxn}/matchround{matching_round}/extract/input_controlpotential.feather")
      )
    ),
    action(
      name = glue("process_controlpotential_{cohort}_{vaxn}_{matching_round}"),
      run = glue("r:latest analysis/matching/process_controlpotential.R"),
      arguments = c(cohort, vaxn, matching_round),
      needs = namelesslst(
        glue("extract_controlpotential_{cohort}_{vaxn}_{matching_round}"),
      ),
      highly_sensitive = lst(
        rds = glue("output/{cohort}/vax{vaxn}/matchround{matching_round}/process/*.rds")
      )
    ),
    action(
      name = glue("match_potential_{cohort}_{vaxn}_{matching_round}"),
      run = glue("r:latest analysis/matching/match_potential.R"),
      arguments = c(cohort, vaxn, matching_round),
      needs = c(
        glue("process_treated_{cohort}_{vaxn}"),
        glue("process_controlpotential_{cohort}_{vaxn}_{matching_round}"),
        if (matching_round > 1) {
          glue("process_controlactual_{cohort}_{vaxn}_{matching_round-1}")
        } else {
          NULL
        }
      ) %>% as.list(),
      highly_sensitive = lst(
        rds = glue("output/{cohort}/vax{vaxn}/matchround{matching_round}/potential/*.rds"),
        csv = glue("output/{cohort}/vax{vaxn}/matchround{matching_round}/potential/*.csv.gz"),
      )
    ),
    action(
      name = glue("extract_controlactual_{cohort}_{vaxn}_{matching_round}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_controlactual",
        " --output-file output/{cohort}/vax{vaxn}/matchround{matching_round}/extract/input_controlactual.feather",
        " --param cohort={cohort}",
        " --param matching_round={matching_round}",
        " --param vaxn={vaxn}",
      ),
      needs = namelesslst(
        glue("match_potential_{cohort}_{vaxn}_{matching_round}"),
      ),
      highly_sensitive = lst(
        cohort = glue("output/{cohort}/vax{vaxn}/matchround{matching_round}/extract/input_controlactual.feather")
      )
    ),
    action(
      name = glue("process_controlactual_{cohort}_{vaxn}_{matching_round}"),
      run = glue("r:latest analysis/matching/process_controlactual.R"),
      arguments = c(cohort, vaxn, matching_round),
      needs = c(
        glue("process_treated_{cohort}_{vaxn}"),
        glue("match_potential_{cohort}_{vaxn}_{matching_round}"),
        glue("extract_controlpotential_{cohort}_{vaxn}_{matching_round}"), # this is only necessary for the dummy data
        glue("extract_controlactual_{cohort}_{vaxn}_{matching_round}"),
        if (matching_round > 1) {
          glue("process_controlactual_{cohort}_{vaxn}_{matching_round-1}")
        } else {
          NULL
        }
      ) %>% as.list(),
      highly_sensitive = lst(
        rds = glue("output/{cohort}/vax{vaxn}/matchround{matching_round}/actual/*.rds"),
        csv = glue("output/{cohort}/vax{vaxn}/matchround{matching_round}/actual/*.csv.gz"),
      )
    )
  )
}

# test function
# action_1matchround("over12", 2)

# create all necessary actions for n matching rounds
action_extract_and_match <- function(cohort, vaxn, n_matching_rounds) {
  allrounds <- map(seq_len(n_matching_rounds), ~ action_1matchround(cohort, vaxn, .x)) %>% flatten()

  splice(

    # all treated people
    action(
      name = glue("extract_treated_{cohort}_{vaxn}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_treated",
        " --output-file output/{cohort}/vax{vaxn}/extract/input_treated.feather",
        " --param cohort={cohort}",
        " --param vaxn={vaxn}",
      ),
      highly_sensitive = lst(
        extract = glue("output/{cohort}/vax{vaxn}/extract/input_treated.feather")
      ),
    ),

    # all treated people
    action(
      name = glue("process_treated_{cohort}_{vaxn}"),
      run = glue("r:latest analysis/treated/process_treated.R"),
      arguments = c(cohort, vaxn),
      needs = namelesslst(
        glue("extract_treated_{cohort}_{vaxn}")
      ),
      highly_sensitive = lst(
        rds = glue("output/{cohort}/vax{vaxn}/treated/*.rds")
      ),
    ),
    allrounds,
    action(
      name = glue("extract_controlfinal_{cohort}_{vaxn}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_controlfinal",
        " --output-file output/{cohort}/vax{vaxn}/extract/input_controlfinal.feather",
        " --param cohort={cohort}",
        " --param n_matching_rounds={n_matching_rounds}",
        " --param vaxn={vaxn}",
      ),
      needs = namelesslst(
        glue("process_controlactual_{cohort}_{vaxn}_{n_matching_rounds}")
      ),
      highly_sensitive = lst(
        extract = glue("output/{cohort}/vax{vaxn}/extract/input_controlfinal.feather")
      ),
    ),
    action(
      name = glue("process_controlfinal_{cohort}_{vaxn}"),
      run = glue("r:latest analysis/matching/process_controlfinal.R"),
      arguments = c(cohort, vaxn),
      needs = c(
        map(
          seq_len(n_matching_rounds),
          ~ glue("process_controlactual_{cohort}_{vaxn}_", .x)
        ),
        glue("extract_controlfinal_{cohort}_{vaxn}"),
        glue("process_treated_{cohort}_{vaxn}")
      ),
      highly_sensitive = lst(
        extract = glue("output/{cohort}/vax{vaxn}/match/*.rds"),
        extract_csv = glue("output/{cohort}/vax{vaxn}/match/*.csv.gz"),
      ),
    )
  )
}

# test action
# action_extract_and_match("over12", 2)


action_table1 <- function(cohort, vaxn) {
  action(
    name = glue("table1_{cohort}_{vaxn}"),
    run = glue("r:latest analysis/matching/table1.R"),
    arguments = c(cohort, vaxn),
    needs = namelesslst(
      glue("process_controlfinal_{cohort}_{vaxn}"),
    ),
    moderately_sensitive = lst(
      csv = glue("output/{cohort}/vax{vaxn}/table1/*.csv"),
      # png= glue("output/{cohort}/vax{vaxn}/table1/*.png"),
    )
  )
}

action_covid_test <-function(cohort, vaxn){
  splice(
    lapply_actions(
      c("treated", "control"),
        function(arm)
        action(
          name = glue("extract_covidtests_{cohort}_{vaxn}_{arm}"),
          run = glue(
            "cohortextractor:latest generate_cohort", 
            " --study-definition study_definition_covidtests", 
            " --output-file output/{cohort}/vax{vaxn}/covidtests/extract/input_covidtests_{arm}.feather",
            " --param cohort={cohort}",
            " --param vaxn={vaxn}",
            " --param arm={arm}"
          ),
          needs = namelesslst(
            glue("process_controlfinal_{cohort}_{vaxn}")
          ),
          highly_sensitive = lst(
            extract = glue("output/{cohort}/vax{vaxn}/covidtests/extract/input_covidtests_{arm}.feather")
          )
        )
    ),
    action(
      name = glue("process_covidtests_{cohort}_{vaxn}"),
      run = "r:latest analysis/covidtests/process_covidtests.R",
      arguments = c(cohort, vaxn),
      needs = namelesslst(
        glue("process_controlfinal_{cohort}_{vaxn}"),
        glue("extract_covidtests_{cohort}_{vaxn}_treated"),
        glue("extract_covidtests_{cohort}_{vaxn}_control")
      ),
      highly_sensitive = lst(
        extract = glue("output/{cohort}/vax{vaxn}/covidtests/process/*.rds"),
      ),
      moderately_sensitive = lst(
        skim = glue("output/{cohort}/vax{vaxn}/covidtests/extract/*.txt"),
        png = glue("output/{cohort}/vax{vaxn}/covidtests/checks/*.png")
      )
    ),
  
    action(
      name = glue("summarise_covidtests_{cohort}_{vaxn}"),
      run = "r:latest analysis/covidtests/summarise_covidtests.R",
      arguments = c(cohort, vaxn, "all"), # may want to look in subgroups later, but for now just "all"
      needs = namelesslst(
        glue("process_covidtests_{cohort}_{vaxn}")
      ),
      moderately_sensitive = lst(
        csv = glue("output/{cohort}/vax{vaxn}/covidtests/summary/all/*.csv"),
        png = glue("output/{cohort}/vax{vaxn}/covidtests/summary/all/*.png")
      )
    )
  )
}

action_km <- function(cohort, vaxn, subgroup, outcome) {
  action(
    name = glue("km_{cohort}_{vaxn}_{subgroup}_{outcome}"),
    run = glue("r:latest analysis/model/km.R"),
    arguments = c(cohort, vaxn, subgroup, outcome),
    needs = namelesslst(
      glue("process_controlfinal_{cohort}_{vaxn}"),
    ),
    moderately_sensitive = lst(
      # csv= glue("output/{cohort}/vax{vaxn}/models/km/{subgroup}/{outcome}/*.csv"),
      rds = glue("output/{cohort}/vax{vaxn}/models/km/{subgroup}/{outcome}/*.rds"),
      png = glue("output/{cohort}/vax{vaxn}/models/km/{subgroup}/{outcome}/*.png"),
    )
  )
}

action_eventcounts <- function(cohort, vaxn, subgroup) {
  action(
    name = glue("eventcounts_{cohort}_{vaxn}_{subgroup}"),
    run = glue("r:latest analysis/model/eventcounts.R"),
    arguments = c(cohort, vaxn, subgroup),
    needs = namelesslst(
      glue("process_controlfinal_{cohort}_{vaxn}"),
    ),
    moderately_sensitive = lst(
      rds = glue("output/{cohort}/vax{vaxn}/models/eventcounts/{subgroup}/*.rds"),
    )
  )
}

action_combine <- function(cohort, vaxn) {
  action(
    name = glue("combine_{cohort}_{vaxn}"),
    run = glue("r:latest analysis/model/combine.R"),
    arguments = c(cohort, vaxn),
    needs = splice(
      as.list(
        glue_data(
          .x = expand_grid(
            subgroup = c("all", "prior_covid_infection"),
            outcome = c("postest", "emergency", "covidemergency", "covidadmitted", "covidcritcare", "coviddeath", "noncoviddeath","admitted_unplanned","pericarditis","myocarditis","fracture","noncovidadmitted","outcome_vax_2"),
          ),
          "km_{cohort}_{vaxn}_{subgroup}_{outcome}"
        )
      ),
      as.list(
        glue_data(
          .x = expand_grid(
            subgroup = c("all", "prior_covid_infection"),
          ),
          "eventcounts_{cohort}_{vaxn}_{subgroup}"
        )
      )
    ),
    moderately_sensitive = lst(
      rds = glue("output/{cohort}/vax{vaxn}/models/combined/*.csv"),
      png = glue("output/{cohort}/vax{vaxn}/models/combined/*.png"),
    )
  )
}

action_skim <- function(cohort, vaxn) {
  action(
    name = glue("skim_{cohort}_{vaxn}_matched"),
    run = "r:latest analysis/data_skim.R",
    arguments = c(glue("output/{cohort}/vax{vaxn}/match/data_matched.rds"), glue("output/{cohort}/vax{vaxn}/skim")),
    needs = list(glue("process_controlfinal_{cohort}_{vaxn}")),
    moderately_sensitive = lst(
      cohort = glue("output/{cohort}/vax{vaxn}/skim/*.txt")
    )
  )
}

action_skim_treated <- function(cohort, vaxn) {
  action(
    name = glue("skim_{cohort}_{vaxn}_treated"),
    run = "r:latest analysis/data_skim.R",
    arguments = c(glue("output/{cohort}/vax{vaxn}/treated/data_treatedeligible.rds"), glue("output/{cohort}/vax{vaxn}/skim/treated")),
    needs = list(glue("process_treated_{cohort}_{vaxn}")),
    moderately_sensitive = lst(
      cohort = glue("output/{cohort}/vax{vaxn}/skim/treated/*.txt")
    )
  )
}

action_skim_control <- function(cohort, vaxn,matching_round) {
  action(
    name = glue("skim_{cohort}_{vaxn}_control"),
    run = "r:latest analysis/data_skim.R",
    arguments = c(glue("output/{cohort}/vax{vaxn}/matchround{matching_round}/process/data_controlpotential.rds"), glue("output/{cohort}/vax{vaxn}/skim/control")),
    needs = list(glue("process_controlpotential_{cohort}_{vaxn}_{matching_round}")),
    moderately_sensitive = lst(
      cohort = glue("output/{cohort}/vax{vaxn}/skim/control/*.txt")
    )
  )
}


# specify project ----

## defaults ----
defaults_list <- lst(
  version = "3.0",
  expectations = lst(population_size = 100000L)
)

## actions ----
actions_list <- splice(
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "DO NOT EDIT project.yaml DIRECTLY",
    "This file is created by create-project.R",
    "Edit and run create-project.R to update the project.yaml",
    "# # # # # # # # # # # # # # # # # # #",
    " "
  ),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Vax1, Over 12s cohort",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Extract and match"
  ),
  action_extract_and_match("over12", 1, n_matching_rounds),
  action_skim_treated("over12", 1),
  action_skim_control("over12", 1, 1),
  action_skim("over12", 1),
  action_table1("over12", 1),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Model"
  ),
  action_km("over12", 1, "all", "postest"),
  action_km("over12", 1, "all", "emergency"),
  action_km("over12", 1, "all", "covidemergency"),
  action_km("over12", 1, "all", "covidadmitted"),
  action_km("over12", 1, "all", "covidcritcare"),
  action_km("over12", 1, "all", "coviddeath"),
  action_km("over12", 1, "all", "noncoviddeath"),
  action_km("over12", 1, "all", "admitted_unplanned"),
  action_km("over12", 1, "all", "pericarditis"),
  action_km("over12", 1, "all", "myocarditis"),
  action_km("over12", 1, "all", "fracture"),
  action_km("over12", 1, "all", "noncovidadmitted"),
  action_km("over12", 1, "all", "outcome_vax_2"),
  action_km("over12", 1, "prior_covid_infection", "postest"),
  action_km("over12", 1, "prior_covid_infection", "emergency"),
  action_km("over12", 1, "prior_covid_infection", "covidemergency"),
  action_km("over12", 1, "prior_covid_infection", "covidadmitted"),
  action_km("over12", 1, "prior_covid_infection", "covidcritcare"),
  action_km("over12", 1, "prior_covid_infection", "coviddeath"),
  action_km("over12", 1, "prior_covid_infection", "noncoviddeath"),
  action_km("over12", 1, "prior_covid_infection", "admitted_unplanned"),
  action_km("over12", 1, "prior_covid_infection", "pericarditis"),
  action_km("over12", 1, "prior_covid_infection", "myocarditis"),
  action_km("over12", 1, "prior_covid_infection", "fracture"),
  action_km("over12", 1, "prior_covid_infection", "noncovidadmitted"),
  action_km("over12", 1, "prior_covid_infection", "outcome_vax_2"),
  action_eventcounts("over12", 1, "all"),
  action_eventcounts("over12", 1, "prior_covid_infection"),
  action_combine("over12", 1),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Covid tests data",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  action_covid_test("over12", 1),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Vax2, Over 12s cohort",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  action_extract_and_match("over12", 2, n_matching_rounds),
  action_skim("over12", 2),
  action_table1("over12", 2),
  action_km("over12", 2, "all", "postest"),
  action_km("over12", 2, "all", "emergency"),
  action_km("over12", 2, "all", "covidemergency"),
  action_km("over12", 2, "all", "covidadmitted"),
  action_km("over12", 2, "all", "covidcritcare"),
  action_km("over12", 2, "all", "coviddeath"),
  action_km("over12", 2, "all", "noncoviddeath"),
  action_km("over12", 2, "all", "admitted_unplanned"),
  action_km("over12", 2, "all", "pericarditis"),
  action_km("over12", 2, "all", "myocarditis"),
  action_km("over12", 2, "all", "fracture"),
  action_km("over12", 2, "all", "noncovidadmitted"),
  action_km("over12", 2, "all", "outcome_vax_2"),
  action_km("over12", 2, "prior_covid_infection", "postest"),
  action_km("over12", 2, "prior_covid_infection", "emergency"),
  action_km("over12", 2, "prior_covid_infection", "covidemergency"),
  action_km("over12", 2, "prior_covid_infection", "covidadmitted"),
  action_km("over12", 2, "prior_covid_infection", "covidcritcare"),
  action_km("over12", 2, "prior_covid_infection", "coviddeath"),
  action_km("over12", 2, "prior_covid_infection", "noncoviddeath"),
  action_km("over12", 2, "prior_covid_infection", "admitted_unplanned"),
  action_km("over12", 2, "prior_covid_infection", "pericarditis"),
  action_km("over12", 2, "prior_covid_infection", "myocarditis"),
  action_km("over12", 2, "prior_covid_infection", "fracture"),
  action_km("over12", 2, "prior_covid_infection", "noncovidadmitted"),
  action_km("over12", 2, "prior_covid_infection", "outcome_vax_2"),
  action_eventcounts("over12", 2, "all"),
  action_eventcounts("over12", 2, "prior_covid_infection"),
  action_combine("over12", 2),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Covid tests data",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  action_covid_test("over12", 2),

  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Vax1, Under 12s cohort",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Extract and match"
  ),
  action_extract_and_match("under12", 1, n_matching_rounds),
  action_skim("under12", 1),
  action_table1("under12", 1),

  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Model"
  ),
  action_km("under12", 1, "all", "postest"),
  action_km("under12", 1, "all", "emergency"),
  action_km("under12", 1, "all", "covidemergency"),
  action_km("under12", 1, "all", "covidadmitted"),
  action_km("under12", 1, "all", "covidcritcare"),
  action_km("under12", 1, "all", "coviddeath"),
  action_km("under12", 1, "all", "noncoviddeath"),
  action_km("under12", 1, "all", "admitted_unplanned"),
  action_km("under12", 1, "all", "pericarditis"),
  action_km("under12", 1, "all", "myocarditis"),
  action_km("under12", 1, "all", "fracture"),
  action_km("under12", 1, "all", "noncovidadmitted"),
  action_km("under12", 1, "all", "outcome_vax_2"),
  action_km("under12", 1, "prior_covid_infection", "postest"),
  action_km("under12", 1, "prior_covid_infection", "emergency"),
  action_km("under12", 1, "prior_covid_infection", "covidemergency"),
  action_km("under12", 1, "prior_covid_infection", "covidadmitted"),
  action_km("under12", 1, "prior_covid_infection", "covidcritcare"),
  action_km("under12", 1, "prior_covid_infection", "coviddeath"),
  action_km("under12", 1, "prior_covid_infection", "noncoviddeath"),
  action_km("under12", 1, "prior_covid_infection", "admitted_unplanned"),
  action_km("under12", 1, "prior_covid_infection", "pericarditis"),
  action_km("under12", 1, "prior_covid_infection", "myocarditis"),
  action_km("under12", 1, "prior_covid_infection", "fracture"),
  action_km("under12", 1, "prior_covid_infection", "noncovidadmitted"),
  action_km("under12", 1, "prior_covid_infection", "outcome_vax_2"),
  action_eventcounts("under12", 1, "all"),
  action_eventcounts("under12", 1, "prior_covid_infection"),
  action_combine("under12", 1),
    comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Covid tests data",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  action_covid_test("under12", 1),

   comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Vax2, Under 12s cohort",
    "# # # # # # # # # # # # # # # # # # #"
  ),

  action_extract_and_match("under12", 2, n_matching_rounds),
  action_skim("under12", 2),
  action_table1("under12", 2),

  action_km("under12", 2, "all", "postest"),
  action_km("under12", 2, "all", "emergency"),
  action_km("under12", 2, "all", "covidemergency"),
  action_km("under12", 2, "all", "covidadmitted"),
  action_km("under12", 2, "all", "covidcritcare"),
  action_km("under12", 2, "all", "coviddeath"),
  action_km("under12", 2, "all", "noncoviddeath"),
  action_km("under12", 2, "all", "admitted_unplanned"),
  action_km("under12", 2, "all", "pericarditis"),
  action_km("under12", 2, "all", "myocarditis"),
  action_km("under12", 2, "all", "fracture"),
  action_km("under12", 2, "all", "noncovidadmitted"),
  action_km("under12", 2, "all", "outcome_vax_2"),
  action_km("under12", 2, "prior_covid_infection", "postest"),
  action_km("under12", 2, "prior_covid_infection", "emergency"),
  action_km("under12", 2, "prior_covid_infection", "covidemergency"),
  action_km("under12", 2, "prior_covid_infection", "covidadmitted"),
  action_km("under12", 2, "prior_covid_infection", "covidcritcare"),
  action_km("under12", 2, "prior_covid_infection", "coviddeath"),
  action_km("under12", 2, "prior_covid_infection", "noncoviddeath"),
  action_km("under12", 2, "prior_covid_infection", "admitted_unplanned"),
  action_km("under12", 2, "prior_covid_infection", "pericarditis"),
  action_km("under12", 2, "prior_covid_infection", "myocarditis"),
  action_km("under12", 2, "prior_covid_infection", "fracture"),
  action_km("under12", 2, "prior_covid_infection", "noncovidadmitted"),
  action_km("under12", 2, "prior_covid_infection", "outcome_vax_2"),
  action_eventcounts("under12", 2, "all"),
  action_eventcounts("under12", 2, "prior_covid_infection"),
  action_combine("under12", 2),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Covid tests data",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  action_covid_test("under12", 2),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Move files for release",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  action(
    name = "release",
    run = glue("r:latest analysis/release_objects.R"),
    needs = namelesslst(
      glue("table1_over12_1"),
      glue("combine_over12_1"),
      glue("summarise_covidtests_over12_1"),
      glue("table1_under12_1"),
      glue("combine_under12_1"),
      glue("summarise_covidtests_under12_1"),
      glue("table1_over12_2"),
      glue("combine_over12_2"),
      glue("summarise_covidtests_over12_2"),
      glue("table1_under12_2"),
      glue("combine_under12_2"),
      glue("summarise_covidtests_under12_2"),
    ),
    moderately_sensitive = lst(
      txt = glue("output/meta-release/*.txt"),
      csv = glue("output/release/*.csv"),
    ),
  ),
  comment("#### End ####")
)

project_list <- splice(
  defaults_list,
  list(actions = actions_list)
)

## convert list to yaml, reformat comments and whitespace ----
thisproject <- as.yaml(project_list, indent = 2) %>%
  # convert comment actions to comments
  convert_comment_actions() %>%
  # add one blank line before level 1 and level 2 keys
  str_replace_all("\\\n(\\w)", "\n\n\\1") %>%
  str_replace_all("\\\n\\s\\s(\\w)", "\n\n  \\1")


# if running via opensafely, check that the project on disk is the same as the project created here:
if (Sys.getenv("OPENSAFELY_BACKEND") %in% c("expectations", "tpp")) {
  thisprojectsplit <- str_split(thisproject, "\n")
  currentproject <- readLines(here("project.yaml"))

  stopifnot("project.yaml is not up-to-date with create-project.R.  Run create-project.R before running further actions." = identical(thisprojectsplit, currentproject))

  # if running manually, output new project as normal
} else if (Sys.getenv("OPENSAFELY_BACKEND") %in% c("")) {

  ## output to file ----
  writeLines(thisproject, here("project.yaml"))
  # yaml::write_yaml(project_list, file =here("project.yaml"))

  ## grab all action names and send to a txt file

  names(actions_list) %>%
    tibble(action = .) %>%
    mutate(
      model = action == "" & lag(action != "", 1, TRUE),
      model_number = cumsum(model),
    ) %>%
    group_by(model_number) %>%
    summarise(
      sets = str_trim(paste(action, collapse = " "))
    ) %>%
    pull(sets) %>%
    paste(collapse = "\n") %>%
    writeLines(here("actions.txt"))

  # fail if backend not recognised
} else {
  stop("Backend not recognised by create.project.R script")
}

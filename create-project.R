library("tidyverse")
library("yaml")
library("here")
library("glue")

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

## generate dataset report function
action_report <- function(cohort, matching_round) {
  action(
    name = glue("generate_dataset_report_{cohort}{matching_round}"),
    run = glue("dataset-report:v0.0.24"),
    arguments = glue("--input-files output/input_{cohort}{matching_round}.feather", "  --output-dir output/"),
    needs = list(glue("generate_study_{cohort}{matching_round}")),
    moderately_sensitive = list(
      dataset_report = glue("output/input_{cohort}{matching_round}.html")
    ),
  )
}

## generate study cohort function
action_generate <- function(cohort, matching_round) {
  splice(
    action(
      name = glue("generate_study_{cohort}{matching_round}"),
      run = glue("cohortextractor:latest generate_cohort --study-definition study_definition_{cohort}{matching_round}  --output-format feather"),
      highly_sensitive = list(
        cohort = glue("output/input_{cohort}{matching_round}.feather")
      ),
    ),
    action_report(cohort, matching_round)
  )
}

action_generate_needs <- function(cohort, agegroup, matching_round) {
  splice(
    action(
      name = glue("generate_study_{cohort}{matching_round}"),
      run = glue("cohortextractor:latest generate_cohort
                   --study-definition study_definition_{cohort}{matching_round}
                   --output-format feather"),
      needs = list(glue("matching{matching_round}_{agegroup}")),
      highly_sensitive = list(
        cohort = glue("output/input_{cohort}{matching_round}.feather")
      ),
    ),
    action_report(cohort, matching_round)
  )
}


action_generate_date <- function(cohort, startdate, matching_round) {
  splice(
    action(
      name = glue("generate_study_{cohort}{matching_round}"),
      run = glue("cohortextractor:latest generate_cohort --study-definition study_definition_{cohort} --output-format feather"),
      arguments = glue("--index-date-range \"{startdate} to {startdate} by week\""),
      highly_sensitive = list(
        dataset_report = glue("output/input_{cohort}_{startdate}.feather")
      ),
    )
  )
}


## data process function
action_process <- function(cohort, agegroup, matching_round) {
  if (cohort == "treated") {
    eligible <- "_eligible"
    splice(
      action(
        name = glue("data_process_{cohort}{matching_round}_{agegroup}"),
        run = glue("r:latest analysis/data_process_{cohort}.R {agegroup} {matching_round}"),
        needs = list(glue("generate_study_{cohort}{matching_round}")),
        highly_sensitive = lst(
          rds = glue("output/data/data_{cohort}{matching_round}{eligible}_{agegroup}.rds")
        ),
        moderately_sensitive = lst(
          flowchart = glue("output/data/flowchart_{cohort}{matching_round}{eligible}_{agegroup}.csv")
        ),
      )
    )
  } else {
    eligible <- ""
    splice(
      action(
        name = glue("data_process_{cohort}{matching_round}_{agegroup}"),
        run = glue("r:latest analysis/data_process_{cohort}.R {agegroup} {matching_round}"),
        needs = list(glue("generate_study_{cohort}{matching_round}")),
        highly_sensitive = lst(
          rds = glue("output/data/data_{cohort}{matching_round}{eligible}_{agegroup}.rds")
        ),
      )
    )
  }
}


## skim function
action_skim <- function(cohort, agegroup) {
  splice(
    action(
      name = glue("skim_data_{cohort}_{agegroup}"),
      run = glue("r:latest analysis/data_skim.R"),
      arguments = glue("output/data/data_{cohort}_eligible_{agegroup}.rds", "  output/data_properties"),
      needs = list(glue("data_process_{cohort}_{agegroup}")),
      moderately_sensitive = lst(
        txt = glue("output/data_properties/data_{cohort}_eligible_{agegroup}*.txt")
      ),
    )
  )
}
## match action function ----

action_match <- function(cohort1, cohort2, agegroup, matching_round) {
  splice(
    action(
      name = glue("matching{matching_round}_{agegroup}"),
      run = glue("r:latest analysis/matching.R"),
      arguments = c(agegroup, matching_round),
      needs = list(
        glue("data_process_{cohort1}_{agegroup}"),
        glue("data_process_{cohort2}{matching_round}_{agegroup}")
      ),
      highly_sensitive = list(
        rds1 = glue("output/match/data_potential_matchstatus{matching_round}_{agegroup}.rds"),
        rds2 = glue("output/match/data_potential_matched{matching_round}_{agegroup}.rds"),
        csv =  glue("output/match/potential_matched_controls{matching_round}_{agegroup}.csv.gz")
      ),
    ),
    action(
      name = glue("skim_potential_matched{matching_round}_{agegroup}"),
      run = glue("r:latest analysis/data_skim.R"),
      arguments = glue("output/match/data_potential_matched{matching_round}_{agegroup}.rds", "  output/data_properties"),
      needs = list(glue("matching{matching_round}_{agegroup}")),
      moderately_sensitive = lst(
        txt = glue("output/data_properties/data_potential_matched{matching_round}_{agegroup}*.txt")
      ),
    )
  )
}

action_match_filter <- function(agegroup, matching_round) {
  action(
    name = glue("matching_filter{matching_round}_{agegroup}"),
    run = glue("r:latest analysis/matching_filter.R"),
    arguments = c(agegroup, matching_round),
    needs = list(
      glue("matching{matching_round}_{agegroup}"),
      glue("generate_study_control_potential{matching_round}")
    ),
    highly_sensitive = list(
      rds1 = glue("output/match/data_matchstatus_allrounds{matching_round}_{agegroup}.rds"),
      rds2 = glue("output/match/data_match_actual{matching_round}_{agegroup}.rds")
    ),
  )
}

action_combine <- function(agegroup) {
  action(
    name = glue("combine_together_{agegroup}"),
    run = glue("r:latest analysis/matching_combine.R"),
    arguments = c(agegroup),
    needs = list(
      glue("matching_filter1_{agegroup}"),
      glue("matching_filter2_{agegroup}")
    ),
    highly_sensitive = list(
      rds = glue("output/match/data_match_all.rds")
    ),
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
    "# # # # # # # # # # # # # # # # # # #"
  ),
  comment("# # # # # # # # # # # # # # # # # # #", "Pre-server scripts", "# # # # # # # # # # # # # # # # # # #"),

  # do not incorporate into project for now -- just run locally

  # action(
  #   name = "checkyaml",
  #   run = "r:latest create-project.R",
  #   moderately_sensitive = lst(
  #     project = "project.yaml"
  #   )
  # ),

  # action(
  #   name = "dummydata",
  #   run = "r:latest analysis/dummydata.R",
  #   moderately_sensitive = lst(
  #     metadata = "output/design/*"
  #   )
  # ),


  comment("# # # # # # # # # # # # # # # # # # #", "Extract and tidy", "# # # # # # # # # # # # # # # # # # #"),
  action_generate("treated", ""),
  action_process("treated", "over12", ""),
  comment("# # # # # # # # # # # # # # # # # # #", "skim data", "# # # # # # # # # # # # # # # # # # #"),
  action_skim("treated", "over12"),
  comment("# # # # # # # # # # # # # # # # # # #", "matching round 1", "# # # # # # # # # # # # # # # # # # #"),
  action_generate_date("control_potential", "2021-09-20", "1"),
  action_process("control_potential", "over12", "1"),
  action_match("treated", "control_potential", "over12", "1"),
  action_generate_needs("control_match", "over12", "1"),
  action_match_filter("over12", "1")#,
  # comment("# # # # # # # # # # # # # # # # # # #", "matching round 2", "# # # # # # # # # # # # # # # # # # #"),
  # action_generate_date("control_potential", "2021-10-04", "2"),
  # action_process("control_potential", "over12", "2"),
  # action_match("treated", "control_potential", "over12", "2"),
  # action_generate_needs("control_match", "over12", "2"),
  # action_match_filter("over12", "2"),
  # comment("# # # # # # # # # # # # # # # # # # #", "combine together", "# # # # # # # # # # # # # # # # # # #"),
  # action_combine("over12")
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
  stop("Backend not recognised")
}

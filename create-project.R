library('tidyverse')
library('yaml')
library('here')
library('glue')

# create action functions ----

## create comment function ----
comment <- function(...){
  list_comments <- list(...)
  comments <- map(list_comments, ~paste0("## ", ., " ##"))
  comments
}


## create function to convert comment "actions" in a yaml string into proper comments
convert_comment_actions <-function(yaml.txt){
  yaml.txt %>%
    str_replace_all("\\\n(\\s*)\\'\\'\\:(\\s*)\\'", "\n\\1")  %>%
    #str_replace_all("\\\n(\\s*)\\'", "\n\\1") %>%
    str_replace_all("([^\\'])\\\n(\\s*)\\#\\#", "\\1\n\n\\2\\#\\#") %>%
    str_replace_all("\\#\\#\\'\\\n", "\n")
}


## generic action function ----
action <- function(
  name,
  run,
  arguments=NULL,
  needs=NULL,
  highly_sensitive=NULL,
  moderately_sensitive=NULL,
  ... # other arguments / options for special action types
){

  outputs <- list(
    highly_sensitive = highly_sensitive,
    moderately_sensitive = moderately_sensitive
  )
  outputs[sapply(outputs, is.null)] <- NULL

  action <- list(
    run = paste(c(run, arguments), collapse=" "),
    needs = needs,
    outputs = outputs,
    ... = ...
  )
  action[sapply(action, is.null)] <- NULL

  action_list <- list(name = action)
  names(action_list) <- name

  action_list
}


## match action function ----

action_match <- function(treatment){

  splice(

    action(
      name = glue("match_seqtrialcox_{treatment}"),
      run = glue("r:latest analysis/match_seqtrialcox.R"),
      arguments = c(treatment),
      needs = list("data_selection", "data_process_long"),
      highly_sensitive = lst(
        rds = glue("output/match/{treatment}/match_*.rds")
      ),
      moderately_sensitive = lst(
        txt = glue("output/match/{treatment}/match_*.txt"),
        #csv = glue("output/match/{treatment}/match_*.csv"),
      )
    ),

    action(
      name = glue("merge_seqtrialcox_{treatment}"),
      run = glue("r:latest analysis/merge_seqtrialcox.R"),
      arguments = c(treatment),
      needs = list("data_process", "data_process_long", "data_selection",  glue("match_seqtrialcox_{treatment}")),
      moderately_sensitive = lst(
        txt = glue("output/match/{treatment}/merge_*.txt"),
        csv = glue("output/match/{treatment}/merge_*.csv"),
        #svg = glue("output/match/{treatment}/merge_*.svg"),
        png = glue("output/match/{treatment}/merge_*.png"),
        pdf = glue("output/match/{treatment}/merge_*.pdf"),
        html = glue("output/match/{treatment}/merge_*.html")
      )
    )
  )


}

## model action function ----
action_model <- function(
  treatment, outcome, subgroup
){

  splice(

    action(
      name = glue("model_seqtrialcox_{treatment}_{outcome}_{subgroup}"),
      run = glue("r:latest analysis/model_seqtrialcox.R"),
      arguments = c(treatment, outcome, subgroup),
      needs = list(
        glue("match_seqtrialcox_{treatment}"),
        "data_selection",
        "data_process_long"
      ),
      highly_sensitive = lst(
        rds = glue("output/models/seqtrialcox/{treatment}/{outcome}/{subgroup}/model_*.rds")
      ),
      moderately_sensitive = lst(
        txt = glue("output/models/seqtrialcox/{treatment}/{outcome}/{subgroup}/model_*.txt"),
        csv = glue("output/models/seqtrialcox/{treatment}/{outcome}/{subgroup}/model_*.csv")
      )
    ),

    action(
      name = glue("report_seqtrialcox_{treatment}_{outcome}_{subgroup}"),
      run = glue("r:latest analysis/report_seqtrialcox.R"),
      arguments = c(treatment, outcome, subgroup),
      needs = list(
        "data_selection",
        glue("model_seqtrialcox_{treatment}_{outcome}_{subgroup}"),
        glue("match_seqtrialcox_{treatment}")

      ),
      moderately_sensitive = lst(
        csv = glue("output/models/seqtrialcox/{treatment}/{outcome}/{subgroup}/report_*.csv"),
        svg = glue("output/models/seqtrialcox/{treatment}/{outcome}/{subgroup}/report_*.svg"),
        png = glue("output/models/seqtrialcox/{treatment}/{outcome}/{subgroup}/report_*.png")
      )
    )
  )
}

## model action function ----
action_combine_model <- function(
    subgroup, subgroup_levels
){
  dash <- if(paste0(subgroup_levels, collapse="")=="") "" else "-"
  action(
    name = glue("combine_model_{subgroup}"),
    run = glue("r:latest analysis/combine_model.R"),
    arguments = c(subgroup),
    needs = splice(
      as.list(
        glue_data(
          .x=expand_grid(
            treatment=c("pfizer", "moderna")
          ),
          "match_seqtrialcox_{treatment}"
        )
      ),
      as.list(
        glue_data(
          .x=expand_grid(
            subgroups = paste0(subgroup,dash,subgroup_levels),
            treatment=c("pfizer", "moderna"),
            outcome=c("postest", "covidemergency", "covidadmittedproxy1", "covidadmitted", "noncovidadmitted", "coviddeath", "noncoviddeath"),
            script=c("model", "report"),

          ),
          "{script}_seqtrialcox_{treatment}_{outcome}_{subgroups}"
        )
      )
    ),
    moderately_sensitive = lst(
      csv = glue("output/models/seqtrialcox/combined/{subgroup}/*.csv"),
      png = glue("output/models/seqtrialcox/combined/{subgroup}/*.png"),
      pdf = glue("output/models/seqtrialcox/combined/{subgroup}/*.pdf"),
      svg = glue("output/models/seqtrialcox/combined/{subgroup}/*.svg"),
      html = glue("output/models/seqtrialcox/combined/{subgroup}/*.html"),
    )
  )
}

# specify project ----

## defaults ----
defaults_list <- lst(
  version = "3.0",
  expectations= lst(population_size=100000L)
)

## actions ----
actions_list <- splice(

  comment("# # # # # # # # # # # # # # # # # # #",
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

  action(
    name = "extract",
    run = "cohortextractor:latest generate_cohort --study-definition study_definition --output-format feather",
    needs = list(),
    highly_sensitive = lst(
      cohort = "output/input.feather"
    )
  ),

  action(
    name = "extract_report",
    run = "cohort-report:v3.0.0 output/input.feather",
    needs = list("extract"),
    config = list(output_path = "output/data/reports/extract/"),
    moderately_sensitive = lst(
      html = "output/data/reports/extract/*.html",
      png = "output/data/reports/extract/*.png",
    )
  ),


  action(
    name = "data_process",
    run = "r:latest analysis/data_process.R",
    needs = list("extract"),
    highly_sensitive = lst(
      rds = "output/data/data_processed.rds",
      vaxlong = "output/data/data_vaxlong.rds"
    )
  ),

  action(
    name = "skim_process",
    run = "r:latest analysis/data_skim.R",
    arguments = c("output/data/data_processed.rds", "output/data_properties"),
    needs = list("data_process"),
    moderately_sensitive = lst(
      cohort = "output/data_properties/data_processed*.txt"
    )
  ),

  action(
    name = "data_process_long",
    run = "r:latest analysis/data_process_long.R",
    needs = list("data_process"),
    highly_sensitive = lst(
      processed = "output/data/data_long*.rds",
    )
  ),

  action(
    name = "data_selection",
    run = "r:latest analysis/data_selection.R",
    needs = list("data_process"),
    highly_sensitive = lst(
      data = "output/data/data_cohort.rds",
      feather = "output/data/data_cohort.feather"
    ),
    moderately_sensitive = lst(
      flow = "output/data/flowchart.csv"
    )
  ),

  action(
    name = "skim_selection",
    run = "r:latest analysis/data_skim.R",
    arguments = c("output/data/data_cohort.rds", "output/data_properties"),
    needs = list("data_selection"),
    moderately_sensitive = lst(
      cohort = "output/data_properties/data_cohort*.txt"
    )
  ),


  action(
    name = "cohort_report",
    run = "cohort-report:v3.0.0 output/data/data_cohort.feather",
    needs = list("data_selection"),
    config = list(output_path = "output/data/reports/cohort/"),
    moderately_sensitive = lst(
      html = "output/data/reports/cohort/*.html",
      png = "output/data/reports/cohort/*.png",
    )
  ),

  comment("# # # # # # # # # # # # # # # # # # #", "Descriptive stats", "# # # # # # # # # # # # # # # # # # #"),

  action(
    name = "descriptive_table1",
    run = "r:latest analysis/table1.R",
    needs = list("data_selection"),
    moderately_sensitive = lst(
      html = "output/descriptive/table1/*.html",
      csv = "output/descriptive/table1/*.csv"
    )
  ),

  action(
    name = "descriptive_vaxdate",
    run = "r:latest analysis/vax_date.R",
    needs = list("data_selection"),
    moderately_sensitive = lst(
      png = "output/descriptive/vaxdate/*.png",
      pdf = "output/descriptive/vaxdate/*.pdf",
      svg = "output/descriptive/vaxdate/*.svg"
    )
  ),


  comment("# # # # # # # # # # # # # # # # # # #", "Matching", "# # # # # # # # # # # # # # # # # # #"),

  action_match("pfizer"),
  action_match("moderna"),

  action(
    name = "combine_match",
    run = "r:latest analysis/combine_match.R",
    needs = splice(
      as.list(
        glue_data(
          .x=expand_grid(
            script = c("match", "merge"),
            treatment=c("pfizer", "moderna")
          ),
          "{script}_seqtrialcox_{treatment}",
        )
      )
    ),
    moderately_sensitive = lst(
      csv = "output/match/combined/*.csv",
      # png = "output/match/combined/*.png",
      # pdf = "output/match/combined/*.pdf",
      # svg = "output/match/combined/*.svg"
    )
  ),


  comment("# # # # # # # # # # # # # # # # # # #", "Pfizer models", "# # # # # # # # # # # # # # # # # # #"),


  comment("### Overall models ('none')"),

  action_model("pfizer", "postest", "none"),
  action_model("pfizer", "covidemergency", "none"),
  action_model("pfizer", "covidadmittedproxy1", "none"),
  action_model("pfizer", "covidadmitted", "none"),
  action_model("pfizer", "noncovidadmitted", "none"),
  action_model("pfizer", "covidcc", "none"),
  action_model("pfizer", "coviddeath", "none"),
  action_model("pfizer", "noncoviddeath", "none"),

  comment("### Models by primary course ('vax12_type')"),

  action_model("pfizer", "postest", "vax12_type-az-az"),
  action_model("pfizer", "postest", "vax12_type-pfizer-pfizer"),
  action_model("pfizer", "covidemergency", "vax12_type-az-az"),
  action_model("pfizer", "covidemergency", "vax12_type-pfizer-pfizer"),
  action_model("pfizer", "covidadmittedproxy1", "vax12_type-az-az"),
  action_model("pfizer", "covidadmittedproxy1", "vax12_type-pfizer-pfizer"),
  action_model("pfizer", "covidadmitted", "vax12_type-az-az"),
  action_model("pfizer", "covidadmitted", "vax12_type-pfizer-pfizer"),
  action_model("pfizer", "noncovidadmitted", "vax12_type-az-az"),
  action_model("pfizer", "noncovidadmitted", "vax12_type-pfizer-pfizer"),
  action_model("pfizer", "covidcc", "vax12_type-az-az"),
  action_model("pfizer", "covidcc", "vax12_type-pfizer-pfizer"),
  action_model("pfizer", "coviddeath", "vax12_type-az-az"),
  action_model("pfizer", "coviddeath", "vax12_type-pfizer-pfizer"),
  action_model("pfizer", "noncoviddeath", "vax12_type-az-az"),
  action_model("pfizer", "noncoviddeath", "vax12_type-pfizer-pfizer"),


  comment("### Models by clinical extremely vulnerable ('cev')"),

  action_model("pfizer", "postest", "cev-FALSE"),
  action_model("pfizer", "postest", "cev-TRUE"),
  action_model("pfizer", "covidemergency", "cev-FALSE"),
  action_model("pfizer", "covidemergency", "cev-TRUE"),
  action_model("pfizer", "covidadmittedproxy1", "cev-FALSE"),
  action_model("pfizer", "covidadmittedproxy1", "cev-TRUE"),
  action_model("pfizer", "covidadmitted", "cev-FALSE"),
  action_model("pfizer", "covidadmitted", "cev-TRUE"),
  action_model("pfizer", "noncovidadmitted", "cev-FALSE"),
  action_model("pfizer", "noncovidadmitted", "cev-TRUE"),
  action_model("pfizer", "covidcc", "cev-FALSE"),
  action_model("pfizer", "covidcc", "cev-TRUE"),
  action_model("pfizer", "coviddeath", "cev-FALSE"),
  action_model("pfizer", "coviddeath", "cev-TRUE"),
  action_model("pfizer", "noncoviddeath", "cev-FALSE"),
  action_model("pfizer", "noncoviddeath", "cev-TRUE"),

  comment("### Models by prior infection ('prior_covid_infection')"),

  action_model("pfizer", "postest", "prior_covid_infection-FALSE"),
  action_model("pfizer", "postest", "prior_covid_infection-TRUE"),
  action_model("pfizer", "covidemergency", "prior_covid_infection-FALSE"),
  action_model("pfizer", "covidemergency", "prior_covid_infection-TRUE"),
  action_model("pfizer", "covidadmittedproxy1", "prior_covid_infection-FALSE"),
  action_model("pfizer", "covidadmittedproxy1", "prior_covid_infection-TRUE"),
  action_model("pfizer", "covidadmitted", "prior_covid_infection-FALSE"),
  action_model("pfizer", "covidadmitted", "prior_covid_infection-TRUE"),
  action_model("pfizer", "noncovidadmitted", "prior_covid_infection-FALSE"),
  action_model("pfizer", "noncovidadmitted", "prior_covid_infection-TRUE"),
  action_model("pfizer", "covidcc", "prior_covid_infection-FALSE"),
  action_model("pfizer", "covidcc", "prior_covid_infection-TRUE"),
  action_model("pfizer", "coviddeath", "prior_covid_infection-FALSE"),
  action_model("pfizer", "coviddeath", "prior_covid_infection-TRUE"),
  action_model("pfizer", "noncoviddeath", "prior_covid_infection-FALSE"),
  action_model("pfizer", "noncoviddeath", "prior_covid_infection-TRUE"),

  comment("### Models by age ('age65plus')"),

  action_model("pfizer", "postest", "age65plus-FALSE"),
  action_model("pfizer", "postest", "age65plus-TRUE"),
  action_model("pfizer", "covidemergency", "age65plus-FALSE"),
  action_model("pfizer", "covidemergency", "age65plus-TRUE"),
  action_model("pfizer", "covidadmittedproxy1", "age65plus-FALSE"),
  action_model("pfizer", "covidadmittedproxy1", "age65plus-TRUE"),
  action_model("pfizer", "covidadmitted", "age65plus-FALSE"),
  action_model("pfizer", "covidadmitted", "age65plus-TRUE"),
  action_model("pfizer", "noncovidadmitted", "age65plus-FALSE"),
  action_model("pfizer", "noncovidadmitted", "age65plus-TRUE"),
  action_model("pfizer", "covidcc", "age65plus-FALSE"),
  action_model("pfizer", "covidcc", "age65plus-TRUE"),
  action_model("pfizer", "coviddeath", "age65plus-FALSE"),
  action_model("pfizer", "coviddeath", "age65plus-TRUE"),
  action_model("pfizer", "noncoviddeath", "age65plus-FALSE"),
  action_model("pfizer", "noncoviddeath", "age65plus-TRUE"),

  comment("# # # # # # # # # # # # # # # # # # #", "Moderna models", "# # # # # # # # # # # # # # # # # # #"),

  comment("### Overall models ('none')"),

  action_model("moderna", "postest", "none"),
  action_model("moderna", "covidemergency", "none"),
  action_model("moderna", "covidadmittedproxy1", "none"),
  action_model("moderna", "covidadmitted", "none"),
  action_model("moderna", "noncovidadmitted", "none"),
  action_model("moderna", "covidcc", "none"),
  action_model("moderna", "coviddeath", "none"),
  action_model("moderna", "noncoviddeath", "none"),

  comment("### Models by primary course ('vax12_type')"),

  action_model("moderna", "postest", "vax12_type-az-az"),
  action_model("moderna", "postest", "vax12_type-pfizer-pfizer"),
  action_model("moderna", "covidemergency", "vax12_type-az-az"),
  action_model("moderna", "covidemergency", "vax12_type-pfizer-pfizer"),
  action_model("moderna", "covidadmittedproxy1", "vax12_type-az-az"),
  action_model("moderna", "covidadmittedproxy1", "vax12_type-pfizer-pfizer"),
  action_model("moderna", "covidadmitted", "vax12_type-az-az"),
  action_model("moderna", "covidadmitted", "vax12_type-pfizer-pfizer"),
  action_model("moderna", "noncovidadmitted", "vax12_type-az-az"),
  action_model("moderna", "noncovidadmitted", "vax12_type-pfizer-pfizer"),
  action_model("moderna", "covidcc", "vax12_type-az-az"),
  action_model("moderna", "covidcc", "vax12_type-pfizer-pfizer"),
  action_model("moderna", "coviddeath", "vax12_type-az-az"),
  action_model("moderna", "coviddeath", "vax12_type-pfizer-pfizer"),
  action_model("moderna", "noncoviddeath", "vax12_type-az-az"),
  action_model("moderna", "noncoviddeath", "vax12_type-pfizer-pfizer"),


  comment("### Models by clinical extremely vulnerable ('cev')"),

  action_model("moderna", "postest", "cev-FALSE"),
  action_model("moderna", "postest", "cev-TRUE"),
  action_model("moderna", "covidemergency", "cev-FALSE"),
  action_model("moderna", "covidemergency", "cev-TRUE"),
  action_model("moderna", "covidadmittedproxy1", "cev-FALSE"),
  action_model("moderna", "covidadmittedproxy1", "cev-TRUE"),
  action_model("moderna", "covidadmitted", "cev-FALSE"),
  action_model("moderna", "covidadmitted", "cev-TRUE"),
  action_model("moderna", "noncovidadmitted", "cev-FALSE"),
  action_model("moderna", "noncovidadmitted", "cev-TRUE"),
  action_model("moderna", "covidcc", "cev-FALSE"),
  action_model("moderna", "covidcc", "cev-TRUE"),
  action_model("moderna", "coviddeath", "cev-FALSE"),
  action_model("moderna", "coviddeath", "cev-TRUE"),
  action_model("moderna", "noncoviddeath", "cev-FALSE"),
  action_model("moderna", "noncoviddeath", "cev-TRUE"),

  comment("### Models by prior infection ('prior_covid_infection')"),

  action_model("moderna", "postest", "prior_covid_infection-FALSE"),
  action_model("moderna", "postest", "prior_covid_infection-TRUE"),
  action_model("moderna", "covidemergency", "prior_covid_infection-FALSE"),
  action_model("moderna", "covidemergency", "prior_covid_infection-TRUE"),
  action_model("moderna", "covidadmittedproxy1", "prior_covid_infection-FALSE"),
  action_model("moderna", "covidadmittedproxy1", "prior_covid_infection-TRUE"),
  action_model("moderna", "covidadmitted", "prior_covid_infection-FALSE"),
  action_model("moderna", "covidadmitted", "prior_covid_infection-TRUE"),
  action_model("moderna", "noncovidadmitted", "prior_covid_infection-FALSE"),
  action_model("moderna", "noncovidadmitted", "prior_covid_infection-TRUE"),
  action_model("moderna", "covidcc", "prior_covid_infection-FALSE"),
  action_model("moderna", "covidcc", "prior_covid_infection-TRUE"),
  action_model("moderna", "coviddeath", "prior_covid_infection-FALSE"),
  action_model("moderna", "coviddeath", "prior_covid_infection-TRUE"),
  action_model("moderna", "noncoviddeath", "prior_covid_infection-FALSE"),
  action_model("moderna", "noncoviddeath", "prior_covid_infection-TRUE"),

  comment("### Models by age ('age65plus')"),

  action_model("moderna", "postest", "age65plus-FALSE"),
  action_model("moderna", "postest", "age65plus-TRUE"),
  action_model("moderna", "covidemergency", "age65plus-FALSE"),
  action_model("moderna", "covidemergency", "age65plus-TRUE"),
  action_model("moderna", "covidadmittedproxy1", "age65plus-FALSE"),
  action_model("moderna", "covidadmittedproxy1", "age65plus-TRUE"),
  action_model("moderna", "covidadmitted", "age65plus-FALSE"),
  action_model("moderna", "covidadmitted", "age65plus-TRUE"),
  action_model("moderna", "noncovidadmitted", "age65plus-FALSE"),
  action_model("moderna", "noncovidadmitted", "age65plus-TRUE"),
  action_model("moderna", "covidcc", "age65plus-FALSE"),
  action_model("moderna", "covidcc", "age65plus-TRUE"),
  action_model("moderna", "coviddeath", "age65plus-FALSE"),
  action_model("moderna", "coviddeath", "age65plus-TRUE"),
  action_model("moderna", "noncoviddeath", "age65plus-FALSE"),
  action_model("moderna", "noncoviddeath", "age65plus-TRUE"),


  comment("# # # # # # # # # # # # # # # # # # #", "Combine models across treatments and outcomes", "# # # # # # # # # # # # # # # # # # #"),

  action_combine_model("none", ""),
  action_combine_model("vax12_type", c("pfizer-pfizer", "az-az")),
  action_combine_model("cev", c("FALSE", "TRUE")),
  action_combine_model("age65plus", c("FALSE", "TRUE")),
  action_combine_model("prior_covid_infection", c("FALSE", "TRUE")),

  comment("# # # # # # # # # # # # # # # # # # #", "Manuscript", "# # # # # # # # # # # # # # # # # # #"),

  action(
    name = "release_objects",
    run = "r:latest analysis/release_objects.R",
    needs = list(
      "data_selection",
#      "match_seqtrialcox_pfizer",
#      "match_seqtrialcox_moderna",
      "combine_match",
      "combine_model_none",
      "combine_model_vax12_type",
      "combine_model_cev",
      "combine_model_age65plus",
      "combine_model_prior_covid_infection"
    ),
    moderately_sensitive = lst(
      csv = "output/release-objects/*.csv",
      #png = "output/manuscript-objects/*.png",
      txt = "output/files-for-release.txt",
      csvsubgroup = "output/release-objects/*/*.csv",
    )
  )

)


project_list <- splice(
  defaults_list,
  list(actions = actions_list)
)

## convert list to yaml, reformat comments and whitespace ----
thisproject <- as.yaml(project_list, indent=2) %>%
  # convert comment actions to comments
  convert_comment_actions() %>%
  # add one blank line before level 1 and level 2 keys
  str_replace_all("\\\n(\\w)", "\n\n\\1") %>%
  str_replace_all("\\\n\\s\\s(\\w)", "\n\n  \\1")


# if running via opensafely, check that the project on disk is the same as the project created here:
if (Sys.getenv("OPENSAFELY_BACKEND") %in% c("expectations", "tpp")){

  thisprojectsplit <- str_split(thisproject, "\n")
  currentproject <- readLines(here("project.yaml"))

  stopifnot("project.yaml is not up-to-date with create-project.R.  Run create-project.R before running further actions." = identical(thisprojectsplit, currentproject))

# if running manually, output new project as normal
} else if (Sys.getenv("OPENSAFELY_BACKEND") %in% c("")){

## output to file ----
  writeLines(thisproject, here("project.yaml"))
#yaml::write_yaml(project_list, file =here("project.yaml"))

## grab all action names and send to a txt file

names(actions_list) %>% tibble(action=.) %>%
  mutate(
    model = action==""  & lag(action!="", 1, TRUE),
    model_number = cumsum(model),
  ) %>%
  group_by(model_number) %>%
  summarise(
    sets = str_trim(paste(action, collapse=" "))
  ) %>% pull(sets) %>%
  paste(collapse="\n") %>%
  writeLines(here("actions.txt"))

# fail if backend not recognised
} else {
  stop("Backend not recognised")
}


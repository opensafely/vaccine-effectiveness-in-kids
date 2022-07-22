library('here')
library('arrow')
library('tidyverse')

case<-read_feather(here("output", "input_case.feather")) %>%
  mutate(casecontrol="case")

control<-read_feather(here("output", "input_control.feather")) %>%
  mutate(casecontrol="control")

input <-case %>% 
  bind_rows(control) 
 

write_feather(input,here("output", "input.feather"))

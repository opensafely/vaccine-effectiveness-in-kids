library('here')
library('arrow')
library('tidyverse')

case<-read_feather(here("output", "input_case.feather")) %>%
  mutate(casecontrol=as.logical(TRUE))

control<-read_feather(here("output", "input_control.feather")) %>%
  mutate(casecontrol=as.logical(FALSE))

input <-case %>% 
  bind_rows(control)  %>%
   mutate(across(ends_with("_date"),  as.Date))
 

write_feather(input,here("output", "input.feather"))

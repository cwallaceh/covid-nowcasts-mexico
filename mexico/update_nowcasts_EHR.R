# Packages -----------------------------------------------------------------

require(EpiNow)
require(NCoVUtils)
require(furrr)
require(future)
require(dplyr)
require(tidyr)
require(magrittr)

# Get cases ---------------------------------------------------------------

###  Mexico

get_mexico_linelist <- function() {
  #Updated 2020-04-28
  path <- "https://raw.githubusercontent.com/marianarf/covid19_mexico_analysis/master/latest.csv"
  
  #Set up cache
  ch <- memoise::cache_filesystem(".cache")
  mem_read <- memoise::memoise(readr::read_csv, cache = ch)
  #mem_read <- memoise::memoise(readr::read_csv)
  
  cases <- mem_read(path) %>%
    #Quitar acentos en los nombres de los estados
    dplyr::mutate(Region=stringi::stri_trans_general(str = Region, id = "Latin-ASCII")) %>%
    
    #Se les olvido lo de CDMX
    dplyr::mutate(Region = ifelse(Region == "DISTRITO FEDERAL" , "CIUDAD DE MEXICO", Region)) %>%
    
    #Date Symptoms, nuevo formato
    dplyr::mutate(Date_Symptoms=as.Date(Date_Symptoms, format = "%d-%m-%Y")) %>%
    
    # Usamos Date_Confirmed, nuev formato
    dplyr::mutate(Date_Confirmed=as.Date(Date_Confirmed, format = "%d-%m-%Y")) %>%
    #Fix de MDY para pendientes de 14-04, 15-04 y 16-04
    #dplyr::mutate(date2 = as.Date.numeric(
    #  ifelse( is.na(Date_Confirmed), 
    #          as.Date(Date_Confirmed, format = "%m-%d-%Y"), Date_Confirmed ),
    #  origin="1970-01-01")) %>%
    #dplyr::mutate(Date_Confirmed = date2 ) %>%
    
    #Crear columna local o importado
    dplyr::mutate(import_status = ifelse(Origin == "Local" , "local", "imported")) %>%
    
    ##Linelist
    dplyr::mutate(report_delay = as.numeric(Date_Confirmed - Date_Symptoms))  %>%
    dplyr::rename(date_onset = Date_Symptoms, 
                  date_confirm = Date_Confirmed) %>%
    dplyr::select(date_onset, date_confirm, report_delay, import_status)
  
  return(cases)
}

###  Mexico (Regional)
get_mexico_regional_cases <- function() {
  #Updated 2020-04-28 
  path <- "https://raw.githubusercontent.com/marianarf/covid19_mexico_analysis/master/latest.csv"
  
  #Set up cache
  ch <- memoise::cache_filesystem(".cache2")
  mem_read <- memoise::memoise(readr::read_csv, cache = ch)
  #mem_read <- memoise::memoise(readr::read_csv)
  
  cases <- mem_read(path) %>%
    #Quitar acentos en los nombres de los estados
    dplyr::mutate(Region=stringi::stri_trans_general(str = Region, id = "Latin-ASCII")) %>%
    
    #Se les olvido lo de CDMX
    #dplyr::mutate(Region = ifelse(Region == "DISTRITO FEDERAL" , "CIUDAD DE MEXICO", Region)) %>%
    
    # Usamos Date_Confirmed, nuev formato
    dplyr::mutate(date=as.Date(Date_Confirmed, format = "%d-%m-%Y")) %>%
    
    #Fix de MDY para pendientes de 14-04, 15-04 y 16-04
    #dplyr::mutate(date2 = as.Date.numeric(
    #  ifelse( is.na(date), 
    #          as.Date(Date_Confirmed, format = "%m-%d-%Y"), date ),
    #  origin="1970-01-01")) %>%
    #dplyr::mutate(date = date2 ) %>%
    
    #Crear columna local o importado
    dplyr::mutate(import_status = ifelse(Origin == "Local" , "local", "imported")) %>%
    dplyr::group_by(Region, import_status, date) %>%
    
    ## Sumar los casos individuales para obtener los nuevos casos del día por región
    ## Si hubiera recuperados del dia, aqui hay que quitarlos
    dplyr::summarize(day_cases = n()) %>% 
    
    #Limpieza final
    filter(!is.na(Region) & Region != "Region" ) %>%
    
    dplyr::select(date, Region, import_status, day_cases) %>%
    dplyr::group_by(Region, import_status) %>%
    dplyr::rename(cases = day_cases)
  #dplyr::mutate(cases = cumsum(day_cases))
  
  return(cases)
}

# Get cases ---------------------------------------------------------------

NCoVUtils::reset_cache()

# Opcion directo desde archivo subido
# Se quita el primer registro porque sale negativo por el shift
cases <- readr::read_csv('/home/covid/casos_060520.txt') %>% 
  dplyr::filter( cases > 0 )

#cases <- get_mexico_regional_cases() %>% 
#  dplyr::filter(import_status  == "local") %>%
#  dplyr::rename(region = Region)

#cases %>% View()

# Region codes para el mapita
#region_codes <- cases %>%
#  dplyr::select(region, region_code = fips) %>%
#  unique()

#saveRDS(region_codes, "united-states/data/region_codes.rds")

# Get linelist ------------------------------------------------------------

## Usar linelist del backup
#linelist <- readRDS('/home/covid/linelist.rds')

# EHR Fixing....
linelist <- NCoVUtils::get_international_linelist() %>%
            dplyr::filter( report_delay > 0 ) %>%
            dplyr::filter(!is.na(report_delay))

# Set up cores -----------------------------------------------------

future::plan("multiprocess", workers = future::availableCores())

# Run pipeline ----------------------------------------------------

EpiNow::regional_rt_pipeline(
  cases = cases,
  linelist = linelist,
  regional_delay = FALSE,
  target_folder = "mexico/regional",
  case_limit = 10,
  verbose = TRUE
)

# Summarise results -------------------------------------------------------

EpiNow::regional_summary(results_dir = "mexico/regional",
                         summary_dir = "mexico/regional-summary",
                         target_date = "latest",
                         region_scale = "State"
)

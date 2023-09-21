library(tidyverse)
library(shiny)
library(shinyjs)
library(leaflet)

## ------ SETUP ------ 
fac_geodf <- read_csv("fac_geodf.csv")[-1]
captures <- read_csv("captures.csv")[-1]

fac_geodf$start_date[fac_geodf$start_date == -99] <- NA # unknown start dates
fac_geodf$start_date <- as.Date(paste(fac_geodf$start_date, "-01-01 00:00:00", sep = "")) # convert start date to Date object
captures$start_date <- as.Date(paste(captures$start_date, "-01-01", sep = "")) # convert start date to Date object -- not necessary, already knows

# filter the dataset to remove cases where the photo was taken before construction started
captures <- captures %>% filter(start_date <= Acquisitio)

# get date range
min_date = min(fac_geodf$start_date, na.rm = TRUE)
max_date = max(fac_geodf$start_date, na.rm = TRUE)



## ------ CLIENT ------
ui <- fluidPage(
  tags$style(type = "text/css", "
      .js-irs-0 .irs-single, .js-irs-0 .irs-bar-edge, .js-irs-0 .irs-bar { }
      .js-irs-1 .irs-single, .js-irs-1 .irs-bar-edge, .js-irs-1 .irs-bar, .js-irs-1 .irs-from, .js-irs-1 .irs-to {background: red;
                                                  border-top: 1px solid red ;
                                                  border-bottom: 1px solid red ;}
      "),
  titlePanel("Coverage of Nuclear Facilities by the CORONA Recon Satellite Program"),
  sidebarLayout(
    sidebarPanel(
      checkboxInput("showUnknown","Show Facilities with Unknown Start Dates", value = FALSE),
      checkboxInput("showCaptures","Show Spotted Facilities", value = FALSE),
      sliderInput("dateSlider", "Adjust Date:", 
                  min = min_date, 
                  max = max_date, 
                  value = min_date, 
                  step = 49,
                  animate = animationOptions(interval = 250))
    ),
    mainPanel(
      leafletOutput("map", height = "600px", width = "800px"),
      plotOutput("plot")
    )
  )
)



## ------- SERVER ------

server <- function(input, output, session) {
  state <- reactiveValues(fac = fac_geodf)
  
  # handle unknown dates
  adjust_nas <- function() {
    state$fac <- fac_geodf
    
    if(input$showUnknown) {
      state$fac$start_date <- replace(state$fac$start_date, is.na(state$fac$start_date), min_date) # replace NA values with the min slider date
    } else {
      state$fac <- state$fac %>% filter(!is.na(start_date)) #filter them out
    }
  }
  
  # filter by date range shown on slider
  fac_filtered_by_dates <- function() {
    state$fac[state$fac$start_date <= input$dateSlider,]
  }
  
  # filter for facilities which have been captured bf date
  captured_facs <- function() {
    captures %>% filter(Acquisitio <= input$dateSlider) %>% # filter for captures bf current date
      filter(original_facility_name %in% state$fac$original_facility_name) %>% # filter facs which aren't in current state (e.g. NA)
      group_by(fac_index) %>% # group by facility
      filter(Acquisitio == max(Acquisitio)) %>% # keep the most recent captures
      distinct(fac_index, .keep_all = TRUE) # make sure only one capture of each facility is present.
  }
  
  # add markers where there should be markers
  create_markers <- function() {
    leafletProxy(mapId = 'map') %>%
      clearMarkers() %>%
      addCircleMarkers(data = fac_filtered_by_dates(),
                       lng = ~Longitude, lat = ~Latitude,
                       radius = 5,
                       weight = 1,
                       color = "blue",
                       opacity = 1,
                       fillOpacity = 0.5,
                       popup = ~paste("Name: ", original_facility_name, "<br>",
                                      "Facility Start Date: ", start_date,
                                      ifelse(input$showCaptures, "<br>Not Yet Photographed", "")),
      )
    
    if (input$showCaptures) {
      leafletProxy(mapId = 'map') %>%
        addCircleMarkers(data = captured_facs(),
                         lng = ~Longitude, lat = ~Latitude,
                         radius = 5,
                         weight = 1,
                         color = "red",
                         opacity = 1,
                         fillOpacity = 0.7,
                         popup = ~paste("Name: ", original_facility_name, "<br>",
                                        "Facility Start Date: ", start_date, "<br>",
                                        "Most Recently Photographed: ", Acquisitio),
        )
    }
  }
  
  # run on startup. Adjust NAs and filter by date
  output$map <- renderLeaflet({
    map <- leaflet(leafletOptions( minZoom = 0 )) %>%
      addTiles() %>%
      setView(lng = 0,
              lat = 0,
              zoom = 1)
    map
  })
  
  # re-create map whenever date slider is changed
  observeEvent(eventExpr = { input$dateSlider }, handlerExpr = {
    adjust_nas()
    create_markers()
  })
  
  # re-create map when showUnkown checkbox is toggled
  observeEvent(eventExpr = { input$showUnknown }, handlerExpr = {
    adjust_nas()
    create_markers()
  })
  
  # re-create map when showUnkown checkbox is toggled
  observeEvent(eventExpr = { input$showCaptures }, handlerExpr = {
    adjust_nas()
    create_markers()
  })
}

shinyApp(ui, server)
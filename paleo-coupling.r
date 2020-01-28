library(dplyr)
library(lubridate)

# Water Year Assignment Function
WY <- function(dates, start_month = 10) {
  dates.posix = as.POSIXlt(dates)
  offset = ifelse(dates.posix$mon >= start_month - 1, 1, 0)
  adj.year = dates.posix$year + 1900 + offset
  adj.year
}

# Input Hydro settings
num_site <- 1217
workingDir <- file.path('./')
stream <- 'SAC'
sdPerturb <- 1.3


# Immutable (or pre-processed) inputs
# paleo reconstructed
paleoFlows <- file.path(workingDir,
    'immutable',paste0(stream,'_PaleoReconstructed_900_2012.csv'))
# historical simulated
simFlows <- file.path(workingDir,
    'immutable',paste0(stream,'_SimHistorical1950-2003.csv'))

# Livneh
livneh_CCVS_latlng <- file.path(workingDir,
    'immutable','livneh_CCVS_latlng.rds')
livneh_TempDetrended_CCVS <- file.path(workingDir,
    'immutable','livneh_TempDetrended_CCVS.rds')
livneh_Precip_CCVS <- file.path(workingDir,
    'immutable','livneh_Precip_CCVS.rds')

# Processed outputs file paths
if (sdPerturb==1.0) {
  sdPerturbString <- ''
} else {
  sdPerturbString <- paste0(gsub("\\.", "_",sprintf("%0.1f", sdPerturb)),'SD_')
}

paleoAnlaogueFlows <- file.path(workingDir,
    'processed',paste0(stream,'_Paleo_',sdPerturbString,'with_AnalogueSimHistorical.csv'))
outputSites <- file.path(workingDir,
    'processed',paste0('paleo_',stream,'_',sdPerturbString,'analogue_sim_ccvs'))

# Read in Paleo reconstructed streamflow and observed Streamflow
paleoFlows <- read.csv(file.path(paleoFlows))
paleo <- paleoFlows[, 1:2]
colnames(paleo) <- c("Year", "Flow")
paleo$Dataset = "Paleo"

# perturb standard deviation of flow without mean change
for (y in seq(from = 15, to = 1095, by = 30)) {
    yStart <- y-14
    yEnd <- y+15
    flow <- paleo[c(yStart:yEnd),]$Flow
    paleo[c(yStart:yEnd),]$Flow <- flow %>% `-`(mean(flow)) %>% `*`((sd(flow)*sdPerturb)/sd(flow)) %>% `+`(mean(flow))
}

# Read in Historical Simulated Values ####
simFlows <- read.csv(file.path(simFlows))

# append simultated to flow record
flow <- rbind(paleo, simFlows)

# Create Analogue Historical to Paleo ####
for (i in 1:nrow(paleo)) {
  absMin <- which.min(abs(simFlows$Flow - paleo$Flow[i]))
  paleo[i, "AnalogueYear"] <- simFlows$Year[absMin]
  paleo[i, "AnalogueFlow"] <- simFlows$Flow[absMin]
}

# Force 1950-2003 to use 1950-2003 T and P sequence if no sd perturbation
if (sdPerturb == 1.0) {
    paleo$AnalogueYear[which(paleo$Year %in% 1950:2003)] <- 1950:2003
    paleo$AnalogueFlow[which(paleo$Year %in% 1950:2003)] <- simFlows$Flow
}

# Write out Paleo with analogue to processed data archive
write.csv(
  paleo,
  file = paleoAnlaogueFlows,
  row.names = F
)

#### Construct 1100 year record of Temp and Precip
# (from Livneh) based on analogue water year
#add five years of dummy data to wet basins in Hydrologic model
#1954 used because it is an average type year
paleoSim <- c(rep(1954, 5), as.list(paleo[, "AnalogueYear"]))

# read in Livneh data and grid locations for CCVS domain
SITE_TAVG <- readRDS(livneh_TempDetrended_CCVS)
SITE_PRCP <- readRDS(livneh_Precip_CCVS)
SITE_LATLNG <- readRDS(livneh_CCVS_latlng)

# Construct date sequence for the Livneh daily data. Remove leap days, but remove Aug 29ths instead of Feb 29ths to keep wet days
livneh_datesWY <- seq(as.Date('1949/10/1'), as.Date('2003/9/30'), 1)
livneh_leapDays <-
  which(day(livneh_datesWY) == 29 & month(livneh_datesWY) == 2)
livneh_datesWY <- livneh_datesWY[-(livneh_leapDays + 140)]
SITE_PRCP <- data.frame(SITE_PRCP[-(livneh_leapDays + 140),])
SITE_TAVG <- data.frame(SITE_TAVG[-(livneh_leapDays + 140),])

# get list of water year for each day in Livneh date sequence
livnehWY <- WY(livneh_datesWY,10)

# Construct date sequence for the Paleo bootstrapped daily data.
# Again, remove the leap days (as Aug 29)
paleo_datesWY <- seq(as.Date('894/10/1'), as.Date('2011/9/30'), 1)
paleo_leapDays <-  which(day(paleo_datesWY) == 29 & month(paleo_datesWY) == 2)
paleo_datesWY <- paleo_datesWY[-(paleo_leapDays + 140)]


## build index array of days within the livneh data per
# analogue of water year; jittering shifts the day
# by a random (uniform distribution) between -15 and 15
tt = NULL
for (i in 1:length(paleoSim)) {
  tt <- c(c(tt, which(livnehWY == paleoSim[i]) + sample(-15:15, 1)))
}
tt[which(tt<=0)] <- 1
tt[which(tt>length(livnehWY))] <- length(livnehWY)


# Loop through sites and generate 1100 year
# daily record of precip and temp for each
# based on the analogue historical simulation water year
# Initiate data frames with Paleo daily date sequence as first column
FINAL_STOCHASTIC_TEMP_DAILY <- data.frame(paleo_datesWY)
FINAL_STOCHASTIC_PRCP_DAILY <- data.frame(paleo_datesWY)
for (ss in 1:num_site) {

  SITE_TITLE <- substr(SITE_LATLNG[ss],6,22)

  PRCP_SIM_FINAL <- data.frame(SITE_PRCP[tt, ss])
  colnames(PRCP_SIM_FINAL) <- SITE_TITLE

  TAVG_SIM_FINAL <- data.frame(SITE_TAVG[tt, ss])
  colnames(TAVG_SIM_FINAL) <- SITE_TITLE

  SIM_FINAL <- cbind(year(paleo_datesWY),
                     month(paleo_datesWY),
                     day(paleo_datesWY),
                     PRCP_SIM_FINAL,TAVG_SIM_FINAL)

  write.table(
    SIM_FINAL,
    file.path(outputSites,SITE_LATLNG[ss]),
    row.names = FALSE,
    col.names = FALSE,
    sep = "\t"
  )

  FINAL_STOCHASTIC_TEMP_DAILY <-
    cbind(FINAL_STOCHASTIC_TEMP_DAILY, TAVG_SIM_FINAL)
  FINAL_STOCHASTIC_PRCP_DAILY <-
    cbind(FINAL_STOCHASTIC_PRCP_DAILY, PRCP_SIM_FINAL)

}


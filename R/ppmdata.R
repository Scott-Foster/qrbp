#' @name ppmData
#' @title Create a Point Process dataset for spatial presence-only modelling.
#' @description Creates a point process data frame for modelling single species or multiple species (marked) presences. Generates a quadrature scheme based on Berman & Turner 1992; Warton & Shepard 2010. The function can generate a quadrature scheme for a regular grid, quasi-random or random points.
#' @export
#' @param npoints number of background points to create.
#' @param presences a matrix, dataframe or SpatialPoints* object giving the coordinates of each species' presence in (should be a matrix of nsites * 3) with the three columns being c("X","Y","SpeciesID"), where X is longitude, Y is latitude and SpeciesID is a integer, character or factor which assoicates each point to a species. If presences are NULL then ppmdat will return the quadrature (background) points.
#' @param window a Raster* object giving the area over which to generate background points. NA cells are ignored and masked out of returned data.
#' If ignored, a rectangle defining the extent of \code{presences} will be used.
#' @param covariates an optional Raster object containing covariates for modelling the point process (best use a Raster stack or Raster brick).
#' @param resolution resolution setup grid for integration points (default is 1 deg) - but this need to be setup  with reference to original raster resolution.
#' @param method the type of method that should be used to generate background points. The options are:
#' 'grid' generates a regular grid of background points. See Berman & Turner 1992 or Warton & Shepard 2010 for details.
#' 'quasirandom' generates quasirandom background points. See Bratley & Fox 1998 or Foster etal 2015 for details.
#' 'random' generates a random set of background points. See Philips 2006 (ala MaxEnt) for details.
#' @param interpolation either 'simple' or 'bilinear' and this determines the interpolation method for interpolating data across different cell resolutions.
#' 'simple' is nearest neighbour, 'bilinear' is bilinear interpolation.
#' @param coord is the name of site coordinates. The default is c('X','Y').
#' @param control \link[qrbp]{ppmData.control}.
#'

ppmData <- function(npoints = 10000,
                    presences = NULL,
                    window = NULL,
                    covariates = NULL,
                    resolution = NULL,
                    method = c('grid','quasirandom','random'),
                    interpolation='bilinear',
                    coord = c('X','Y'),
                    control=ppmData.control()){

  ## if no resolution is provided guess the nearest resolution to return npoints for grid method.
  if(is.null(resolution)) resolution <- guessResolution(npoints,window)
  if(method=='quasirandom') control$quasiSamps <- ifelse(control$quasiSamps>npoints,control$quasiSamps,npoints*2)

  ## Do some checks.
  presences <- checkDuplicates(presences,coord)
  checkResolution(resolution,window,control,method)
  window <- checkWindow(presences,window)
  tmp <- disaggregateWindow(window,npoints)

  if(is.null(presences)){
   message('Generating background points in the absence of species presences')
   backgroundsites <- switch(method,
                             grid = gridMethod(resolution, window,control),
                             quasirandom = quasirandomMethod(npoints,  window,
                                                             covariates, control, coord),
                             random = randomMethod(npoints, window, covariates))

   # wts <- getTileWeights(presences,backgroundsites[,1:2],coord)
   sitecovariates <- getCovariates(backgroundsites$grid[,coord],covariates,
                                   interpolation=interpolation,
                                   coord=coord,control=control)

  } else {

  presences <- coordMatchDim(presences,3)

  # create background points based on method.
  backgroundsites <- switch(method,
                grid = gridMethod(resolution, window,control),
                quasirandom = quasirandomMethod(npoints,  window,
                                                covariates, control, coord),
                random = randomMethod(npoints,  window, covariates))

  ismulti <- checkMultispecies(presences)
  if(ismulti){
      message("Developing a quadrature scheme for multiple species (marked) dataset.")
      wts <- getMultispeciesWeights(presences, backgroundsites$grid, coord, method, window, epsilon=control$epsilon)
    } else {
      wts <- getSinglespeciesWeights(presences, backgroundsites$grid, coord, method, window, epsilon=control$epsilon)
    }

  # pbxy <- wts[,coord],backgroundsites[,coord])
  sitecovariates <- getCovariates(wts,covariates,interpolation=interpolation,
                                  coord=coord,control=control)
  }

  parameters <- list(npoints=npoints,resolution=resolution,
                     newresolution=backgroundsites$newres,method=method,
                     interpolation=interpolation,control=control)
  dat <- assembleQuadData(presences, backgroundsites$grid, sitecovariates, wts,
                          coord, parameters, control=control)
  class(dat) <- "ppmdata"
  return(dat)
}

#'@title Controls for ppmData generation.
#'@name ppmData.control
#'@param quiet Should any reporting be performed? Default is FALSE, for reporting.
#'@param cores The number of cores to use in fitting of species_mix models. These will be largely used to model the species-specific parameteres.
#'@param maxpoints default is 250000 and sets a limit to number of integration points generated as background data.
#'@param na.rm default is TRUE and uses "na.rm=TRUE" for extracting raster covariate data.
#'@param extractBuffer default is NULL and is the amount of buffer to provide each point on extract (radius from point).
#'@param quasiSamps default is 5000 and is the default number of samples for halton random number generator.
#'@param quasiDims default 2 and is the dimension estimated the quasirandom samples over. Two is the default and results in a spatial quasirandom sample.
#'@param multispeciesFormat default "wide" and is the format required by ecomix. Alternatives are "long" which returns a long table format or "list" which returns a list per species for all species related covariates, weights and presences/background points.
#'@param \dots Other control calls.
#'@export
ppmData.control <- function(quiet = FALSE,
                            cores = 1,
                            maxpoints=250000,
                            na.rm=TRUE,
                            extractBuffer=NULL,
                            quasiSamps=5000,
                            quasiDims=2,
                            multispeciesFormat="wide",
                            epsilon = sqrt(.Machine$double.eps),
                            ...){
  #general controls
  rval <- list(maxpoints=maxpoints,
               na.rm=na.rm,
               extractBuffer=extractBuffer,
               quasiSamps=quasiSamps,
               quasiDims=quasiDims,
               multispeciesFormat=multispeciesFormat,
               epsilon = epsilon)
  rval <- c(rval, list(...))
  rval
}



assembleQuadData <- function(presences, backgroundsites, sitecovariates,
                             wts, coord, parameters, control){

  ismulti <- checkMultispecies(presences)

  if(!ismulti) format <- "long"
  else format <- control$multispeciesFormat

  final_dat <- switch(format,
                      long=longdat(presences, backgroundsites,
                                   sitecovariates,
                                   wts, coord),
                      wide=widedat(presences, backgroundsites,
                                   sitecovariates,
                                   wts, coord),
                      list=listdat(presences, backgroundsites,
                                   sitecovariates,
                                   wts, coord))

  return(list(modelmatrix=final_dat,parameters=parameters))

}


longdat <- function(presences, backgroundsites, sitecovariates=NULL, wts, coord){

  if(!is.null(sitecovariates)){
      dat2 <- merge(wts[,-which(colnames(wts)%in%coord)],sitecovariates[!duplicated(sitecovariates$SiteID),],
                  by = "SiteID", sort=FALSE)
    } else {
      dat2 <- wts
    }
  if(is.null(presences)){ #presences true
      if(!is.null(sitecovariates)){ # covariates true
        dat2 <- cbind(backgroundsites[,c(coord)],sitecovariates,pres=c(rep(0,nrow(backgroundsites))))
      } else { # covariates false
        dat2 <- cbind(backgroundsites[,c(coord)],pres=c(rep(0,nrow(backgroundsites))))
      }
  }
  return(dat2)
}

listdat <- function(presence=NULL, backgroundsites, sitecovariates, wts=NULL, coord){

  if(!is.null(presences)){ #presences true
    if(!is.null(sitecovariates)){ #covariates true
      dat2 <- list(presences=presences[,c(coord,"SpeciesID")],
                   background=backgroundsites[,c(coord,"SpeciesID")],
                   covariates=sitecovariates,
                   pres=c(rep(1,nrow(presences)),rep(0,nrow(backgroundsites))),
                   wts=wts)
    } else { #covariates false
      dat2 <- list(presences=presences[,c(coord,"SpeciesID")],
                   background=backgroundsites[,c(coord,"SpeciesID")],
                   covariates=NULL,
                   pres=c(rep(1,nrow(presences)),rep(0,nrow(backgroundsites))),
                   wts=wts)
    }
  } else { # presences false
    if(!is.null(sitecovariates)){
      dat2 <- list(presences=NULL,
                   background=backgroundsites[,c(coord,"SpeciesID")],
                   covariates=sitecovariates,
                   pres=c(rep(0,nrow(backgroundsites))),
                   wts=wts)
      } else { # covariates false
      dat2 <- list(presences=NULL,
                   background=backgroundsites[,c(coord,"SpeciesID")],
                   covariates=NULL,
                   pres=c(rep(0,nrow(backgroundsites))),
                   wts=wts)
    }
  }
  return(dat2)
}

widedat <- function(presence, backgroundsites, sitecovariates, wts, coord){

  # Assemble a data.frame with all the bits we want.
  pamat <- fastwidemat(wts)
  presences_pamat <- pamat[-which(pamat[,"quad"]==0),-which(colnames(pamat)=='quad')]
  presences_pamat[presences_pamat==0]<-NA
  quad_pamat <- pamat[which(pamat[,"quad"]==0),-which(colnames(pamat)=='quad')]
  quad_pamat[is.na(quad_pamat)]<-0
  response_ppmmat <- as.data.frame(rbind(presences_pamat,quad_pamat))
  response_ppmmat$Const <- 1
  response_ppmmat$SiteID <- as.integer(rownames(response_ppmmat))

  df <- merge(response_ppmmat,sitecovariates[!duplicated(sitecovariates$SiteID),],
              by = "SiteID", sort=FALSE)
  wtsmat <- fastwidematwts(wts)
  ids <- wts[!duplicated(wts[,c('SpeciesID','DatasetID')]),c('SpeciesID','DatasetID')]
  ids <- ids[-which(ids$SpeciesID=='quad'),]
  idx_rows <- df$SiteID
  idx_cols <- match(colnames(quad_pamat),ids$SpeciesID)
  wtsmat <- wtsmat[idx_rows,idx_cols]
  colnames(wtsmat) <- colnames(quad_pamat)
  return(list(mm=df,wtsmat=wtsmat))
}

gridMethod <- function(resolution=1, window, control){

  if(!inherits(window, c('RasterLayer','RasterStack','RasterBrick')))
    stop("'grid' method currently only works a raster input as a 'window'")

  if(inherits(window, c('RasterLayer','RasterStack','RasterBrick'))){

    #set up the dissaggreation or aggregate
    fct <- (res(window)/resolution)[1]

    #if fct is >= 1 dissaggregate, else aggregate
    if(fct>=1) dd <- disaggregate(window, fct, na.rm=control$na.rm)
    else dd <- aggregate(window, 1/fct, na.rm=control$na.rm)

    #create a dataframe of coordinates w/ area
    grid <- as.data.frame(rasterToPoints(dd)[,-3])
    colnames(grid) <- c('X','Y')
  }

  newres <- res(dd)

  return(list(grid=grid,newres=newres))
}

# still working on this method.
quasirandomMethod <- function(npoints, window, covariates=NULL, control,coord){

  #generate a set of potential sites for quasirandom generation
  if(!is.null(covariates)){
    rast_coord <- raster::xyFromCell(covariates,1:raster::ncell(covariates))
    rast_data <- raster::values(covariates)
    na_sites <- which(!complete.cases(rast_data))
    covariates_ext <- raster::extent(covariates)[1:4]
  } else {
    rast_coord <- raster::xyFromCell(window,1:raster::ncell(window))
    rast_data <- raster::values(window)
    na_sites <- which(!complete.cases(rast_data))
    covariates_ext <- raster::extent(window)[1:4]
    }

  potential_sites <- cbind(rast_coord,rast_data)
  potential_sites[na_sites,-1:-2] <- 0

  #if npoints>nrow(potential_sites) recursively create a finer grid.
  if(npoints>nrow(potential_sites[-na_sites,])){
    stop('more background points than cells avaliable')
  }

  dimension <- control$quasiDim
  nSampsToConsider <- control$quasiSamps

  samp <- randtoolbox::halton( nSampsToConsider * 2, dim = dimension + 1, init = TRUE)
  skips <- sample(seq_len(nSampsToConsider), size = dimension + 1, replace = TRUE)
  samp <- do.call("cbind", lapply(1:(dimension + 1),
                                  function(x) samp[skips[x] + 0:(nSampsToConsider - 1), x]))

  myRange <- apply(potential_sites[-na_sites,], -1, range)[,1:dimension]
  for (ii in seq_len(dimension)) samp[, ii] <- myRange[1, ii] + (myRange[2, ii] - myRange[1, ii]) * samp[, ii]

  ## study area
  study.area <- as.matrix(expand.grid(as.data.frame(apply(potential_sites,-1, range)[,1:dimension])))
  if (dimension == 2){
    study.area <- study.area[c(1, 3, 4, 2), ]
    tmp <- mgcv::in.out(study.area, samp[,1:dimension])
    samp <- samp[tmp, ]
  }

  N <- nrow(potential_sites)
  inclusion_probs <- rep(1/N, N)
  inclusion_probs[na_sites] <- 0
  inclusion_probs1 <- inclusion_probs/max(inclusion_probs)

  sampIDs <- class::knn1(potential_sites[,1:dimension],
                         samp[, 1:dimension, drop = FALSE],
                         1:nrow(potential_sites))
  sampIDs.2 <- which(samp[, dimension + 1] < inclusion_probs1[sampIDs])

  if (length(sampIDs.2) >= npoints)
    sampIDs <- sampIDs[sampIDs.2][1:npoints]
  else stop("Failed to find a design. It is possible that the inclusion probabilities are very low and uneven OR that the sampling area is very irregular (e.g. long and skinny) OR something else. Please try again (less likely to work) OR make inclusion probabilities more even (more likely but possibly undesireable) OR increase the number of sites considered (likely but computationally expensive).")
  samp <- as.data.frame(cbind(potential_sites[sampIDs, 1:dimension, drop = FALSE],
                              inclusion_probs[sampIDs], sampIDs))
  colnames(samp) <- c(colnames(potential_sites)[1:dimension],
                      "inclusion.probabilities", "ID")
  grid <- samp[,1:2]
  colnames(grid) <- coord
  return(list(grid=grid,samp=samp,newres=res(window)))
}

randomMethod <- function(npoints, window, covariates = NULL){

  if(!inherits(window, c('RasterLayer','RasterStack','RasterBrick')))
    stop("'grid' method currently only works a raster input as a 'window'")

  if(inherits(window, c('RasterLayer','RasterStack','RasterBrick'))){

    if(npoints>sum(!is.na(window[]))){
      stop('Eeek! More background points than cells avaliable... maybe use a finer grid or less points')
    }

    ## use dismo to get random points.
    randpoints <- dismo::randomPoints(window,npoints)

    #create a dataframe of coordinates w/ area
    colnames(randpoints) <- c('X','Y')
  }

  if(!is.null(covariates)){
    covars <- extract(covariates,randpoints)
    randpoints <- cbind(randpoints,covars)
  }

  return(list(grid=as.data.frame(randpoints),newres=res(window)))
}

coordMatchDim <- function (known.sites,dimension){

  # check object classes
  expectClasses(known.sites,
                c('matrix',
                  'data.frame',
                  'SpatialPoints',
                  'SpatialPointsDataFrame'),
                name = 'known.sites')

  if (is.matrix(known.sites) | is.data.frame(known.sites)) {

    # for matrices/dataframes, make sure there are only two columns
    if (ncol(known.sites) != dimension ) {
      stop (sprintf('known.sites should match the number of dimensions used in quasi-random sampling.
                    The object passed had %i columns, while the sampling dimensions are %i',NCOL(known.sites),dimension))
    }

    # otherwise, coerce into a data.frame and rename the columns
    df <- data.frame(known.sites)

    } else {
      # otherwise, for SpatialPoints* objects, just grab the coordinates
      df <- data.frame(known.sites@coords)
    }

  # set column names
  if (ncol(known.sites)>2) {
    if(!is.null(colnames(known.sites))) colnames(df) <- c("X","Y",colnames(known.sites)[-1:-2])
    colnames(df) <- c('X','Y','SpeciesID')
  } else {
    colnames(df) <- c('X','Y')
  }
  return (df)
}


## function to extract covariates for presence and background points.
getCovariates <- function(pbxy, covariates=NULL, interpolation, coord, control){
  if(is.null(covariates))return(NULL)
  covars <- raster::extract(covariates, pbxy[,coord], method=interpolation,
                            na.rm=control$na.rm, buffer=control$extractBuffer)
  covars <- cbind(SiteID=pbxy[,"SiteID"],pbxy[,coord],covars)
  return(covars)
}

# adjust the resolution to match desired number of background points
guessResolution <- function(npoints,window){
  message('Guessing resolution based on window resolution and approximately ',npoints,' background points')
  reso <- raster::res(window)
  ncello <-  sum(!is.na(window)[])
  newres <- (((ncello*reso[1]))/npoints)
  newres
}

## Some checks, check yo self before you reck yo self. https://www.youtube.com/watch?v=bueFTrwHFEs
## check the covariates that go into building the quadrature scheme.
checkCovariates <- function(covariates){

  if(!is.null(covariates)){
    if(!inherits(covariates, c('RasterLayer','RasterStack','RasterBrick')))
      stop("Covariates must be a raster, rasterstack or rasterbrick of covariates which match the spatial window.")
    covars <- TRUE
  } else {
    covars <- FALSE
  }
  covars
}

## check to see if there are duplicated points per species.
## duplicated points are allowed across multiple species ala marked points.
checkDuplicates <- function(presences,coord){
  if(is.null(presences))return(NULL)
  dups <- duplicated(presences)
  if(sum(dups)>0){ message("There were ",sum(dups)," duplicated points unique to X, Y & SpeciesID, they have been removed.")
  dat <- presences[!dups,]
  } else {
  dat <- presences
  }
  dat <- as.data.frame(dat)
  colnames(dat) <- c(coord,"SpeciesID")
  dat
}

## check to see if the presences dataset is multispecies.
checkMultispecies <- function(presences){
  if(length(unique(presences[,"SpeciesID"]))>1) multi <- TRUE
  else multi <- FALSE
  multi
}

## check resolution and throw error if lots of quad points to be generated.
checkResolution <- function(resolution,window,control,method){
  reso <- raster::res(window)
  ncello <-  sum(!is.na(window)[])
  fct <- (reso/resolution)
  fctprod <- prod(fct)
  newncell <- ncello/(1/fctprod)
if(method%in%"grid"){
    if(newncell>control$maxpoints)stop(message("Hold up, the current resolution of ",resolution," will produce a a grid of approximately ",round(newncell),",\n choose a larger resolution. Limit is currently set to 500000 quadrature points"))
  else message("Based on the provided resolution of ",resolution," a grid of approximately ",round(newncell)," quadrature points will be produced.")
  }
}


checkWindow <- function(presences,window,coord){

  if(is.null(presences)){
    presences <- data.frame(X=runif(100,0,100),Y=runif(100,0,100))
  }

  if (is.null(window)) {
    message("Window is NULL, a raster-based window will be generated based on the extent of 'presences'\n with a default resolution of 1 deg will be returned.")
    window <- defaultWindow(presences,coord)
  }
  window
}

defaultWindow <- function (presences,coord) {
  # get limits
  xlim <- range(presences[,coord[1]])
  ylim <- range(presences[,coord[1]])

  # add on 5%
  xlim <- xlim + c(-1, 1) * diff(xlim) * 0.1
  ylim <- ylim + c(-1, 1) * diff(ylim) * 0.1

  xlim[1] <- floor(xlim[1])
  xlim[2] <- ceiling(xlim[2])
  ylim[1] <- floor(ylim[1])
  ylim[2] <- ceiling(ylim[2])

  e <- extent(c(xlim,ylim))
  sa <- raster(e,res=1, crs="+proj=longlat +datum=WGS84")
  sa[]<- 1:ncell(sa)
  return (sa)
}


fastwidemat <- function(dat){

  dat[,"SiteID"] <- factor(dat[,"SiteID"])
  dat[,"SpeciesID"] <- factor(dat[,"SpeciesID"])

  result <- with(dat, {
    out <- matrix(nrow=nlevels(SiteID), ncol=nlevels(SpeciesID),
                  dimnames=list(levels(SiteID), levels(SpeciesID)))
    out[cbind(SiteID, SpeciesID)] <- pres
    out
  })

  return(result)
}


fastwidematwts <- function(dat){

  dat[,"SiteID"] <- factor(dat[,"SiteID"])
  dat[,"DatasetID"] <- factor(dat[,"DatasetID"])
  # dat[,"SpeciesID"] <- factor(dat[,"SpeciesID"])

  wtsdat <- with(dat, {
    out <- matrix(nrow=nlevels(SiteID), ncol=nlevels(DatasetID),
                  dimnames=list(levels(SiteID), levels(DatasetID)))
    out[cbind(SiteID, DatasetID)] <- wts
    out
  })

  wtsdat
}

# a little function for making a finer scale window.
disaggregateWindow <- function(window, npoints){

  #set up the dissaggreation or aggregate
  nc <- length(window[!is.na(window[])])

  fct <- (nc/npoints)
  if(fct<1) dd <- disaggregate(window, 1/fct, na.rm=control$na.rm)

  return(list(ddwindow = dd,newres=res(dd)))

}




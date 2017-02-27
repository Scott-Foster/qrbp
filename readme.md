qrbp is an r package for generating quasi random background points for Poisson point process models.
----------------------------------------------------------------------------------------------------

The package aims to generate quasi-random background point for use in Poisson point process models. Quasi-random points are an alternative to grid-based or random background point designs. Quasi-random (sampling) background points are an advanced form of spatially-balanced survey design or point stratification, that aims to reduce the frequency of placing samples close to each other (relative to simple randomisations or grid designs). A quasi-random background point design improves efficiency of background point sampling (and subsequent modelling) by reducing the amount of spatial auto-correlation between data implying that each sample is providing as much unique information as possible (Grafston & Tille, 2013) and thus reducing low errors for geostatistical prediction (Diggle & Ribeiro, 2007).

``` r
devtools::install_github('skiptoniam/qrbp')
```

There are two main functions in the `qrbp` package, the first and main function can be used to generate `n` quasi-random background points within a spatial domain. The for background points can be used in Poisson point process modelling in R. The main function is , which takes some coordinates, an area of interest and covariates (and other parameters) and produces a dataset. It is essentially a wrapper around the (excellent and existing) function in the MBHdesign package which already implements quasi-random sampling within a basic domain.

Here is an example using a set of spatial points and a raster. In this example we use the location of the existing sample sites to help generate a new set of back ground points based on an underlying probability of sampling intensity. The probability of estimating the probability of presence from a series of spatial points. The probability of *absence in an area of size A* according to the Poisson distribution is:

*p**r*(*y* = 0)=*e**x**p*(−*λ*(*u*)\**A*)

The prob of *presence* is then:

*p**r*(*y* = 1)=1 − *p**r*(*y* = 0) =1 − *e**x**p*(−*λ*(*u*)\**A*)

where *λ*(*u*) = the intensity value at point *u* and *A* is the area of the sampling unit (cell size). $\\lammbda$ is estimated using `density.ppp` from the spatstat package and then converted into a `inclusion.prob` to inform quasi-random background point selection.

<!-- Generate some random points and a raster to represent study area. -->
<!-- ```{r} -->
<!-- library(raster) -->
<!-- set.seed(123) -->
<!-- N <- 100 -->
<!-- ks <- as.data.frame(cbind(x1=runif(N, min=-10, max=10),x2=runif(N, min=-10, max=10))) -->
<!-- sa <- raster(nrows=100, ncols=100, xmn=-10, xmx=10,ymn=-10,ymx=10) -->
<!-- sa[]<-rnorm(10000) -->
<!-- projection(sa) <- "+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0" -->
<!-- plot(sa) -->
<!-- points(ks$x1,ks$x2,pch=16) -->
<!-- ``` -->
<!-- How many quasi-random background points do we need? Let start with 200. -->
<!-- The function will plot the underlying probability of sampling intensity, the presence points (white) and the generated quasi-random background points. -->
<!-- ```{r} -->
<!-- library(qrbp) -->
<!-- set.seed(123) -->
<!-- n <- 200 -->
<!-- bkpts <- qrbp(n,dimension = 2,known.sites=ks,include.known.sites=TRUE, -->
<!--               study.area = sa,inclusion.probs = NULL,sigma=1,plot.prbs=TRUE) -->
<!-- points(ks$x1,ks$x2,pch=16,col='white') -->
<!-- ``` -->
Import some species data and covariates for modelling

``` r
library(sdm)
library(rgdal)
library(raster)

file <- system.file("external/species.shp", package="sdm") # 
species <- shapefile(file)
path <- system.file("external", package="sdm") # path to the folder contains the data
lst <- list.files(path=path,pattern='asc$',full.names = T) 
preds <- stack(lst)
projection(preds) <- "+proj=merc +lon_0=0 +k=1 +x_0=0 +y_0=0 +a=6378137 +b=6378137 +units=m +no_defs"
```

plot the presence only data (occurrences==1), in the dataset we have the luxury of absences which means that if you were going to model this species correctly, you could do it using absences and have no need generate background points.

``` r
plot(preds[[1]])
points(species[species$Occurrence == 1,],col='red',pch=16,cex=.5)
```

![](readme_files/figure-markdown_github/unnamed-chunk-2-1.png)

For a laugh, let's generate some quasirandom background points and plot them against the presence points

``` r
library(qrbp)
POdata <- species[species$Occurrence == 1,]
bkpts <- generate_background_points(number_of_background_points = 2000,
                                    known_sites = POdata@coords,
                                    study_area = preds[[1]],
                                    model_covariates = preds,
                                    resolution = 2000,
                                    method = 'quasirandom_covariates')
```

    ## Number of samples considered (number of samples found): 20000(0)

    ## Finished

``` r
nrow(bkpts)
```

    ## [1] 2094

Now let's plot our background points

``` r
plot(preds[[1]])
points(bkpts[bkpts$presence == 0,c("x","y")],col='blue',pch=16,cex=.5)
points(bkpts[bkpts$presence == 1,c("x","y")],col='red',pch=16,cex=1)
```

![](readme_files/figure-markdown_github/unnamed-chunk-4-1.png)

Now let's try and generate a ppm using a poisson gam

``` r
library(mgcv)
```

    ## Loading required package: nlme

    ## 
    ## Attaching package: 'nlme'

    ## The following object is masked from 'package:raster':
    ## 
    ##     getData

    ## This is mgcv 1.8-11. For overview type 'help("mgcv-package")'.

``` r
fm1 <- gam(presence ~ s(elevation) +
              s(precipitation) +
              s(temperature) +
              s(vegetation) + 
              offset(log(weights)),
              data = bkpts,
              family = poisson())

p <- predict(object=preds,
             model=fm1,
             type = 'response',
             const=data.frame(weights = 1))

p_cell <- p*res(preds)[1]*res(preds)[2]

plot(p_cell)
```

![](readme_files/figure-markdown_github/unnamed-chunk-5-1.png)

Let's compare to a PA sdm - hopefully we are in the right ball park

``` r
d <- sdmData(formula= ~., train=species, predictors=preds)
m1 <- sdm(Occurrence~.,data=d,methods=c('gam'))
p1 <- predict(m1,newdata=preds)
plot(p1)
```

![](readme_files/figure-markdown_github/unnamed-chunk-6-1.png) \#\#\# References Grafström, Anton, and Yves Tillé. "Doubly balanced spatial sampling with spreading and restitution of auxiliary totals." Environmetrics 24.2 (2013): 120-131.

Diggle, P. J., P. J. Ribeiro, Model-based Geostatistics. Springer Series in Statistics. Springer, 2007.
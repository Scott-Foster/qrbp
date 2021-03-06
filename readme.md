[![Travis build
status](https://travis-ci.com/skiptoniam/qrbp.svg?branch=master)](https://travis-ci.com/skiptoniam/qrbp)

[![Codecov test
coverage](https://codecov.io/gh/skiptoniam/qrbp/branch/master/graph/badge.svg)](https://codecov.io/gh/skiptoniam/qrbp?branch=master)

## qrbp is temporary R package that will be ingested into [ecomix](https://github.com/skiptoniam/ecomix) for generating quasi random background points for multiple species Poisson point process models.

The package aims to setup a model matrix for point process modelling for
multiple species (marked) point processes. The package is based on the
quadrature scheme proposed by Berman & Turner 1993, and Warton & Shepard
2010. The idea behind this package is simple, provided a set of
presences for a species (or multiple species) and a spatial region, we
can generate generate a model matrix which can be included in a Poisson
point process model. The code does provide the ability to produce a
background point data-set without the inclusion of presences (a dummy
grid) or for single species (which was developed as a proof of concept
for the multispecies approach).

We also provide the capacity to generate quasi-random points are an
alternative to grid-based or random background point designs.
Quasi-random (sampling) background points are an advanced form of
spatially-balanced survey design or point stratification, that aims to
reduce the frequency of placing samples close to each other (relative to
simple randomization or grid designs). A quasi-random background point
design improves efficiency of background point sampling (and subsequent
modelling) by reducing the amount of spatial auto-correlation between
data implying that each sample is providing as much unique information
as possible (Grafston & Tille, 2013) and thus reducing low errors for
geostatistical prediction (Diggle & Ribeiro, 2007).

For a worked example with single and multiple species presences see the
package vignette.

### References

Diggle, P. J., P. J. Ribeiro, Model-based Geostatistics. Springer Series
in Statistics. Springer, 2007.

Grafstrom, Anton, and Yves Tille. “Doubly balanced spatial sampling with
spreading and restitution of auxiliary totals.” Environmetrics 24.2
(2013): 120-131.

Warton, D. I., and L. C. Shepherd. “Poisson point process models solve
the pseudo-absence problem for presence-only data in ecology.” The
Annals of Applied Statistics 4.3 (2010): 1383-1402.

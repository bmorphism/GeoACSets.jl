"""
    GeoACSets

Categorical data structures (ACSets) with geospatial capabilities.

Key insight: Use morphisms for structural navigation, geometry for filtering.
- O(1) traversal through spatial hierarchies via `incident`/`subpart`
- Spatial predicates (intersects, within, etc.) for filtering candidates
- Cascading deletes respect containment structure automatically

## Quick Start

```julia
using GeoACSets

# Create a spatial hierarchy
city = SpatialCity{LibGEOS.Polygon, String, Float64}()

# Add structure (morphisms define containment)
r = add_part!(city, :Region, region_name="Downtown", region_geom=downtown_poly)
d = add_part!(city, :District, district_of=r, district_name="Financial", district_geom=fin_poly)
p = add_part!(city, :Parcel, parcel_of=d, parcel_geom=parcel_poly)
b = add_part!(city, :Building, building_on=p, footprint=bldg_poly, floor_area=1000.0)

# Query via morphisms (O(1) per hop)
buildings = buildings_in_region(city, r)

# Filter by spatial predicate
nearby = spatial_filter(city, :Building, :footprint, 
    geom -> LibGEOS.distance(geom, query_point) < 100.0)

# Combine both
result = filter(b -> city[b, :floor_area] > 500, buildings_in_region(city, r))
```
"""
module GeoACSets

using Reexport

@reexport using ACSets
using GeoInterface

# Try to load LibGEOS, but don't fail if unavailable
const HAS_LIBGEOS = try
    @eval using LibGEOS
    true
catch
    false
end

export SpatialCity, SchSpatialCity,
       SpatialGraph, SchSpatialGraph,
       ParcelAdjacency, SchParcelAdjacency,
       spatial_filter, spatial_join,
       buildings_in_region, region_of_building,
       parcels_in_district, district_of_parcel,
       buildings_in_district, parcels_in_region,
       district_of_building, region_of_parcel,
       traverse_up, traverse_down,
       neighbors, edges_between

include("schemas.jl")
include("predicates.jl")
include("traversal.jl")

end # module

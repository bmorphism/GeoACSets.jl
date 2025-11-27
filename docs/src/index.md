# GeoACSets.jl

**Categorical data structures with geospatial capabilities**

GeoACSets combines [ACSets](https://github.com/AlgebraicJulia/ACSets.jl) (Attributed C-Sets) with geospatial capabilities, enabling schema-aware traversal alongside spatial predicates.

## Key Insight

> **Use morphisms for structural navigation, geometry for filtering.**

- **Morphism traversal**: O(k) where k = results (automatic indexing)
- **Spatial join**: O(n log n) with R-tree
- The separation enables schema-aware propagation, correct cascading, homomorphism search

## Installation

```julia
using Pkg
Pkg.add("GeoACSets")
```

## Quick Start

```julia
using GeoACSets

# Create a city with spatial hierarchy
city = SpatialCity{LibGEOS.Polygon, String, Float64}()

# Add a region
r1 = add_part!(city, :Region,
    region_name = "Downtown",
    region_geom = LibGEOS.readgeom("POLYGON((0 0, 100 0, 100 100, 0 100, 0 0))")
)

# Add districts within the region (morphism: district_of → Region)
d1 = add_part!(city, :District,
    district_name = "Financial",
    district_of = r1,
    district_geom = LibGEOS.readgeom("POLYGON((0 0, 50 0, 50 50, 0 50, 0 0))")
)

# Add parcels within districts
p1 = add_part!(city, :Parcel, parcel_of = d1)

# Add buildings on parcels
b1 = add_part!(city, :Building,
    building_on = p1,
    footprint = LibGEOS.readgeom("POLYGON((10 10, 40 10, 40 40, 10 40, 10 10))"),
    floor_area = 900.0
)

# Query via morphisms (O(1) per hop)
buildings = buildings_in_region(city, r1)

# Upward traversal
region = region_of_building(city, b1)
```

## Schemas

### SpatialCity

Hierarchical containment: Region → District → Parcel → Building

```
Region ←─ district_of ─ District ←─ parcel_of ─ Parcel ←─ building_on ─ Building
```

### SpatialGraph

Weighted graph with vertex locations.

### ParcelAdjacency

Parcel boundary relationships.

## Why Morphisms + Geometry?

Traditional spatial databases require expensive spatial joins for hierarchical queries. GeoACSets uses morphisms for O(1) structural navigation while reserving geometry for filtering:

```julia
# Spatial filter, then morphism traversal
nearby_buildings = spatial_filter(city, :Building, :footprint,
    g -> LibGEOS.distance(g, school_geom) < 500)

# Instant hierarchical context via morphisms
for b in nearby_buildings
    district = traverse_up(city, b, :building_on, :parcel_of)
    region = traverse_up(city, b, :building_on, :parcel_of, :district_of)
end
```

## Contents

```@contents
Pages = ["api.md"]
```

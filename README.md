# GeoACSets.jl

[![CI](https://github.com/bmorphism/GeoACSets.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/bmorphism/GeoACSets.jl/actions/workflows/CI.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Categorical data structures with spatial geometry**

GeoACSets combines [ACSets](https://github.com/AlgebraicJulia/ACSets.jl) (Attributed C-Sets) with geospatial capabilities, enabling schema-aware traversal alongside spatial predicates.

## Key Insight

> **Use morphisms for structural navigation, geometry for filtering.**

| Operation | Complexity | When to Use |
|-----------|------------|-------------|
| Morphism traversal | O(k) where k = results | Hierarchical containment, known relationships |
| Spatial join | O(n log n) with R-tree | Ad-hoc proximity, geometric predicates |

This separation enables:
- Schema-aware propagation ("all buildings in region X")
- Correct cascading deletes (remove district → remove all contained parcels)
- Homomorphism search for pattern matching

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/bmorphism/GeoACSets.jl")
```

## Quick Start

```julia
using GeoACSets
using LibGEOS

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
```

## Schemas

### SpatialCity

Hierarchical containment: Region → District → Parcel → Building

```
   Region ←─ district_of ─ District ←─ parcel_of ─ Parcel ←─ building_on ─ Building
     │                        │                       │                       │
     └─ region_geom          └─ district_geom        └─ parcel_geom          └─ footprint
     └─ region_name          └─ district_name                                └─ floor_area
```

### SpatialGraph

Weighted graph with vertex locations:

```
   V ←─ src ─ E ─ tgt → V
   │          │
   └─ location└─ weight
```

### ParcelAdjacency

Parcel boundary relationships:

```
   Parcel ←─ parcel₁ ─ Boundary ─ parcel₂ → Parcel
      │                    │
      └─ parcel_geom       └─ shared_length
```

## Traversal API

### Schema-Aware Navigation

```julia
# Get all buildings in a region (traverses morphisms)
buildings = buildings_in_region(city, region_id)

# Get the region containing a building (follows morphisms up)
region = region_of_building(city, building_id)

# Generic traversal
parcel = traverse_up(city, building_id, :building_on)
district = traverse_up(city, building_id, :building_on, :parcel_of)

# Downward traversal
parcels = traverse_down(city, region_id, :district_of, :parcel_of)
```

### Spatial Filtering

```julia
# Filter by predicate on geometry attribute
large_buildings = spatial_filter(city, :Building, :floor_area, a -> a > 1000)

# Filter with custom geometry predicate
query_region = LibGEOS.readgeom("POLYGON(...)")
intersecting = spatial_filter(city, :Building, :footprint, 
    g -> LibGEOS.intersects(g, query_region))
```

### Graph Operations

```julia
g = SpatialGraph{LibGEOS.Point, Float64}()

# Add vertices and edges
v1 = add_part!(g, :V, location = point1)
v2 = add_part!(g, :V, location = point2)
e = add_part!(g, :E, src = v1, tgt = v2, weight = 5.0)

# Query neighbors
nbrs = neighbors(g, v1)  # [v2]

# Find edges between vertices
es = edges_between(g, v1, v2)  # [e]
```

## Why Morphisms + Geometry?

### Pattern: "Buildings near schools"

**Without GeoACSets** (pure spatial):
```julia
# Must manually join and filter
for b in buildings
    for s in schools
        if distance(b.geom, s.geom) < 500
            # What district? What region? Manual lookup...
        end
    end
end
```

**With GeoACSets**:
```julia
# Spatial filter, then morphism traversal
nearby_buildings = spatial_filter(city, :Building, :footprint,
    g -> LibGEOS.distance(g, school_geom) < 500)

# Instant hierarchical context
for b in nearby_buildings
    district = traverse_up(city, b, :building_on, :parcel_of)
    region = traverse_up(city, b, :building_on, :parcel_of, :district_of)
    # All indexed lookups - no search needed
end
```

### Cascading Deletes

```julia
# Remove a district - all parcels and buildings automatically removed
cascading_rem_part!(city, :District, district_id)
```

This is referential integrity that spatial databases typically lack.

## Use Cases

### Energy Grid Modeling

See `examples/grid_reopt_integration.jl` for integration with [REopt.jl](https://github.com/NREL/REopt.jl):
- Distribution grid hierarchy: Transmission Zone → Substation → Feeder → Transformer → Service Point → DER
- Morphisms encode electrical connectivity
- Spatial queries for site selection, hosting capacity analysis

### World Model

See `examples/world_model.jl` for multi-scale geographic hierarchy:
- Continent → Country → Region → City → Feature
- Haversine distance queries
- Hierarchical aggregations

## Benchmarks

See `docs/benchmarks/SPATIALBENCH_ANALYSIS.md` for comparison with [Apache Sedona SpatialBench](https://github.com/apache/sedona-spatialbench):
- GeoACSets excels at hierarchical queries (Q3-Q4, Q10-Q12)
- Sedona excels at ad-hoc spatial joins (Q1-Q2, Q6-Q8)
- The systems are complementary, not competitive

## Related Work

- [ACSets.jl](https://github.com/AlgebraicJulia/ACSets.jl) - Core categorical data structures
- [Catlab.jl](https://github.com/AlgebraicJulia/Catlab.jl) - Applied category theory
- [LibGEOS.jl](https://github.com/JuliaGeo/LibGEOS.jl) - Geometry operations
- [GeoInterface.jl](https://github.com/JuliaGeo/GeoInterface.jl) - Common geometry traits

## License

MIT

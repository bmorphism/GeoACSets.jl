# Schema-aware traversal helpers for GeoACSets
#
# These exploit the morphism structure for O(1)-per-hop navigation.

# =============================================================================
# SpatialCity Traversals
# =============================================================================

"""
    buildings_in_region(city::SpatialCity, region_id) -> Vector{Int}

Find all buildings transitively contained in a region.

Traverses: Region ← District ← Parcel ← Building

Cost: O(d + p + b) where d, p, b are the number of districts, parcels, buildings
      in the region. Compare to spatial join which is O(n log n) or worse.

# Example
```julia
downtown_buildings = buildings_in_region(city, downtown_id)
```
"""
function buildings_in_region(city::SpatialCity, region_id::Int)
    districts = incident(city, region_id, :district_of)
    parcels = reduce(vcat, [incident(city, d, :parcel_of) for d in districts]; init=Int[])
    buildings = reduce(vcat, [incident(city, p, :building_on) for p in parcels]; init=Int[])
    return buildings
end

"""
    parcels_in_region(city::SpatialCity, region_id) -> Vector{Int}

Find all parcels transitively contained in a region.
"""
function parcels_in_region(city::SpatialCity, region_id::Int)
    districts = incident(city, region_id, :district_of)
    parcels = reduce(vcat, [incident(city, d, :parcel_of) for d in districts]; init=Int[])
    return parcels
end

"""
    buildings_in_district(city::SpatialCity, district_id) -> Vector{Int}

Find all buildings in a district.
"""
function buildings_in_district(city::SpatialCity, district_id::Int)
    parcels = incident(city, district_id, :parcel_of)
    buildings = reduce(vcat, [incident(city, p, :building_on) for p in parcels]; init=Int[])
    return buildings
end

"""
    parcels_in_district(city::SpatialCity, district_id) -> Vector{Int}

Find all parcels in a district.
"""
function parcels_in_district(city::SpatialCity, district_id::Int)
    incident(city, district_id, :parcel_of)
end

"""
    region_of_building(city::SpatialCity, building_id) -> Int

Find the region containing a building.

Traverses: Building → Parcel → District → Region

Cost: O(1) - just three morphism lookups.
"""
function region_of_building(city::SpatialCity, building_id::Int)
    parcel = city[building_id, :building_on]
    district = city[parcel, :parcel_of]
    region = city[district, :district_of]
    return region
end

"""
    district_of_building(city::SpatialCity, building_id) -> Int

Find the district containing a building.
"""
function district_of_building(city::SpatialCity, building_id::Int)
    parcel = city[building_id, :building_on]
    district = city[parcel, :parcel_of]
    return district
end

"""
    district_of_parcel(city::SpatialCity, parcel_id) -> Int

Find the district containing a parcel.
"""
function district_of_parcel(city::SpatialCity, parcel_id::Int)
    city[parcel_id, :parcel_of]
end

"""
    region_of_parcel(city::SpatialCity, parcel_id) -> Int

Find the region containing a parcel.
"""
function region_of_parcel(city::SpatialCity, parcel_id::Int)
    district = city[parcel_id, :parcel_of]
    city[district, :district_of]
end

# =============================================================================
# Generic Traversals
# =============================================================================

"""
    traverse_up(acs, part, morphisms...) -> Int

Follow a chain of morphisms upward (part → ... → ancestor).

# Example
```julia
# Building → Parcel → District → Region
region = traverse_up(city, building_id, :building_on, :parcel_of, :district_of)
```
"""
function traverse_up(acs, part::Int, morphisms::Symbol...)
    current = part
    for m in morphisms
        current = acs[current, m]
    end
    return current
end

"""
    traverse_down(acs, part, morphisms...) -> Vector{Int}

Follow a chain of morphisms downward (ancestor → ... → descendants).

# Example
```julia
# Region → Districts → Parcels → Buildings
buildings = traverse_down(city, region_id, :district_of, :parcel_of, :building_on)
```
"""
function traverse_down(acs, part::Int, morphisms::Symbol...)
    current = [part]
    for m in morphisms
        current = reduce(vcat, [incident(acs, p, m) for p in current]; init=Int[])
    end
    return current
end

# =============================================================================
# SpatialGraph Traversals
# =============================================================================

"""
    neighbors(g::SpatialGraph, vertex_id) -> Vector{Int}

Find all vertices adjacent to a given vertex.
"""
function neighbors(g::SpatialGraph, v::Int)
    outgoing = incident(g, v, :src)
    incoming = incident(g, v, :tgt)
    targets = [g[e, :tgt] for e in outgoing]
    sources = [g[e, :src] for e in incoming]
    unique(vcat(targets, sources))
end

"""
    edges_between(g::SpatialGraph, v1, v2) -> Vector{Int}

Find all edges connecting two vertices (in either direction).
"""
function edges_between(g::SpatialGraph, v1::Int, v2::Int)
    out1 = filter(e -> g[e, :tgt] == v2, incident(g, v1, :src))
    out2 = filter(e -> g[e, :tgt] == v1, incident(g, v2, :src))
    vcat(out1, out2)
end

# Spatial predicate wrappers for GeoACSets
#
# These wrap LibGEOS/GeoInterface predicates for use with ACSet filtering.

"""
    spatial_filter(acs, object, attr, predicate) -> Vector{Int}

Filter parts of `object` by applying `predicate` to their geometry attribute `attr`.

# Arguments
- `acs`: the ACSet
- `object`: symbol for the object type (e.g., :Building)
- `attr`: symbol for the geometry attribute (e.g., :footprint)
- `predicate`: function Geom -> Bool

# Returns
Vector of part IDs where predicate returns true.

# Example
```julia
# Find buildings within a query polygon
within_query = spatial_filter(city, :Building, :footprint, 
    geom -> LibGEOS.within(geom, query_polygon))

# Find parcels intersecting a buffer
intersecting = spatial_filter(city, :Parcel, :parcel_geom,
    geom -> LibGEOS.intersects(geom, buffer_polygon))
```
"""
function spatial_filter(acs, object::Symbol, attr::Symbol, predicate::Function)
    filter(parts(acs, object)) do p
        geom = acs[p, attr]
        !isnothing(geom) && predicate(geom)
    end
end

"""
    spatial_filter(acs, object, attr, relation, query_geom) -> Vector{Int}

Filter parts by a binary spatial relation with a query geometry.

# Arguments
- `acs`: the ACSet
- `object`: symbol for the object type
- `attr`: symbol for the geometry attribute
- `relation`: binary predicate (geom, query) -> Bool
- `query_geom`: the query geometry

# Example
```julia
# Find buildings within 100m of a point
if HAS_LIBGEOS
    nearby = spatial_filter(city, :Building, :footprint,
        (g, q) -> LibGEOS.distance(g, q) < 100.0, query_point)
end
```
"""
function spatial_filter(acs, object::Symbol, attr::Symbol, relation::Function, query_geom)
    spatial_filter(acs, object, attr, geom -> relation(geom, query_geom))
end

"""
    spatial_join(acs, obj1, attr1, obj2, attr2, relation) -> Vector{Tuple{Int,Int}}

Find all pairs (p1, p2) where relation(geom1, geom2) is true.

# Arguments
- `acs`: the ACSet
- `obj1`, `attr1`: first object type and geometry attribute
- `obj2`, `attr2`: second object type and geometry attribute
- `relation`: binary spatial predicate

# Returns
Vector of (part1_id, part2_id) tuples.

# Example
```julia
# Find all (parcel, building) pairs where building intersects parcel
# (This is the spatial equivalent of what morphisms give us for free!)
if HAS_LIBGEOS
    intersections = spatial_join(city, :Parcel, :parcel_geom, 
                                  :Building, :footprint, LibGEOS.intersects)
end
```

Note: For containment relationships, prefer using morphisms directly!
This is O(n*m) while morphism traversal is O(k).
"""
function spatial_join(acs, obj1::Symbol, attr1::Symbol, 
                      obj2::Symbol, attr2::Symbol, relation::Function)
    results = Tuple{Int,Int}[]
    for p1 in parts(acs, obj1)
        g1 = acs[p1, attr1]
        isnothing(g1) && continue
        for p2 in parts(acs, obj2)
            g2 = acs[p2, attr2]
            isnothing(g2) && continue
            if relation(g1, g2)
                push!(results, (p1, p2))
            end
        end
    end
    results
end

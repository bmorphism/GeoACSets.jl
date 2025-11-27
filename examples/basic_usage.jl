# =============================================================================
# GeoACSets Basic Usage Example
# =============================================================================
#
# This example demonstrates the core GeoACSets pattern:
#   "Use morphisms for structural navigation, geometry for filtering"
#
# Run with:
#   julia --project=~/.topos/geo_acsets examples/basic_usage.jl

using GeoACSets

# -----------------------------------------------------------------------------
# 1. Create a SpatialCity with mock geometry (no LibGEOS required)
# -----------------------------------------------------------------------------

# For real usage, replace MockPolygon with LibGEOS.Polygon
struct MockPolygon
    coords::Vector{Tuple{Float64, Float64}}
end

# Create an empty city
city = SpatialCity{MockPolygon, String, Float64}()

println("=" ^ 60)
println("GeoACSets Basic Usage Example")
println("=" ^ 60)

# -----------------------------------------------------------------------------
# 2. Build the spatial hierarchy (Region → District → Parcel → Building)
# -----------------------------------------------------------------------------

println("\n📍 Building spatial hierarchy...")

# Add regions
downtown = add_part!(city, :Region,
    region_name = "Downtown",
    region_geom = MockPolygon([(0.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0)])
)
suburbs = add_part!(city, :Region,
    region_name = "Suburbs",
    region_geom = MockPolygon([(100.0, 0.0), (200.0, 0.0), (200.0, 100.0), (100.0, 100.0)])
)

# Add districts (morphism: district_of → Region)
financial = add_part!(city, :District,
    district_name = "Financial",
    district_of = downtown,
    district_geom = MockPolygon([(0.0, 0.0), (50.0, 0.0), (50.0, 50.0), (0.0, 50.0)])
)
arts = add_part!(city, :District,
    district_name = "Arts",
    district_of = downtown,
    district_geom = MockPolygon([(50.0, 0.0), (100.0, 0.0), (100.0, 50.0), (50.0, 50.0)])
)
residential = add_part!(city, :District,
    district_name = "Residential",
    district_of = suburbs
)

# Add parcels (morphism: parcel_of → District)
parcel_a = add_part!(city, :Parcel, parcel_of = financial,
    parcel_geom = MockPolygon([(0.0, 0.0), (25.0, 0.0), (25.0, 25.0), (0.0, 25.0)])
)
parcel_b = add_part!(city, :Parcel, parcel_of = financial,
    parcel_geom = MockPolygon([(25.0, 0.0), (50.0, 0.0), (50.0, 25.0), (25.0, 25.0)])
)
parcel_c = add_part!(city, :Parcel, parcel_of = arts)
parcel_d = add_part!(city, :Parcel, parcel_of = residential)

# Add buildings (morphism: building_on → Parcel)
tower_1 = add_part!(city, :Building, building_on = parcel_a,
    footprint = MockPolygon([(5.0, 5.0), (20.0, 5.0), (20.0, 20.0), (5.0, 20.0)]),
    floor_area = 10000.0
)
tower_2 = add_part!(city, :Building, building_on = parcel_a,
    footprint = MockPolygon([(2.0, 2.0), (8.0, 2.0), (8.0, 8.0), (2.0, 8.0)]),
    floor_area = 5000.0
)
gallery = add_part!(city, :Building, building_on = parcel_c,
    footprint = MockPolygon([(60.0, 10.0), (90.0, 10.0), (90.0, 40.0), (60.0, 40.0)]),
    floor_area = 900.0
)
house = add_part!(city, :Building, building_on = parcel_d,
    footprint = MockPolygon([(110.0, 10.0), (130.0, 10.0), (130.0, 30.0), (110.0, 30.0)]),
    floor_area = 200.0
)

println("  Created: $(nparts(city, :Region)) regions, $(nparts(city, :District)) districts, " *
        "$(nparts(city, :Parcel)) parcels, $(nparts(city, :Building)) buildings")

# -----------------------------------------------------------------------------
# 3. Morphism Traversal (structural navigation)
# -----------------------------------------------------------------------------

println("\n🔗 Morphism traversal (O(k) lookups):")

# Upward: Building → Region
for b in parts(city, :Building)
    name = city[b, :floor_area]
    region = region_of_building(city, b)
    region_name = city[region, :region_name]
    println("  Building $(b) ($(name) sqft) is in region: $(region_name)")
end

# Downward: Region → Buildings
println("\n  Buildings in Downtown:")
downtown_buildings = buildings_in_region(city, downtown)
for b in downtown_buildings
    println("    Building $(b): $(city[b, :floor_area]) sqft")
end

# Generic traversal
println("\n  Generic traverse_up from building $(tower_1):")
println("    → Parcel: $(traverse_up(city, tower_1, :building_on))")
println("    → District: $(traverse_up(city, tower_1, :building_on, :parcel_of))")
println("    → Region: $(traverse_up(city, tower_1, :building_on, :parcel_of, :district_of))")

# -----------------------------------------------------------------------------
# 4. Spatial Filtering (geometry predicates)
# -----------------------------------------------------------------------------

println("\n🗺️  Spatial filtering:")

# Filter buildings by floor area
large_buildings = spatial_filter(city, :Building, :floor_area, a -> a > 1000)
println("  Large buildings (>1000 sqft): $(large_buildings)")
for b in large_buildings
    region = region_of_building(city, b)
    println("    Building $(b) in $(city[region, :region_name]): $(city[b, :floor_area]) sqft")
end

# -----------------------------------------------------------------------------
# 5. Cascading Delete (referential integrity)
# -----------------------------------------------------------------------------

println("\n🗑️  Cascading delete demonstration:")
println("  Before: $(nparts(city, :District)) districts, $(nparts(city, :Parcel)) parcels, $(nparts(city, :Building)) buildings")

# Delete the Financial district - cascades to parcels and buildings
cascading_rem_part!(city, :District, financial)

println("  After removing Financial district:")
println("    $(nparts(city, :District)) districts, $(nparts(city, :Parcel)) parcels, $(nparts(city, :Building)) buildings")

# -----------------------------------------------------------------------------
# 6. SpatialGraph example
# -----------------------------------------------------------------------------

println("\n📊 SpatialGraph example:")

g = SpatialGraph{MockPolygon, Float64}()

# Create a triangle of vertices
v1 = add_part!(g, :V, location = MockPolygon([(0.0, 0.0)]))
v2 = add_part!(g, :V, location = MockPolygon([(1.0, 0.0)]))
v3 = add_part!(g, :V, location = MockPolygon([(0.5, 1.0)]))

# Add edges
add_part!(g, :E, src = v1, tgt = v2, weight = 1.0)
add_part!(g, :E, src = v2, tgt = v3, weight = 2.0)
add_part!(g, :E, src = v3, tgt = v1, weight = 3.0)

println("  Created graph with $(nparts(g, :V)) vertices and $(nparts(g, :E)) edges")
println("  Neighbors of v1: $(neighbors(g, v1))")
println("  Edges between v1 and v2: $(edges_between(g, v1, v2))")

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

println("\n" * "=" ^ 60)
println("Key insight: Morphisms give O(k) navigation, geometry gives filtering")
println("  - traverse_up/down: follow indexed morphisms")
println("  - spatial_filter: predicate over geometry attributes")
println("  - cascading_rem_part!: automatic referential integrity")
println("=" ^ 60)

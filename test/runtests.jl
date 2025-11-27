using Test
using GeoACSets

# =============================================================================
# Mock Geometry Type (for testing without LibGEOS)
# =============================================================================

struct MockPolygon
    coords::Vector{Tuple{Float64, Float64}}
end

mock_intersects(a::MockPolygon, b::MockPolygon) = true
mock_within(a::MockPolygon, b::MockPolygon) = true
mock_area(p::MockPolygon) = abs(sum(
    p.coords[i][1] * p.coords[mod1(i+1, length(p.coords))][2] -
    p.coords[mod1(i+1, length(p.coords))][1] * p.coords[i][2]
    for i in 1:length(p.coords)
) / 2)

# =============================================================================
# Tests
# =============================================================================

@testset "GeoACSets" begin

    @testset "SpatialCity Schema" begin
        city = SpatialCity{MockPolygon, String, Float64}()
        
        # Add regions
        r1 = add_part!(city, :Region,
            region_name = "Downtown",
            region_geom = MockPolygon([(0.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0)])
        )
        r2 = add_part!(city, :Region,
            region_name = "Suburbs",
            region_geom = MockPolygon([(100.0, 0.0), (200.0, 0.0), (200.0, 100.0), (100.0, 100.0)])
        )
        
        @test nparts(city, :Region) == 2
        @test city[r1, :region_name] == "Downtown"
        
        # Add districts
        d1 = add_part!(city, :District,
            district_name = "Financial",
            district_of = r1,
            district_geom = MockPolygon([(0.0, 0.0), (50.0, 0.0), (50.0, 50.0), (0.0, 50.0)])
        )
        d2 = add_part!(city, :District,
            district_name = "Residential", 
            district_of = r1,
            district_geom = MockPolygon([(50.0, 0.0), (100.0, 0.0), (100.0, 50.0), (50.0, 50.0)])
        )
        
        @test nparts(city, :District) == 2
        @test incident(city, r1, :district_of) == [d1, d2]
        
        # Add parcels
        p1 = add_part!(city, :Parcel, parcel_of = d1,
            parcel_geom = MockPolygon([(0.0, 0.0), (25.0, 0.0), (25.0, 25.0), (0.0, 25.0)])
        )
        p2 = add_part!(city, :Parcel, parcel_of = d1,
            parcel_geom = MockPolygon([(25.0, 0.0), (50.0, 0.0), (50.0, 25.0), (25.0, 25.0)])
        )
        p3 = add_part!(city, :Parcel, parcel_of = d2,
            parcel_geom = MockPolygon([(50.0, 0.0), (75.0, 0.0), (75.0, 25.0), (50.0, 25.0)])
        )
        
        @test nparts(city, :Parcel) == 3
        
        # Add buildings
        b1 = add_part!(city, :Building, building_on = p1,
            footprint = MockPolygon([(5.0, 5.0), (20.0, 5.0), (20.0, 20.0), (5.0, 20.0)]),
            floor_area = 225.0
        )
        b2 = add_part!(city, :Building, building_on = p1,
            footprint = MockPolygon([(2.0, 2.0), (8.0, 2.0), (8.0, 8.0), (2.0, 8.0)]),
            floor_area = 36.0
        )
        b3 = add_part!(city, :Building, building_on = p2,
            footprint = MockPolygon([(30.0, 5.0), (45.0, 5.0), (45.0, 20.0), (30.0, 20.0)]),
            floor_area = 225.0
        )
        
        @test nparts(city, :Building) == 3
    end

    @testset "Traversal - buildings_in_region" begin
        city = SpatialCity{MockPolygon, String, Float64}()
        
        r1 = add_part!(city, :Region, region_name = "R1")
        r2 = add_part!(city, :Region, region_name = "R2")
        
        d1 = add_part!(city, :District, district_name = "D1", district_of = r1)
        d2 = add_part!(city, :District, district_name = "D2", district_of = r1)
        d3 = add_part!(city, :District, district_name = "D3", district_of = r2)
        
        p1 = add_part!(city, :Parcel, parcel_of = d1)
        p2 = add_part!(city, :Parcel, parcel_of = d2)
        p3 = add_part!(city, :Parcel, parcel_of = d3)
        
        b1 = add_part!(city, :Building, building_on = p1, floor_area = 100.0)
        b2 = add_part!(city, :Building, building_on = p1, floor_area = 200.0)
        b3 = add_part!(city, :Building, building_on = p2, floor_area = 300.0)
        b4 = add_part!(city, :Building, building_on = p3, floor_area = 400.0)
        
        # Buildings in R1 should be b1, b2, b3
        r1_buildings = buildings_in_region(city, r1)
        @test sort(r1_buildings) == [b1, b2, b3]
        
        # Buildings in R2 should be b4
        r2_buildings = buildings_in_region(city, r2)
        @test r2_buildings == [b4]
    end

    @testset "Traversal - region_of_building" begin
        city = SpatialCity{MockPolygon, String, Float64}()
        
        r1 = add_part!(city, :Region, region_name = "R1")
        d1 = add_part!(city, :District, district_name = "D1", district_of = r1)
        p1 = add_part!(city, :Parcel, parcel_of = d1)
        b1 = add_part!(city, :Building, building_on = p1, floor_area = 100.0)
        
        @test region_of_building(city, b1) == r1
    end

    @testset "Traversal - generic traverse_up/down" begin
        city = SpatialCity{MockPolygon, String, Float64}()
        
        r1 = add_part!(city, :Region, region_name = "R1")
        d1 = add_part!(city, :District, district_name = "D1", district_of = r1)
        p1 = add_part!(city, :Parcel, parcel_of = d1)
        b1 = add_part!(city, :Building, building_on = p1, floor_area = 100.0)
        
        # Traverse up
        @test traverse_up(city, b1, :building_on) == p1
        @test traverse_up(city, b1, :building_on, :parcel_of) == d1
        @test traverse_up(city, b1, :building_on, :parcel_of, :district_of) == r1
        
        # Traverse down
        @test traverse_down(city, r1, :district_of) == [d1]
        @test traverse_down(city, r1, :district_of, :parcel_of) == [p1]
        @test traverse_down(city, r1, :district_of, :parcel_of, :building_on) == [b1]
    end

    @testset "Cascading Delete" begin
        city = SpatialCity{MockPolygon, String, Float64}()
        
        r1 = add_part!(city, :Region, region_name = "R1")
        d1 = add_part!(city, :District, district_name = "D1", district_of = r1)
        d2 = add_part!(city, :District, district_name = "D2", district_of = r1)
        p1 = add_part!(city, :Parcel, parcel_of = d1)
        p2 = add_part!(city, :Parcel, parcel_of = d2)
        b1 = add_part!(city, :Building, building_on = p1, floor_area = 100.0)
        b2 = add_part!(city, :Building, building_on = p2, floor_area = 200.0)
        
        @test nparts(city, :Building) == 2
        @test nparts(city, :Parcel) == 2
        
        # Delete d1 - should cascade to p1 and b1
        cascading_rem_part!(city, :District, d1)
        
        @test nparts(city, :District) == 1
        @test nparts(city, :Parcel) == 1
        @test nparts(city, :Building) == 1
    end

    @testset "Spatial Filter" begin
        city = SpatialCity{MockPolygon, String, Float64}()
        
        r1 = add_part!(city, :Region, region_name = "R1")
        d1 = add_part!(city, :District, district_name = "D1", district_of = r1)
        p1 = add_part!(city, :Parcel, parcel_of = d1)
        
        b1 = add_part!(city, :Building, building_on = p1, floor_area = 100.0)
        b2 = add_part!(city, :Building, building_on = p1, floor_area = 200.0)
        b3 = add_part!(city, :Building, building_on = p1, floor_area = 300.0)
        
        # Filter by floor area (using spatial_filter on numeric attribute as proxy)
        large = spatial_filter(city, :Building, :floor_area, a -> a > 150)
        @test sort(large) == [b2, b3]
    end

    @testset "SpatialGraph" begin
        g = SpatialGraph{MockPolygon, Float64}()
        
        v1 = add_part!(g, :V, location = MockPolygon([(0.0, 0.0)]))
        v2 = add_part!(g, :V, location = MockPolygon([(1.0, 0.0)]))
        v3 = add_part!(g, :V, location = MockPolygon([(0.5, 1.0)]))
        
        e1 = add_part!(g, :E, src = v1, tgt = v2, weight = 1.0)
        e2 = add_part!(g, :E, src = v2, tgt = v3, weight = 2.0)
        e3 = add_part!(g, :E, src = v3, tgt = v1, weight = 3.0)
        
        @test nparts(g, :V) == 3
        @test nparts(g, :E) == 3
        
        # Test neighbors
        n1 = neighbors(g, v1)
        @test sort(n1) == [v2, v3]
        
        # Test edges_between
        @test edges_between(g, v1, v2) == [e1]
        @test edges_between(g, v2, v1) == [e1]
    end

end

println("\n✓ All tests passed!")

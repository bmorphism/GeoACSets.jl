# =============================================================================
# Spatial Grid Model: GeoACSets + TulipaEnergy + REopt Integration
# =============================================================================
#
# USE CASE: Distribution Grid Planning with Spatial Awareness
#
# Problem: Utility planners need to answer questions like:
#   - Where should we place new solar + storage to minimize congestion?
#   - Which feeders serve the most critical facilities?
#   - How does DER placement affect hosting capacity across zones?
#   - What's the upgrade cost for each substation's service territory?
#
# Solution: Combine GeoACSets' structural navigation with energy optimization
#
# Architecture:
#   GeoACSets        → Spatial hierarchy + containment relationships
#   TulipaEnergy     → Investment & dispatch optimization  
#   REopt.jl         → DER sizing & resilience analysis
#   PowerModels.jl   → Power flow & OPF (optional)
#
# Key insight: The grid IS a spatial hierarchy
#   TransmissionZone → Substation → Feeder → Transformer → Meter/Load
#   
#   GeoACSets morphisms give O(1) "which substation serves this building?"
#   while geometry enables "find all loads within 500m of this fault location"
#
# =============================================================================

using GeoACSets
using ACSets.Schemas: BasicSchema

# =============================================================================
# Schema: Spatial Distribution Grid
# =============================================================================

#=
The distribution grid has a natural spatial hierarchy:

    TransmissionZone (planning area, ~100s of sq mi)
        └── Substation (bulk power delivery point)
              └── Feeder (distribution circuit, ~4-34.5 kV)
                    └── Transformer (step-down to service voltage)
                          └── ServicePoint (meter location)
                                └── DER (solar, storage, EV charger, etc.)

Each level has:
  - A geometry (service territory polygon, or point location)
  - Attributes (capacity, loading, voltage, etc.)
  - Morphism to parent (which substation does this feeder belong to?)

This enables queries that are impossible or expensive in traditional GIS:
  - "Total DER capacity on feeders served by Substation X" → O(feeders + transformers)
  - "Which transmission zone has the most hosting capacity?" → aggregate up
  - "Cascade a substation outage to all affected loads" → follow morphisms down
=#

const SchDistributionGrid = BasicSchema(
    # Objects (spatial hierarchy levels)
    [:TransmissionZone, :Substation, :Feeder, :Transformer, :ServicePoint, :DER],
    
    # Morphisms (containment - "served by")
    [
        (:substation_in, :Substation, :TransmissionZone),
        (:feeder_at, :Feeder, :Substation),
        (:transformer_on, :Transformer, :Feeder),
        (:service_at, :ServicePoint, :Transformer),
        (:der_at, :DER, :ServicePoint)
    ],
    
    # Attribute types
    [:Geom, :Name, :ID, :Capacity, :Load, :Voltage, :Status, :DERType, :Cost],
    
    # Attributes
    [
        # TransmissionZone
        (:zone_geom, :TransmissionZone, :Geom),
        (:zone_name, :TransmissionZone, :Name),
        (:zone_id, :TransmissionZone, :ID),
        
        # Substation
        (:sub_geom, :Substation, :Geom),  # point location
        (:sub_name, :Substation, :Name),
        (:sub_id, :Substation, :ID),
        (:sub_capacity_mva, :Substation, :Capacity),
        (:sub_load_mw, :Substation, :Load),
        (:sub_voltage_kv, :Substation, :Voltage),
        
        # Feeder
        (:feeder_geom, :Feeder, :Geom),  # linestring or polygon
        (:feeder_id, :Feeder, :ID),
        (:feeder_capacity_mw, :Feeder, :Capacity),
        (:feeder_load_mw, :Feeder, :Load),
        (:feeder_voltage_kv, :Feeder, :Voltage),
        (:feeder_length_mi, :Feeder, :Capacity),  # reuse Capacity type for length
        
        # Transformer
        (:xfmr_geom, :Transformer, :Geom),  # point
        (:xfmr_id, :Transformer, :ID),
        (:xfmr_capacity_kva, :Transformer, :Capacity),
        (:xfmr_load_kw, :Transformer, :Load),
        
        # ServicePoint (meter)
        (:sp_geom, :ServicePoint, :Geom),  # point
        (:sp_id, :ServicePoint, :ID),
        (:sp_load_kw, :ServicePoint, :Load),
        (:sp_customer_type, :ServicePoint, :Name),  # residential, commercial, industrial
        (:sp_critical, :ServicePoint, :Status),     # is this a critical facility?
        
        # DER (distributed energy resource)
        (:der_geom, :DER, :Geom),
        (:der_id, :DER, :ID),
        (:der_type, :DER, :DERType),       # PV, storage, wind, EV, CHP
        (:der_capacity_kw, :DER, :Capacity),
        (:der_cost_usd, :DER, :Cost),
        (:der_status, :DER, :Status)       # proposed, installed, operational
    ]
)

@acset_type DistributionGrid(SchDistributionGrid, 
    index=[:substation_in, :feeder_at, :transformer_on, :service_at, :der_at])

# =============================================================================
# Traversal Functions for Grid Model
# =============================================================================

"""All feeders at a substation"""
feeders_at_substation(g, sub) = incident(g, sub, :feeder_at)

"""All transformers on a feeder"""
transformers_on_feeder(g, feeder) = incident(g, feeder, :transformer_on)

"""All service points at a transformer"""
services_at_transformer(g, xfmr) = incident(g, xfmr, :service_at)

"""All DERs at a service point"""
ders_at_service(g, sp) = incident(g, sp, :der_at)

"""All service points on a feeder (via transformers)"""
function services_on_feeder(g, feeder)
    xfmrs = transformers_on_feeder(g, feeder)
    reduce(vcat, [services_at_transformer(g, x) for x in xfmrs]; init=Int[])
end

"""All DERs on a feeder"""
function ders_on_feeder(g, feeder)
    services = services_on_feeder(g, feeder)
    reduce(vcat, [ders_at_service(g, sp) for sp in services]; init=Int[])
end

"""All service points at a substation (via feeders → transformers)"""
function services_at_substation(g, sub)
    feeders = feeders_at_substation(g, sub)
    reduce(vcat, [services_on_feeder(g, f) for f in feeders]; init=Int[])
end

"""All DERs at a substation"""
function ders_at_substation(g, sub)
    services = services_at_substation(g, sub)
    reduce(vcat, [ders_at_service(g, sp) for sp in services]; init=Int[])
end

"""Which substation serves a service point? (upward traversal)"""
function substation_of_service(g, sp)
    xfmr = g[sp, :service_at]
    feeder = g[xfmr, :transformer_on]
    g[feeder, :feeder_at]
end

"""Which transmission zone contains a DER?"""
function zone_of_der(g, der)
    sp = g[der, :der_at]
    sub = substation_of_service(g, sp)
    g[sub, :substation_in]
end

# =============================================================================
# Aggregation Functions (for optimization integration)
# =============================================================================

"""Total load at a substation (MW)"""
function total_load_at_substation(g, sub)
    services = services_at_substation(g, sub)
    sum(g[sp, :sp_load_kw] for sp in services; init=0.0) / 1000.0
end

"""Total DER capacity at a substation (kW) by type"""
function der_capacity_at_substation(g, sub; der_type=nothing)
    ders = ders_at_substation(g, sub)
    if der_type !== nothing
        ders = filter(d -> g[d, :der_type] == der_type, ders)
    end
    sum(g[d, :der_capacity_kw] for d in ders; init=0.0)
end

"""Hosting capacity remaining on a feeder (kW)"""
function hosting_capacity(g, feeder)
    capacity_mw = g[feeder, :feeder_capacity_mw]
    load_mw = g[feeder, :feeder_load_mw]
    existing_der_kw = sum(g[d, :der_capacity_kw] for d in ders_on_feeder(g, feeder); init=0.0)
    # Simple hosting capacity = (capacity - load) * 1000 - existing DER
    # Real calculation would involve power flow analysis
    max(0.0, (capacity_mw - load_mw) * 1000.0 - existing_der_kw)
end

"""Count critical facilities at a substation"""
function critical_facilities_at_substation(g, sub)
    services = services_at_substation(g, sub)
    count(sp -> g[sp, :sp_critical] == "yes", services)
end

"""All feeders in a transmission zone (for regional planning)"""
function feeders_in_zone(g, zone)
    subs = incident(g, zone, :substation_in)
    reduce(vcat, [feeders_at_substation(g, s) for s in subs]; init=Int[])
end

# =============================================================================
# Spatial Queries (combine morphisms + geometry)
# =============================================================================

"""Find all service points within radius of a fault location"""
function services_near_fault(g, fault_lat, fault_lon, radius_km)
    # Haversine distance
    function haversine(lat1, lon1, lat2, lon2)
        R = 6371.0
        φ1, φ2 = deg2rad(lat1), deg2rad(lat2)
        Δφ = deg2rad(lat2 - lat1)
        Δλ = deg2rad(lon2 - lon1)
        a = sin(Δφ/2)^2 + cos(φ1) * cos(φ2) * sin(Δλ/2)^2
        2R * asin(sqrt(a))
    end
    
    # Filter by geometry
    filter(parts(g, :ServicePoint)) do sp
        geom = g[sp, :sp_geom]
        if geom !== nothing && hasfield(typeof(geom), :lat)
            haversine(fault_lat, fault_lon, geom.lat, geom.lon) <= radius_km
        else
            false
        end
    end
end

"""Find substations with capacity issues in a zone"""
function overloaded_substations(g, zone; threshold=0.9)
    subs = incident(g, zone, :substation_in)
    filter(subs) do s
        capacity = g[s, :sub_capacity_mva]
        load = g[s, :sub_load_mw]
        capacity > 0 && (load / capacity) >= threshold
    end
end

# =============================================================================
# Integration Points with TulipaEnergy / REopt
# =============================================================================

#=
TULIPAENERGY INTEGRATION:

TulipaEnergyModel.jl uses a graph-based approach where assets connect directly.
GeoACSets can provide the spatial structure:

1. Export substation/feeder topology to Tulipa's graph format
2. Each Feeder becomes a "hub" in Tulipa
3. DERs become assets connected to hubs
4. Constraints come from hosting capacity calculations

function export_to_tulipa(g::DistributionGrid)
    # For each feeder, create a Tulipa hub with:
    #   - max_import = feeder_capacity_mw
    #   - location = feeder centroid (for transmission costs)
    
    # For each DER, create a Tulipa asset with:
    #   - connected_to = feeder hub
    #   - capacity = der_capacity_kw
    #   - type = der_type (maps to Tulipa producer/consumer/storage)
end
=#

#=
REOPT.JL INTEGRATION:

REopt optimizes DER sizing for individual sites. GeoACSets enables:

1. Portfolio analysis: Run REopt for all critical facilities in a zone
2. Aggregate results back up the hierarchy
3. Check if aggregate DER exceeds hosting capacity
4. Iterate: if violated, add upgrade costs or constrain DER

function run_portfolio_reopt(g::DistributionGrid, zone)
    critical_sps = filter(sp -> g[sp, :sp_critical] == "yes", 
                          services_in_zone(g, zone))
    
    results = Dict()
    for sp in critical_sps
        # Build REopt scenario for this service point
        scenario = REoptScenario(
            latitude = g[sp, :sp_geom].lat,
            longitude = g[sp, :sp_geom].lon,
            load_kw = g[sp, :sp_load_kw],
            # ... other REopt inputs
        )
        results[sp] = run_reopt(scenario)
    end
    
    # Aggregate by feeder to check hosting capacity
    for feeder in feeders_in_zone(g, zone)
        proposed_der = sum(results[sp].pv_kw + results[sp].storage_kw 
                         for sp in services_on_feeder(g, feeder) 
                         if haskey(results, sp); init=0.0)
        hc = hosting_capacity(g, feeder)
        if proposed_der > hc
            @warn "Feeder $(g[feeder, :feeder_id]) needs upgrade: $proposed_der kW proposed, $hc kW available"
        end
    end
    
    return results
end
=#

# =============================================================================
# Demo: Build a Sample Grid
# =============================================================================

# Simple point type for demo
struct GridPoint
    lat::Float64
    lon::Float64
end

function build_sample_grid()
    g = DistributionGrid{GridPoint, String, String, Float64, Float64, Float64, String, String, Float64}()
    
    # Transmission Zone
    zone1 = add_part!(g, :TransmissionZone,
        zone_name = "Metro East",
        zone_id = "TZ-001"
    )
    
    # Substations
    sub1 = add_part!(g, :Substation,
        sub_geom = GridPoint(40.7128, -74.0060),
        sub_name = "Downtown Sub",
        sub_id = "SUB-001",
        sub_capacity_mva = 50.0,
        sub_load_mw = 35.0,
        sub_voltage_kv = 13.8,
        substation_in = zone1
    )
    
    sub2 = add_part!(g, :Substation,
        sub_geom = GridPoint(40.7580, -73.9855),
        sub_name = "Midtown Sub", 
        sub_id = "SUB-002",
        sub_capacity_mva = 75.0,
        sub_load_mw = 60.0,
        sub_voltage_kv = 13.8,
        substation_in = zone1
    )
    
    # Feeders at Downtown Sub
    f1 = add_part!(g, :Feeder,
        feeder_id = "FDR-001",
        feeder_capacity_mw = 12.0,
        feeder_load_mw = 8.5,
        feeder_voltage_kv = 13.8,
        feeder_length_mi = 4.2,
        feeder_at = sub1
    )
    
    f2 = add_part!(g, :Feeder,
        feeder_id = "FDR-002", 
        feeder_capacity_mw = 10.0,
        feeder_load_mw = 9.2,
        feeder_voltage_kv = 13.8,
        feeder_length_mi = 3.8,
        feeder_at = sub1
    )
    
    # Feeders at Midtown Sub
    f3 = add_part!(g, :Feeder,
        feeder_id = "FDR-003",
        feeder_capacity_mw = 15.0,
        feeder_load_mw = 11.0,
        feeder_voltage_kv = 13.8,
        feeder_length_mi = 5.1,
        feeder_at = sub2
    )
    
    # Transformers on Feeder 1
    for i in 1:3
        xfmr = add_part!(g, :Transformer,
            xfmr_geom = GridPoint(40.712 + i*0.002, -74.005 + i*0.001),
            xfmr_id = "XFMR-001-$i",
            xfmr_capacity_kva = 500.0,
            xfmr_load_kw = 350.0,
            transformer_on = f1
        )
        
        # Service points at each transformer
        for j in 1:5
            sp = add_part!(g, :ServicePoint,
                sp_geom = GridPoint(40.712 + i*0.002 + j*0.0001, -74.005 + i*0.001 + j*0.0001),
                sp_id = "SP-001-$i-$j",
                sp_load_kw = 50.0 + rand() * 100,
                sp_customer_type = rand(["residential", "commercial"]),
                sp_critical = rand() < 0.1 ? "yes" : "no",
                service_at = xfmr
            )
            
            # Some service points have DERs
            if rand() < 0.3
                add_part!(g, :DER,
                    der_id = "DER-$i-$j",
                    der_type = rand(["PV", "storage", "EV"]),
                    der_capacity_kw = rand([5.0, 10.0, 25.0, 50.0]),
                    der_cost_usd = 0.0,
                    der_status = "installed",
                    der_at = sp
                )
            end
        end
    end
    
    return g, zone1, sub1, sub2, f1, f2, f3
end

# =============================================================================
# Run Demo
# =============================================================================

println("=" ^ 70)
println("GeoACSets Distribution Grid Model")
println("Integration with TulipaEnergy + REopt.jl")
println("=" ^ 70)

g, zone, sub1, sub2, f1, f2, f3 = build_sample_grid()

println("\n📊 Grid Statistics:")
println("  Transmission Zones: $(nparts(g, :TransmissionZone))")
println("  Substations:        $(nparts(g, :Substation))")
println("  Feeders:            $(nparts(g, :Feeder))")
println("  Transformers:       $(nparts(g, :Transformer))")
println("  Service Points:     $(nparts(g, :ServicePoint))")
println("  DERs:               $(nparts(g, :DER))")

println("\n🔌 Substation Analysis:")
for sub in parts(g, :Substation)
    name = g[sub, :sub_name]
    load = total_load_at_substation(g, sub)
    cap = g[sub, :sub_capacity_mva]
    der_pv = der_capacity_at_substation(g, sub; der_type="PV")
    der_storage = der_capacity_at_substation(g, sub; der_type="storage")
    critical = critical_facilities_at_substation(g, sub)
    
    println("\n  $name:")
    println("    Load: $(round(load, digits=1)) MW / $(cap) MVA capacity ($(round(100*load/cap, digits=1))%)")
    println("    DERs: $(round(der_pv, digits=1)) kW PV, $(round(der_storage, digits=1)) kW storage")
    println("    Critical facilities: $critical")
end

println("\n⚡ Feeder Hosting Capacity:")
for feeder in parts(g, :Feeder)
    id = g[feeder, :feeder_id]
    hc = hosting_capacity(g, feeder)
    ders = ders_on_feeder(g, feeder)
    existing = sum(g[d, :der_capacity_kw] for d in ders; init=0.0)
    println("  $id: $(round(hc, digits=0)) kW available ($(round(existing, digits=0)) kW installed)")
end

println("\n🎯 Key Integration Points:")
println("""
  1. TulipaEnergy: Export feeders as hubs, DERs as assets
     - Optimize investment across entire zone
     - Hosting capacity → hub import constraints
     
  2. REopt.jl: Run per-site optimization for critical facilities
     - Aggregate results to check feeder constraints
     - Iterate with upgrade costs if capacity exceeded
     
  3. PowerModels.jl: Power flow validation
     - Build network from transformer topology
     - Verify voltage/thermal limits post-optimization
""")

println("\n" * "=" ^ 70)
println("Morphisms give O(1) 'which substation serves this meter?'")
println("Geometry enables 'find all loads within 500m of fault'")
println("=" ^ 70)

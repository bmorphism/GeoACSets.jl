# =============================================================================
# GeoACSets + REopt.jl: Full Distribution Grid DER Planning
# =============================================================================
#
# This example demonstrates:
#   1. Building a spatial distribution grid model with GeoACSets
#   2. Running REopt optimization for critical facilities
#   3. Aggregating results by feeder to check hosting capacity
#   4. Identifying feeders that need upgrades
#
# Requirements:
#   julia> ] add REopt HiGHS
#
# Run with:
#   julia --project=~/.topos/geo_acsets examples/grid_reopt_integration.jl
#
# =============================================================================

using GeoACSets
using ACSets.Schemas: BasicSchema
using REopt
using HiGHS

# =============================================================================
# 1. Distribution Grid Schema (from spatial_grid_model.jl)
# =============================================================================

const SchDistributionGrid = BasicSchema(
    [:TransmissionZone, :Substation, :Feeder, :Transformer, :ServicePoint, :DER],
    [
        (:substation_in, :Substation, :TransmissionZone),
        (:feeder_at, :Feeder, :Substation),
        (:transformer_on, :Transformer, :Feeder),
        (:service_at, :ServicePoint, :Transformer),
        (:der_at, :DER, :ServicePoint)
    ],
    [:Geom, :Name, :ID, :Capacity, :Load, :Voltage, :Status, :DERType, :Cost],
    [
        (:zone_geom, :TransmissionZone, :Geom),
        (:zone_name, :TransmissionZone, :Name),
        (:zone_id, :TransmissionZone, :ID),
        (:sub_geom, :Substation, :Geom),
        (:sub_name, :Substation, :Name),
        (:sub_id, :Substation, :ID),
        (:sub_capacity_mva, :Substation, :Capacity),
        (:sub_load_mw, :Substation, :Load),
        (:sub_voltage_kv, :Substation, :Voltage),
        (:feeder_geom, :Feeder, :Geom),
        (:feeder_id, :Feeder, :ID),
        (:feeder_capacity_mw, :Feeder, :Capacity),
        (:feeder_load_mw, :Feeder, :Load),
        (:feeder_voltage_kv, :Feeder, :Voltage),
        (:feeder_length_mi, :Feeder, :Capacity),
        (:xfmr_geom, :Transformer, :Geom),
        (:xfmr_id, :Transformer, :ID),
        (:xfmr_capacity_kva, :Transformer, :Capacity),
        (:xfmr_load_kw, :Transformer, :Load),
        (:sp_geom, :ServicePoint, :Geom),
        (:sp_id, :ServicePoint, :ID),
        (:sp_load_kw, :ServicePoint, :Load),
        (:sp_customer_type, :ServicePoint, :Name),
        (:sp_critical, :ServicePoint, :Status),
        (:der_geom, :DER, :Geom),
        (:der_id, :DER, :ID),
        (:der_type, :DER, :DERType),
        (:der_capacity_kw, :DER, :Capacity),
        (:der_cost_usd, :DER, :Cost),
        (:der_status, :DER, :Status)
    ]
)

@acset_type DistributionGrid(SchDistributionGrid, 
    index=[:substation_in, :feeder_at, :transformer_on, :service_at, :der_at])

# =============================================================================
# 2. Grid Traversal Functions
# =============================================================================

feeders_at_substation(g, sub) = incident(g, sub, :feeder_at)
transformers_on_feeder(g, feeder) = incident(g, feeder, :transformer_on)
services_at_transformer(g, xfmr) = incident(g, xfmr, :service_at)
ders_at_service(g, sp) = incident(g, sp, :der_at)

function services_on_feeder(g, feeder)
    xfmrs = transformers_on_feeder(g, feeder)
    reduce(vcat, [services_at_transformer(g, x) for x in xfmrs]; init=Int[])
end

function ders_on_feeder(g, feeder)
    services = services_on_feeder(g, feeder)
    reduce(vcat, [ders_at_service(g, sp) for sp in services]; init=Int[])
end

function feeder_of_service(g, sp)
    xfmr = g[sp, :service_at]
    g[xfmr, :transformer_on]
end

function hosting_capacity(g, feeder)
    capacity_mw = g[feeder, :feeder_capacity_mw]
    load_mw = g[feeder, :feeder_load_mw]
    existing_der_kw = sum(g[d, :der_capacity_kw] for d in ders_on_feeder(g, feeder); init=0.0)
    max(0.0, (capacity_mw - load_mw) * 1000.0 - existing_der_kw)
end

# =============================================================================
# 3. Point Type for Geometry
# =============================================================================

struct GridPoint
    lat::Float64
    lon::Float64
end

# =============================================================================
# 4. Build Sample Distribution Grid
# =============================================================================

function build_sample_grid()
    g = DistributionGrid{GridPoint, String, String, Float64, Float64, Float64, String, String, Float64}()
    
    # Transmission Zone - San Diego region
    zone = add_part!(g, :TransmissionZone,
        zone_name = "San Diego Metro",
        zone_id = "SDGE-01"
    )
    
    # Substations
    sub1 = add_part!(g, :Substation,
        sub_geom = GridPoint(32.7157, -117.1611),
        sub_name = "Downtown Sub",
        sub_id = "SUB-DT01",
        sub_capacity_mva = 50.0,
        sub_load_mw = 35.0,
        sub_voltage_kv = 12.47,
        substation_in = zone
    )
    
    sub2 = add_part!(g, :Substation,
        sub_geom = GridPoint(32.8328, -117.1713),
        sub_name = "Mission Valley Sub",
        sub_id = "SUB-MV01",
        sub_capacity_mva = 75.0,
        sub_load_mw = 55.0,
        sub_voltage_kv = 12.47,
        substation_in = zone
    )
    
    # Feeders
    feeders_data = [
        # (id, sub, capacity_mw, load_mw)
        ("FDR-DT-101", sub1, 10.0, 7.5),
        ("FDR-DT-102", sub1, 12.0, 9.0),
        ("FDR-MV-201", sub2, 15.0, 11.0),
        ("FDR-MV-202", sub2, 12.0, 10.5),
    ]
    
    feeder_ids = Dict{String, Int}()
    for (fid, sub, cap, load) in feeders_data
        f = add_part!(g, :Feeder,
            feeder_id = fid,
            feeder_capacity_mw = cap,
            feeder_load_mw = load,
            feeder_voltage_kv = 12.47,
            feeder_length_mi = 5.0 + rand() * 3.0,
            feeder_at = sub
        )
        feeder_ids[fid] = f
    end
    
    # Critical facilities with realistic data
    # (name, feeder_id, load_kw, lat, lon, is_critical)
    facilities = [
        # Downtown - hospitals, data centers, emergency services
        ("UCSD Medical Center", "FDR-DT-101", 2500.0, 32.7180, -117.1580, true),
        ("Sharp Memorial Hospital", "FDR-DT-101", 3000.0, 32.7220, -117.1650, true),
        ("Downtown Data Center", "FDR-DT-102", 5000.0, 32.7140, -117.1620, true),
        ("City Hall", "FDR-DT-102", 800.0, 32.7198, -117.1628, true),
        ("Central Fire Station", "FDR-DT-101", 150.0, 32.7160, -117.1590, true),
        
        # Commercial buildings (not critical)
        ("Office Tower A", "FDR-DT-101", 1200.0, 32.7170, -117.1600, false),
        ("Retail Center", "FDR-DT-102", 600.0, 32.7155, -117.1640, false),
        
        # Mission Valley - more commercial + some critical
        ("Scripps Mercy Hospital", "FDR-MV-201", 2800.0, 32.8300, -117.1700, true),
        ("Police HQ", "FDR-MV-201", 400.0, 32.8310, -117.1680, true),
        ("Wastewater Treatment", "FDR-MV-202", 1500.0, 32.8350, -117.1750, true),
        
        # Commercial
        ("Fashion Valley Mall", "FDR-MV-201", 3500.0, 32.8280, -117.1710, false),
        ("Mission Valley Office Park", "FDR-MV-202", 2000.0, 32.8340, -117.1720, false),
    ]
    
    sp_map = Dict{String, Int}()  # facility name → service point id
    
    for (name, fid, load, lat, lon, critical) in facilities
        feeder = feeder_ids[fid]
        
        # Create transformer for this facility
        xfmr = add_part!(g, :Transformer,
            xfmr_geom = GridPoint(lat, lon),
            xfmr_id = "XFMR-$(name[1:3])",
            xfmr_capacity_kva = load * 1.2,  # 20% headroom
            xfmr_load_kw = load,
            transformer_on = feeder
        )
        
        # Create service point
        sp = add_part!(g, :ServicePoint,
            sp_geom = GridPoint(lat, lon),
            sp_id = "SP-$(name)",
            sp_load_kw = load,
            sp_customer_type = critical ? "critical" : "commercial",
            sp_critical = critical ? "yes" : "no",
            service_at = xfmr
        )
        
        sp_map[name] = sp
    end
    
    return g, zone, feeder_ids, sp_map
end

# =============================================================================
# 5. REopt Integration
# =============================================================================

"""
Build REopt inputs for a service point in the grid.
Uses simplified inputs for demonstration.
"""
function build_reopt_inputs(g, sp_id::Int)
    load_kw = g[sp_id, :sp_load_kw]
    geom = g[sp_id, :sp_geom]
    
    # Generate a simple flat load profile (8760 hours)
    # Real application would use actual load data
    annual_load = fill(load_kw, 8760)
    
    Dict(
        :Site => Dict(
            :latitude => geom.lat,
            :longitude => geom.lon,
            :land_acres => 10.0,  # Available land for PV
        ),
        :ElectricLoad => Dict(
            :loads_kw => annual_load,
        ),
        :ElectricUtility => Dict(
            :net_metering_limit_kw => 1000.0,
        ),
        :ElectricTariff => Dict(
            :urdb_label => "5ed6c1a55457a3367add15ae",  # Commercial rate
        ),
        :PV => Dict(
            :min_kw => 0.0,
            :max_kw => load_kw * 0.5,  # Up to 50% of peak load
        ),
        :ElectricStorage => Dict(
            :min_kw => 0.0,
            :max_kw => load_kw * 0.25,  # Up to 25% of peak load
            :min_kwh => 0.0,
            :max_kwh => load_kw * 1.0,  # Up to 4 hours at 25% power
        ),
    )
end

"""
Run REopt for a single service point.
Returns proposed PV and storage sizes.
"""
function run_reopt_for_site(g, sp_id::Int; verbose=false)
    inputs = build_reopt_inputs(g, sp_id)
    
    sp_name = g[sp_id, :sp_id]
    load_kw = g[sp_id, :sp_load_kw]
    
    verbose && println("  Running REopt for $sp_name ($(load_kw) kW load)...")
    
    try
        # Build and solve REopt model
        s = Scenario(inputs)
        inputs_obj = REoptInputs(s)
        
        m = Model(HiGHS.Optimizer)
        set_silent(m)
        
        results = run_reopt(m, inputs_obj)
        
        pv_kw = get(results, "PV", Dict())
        storage = get(results, "ElectricStorage", Dict())
        
        pv_size = get(pv_kw, "size_kw", 0.0)
        storage_kw = get(storage, "size_kw", 0.0)
        storage_kwh = get(storage, "size_kwh", 0.0)
        
        return (
            sp_id = sp_id,
            sp_name = sp_name,
            load_kw = load_kw,
            pv_kw = pv_size,
            storage_kw = storage_kw,
            storage_kwh = storage_kwh,
            success = true
        )
    catch e
        verbose && println("    ⚠ REopt failed: $(typeof(e))")
        # Return zeros on failure
        return (
            sp_id = sp_id,
            sp_name = sp_name,
            load_kw = load_kw,
            pv_kw = 0.0,
            storage_kw = 0.0,
            storage_kwh = 0.0,
            success = false
        )
    end
end

"""
Run simplified DER sizing (when REopt API isn't available).
Uses rule-of-thumb sizing for demonstration.
"""
function simplified_der_sizing(g, sp_id::Int)
    sp_name = g[sp_id, :sp_id]
    load_kw = g[sp_id, :sp_load_kw]
    
    # Simple sizing rules:
    # - PV: 30% of annual load (typical for commercial with good solar)
    # - Storage: 2-hour duration at 15% of peak
    pv_kw = load_kw * 0.30
    storage_kw = load_kw * 0.15
    storage_kwh = storage_kw * 2.0
    
    return (
        sp_id = sp_id,
        sp_name = sp_name,
        load_kw = load_kw,
        pv_kw = pv_kw,
        storage_kw = storage_kw,
        storage_kwh = storage_kwh,
        success = true
    )
end

# =============================================================================
# 6. Portfolio Analysis: Run DER Sizing for All Critical Facilities
# =============================================================================

function run_portfolio_analysis(g; use_reopt=false, verbose=true)
    verbose && println("\n" * "=" ^ 60)
    verbose && println("PORTFOLIO DER ANALYSIS")
    verbose && println("=" ^ 60)
    
    # Find all critical facilities
    critical_sps = filter(parts(g, :ServicePoint)) do sp
        g[sp, :sp_critical] == "yes"
    end
    
    verbose && println("\nFound $(length(critical_sps)) critical facilities")
    
    # Run DER sizing for each
    results = []
    for sp in critical_sps
        if use_reopt
            result = run_reopt_for_site(g, sp; verbose=verbose)
        else
            result = simplified_der_sizing(g, sp)
        end
        push!(results, result)
        
        if verbose && result.success
            println("  $(result.sp_name): $(round(result.pv_kw, digits=1)) kW PV, " *
                   "$(round(result.storage_kw, digits=1)) kW / $(round(result.storage_kwh, digits=1)) kWh storage")
        end
    end
    
    return results
end

# =============================================================================
# 7. Aggregate Results by Feeder & Check Hosting Capacity
# =============================================================================

function check_hosting_capacity(g, results; verbose=true)
    verbose && println("\n" * "=" ^ 60)
    verbose && println("HOSTING CAPACITY ANALYSIS")
    verbose && println("=" ^ 60)
    
    # Group results by feeder
    feeder_der = Dict{Int, Float64}()
    for r in results
        if r.success
            feeder = feeder_of_service(g, r.sp_id)
            total_der = r.pv_kw + r.storage_kw
            feeder_der[feeder] = get(feeder_der, feeder, 0.0) + total_der
        end
    end
    
    # Check each feeder
    violations = []
    
    verbose && println("\nFeeder Analysis:")
    for feeder in parts(g, :Feeder)
        fid = g[feeder, :feeder_id]
        hc = hosting_capacity(g, feeder)
        proposed = get(feeder_der, feeder, 0.0)
        existing = sum(g[d, :der_capacity_kw] for d in ders_on_feeder(g, feeder); init=0.0)
        
        status = proposed <= hc ? "✓" : "⚠ UPGRADE NEEDED"
        
        if verbose
            println("\n  $fid:")
            println("    Hosting capacity:  $(round(hc, digits=0)) kW")
            println("    Existing DER:      $(round(existing, digits=0)) kW")
            println("    Proposed new DER:  $(round(proposed, digits=0)) kW")
            println("    Status:            $status")
        end
        
        if proposed > hc
            push!(violations, (
                feeder_id = fid,
                feeder = feeder,
                hosting_capacity = hc,
                proposed_der = proposed,
                shortfall = proposed - hc
            ))
        end
    end
    
    return violations
end

# =============================================================================
# 8. Generate Upgrade Recommendations
# =============================================================================

function generate_recommendations(g, violations; verbose=true)
    verbose && println("\n" * "=" ^ 60)
    verbose && println("UPGRADE RECOMMENDATIONS")
    verbose && println("=" ^ 60)
    
    if isempty(violations)
        verbose && println("\n✓ No feeder upgrades required!")
        verbose && println("  All proposed DER fits within existing hosting capacity.")
        return []
    end
    
    recommendations = []
    total_upgrade_cost = 0.0
    
    for v in violations
        # Estimate upgrade cost ($500/kW is typical for distribution upgrades)
        upgrade_kw = ceil(v.shortfall / 100) * 100  # Round up to nearest 100 kW
        cost_per_kw = 500.0
        upgrade_cost = upgrade_kw * cost_per_kw
        total_upgrade_cost += upgrade_cost
        
        rec = (
            feeder_id = v.feeder_id,
            shortfall_kw = v.shortfall,
            recommended_upgrade_kw = upgrade_kw,
            estimated_cost = upgrade_cost
        )
        push!(recommendations, rec)
        
        if verbose
            println("\n  $(v.feeder_id):")
            println("    Shortfall:           $(round(v.shortfall, digits=0)) kW")
            println("    Recommended upgrade: $(round(upgrade_kw, digits=0)) kW")
            println("    Estimated cost:      \$$(round(Int, upgrade_cost))")
        end
    end
    
    if verbose
        println("\n  TOTAL UPGRADE COST: \$$(round(Int, total_upgrade_cost))")
    end
    
    return recommendations
end

# =============================================================================
# 9. Add Proposed DERs to Grid Model
# =============================================================================

function add_proposed_ders!(g, results)
    for r in results
        if r.success && (r.pv_kw > 0 || r.storage_kw > 0)
            # Add PV
            if r.pv_kw > 0
                add_part!(g, :DER,
                    der_id = "PROP-PV-$(r.sp_name)",
                    der_type = "PV",
                    der_capacity_kw = r.pv_kw,
                    der_cost_usd = r.pv_kw * 1500.0,  # ~$1500/kW installed
                    der_status = "proposed",
                    der_at = r.sp_id
                )
            end
            
            # Add storage
            if r.storage_kw > 0
                add_part!(g, :DER,
                    der_id = "PROP-BESS-$(r.sp_name)",
                    der_type = "storage",
                    der_capacity_kw = r.storage_kw,
                    der_cost_usd = r.storage_kwh * 400.0,  # ~$400/kWh
                    der_status = "proposed",
                    der_at = r.sp_id
                )
            end
        end
    end
end

# =============================================================================
# 10. Main: Run Full Analysis
# =============================================================================

println("=" ^ 70)
println("GeoACSets + REopt.jl: Distribution Grid DER Planning")
println("=" ^ 70)

# Build the grid
println("\n📍 Building distribution grid model...")
grid, zone, feeders, sp_map = build_sample_grid()

println("\n📊 Grid Statistics:")
println("  Zone:           $(grid[1, :zone_name])")
println("  Substations:    $(nparts(grid, :Substation))")
println("  Feeders:        $(nparts(grid, :Feeder))")
println("  Transformers:   $(nparts(grid, :Transformer))")
println("  Service Points: $(nparts(grid, :ServicePoint))")
println("  Existing DERs:  $(nparts(grid, :DER))")

# Run portfolio analysis (simplified mode - no API calls needed)
results = run_portfolio_analysis(grid; use_reopt=false, verbose=true)

# Check hosting capacity
violations = check_hosting_capacity(grid, results; verbose=true)

# Generate recommendations
recommendations = generate_recommendations(grid, violations; verbose=true)

# Add proposed DERs to grid model
add_proposed_ders!(grid, results)

println("\n" * "=" ^ 70)
println("FINAL GRID STATE")
println("=" ^ 70)

println("\n📊 Updated Statistics:")
println("  Service Points: $(nparts(grid, :ServicePoint))")
println("  Total DERs:     $(nparts(grid, :DER))")

# Summary by DER type
for der_type in ["PV", "storage"]
    ders = filter(d -> grid[d, :der_type] == der_type, parts(grid, :DER))
    proposed = filter(d -> grid[d, :der_status] == "proposed", ders)
    total_kw = sum(grid[d, :der_capacity_kw] for d in ders; init=0.0)
    total_cost = sum(grid[d, :der_cost_usd] for d in ders; init=0.0)
    
    println("\n  $(uppercase(der_type)):")
    println("    Count:      $(length(ders)) ($(length(proposed)) proposed)")
    println("    Capacity:   $(round(total_kw, digits=1)) kW")
    println("    Est. cost:  \$$(round(Int, total_cost))")
end

println("\n" * "=" ^ 70)
println("KEY INSIGHT: GeoACSets morphisms enabled O(1) feeder lookups")
println("for aggregating DER capacity across the spatial hierarchy.")
println("=" ^ 70)

# Grid Integration Use Case

GeoACSets provides a powerful foundation for spatial energy system modeling by combining categorical data structures with geospatial capabilities.

## The Problem

Utility planners face questions that require both **structural** and **spatial** reasoning:

1. "Where should we place new solar + storage to minimize grid congestion?"
2. "Which feeders serve the most critical facilities?"
3. "How does DER placement affect hosting capacity across planning zones?"
4. "What's the upgrade cost for each substation's service territory?"

Traditional approaches use either:
- **GIS databases**: Good at spatial queries, bad at hierarchical traversal
- **Network models**: Good at topology, no spatial awareness

GeoACSets bridges this gap.

## The Grid as a Spatial Hierarchy

The distribution grid has a natural hierarchical structure:

```
TransmissionZone (planning area)
    └── Substation (bulk power delivery)
          └── Feeder (distribution circuit, 4-34.5 kV)
                └── Transformer (step-down)
                      └── ServicePoint (meter)
                            └── DER (solar, storage, EV, etc.)
```

Each level has:
- **Geometry**: service territory polygon or point location
- **Attributes**: capacity, loading, voltage, etc.
- **Morphism to parent**: structural containment relationship

## GeoACSets Schema

```julia
const SchDistributionGrid = BasicSchema(
    [:TransmissionZone, :Substation, :Feeder, :Transformer, :ServicePoint, :DER],
    [
        (:substation_in, :Substation, :TransmissionZone),
        (:feeder_at, :Feeder, :Substation),
        (:transformer_on, :Transformer, :Feeder),
        (:service_at, :ServicePoint, :Transformer),
        (:der_at, :DER, :ServicePoint)
    ],
    # ... attributes
)
```

## Why This Matters

### Query: "Total DER on feeders served by Substation X"

**Without GeoACSets** (spatial join):
```sql
SELECT SUM(der.capacity_kw)
FROM der
JOIN service_point ON ST_Contains(service_point.geom, der.geom)
JOIN transformer ON ST_Contains(transformer.service_area, service_point.geom)
JOIN feeder ON ST_Intersects(feeder.corridor, transformer.geom)
JOIN substation ON ST_Contains(substation.service_area, feeder.origin)
WHERE substation.id = 'X'
```
**Complexity**: O(n log n) per join, requires spatial indexes, error-prone

**With GeoACSets** (morphism traversal):
```julia
ders = ders_at_substation(grid, sub_x)
total = sum(grid[d, :der_capacity_kw] for d in ders)
```
**Complexity**: O(feeders + transformers + services + ders) — linear in result size

### Query: "Cascade outage from substation to all affected loads"

```julia
# Instant: follow morphisms down
affected_services = services_at_substation(grid, failed_sub)
affected_ders = ders_at_substation(grid, failed_sub)

# For each, get hierarchical context
for sp in affected_services
    xfmr = grid[sp, :service_at]
    feeder = grid[xfmr, :transformer_on]
    # ... handle outage propagation
end
```

### Query: "Find all loads within 500m of fault location"

```julia
# Spatial filter for proximity
nearby = services_near_fault(grid, fault_lat, fault_lon, 0.5)

# Then use morphisms for context
for sp in nearby
    feeder = grid[grid[sp, :service_at], :transformer_on]
    println("Affected: $(grid[sp, :sp_id]) on feeder $(grid[feeder, :feeder_id])")
end
```

## Integration with Energy Optimization Tools

### TulipaEnergyModel.jl

[TulipaEnergyModel.jl](https://github.com/TulipaEnergy/TulipaEnergyModel.jl) optimizes investment and dispatch across energy systems. GeoACSets provides the spatial layer:

1. **Export topology**: Each Feeder becomes a Tulipa "hub"
2. **Set constraints**: Hosting capacity from GeoACSets → hub import limits
3. **Attach assets**: DERs become Tulipa producers/storage connected to hubs
4. **Optimize**: Tulipa finds cost-optimal investment plan
5. **Validate**: Check results against feeder/transformer limits

```julia
function export_to_tulipa(g::DistributionGrid)
    hubs = []
    for feeder in parts(g, :Feeder)
        push!(hubs, (
            id = g[feeder, :feeder_id],
            max_import_mw = g[feeder, :feeder_capacity_mw],
            # location for transmission cost calculation
        ))
    end
    # ... export DERs as assets connected to hubs
end
```

### REopt.jl

[REopt.jl](https://github.com/NREL/REopt.jl) optimizes DER sizing for individual sites. GeoACSets enables portfolio analysis:

1. **Identify targets**: Critical facilities in a planning zone
2. **Run optimization**: REopt for each site
3. **Aggregate**: Sum proposed DER by feeder
4. **Check constraints**: Compare against hosting capacity
5. **Iterate**: Add upgrade costs or constrain if violated

```julia
function run_portfolio_reopt(g::DistributionGrid, zone)
    # Find critical facilities
    critical = filter(sp -> g[sp, :sp_critical] == "yes", 
                      services_in_zone(g, zone))
    
    results = Dict()
    for sp in critical
        results[sp] = run_reopt(site_scenario(g, sp))
    end
    
    # Check feeder constraints
    for feeder in feeders_in_zone(g, zone)
        proposed = sum_proposed_der(results, services_on_feeder(g, feeder))
        if proposed > hosting_capacity(g, feeder)
            @warn "Feeder $(g[feeder, :feeder_id]) needs upgrade"
        end
    end
end
```

### PowerModels.jl

[PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl) provides power flow and optimal power flow. GeoACSets can:

1. **Build network**: Export transformer/feeder topology to PowerModels format
2. **Set injections**: DER generation and load from GeoACSets attributes
3. **Run power flow**: Validate voltage/thermal limits
4. **Update state**: Write results back to GeoACSets

## Key Advantages

| Capability | Traditional GIS | GeoACSets |
|------------|----------------|-----------|
| "Which substation serves this meter?" | Spatial join O(log n) | Morphism O(1) |
| "All DERs in planning zone" | Multi-table spatial join | Traversal O(k) |
| "Cascade outage effects" | Complex recursive query | Follow morphisms |
| Referential integrity | Manual enforcement | Automatic (cascading delete) |
| Schema enforcement | Application-level | Type-level |

## Example Output

```
📊 Grid Statistics:
  Transmission Zones: 1
  Substations:        2
  Feeders:            3
  Transformers:       3
  Service Points:     15
  DERs:               5

🔌 Substation Analysis:

  Downtown Sub:
    Load: 1.4 MW / 50.0 MVA capacity (2.8%)
    DERs: 35.0 kW PV, 25.0 kW storage
    Critical facilities: 2

⚡ Feeder Hosting Capacity:
  FDR-001: 3440 kW available (60 kW installed)
  FDR-002: 800 kW available (0 kW installed)
  FDR-003: 4000 kW available (0 kW installed)
```

## Getting Started

See `examples/spatial_grid_model.jl` for a complete working example.

```julia
using GeoACSets

# Load or build your grid model
grid = build_distribution_grid(...)

# Query hierarchically
feeders = feeders_at_substation(grid, sub_id)
services = services_on_feeder(grid, feeder_id)

# Aggregate for optimization
total_load = total_load_at_substation(grid, sub_id)
hc = hosting_capacity(grid, feeder_id)

# Combine with spatial queries
nearby = services_near_fault(grid, lat, lon, radius_km)
```

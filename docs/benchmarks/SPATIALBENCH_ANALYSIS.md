# SpatialBench Analysis for GeoACSets

## What is SpatialBench?

SpatialBench is a benchmark for assessing geospatial SQL analytics query performance across database systems. It provides a reproducible and scalable way to evaluate the performance of spatial data engines using realistic synthetic workloads.

Inspired by the Star Schema Benchmark (SSB) and NYC taxi data, SpatialBench combines realistic urban mobility scenarios with a star schema extended with spatial attributes like pickup/dropoff points, zones, and building footprints.

See: https://github.com/apache/sedona-spatialbench

## SpatialBench Schema

SpatialBench defines a spatial star schema with the following tables:
- **Trip** (Fact Table): Individual trip records with pickup & dropoff points (6M × SF)
- **Customer** (Dimension): Trip customer info, no spatial attributes (30K × SF)
- **Driver** (Dimension): Trip driver info, no spatial attributes (500 × SF)
- **Vehicle** (Dimension): Trip vehicle info, no spatial attributes (100 × SF)
- **Zone** (Dimension): Administrative zones with Polygon geometry (tiered by SF)
- **Building** (Dimension): Building footprints with Polygon geometry (20K × (1 + log₂(SF)))

## SpatialBench Query Categories

The benchmark includes 12 SQL queries testing:
1. **Spatial filters** (point-in-polygon, bounding box)
2. **Spatial joins** (ST_Contains, ST_Intersects)
3. **Distance queries** (ST_DWithin, KNN)
4. **Geometric operations** (area, intersection, IoU)
5. **Spatial aggregations** (GROUP BY with spatial predicates)

### Example Query (Distance Join + Aggregation)
```sql
SELECT b.b_buildingkey, b.b_name, COUNT(*) AS nearby_pickup_count
FROM trip t
JOIN building b ON ST_DWithin(t.t_pickup_loc, b.b_boundary, 500)
GROUP BY b.b_buildingkey, b.b_name
ORDER BY nearby_pickup_count DESC;
```

## GeoACSets vs SpatialBench: Different Design Goals

| Aspect | SpatialBench / SedonaDB | GeoACSets |
|--------|------------------------|-----------|
| **Primary goal** | Fast spatial SQL analytics | Schema-aware structural navigation |
| **Join strategy** | Spatial predicates (R-tree) | Morphisms (indexed foreign keys) |
| **Hierarchy** | Flat star schema | Deeply nested containment |
| **Query pattern** | Ad-hoc spatial joins | Pre-defined relationships |
| **Complexity** | O(n log n) spatial join | O(k) morphism traversal |
| **Use case** | Analytics, reporting | Transactional, graph-like |

## Which SpatialBench Queries Are Relevant?

### ✅ RELEVANT: Queries GeoACSets Can Excel At

**Q3-Q4: Point-in-Polygon Containment**
- SpatialBench: `WHERE ST_Contains(zone.boundary, trip.pickup_loc)`
- GeoACSets: If containment is pre-computed as morphisms, this is O(1)
- **Advantage**: GeoACSets wins when relationships are known at insert time

**Q10-Q11: Hierarchical Spatial Joins**
- SpatialBench: Multi-table spatial joins (trip → zone → building)
- GeoACSets: Morphism chain traversal
- **Advantage**: GeoACSets wins when hierarchy is explicit

**Q12: KNN with Aggregation**
- SpatialBench: Find K nearest buildings, aggregate
- GeoACSets: If buildings are linked to zones via morphisms, aggregation is trivial

### ⚠️ PARTIALLY RELEVANT: Mixed Results Expected

**Q5: Spatial Aggregation**
- SpatialBench: `GROUP BY zone_id` with spatial filter
- GeoACSets: Needs geometry for filter, morphisms for grouping
- **Note**: GeoACSets adds value for the grouping step, not filtering

**Q9: Intersection / IoU**
- SpatialBench: `ST_Intersection(a.geom, b.geom)`, `ST_Area(...)`
- GeoACSets: Still needs geometry library (LibGEOS)
- **Note**: GeoACSets doesn't optimize raw geometry operations

### ❌ NOT RELEVANT: GeoACSets Won't Help

**Q1-Q2: Simple Spatial Filters**
- SpatialBench: `WHERE ST_Within(point, bbox)`
- GeoACSets: Same as any spatial DB; no morphism advantage
- **Note**: These test raw spatial index performance

**Q6-Q8: Distance Joins without Hierarchy**
- SpatialBench: `ST_DWithin(a.point, b.point, radius)`
- GeoACSets: No pre-defined relationship; needs spatial join
- **Note**: These are pure geometry operations

## Proposed GeoACSets Benchmark Queries

To fairly compare GeoACSets, we need queries that exploit its morphism structure:

### GB1: Hierarchical Aggregation (GeoACSets Sweet Spot)
```
"Total trips in each zone, grouped by zone's parent region"

SpatialBench approach:
  - Spatial join trip → zone
  - Another spatial join zone → region
  - GROUP BY region

GeoACSets approach:
  - Pre-defined: trip.zone_in morphism
  - Pre-defined: zone.region_in morphism
  - Traverse morphisms, aggregate
```

### GB2: Cascading Containment
```
"All trips affected by closing a region"

SpatialBench approach:
  - Recursive spatial joins
  
GeoACSets approach:
  - Follow incident() down the hierarchy
  - O(affected trips), not O(all trips)
```

### GB3: Upward Context Lookup
```
"For each trip, find the region name"

SpatialBench approach:
  - Spatial join trip → zone → region (2 joins)

GeoACSets approach:
  - trip[t, :zone_in] → zone[z, :region_in]
  - O(1) per trip
```

### GB4: Mixed Spatial + Structural
```
"Buildings within 500m of trips that started in zone X"

SpatialBench approach:
  - Filter trips by spatial join with zone
  - Distance join to buildings

GeoACSets approach:
  - Filter trips by morphism (zone_in == X)
  - Distance join to buildings (still spatial)
  
Advantage: First filter is O(1) per trip instead of O(log n)
```

## Implementation Plan

### Phase 1: Schema Mapping
Create GeoACSets schema that mirrors SpatialBench:

```julia
const SchSpatialBench = BasicSchema(
    [:Trip, :Customer, :Driver, :Vehicle, :Zone, :Building, :Region],
    [
        # Morphisms encode containment
        (:pickup_zone, :Trip, :Zone),    # trip's pickup zone
        (:dropoff_zone, :Trip, :Zone),   # trip's dropoff zone
        (:zone_region, :Zone, :Region),  # zone's parent region
        (:building_zone, :Building, :Zone),  # building's zone
        (:customer_of, :Trip, :Customer),
        (:driver_of, :Trip, :Driver),
        (:vehicle_of, :Trip, :Vehicle),
    ],
    # ... attributes including geometries
)
```

### Phase 2: Data Loading
- Load SpatialBench Parquet files
- Compute morphisms via spatial join (one-time cost)
- Store as GeoACSet

### Phase 3: Query Comparison
For queries Q3, Q4, Q10, Q11, Q12:
1. Run SpatialBench SQL on SedonaDB
2. Run equivalent GeoACSets morphism traversal
3. Compare latency

### Phase 4: Report Results
- Where GeoACSets wins: hierarchical queries
- Where SedonaDB wins: ad-hoc spatial joins
- Breakeven point: when to use which

## Expected Results

| Query Type | SedonaDB | GeoACSets | Winner |
|------------|----------|-----------|--------|
| Simple spatial filter | Fast | Same | Tie |
| Ad-hoc distance join | Fast | Slow (no index) | SedonaDB |
| Pre-defined containment | O(n log n) | O(k) | GeoACSets |
| Hierarchical aggregation | Multi-join | Traversal | GeoACSets |
| Cascading operations | Complex | Simple | GeoACSets |
| Schema enforcement | None | Automatic | GeoACSets |

## Conclusion

SpatialBench is designed for **analytical workloads** with ad-hoc spatial queries. GeoACSets excels at **transactional/operational workloads** where relationships are known in advance.

**Use SpatialBench to test:**
- Raw spatial predicate performance
- Ad-hoc query flexibility
- Scale-out characteristics

**Use GeoACSets for:**
- Hierarchical navigation (grid topology, administrative boundaries)
- Referential integrity (cascading deletes)
- Known relationship patterns (zone containment, feeder service territories)

The two systems are complementary:
- **SpatialBench/SedonaDB**: Data lake analytics
- **GeoACSets**: Operational systems with structured spatial hierarchies

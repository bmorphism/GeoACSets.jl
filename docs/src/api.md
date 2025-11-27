# API Reference

## Schemas

```@docs
SchSpatialCity
SpatialCity
SchSpatialGraph
SpatialGraph
SchParcelAdjacency
ParcelAdjacency
```

## Spatial Predicates

```@docs
spatial_filter
spatial_join
```

## Traversal Functions

### SpatialCity Traversals

```@docs
buildings_in_region
buildings_in_district
parcels_in_region
parcels_in_district
region_of_building
district_of_building
region_of_parcel
district_of_parcel
```

### Generic Traversals

```@docs
traverse_up
traverse_down
```

### SpatialGraph Traversals

```@docs
neighbors
edges_between
```

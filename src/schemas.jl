# Common spatial schemas for GeoACSets
#
# Design principle: Morphisms encode containment/adjacency relationships.
# Geometry attributes are for visualization and spatial predicates.

"""
    SchSpatialCity

A 4-level spatial hierarchy: Region → District → Parcel → Building

Objects:
- Region: largest administrative unit
- District: subdivision of a region  
- Parcel: land parcel within a district
- Building: structure on a parcel

Morphisms (containment):
- district_of: District → Region
- parcel_of: Parcel → District
- building_on: Building → Parcel

Attributes:
- region_geom, district_geom, parcel_geom: boundary geometries
- footprint: building footprint geometry
- region_name, district_name: string identifiers
- floor_area: building floor area (numeric)
"""
const SchSpatialCity = BasicSchema(
    [:Region, :District, :Parcel, :Building],
    [
        (:district_of, :District, :Region),
        (:parcel_of, :Parcel, :District),
        (:building_on, :Building, :Parcel)
    ],
    [:Geom, :Name, :Area],
    [
        (:region_geom, :Region, :Geom),
        (:district_geom, :District, :Geom),
        (:parcel_geom, :Parcel, :Geom),
        (:footprint, :Building, :Geom),
        (:region_name, :Region, :Name),
        (:district_name, :District, :Name),
        (:floor_area, :Building, :Area)
    ]
)

"""
    SpatialCity{Geom, Name, Area}

ACSet type for the SpatialCity schema.

Type parameters:
- `Geom`: geometry type (e.g., LibGEOS.Polygon, GeoInterface.Polygon)
- `Name`: name type (typically String or Symbol)
- `Area`: numeric type for floor area (typically Float64)

Indexed morphisms for fast `incident` queries:
- district_of, parcel_of, building_on
"""
@acset_type SpatialCity(SchSpatialCity, index=[:district_of, :parcel_of, :building_on])


"""
    SchSpatialGraph

A graph with spatial vertices.

Objects:
- V: vertices with location
- E: edges connecting vertices

Morphisms:
- src: E → V (source vertex)
- tgt: E → V (target vertex)

Attributes:
- location: vertex geometry (point)
- edge_geom: edge geometry (linestring, optional)
- weight: edge weight (numeric)
"""
const SchSpatialGraph = BasicSchema(
    [:V, :E],
    [(:src, :E, :V), (:tgt, :E, :V)],
    [:Geom, :Weight],
    [
        (:location, :V, :Geom),
        (:edge_geom, :E, :Geom),
        (:weight, :E, :Weight)
    ]
)

@acset_type SpatialGraph(SchSpatialGraph, index=[:src, :tgt])


"""
    SchParcelAdjacency

Parcels with explicit adjacency relationships.

Objects:
- Parcel: land parcels
- Adjacency: adjacency relationships between parcels

Morphisms:
- left: Adjacency → Parcel
- right: Adjacency → Parcel

Attributes:
- boundary: parcel boundary geometry
- shared_length: length of shared boundary (numeric)
"""
const SchParcelAdjacency = BasicSchema(
    [:Parcel, :Adjacency],
    [(:left, :Adjacency, :Parcel), (:right, :Adjacency, :Parcel)],
    [:Geom, :Length],
    [
        (:boundary, :Parcel, :Geom),
        (:shared_length, :Adjacency, :Length)
    ]
)

@acset_type ParcelAdjacency(SchParcelAdjacency, index=[:left, :right])

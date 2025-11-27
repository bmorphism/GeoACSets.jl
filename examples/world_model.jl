# =============================================================================
# GeoACSets World Model
# =============================================================================
#
# A multi-scale spatial model using real geographic data:
#   Continent → Country → Region/State → City → (optional: District → Building)
#
# Data sources:
#   - Natural Earth (public domain): countries, regions, cities
#   - OpenStreetMap (ODbL): detailed features
#
# Run with:
#   julia --project=~/.topos/geo_acsets examples/world_model.jl

using GeoACSets
using ACSets.Schemas: BasicSchema

# =============================================================================
# Schema: Multi-Scale World Model
# =============================================================================

# Continent → Country → Region → City → Feature
const SchWorld = BasicSchema(
    # Objects
    [:Continent, :Country, :Region, :City, :Feature],
    # Morphisms (hom_name, dom, codom)
    [
        (:country_in, :Country, :Continent),
        (:region_in, :Region, :Country),
        (:city_in, :City, :Region),
        (:feature_in, :Feature, :City)
    ],
    # Attribute types
    [:Name, :Code, :Population, :Area, :Lat, :Lon, :Category],
    # Attributes (attr_name, ob, attrtype)
    [
        (:continent_name, :Continent, :Name),
        (:country_name, :Country, :Name),
        (:country_code, :Country, :Code),
        (:country_pop, :Country, :Population),
        (:country_area, :Country, :Area),
        (:region_name, :Region, :Name),
        (:region_code, :Region, :Code),
        (:region_pop, :Region, :Population),
        (:city_name, :City, :Name),
        (:city_pop, :City, :Population),
        (:city_lat, :City, :Lat),
        (:city_lon, :City, :Lon),
        (:feature_name, :Feature, :Name),
        (:feature_cat, :Feature, :Category),
        (:feature_lat, :Feature, :Lat),
        (:feature_lon, :Feature, :Lon)
    ]
)

@acset_type World(SchWorld, index=[:country_in, :region_in, :city_in, :feature_in])

# =============================================================================
# Helper: Haversine distance (km)
# =============================================================================

function haversine(lat1, lon1, lat2, lon2)
    R = 6371.0  # Earth radius in km
    φ1, φ2 = deg2rad(lat1), deg2rad(lat2)
    Δφ = deg2rad(lat2 - lat1)
    Δλ = deg2rad(lon2 - lon1)
    a = sin(Δφ/2)^2 + cos(φ1) * cos(φ2) * sin(Δλ/2)^2
    2R * asin(sqrt(a))
end

# =============================================================================
# Data: Embedded Geographic Data (no network required)
# =============================================================================

# Continent definitions
const CONTINENTS = [
    "Africa", "Antarctica", "Asia", "Europe", 
    "North America", "Oceania", "South America"
]

# Country data: (name, code, continent, population, area_km2)
const COUNTRIES = [
    # Europe
    ("France", "FR", "Europe", 67_390_000, 643_801),
    ("Germany", "DE", "Europe", 83_240_000, 357_386),
    ("United Kingdom", "GB", "Europe", 67_886_000, 242_495),
    ("Italy", "IT", "Europe", 60_461_000, 301_340),
    ("Spain", "ES", "Europe", 46_754_000, 505_990),
    ("Netherlands", "NL", "Europe", 17_134_000, 41_543),
    ("Poland", "PL", "Europe", 37_846_000, 312_696),
    ("Sweden", "SE", "Europe", 10_099_000, 450_295),
    ("Norway", "NO", "Europe", 5_421_000, 385_207),
    ("Switzerland", "CH", "Europe", 8_654_000, 41_291),
    
    # Asia
    ("China", "CN", "Asia", 1_411_778_000, 9_596_960),
    ("India", "IN", "Asia", 1_380_004_000, 3_287_263),
    ("Japan", "JP", "Asia", 126_476_000, 377_975),
    ("South Korea", "KR", "Asia", 51_269_000, 100_210),
    ("Indonesia", "ID", "Asia", 273_524_000, 1_904_569),
    ("Thailand", "TH", "Asia", 69_800_000, 513_120),
    ("Vietnam", "VN", "Asia", 97_339_000, 331_212),
    ("Singapore", "SG", "Asia", 5_850_000, 728),
    
    # North America
    ("United States", "US", "North America", 331_002_000, 9_833_520),
    ("Canada", "CA", "North America", 37_742_000, 9_984_670),
    ("Mexico", "MX", "North America", 128_933_000, 1_964_375),
    
    # South America
    ("Brazil", "BR", "South America", 212_559_000, 8_515_767),
    ("Argentina", "AR", "South America", 45_196_000, 2_780_400),
    ("Chile", "CL", "South America", 19_116_000, 756_102),
    ("Colombia", "CO", "South America", 50_882_000, 1_141_748),
    
    # Africa
    ("Nigeria", "NG", "Africa", 206_140_000, 923_768),
    ("Egypt", "EG", "Africa", 102_334_000, 1_002_450),
    ("South Africa", "ZA", "Africa", 59_309_000, 1_221_037),
    ("Kenya", "KE", "Africa", 53_771_000, 580_367),
    ("Morocco", "MA", "Africa", 36_911_000, 446_550),
    
    # Oceania
    ("Australia", "AU", "Oceania", 25_499_000, 7_692_024),
    ("New Zealand", "NZ", "Oceania", 4_822_000, 270_467),
]

# Region data: (name, code, country_code, population)
const REGIONS = [
    # United States
    ("California", "CA", "US", 39_538_000),
    ("Texas", "TX", "US", 29_145_000),
    ("Florida", "FL", "US", 21_538_000),
    ("New York", "NY", "US", 20_201_000),
    ("Illinois", "IL", "US", 12_812_000),
    ("Pennsylvania", "PA", "US", 13_003_000),
    ("Massachusetts", "MA", "US", 7_029_000),
    ("Washington", "WA", "US", 7_615_000),
    ("Colorado", "CO", "US", 5_774_000),
    
    # Germany
    ("Bavaria", "BY", "DE", 13_140_000),
    ("North Rhine-Westphalia", "NW", "DE", 17_932_000),
    ("Baden-Württemberg", "BW", "DE", 11_103_000),
    ("Berlin", "BE", "DE", 3_645_000),
    ("Hamburg", "HH", "DE", 1_852_000),
    
    # France
    ("Île-de-France", "IDF", "FR", 12_278_000),
    ("Auvergne-Rhône-Alpes", "ARA", "FR", 8_043_000),
    ("Provence-Alpes-Côte d'Azur", "PAC", "FR", 5_055_000),
    
    # UK
    ("England", "ENG", "GB", 56_287_000),
    ("Scotland", "SCT", "GB", 5_454_000),
    ("Wales", "WLS", "GB", 3_136_000),
    
    # Japan
    ("Kanto", "KT", "JP", 43_000_000),
    ("Kansai", "KS", "JP", 22_000_000),
    ("Chubu", "CB", "JP", 21_000_000),
    
    # China
    ("Guangdong", "GD", "CN", 126_010_000),
    ("Shandong", "SD", "CN", 101_530_000),
    ("Henan", "HA", "CN", 99_370_000),
    ("Sichuan", "SC", "CN", 83_670_000),
    ("Jiangsu", "JS", "CN", 84_750_000),
    
    # Brazil
    ("São Paulo", "SP", "BR", 46_289_000),
    ("Minas Gerais", "MG", "BR", 21_293_000),
    ("Rio de Janeiro", "RJ", "BR", 17_366_000),
    
    # Australia
    ("New South Wales", "NSW", "AU", 8_166_000),
    ("Victoria", "VIC", "AU", 6_681_000),
    ("Queensland", "QLD", "AU", 5_185_000),
]

# City data: (name, region_code, country_code, population, lat, lon)
const CITIES = [
    # US - California
    ("Los Angeles", "CA", "US", 3_979_576, 34.0522, -118.2437),
    ("San Francisco", "CA", "US", 873_965, 37.7749, -122.4194),
    ("San Diego", "CA", "US", 1_423_851, 32.7157, -117.1611),
    ("San Jose", "CA", "US", 1_021_795, 37.3382, -121.8863),
    
    # US - Texas
    ("Houston", "TX", "US", 2_320_268, 29.7604, -95.3698),
    ("Dallas", "TX", "US", 1_343_573, 32.7767, -96.7970),
    ("Austin", "TX", "US", 978_908, 30.2672, -97.7431),
    ("San Antonio", "TX", "US", 1_547_253, 29.4241, -98.4936),
    
    # US - New York
    ("New York City", "NY", "US", 8_336_817, 40.7128, -74.0060),
    ("Buffalo", "NY", "US", 278_349, 42.8864, -78.8784),
    
    # US - Florida
    ("Miami", "FL", "US", 467_963, 25.7617, -80.1918),
    ("Orlando", "FL", "US", 307_573, 28.5383, -81.3792),
    ("Tampa", "FL", "US", 399_700, 27.9506, -82.4572),
    
    # US - Massachusetts
    ("Boston", "MA", "US", 692_600, 42.3601, -71.0589),
    ("Cambridge", "MA", "US", 118_403, 42.3736, -71.1097),
    
    # US - Washington
    ("Seattle", "WA", "US", 753_675, 47.6062, -122.3321),
    
    # US - Illinois
    ("Chicago", "IL", "US", 2_746_388, 41.8781, -87.6298),
    
    # US - Colorado
    ("Denver", "CO", "US", 727_211, 39.7392, -104.9903),
    
    # Germany
    ("Munich", "BY", "DE", 1_484_226, 48.1351, 11.5820),
    ("Berlin", "BE", "DE", 3_644_826, 52.5200, 13.4050),
    ("Hamburg", "HH", "DE", 1_841_179, 53.5511, 9.9937),
    ("Cologne", "NW", "DE", 1_085_664, 50.9375, 6.9603),
    ("Frankfurt", "BW", "DE", 753_056, 50.1109, 8.6821),
    ("Stuttgart", "BW", "DE", 634_830, 48.7758, 9.1829),
    
    # France
    ("Paris", "IDF", "FR", 2_161_000, 48.8566, 2.3522),
    ("Lyon", "ARA", "FR", 513_275, 45.7640, 4.8357),
    ("Marseille", "PAC", "FR", 861_635, 43.2965, 5.3698),
    ("Nice", "PAC", "FR", 343_064, 43.7102, 7.2620),
    
    # UK
    ("London", "ENG", "GB", 8_982_000, 51.5074, -0.1278),
    ("Manchester", "ENG", "GB", 547_627, 53.4808, -2.2426),
    ("Birmingham", "ENG", "GB", 1_141_816, 52.4862, -1.8904),
    ("Edinburgh", "SCT", "GB", 488_050, 55.9533, -3.1883),
    ("Glasgow", "SCT", "GB", 633_120, 55.8642, -4.2518),
    ("Cardiff", "WLS", "GB", 362_400, 51.4816, -3.1791),
    
    # Japan
    ("Tokyo", "KT", "JP", 13_960_000, 35.6762, 139.6503),
    ("Yokohama", "KT", "JP", 3_749_000, 35.4437, 139.6380),
    ("Osaka", "KS", "JP", 2_691_000, 34.6937, 135.5023),
    ("Kyoto", "KS", "JP", 1_475_000, 35.0116, 135.7681),
    ("Nagoya", "CB", "JP", 2_296_000, 35.1815, 136.9066),
    
    # China
    ("Shenzhen", "GD", "CN", 12_528_000, 22.5431, 114.0579),
    ("Guangzhou", "GD", "CN", 13_501_000, 23.1291, 113.2644),
    ("Shanghai", "JS", "CN", 24_281_000, 31.2304, 121.4737),
    ("Chengdu", "SC", "CN", 16_044_000, 30.5728, 104.0668),
    
    # Brazil
    ("São Paulo", "SP", "BR", 12_325_000, -23.5505, -46.6333),
    ("Rio de Janeiro", "RJ", "BR", 6_748_000, -22.9068, -43.1729),
    ("Belo Horizonte", "MG", "BR", 2_722_000, -19.9167, -43.9345),
    
    # Australia
    ("Sydney", "NSW", "AU", 5_312_000, -33.8688, 151.2093),
    ("Melbourne", "VIC", "AU", 5_078_000, -37.8136, 144.9631),
    ("Brisbane", "QLD", "AU", 2_514_000, -27.4698, 153.0251),
]

# Features: (name, city_name, country_code, category, lat, lon)
const FEATURES = [
    # New York
    ("Statue of Liberty", "New York City", "US", "monument", 40.6892, -74.0445),
    ("Central Park", "New York City", "US", "park", 40.7829, -73.9654),
    ("Empire State Building", "New York City", "US", "building", 40.7484, -73.9857),
    ("Times Square", "New York City", "US", "landmark", 40.7580, -73.9855),
    ("Brooklyn Bridge", "New York City", "US", "bridge", 40.7061, -73.9969),
    
    # San Francisco
    ("Golden Gate Bridge", "San Francisco", "US", "bridge", 37.8199, -122.4783),
    ("Alcatraz Island", "San Francisco", "US", "landmark", 37.8267, -122.4230),
    ("Fisherman's Wharf", "San Francisco", "US", "landmark", 37.8080, -122.4177),
    
    # Los Angeles
    ("Hollywood Sign", "Los Angeles", "US", "landmark", 34.1341, -118.3215),
    ("Santa Monica Pier", "Los Angeles", "US", "landmark", 34.0083, -118.4975),
    ("Griffith Observatory", "Los Angeles", "US", "landmark", 34.1184, -118.3004),
    
    # Paris
    ("Eiffel Tower", "Paris", "FR", "monument", 48.8584, 2.2945),
    ("Louvre Museum", "Paris", "FR", "museum", 48.8606, 2.3376),
    ("Notre-Dame", "Paris", "FR", "cathedral", 48.8530, 2.3499),
    ("Arc de Triomphe", "Paris", "FR", "monument", 48.8738, 2.2950),
    ("Sacré-Cœur", "Paris", "FR", "cathedral", 48.8867, 2.3431),
    
    # London
    ("Big Ben", "London", "GB", "monument", 51.5007, -0.1246),
    ("Tower of London", "London", "GB", "castle", 51.5081, -0.0759),
    ("Buckingham Palace", "London", "GB", "palace", 51.5014, -0.1419),
    ("British Museum", "London", "GB", "museum", 51.5194, -0.1270),
    ("London Eye", "London", "GB", "landmark", 51.5033, -0.1196),
    
    # Tokyo
    ("Tokyo Tower", "Tokyo", "JP", "tower", 35.6586, 139.7454),
    ("Senso-ji Temple", "Tokyo", "JP", "temple", 35.7148, 139.7967),
    ("Shibuya Crossing", "Tokyo", "JP", "landmark", 35.6595, 139.7004),
    ("Meiji Shrine", "Tokyo", "JP", "shrine", 35.6764, 139.6993),
    
    # Sydney
    ("Sydney Opera House", "Sydney", "AU", "landmark", -33.8568, 151.2153),
    ("Sydney Harbour Bridge", "Sydney", "AU", "bridge", -33.8523, 151.2108),
    ("Bondi Beach", "Sydney", "AU", "beach", -33.8915, 151.2767),
    
    # Rio de Janeiro
    ("Christ the Redeemer", "Rio de Janeiro", "BR", "monument", -22.9519, -43.2105),
    ("Sugarloaf Mountain", "Rio de Janeiro", "BR", "landmark", -22.9492, -43.1545),
    ("Copacabana Beach", "Rio de Janeiro", "BR", "beach", -22.9711, -43.1822),
]

# =============================================================================
# Build the World Model
# =============================================================================

function build_world()
    world = World{String, String, Int, Float64, Float64, Float64, String}()
    
    # Index maps for lookups
    continent_ids = Dict{String, Int}()
    country_ids = Dict{String, Int}()
    region_ids = Dict{String, Int}()  # key: "region_code:country_code"
    city_ids = Dict{String, Int}()    # key: "city_name:country_code"
    
    # 1. Add continents
    println("Adding continents...")
    for name in CONTINENTS
        id = add_part!(world, :Continent, continent_name = name)
        continent_ids[name] = id
    end
    
    # 2. Add countries
    println("Adding countries...")
    for (name, code, continent, pop, area) in COUNTRIES
        id = add_part!(world, :Country,
            country_name = name,
            country_code = code,
            country_in = continent_ids[continent],
            country_pop = pop,
            country_area = Float64(area)
        )
        country_ids[code] = id
    end
    
    # 3. Add regions
    println("Adding regions...")
    for (name, code, country_code, pop) in REGIONS
        if haskey(country_ids, country_code)
            id = add_part!(world, :Region,
                region_name = name,
                region_code = code,
                region_in = country_ids[country_code],
                region_pop = pop
            )
            region_ids["$code:$country_code"] = id
        end
    end
    
    # 4. Add cities
    println("Adding cities...")
    for (name, region_code, country_code, pop, lat, lon) in CITIES
        key = "$region_code:$country_code"
        if haskey(region_ids, key)
            id = add_part!(world, :City,
                city_name = name,
                city_in = region_ids[key],
                city_pop = pop,
                city_lat = lat,
                city_lon = lon
            )
            city_ids["$name:$country_code"] = id
        end
    end
    
    # 5. Add features
    println("Adding features...")
    for (name, city_name, country_code, cat, lat, lon) in FEATURES
        key = "$city_name:$country_code"
        if haskey(city_ids, key)
            add_part!(world, :Feature,
                feature_name = name,
                feature_in = city_ids[key],
                feature_cat = cat,
                feature_lat = lat,
                feature_lon = lon
            )
        end
    end
    
    return world, continent_ids, country_ids, region_ids, city_ids
end

# =============================================================================
# Traversal Functions for World Model
# =============================================================================

"""Get all countries in a continent"""
countries_in_continent(w, c) = incident(w, c, :country_in)

"""Get all regions in a country"""
regions_in_country(w, c) = incident(w, c, :region_in)

"""Get all cities in a region"""
cities_in_region(w, r) = incident(w, r, :city_in)

"""Get all features in a city"""
features_in_city(w, c) = incident(w, c, :feature_in)

"""Get all cities in a country (via regions)"""
function cities_in_country(w, country)
    regions = regions_in_country(w, country)
    reduce(vcat, [cities_in_region(w, r) for r in regions]; init=Int[])
end

"""Get all features in a country"""
function features_in_country(w, country)
    cities = cities_in_country(w, country)
    reduce(vcat, [features_in_city(w, c) for c in cities]; init=Int[])
end

"""Get continent of a city"""
function continent_of_city(w, city)
    region = w[city, :city_in]
    country = w[region, :region_in]
    w[country, :country_in]
end

"""Find cities within radius (km) of a point"""
function cities_near(w, lat, lon, radius_km)
    filter(parts(w, :City)) do c
        haversine(lat, lon, w[c, :city_lat], w[c, :city_lon]) <= radius_km
    end
end

"""Find features within radius (km) of a point"""
function features_near(w, lat, lon, radius_km)
    filter(parts(w, :Feature)) do f
        haversine(lat, lon, w[f, :feature_lat], w[f, :feature_lon]) <= radius_km
    end
end

"""Total population of a continent"""
function continent_population(w, continent)
    countries = countries_in_continent(w, continent)
    sum(w[c, :country_pop] for c in countries; init=0)
end

"""Find the largest city in a country"""
function largest_city(w, country)
    cities = cities_in_country(w, country)
    isempty(cities) ? nothing : cities[argmax([w[c, :city_pop] for c in cities])]
end

# =============================================================================
# Demo
# =============================================================================

println("=" ^ 70)
println("GeoACSets World Model")
println("=" ^ 70)

world, continent_ids, country_ids, region_ids, city_ids = build_world()

println("\n📊 World Model Statistics:")
println("  Continents: $(nparts(world, :Continent))")
println("  Countries:  $(nparts(world, :Country))")
println("  Regions:    $(nparts(world, :Region))")
println("  Cities:     $(nparts(world, :City))")
println("  Features:   $(nparts(world, :Feature))")

# =============================================================================
# Query Examples
# =============================================================================

println("\n" * "=" ^ 70)
println("QUERY EXAMPLES")
println("=" ^ 70)

# 1. Hierarchy traversal
println("\n🌍 Countries in Europe:")
europe = continent_ids["Europe"]
for c in countries_in_continent(world, europe)
    name = world[c, :country_name]
    pop = world[c, :country_pop]
    println("  $name (pop: $(pop ÷ 1_000_000)M)")
end

# 2. Multi-level traversal
println("\n🏙️ Cities in Germany:")
germany = country_ids["DE"]
for city in cities_in_country(world, germany)
    name = world[city, :city_name]
    pop = world[city, :city_pop]
    println("  $name (pop: $(pop ÷ 1000)K)")
end

# 3. Feature lookup
println("\n🗽 Features in New York City:")
nyc = city_ids["New York City:US"]
for f in features_in_city(world, nyc)
    name = world[f, :feature_name]
    cat = world[f, :feature_cat]
    println("  $name ($cat)")
end

# 4. Spatial query: cities near coordinates
println("\n📍 Cities within 100km of Paris (48.86°N, 2.35°E):")
for city in cities_near(world, 48.8566, 2.3522, 100.0)
    name = world[city, :city_name]
    lat, lon = world[city, :city_lat], world[city, :city_lon]
    dist = haversine(48.8566, 2.3522, lat, lon)
    println("  $name ($(round(dist, digits=1)) km)")
end

# 5. Spatial query: features near coordinates
println("\n🎯 Features within 5km of Times Square (40.758°N, 73.986°W):")
for f in features_near(world, 40.758, -73.986, 5.0)
    name = world[f, :feature_name]
    lat, lon = world[f, :feature_lat], world[f, :feature_lon]
    dist = haversine(40.758, -73.986, lat, lon)
    println("  $name ($(round(dist, digits=2)) km)")
end

# 6. Aggregation queries
println("\n📈 Continental populations:")
for name in CONTINENTS
    cont = continent_ids[name]
    pop = continent_population(world, cont)
    if pop > 0
        println("  $name: $(pop ÷ 1_000_000)M")
    end
end

# 7. Cross-continent query
println("\n🏆 Largest city per country (sample):")
for code in ["US", "JP", "DE", "BR", "AU"]
    country = country_ids[code]
    lc = largest_city(world, country)
    if lc !== nothing
        city_name = world[lc, :city_name]
        country_name = world[country, :country_name]
        pop = world[lc, :city_pop]
        println("  $country_name: $city_name ($(pop ÷ 1000)K)")
    end
end

# 8. Upward traversal
println("\n⬆️ Upward traversal from Eiffel Tower:")
eiffel = findfirst(f -> world[f, :feature_name] == "Eiffel Tower", parts(world, :Feature))
city = world[eiffel, :feature_in]
region = world[city, :city_in]
country = world[region, :region_in]
continent = world[country, :country_in]
println("  Feature:   $(world[eiffel, :feature_name])")
println("  City:      $(world[city, :city_name])")
println("  Region:    $(world[region, :region_name])")
println("  Country:   $(world[country, :country_name])")
println("  Continent: $(world[continent, :continent_name])")

# 9. Feature category filter
println("\n⛩️ All temples and shrines:")
for f in parts(world, :Feature)
    cat = world[f, :feature_cat]
    if cat in ["temple", "shrine"]
        fname = world[f, :feature_name]
        cname = world[world[f, :feature_in], :city_name]
        println("  $fname ($cname)")
    end
end

# 10. Distance matrix between cities
println("\n📏 Distance matrix (km) - Major Asian cities:")
# (city_name, country_code)
asian_city_keys = [("Tokyo", "JP"), ("Shanghai", "CN"), ("Shenzhen", "CN")]
print("             ")
for (cname, _) in asian_city_keys
    print(lpad(cname[1:min(8,end)], 10))
end
println()
for (name1, cc1) in asian_city_keys
    print(lpad(name1[1:min(8,end)], 12), " ")
    for (name2, cc2) in asian_city_keys
        c1 = city_ids["$name1:$cc1"]
        c2 = city_ids["$name2:$cc2"]
        d = haversine(
            world[c1, :city_lat], world[c1, :city_lon],
            world[c2, :city_lat], world[c2, :city_lon]
        )
        print(lpad(round(Int, d), 10))
    end
    println()
end

println("\n" * "=" ^ 70)
println("Key: Morphisms enable O(1) hierarchy traversal, geometry enables spatial queries")
println("=" ^ 70)

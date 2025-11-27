using Documenter
using GeoACSets

makedocs(
    sitename = "GeoACSets.jl",
    modules = [GeoACSets],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://bmorphism.github.io/GeoACSets.jl",
    ),
    pages = [
        "Home" => "index.md",
        "Grid Integration" => "grid_integration.md",
        "API Reference" => "api.md",
    ],
)

deploydocs(
    repo = "github.com/bmorphism/GeoACSets.jl.git",
    devbranch = "main",
    push_preview = true,
)

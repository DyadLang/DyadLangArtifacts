module DyadLangArtifacts

using Artifacts, LazyArtifacts

"""
    dyad_cli_js() -> String

Get the path to the bundled dyad-cli.js file.
This can be run with Node.js: `node \$(dyad_cli_js()) compile ...`

# Example
```julia
using NodeJS_22_jll
using DyadLangArtifacts

js_path = dyad_cli_js()
NodeJS_22_jll.node() do node
    run(`\$node \$js_path --help`)
end
```
"""
function dyad_cli_js()
    return joinpath(@artifact_str("dyad-cli"), "dyad-cli.js")
end

"""
    dyadlang_artifact_dir(name::String) -> String

Get the directory of a specific artifact.
This will be a directory that contains the artifact data,
and optionally an ATTRIBUTION.md file with attribution information.

# Example
```julia
artifact_dir = dyadlang_artifact_dir("dyad-cli")
println(artifact_dir)
```
"""
function dyadlang_artifact_dir(name::String)
    return @artifact_str name
end

"""
    get_attribution(artifact_name::String) -> String

Get the attribution information for a specific artifact.
Returns the contents of the ATTRIBUTION.md file included with the artifact.

# Example
```julia
attribution = get_attribution("dyad-cli")
println(attribution)
```
"""
function get_attribution(artifact_name::String)
    artifact_path = dyadlang_artifact_dir(artifact_name)
    attribution_file = joinpath(artifact_path, "ATTRIBUTION.md")

    if !isfile(attribution_file)
        return "Attribution file not found for artifact: $artifact_name"
    end
    return read(attribution_file, String)
end

"""
    list_artifacts() -> Vector{String}

List all available artifacts in this package.
"""
function list_artifacts()
    artifacts_toml = joinpath(dirname(@__DIR__), "Artifacts.toml")
    if !isfile(artifacts_toml)
        return String[]
    end

    # Simple parsing - just get top-level keys
    artifacts = String[]
    for line in readlines(artifacts_toml)
        m = match(r"^\[([^\]]+)\]", line)
        if m !== nothing && !occursin(".", m[1])
            push!(artifacts, m[1])
        end
    end

    return sort(unique(artifacts))
end

export dyad_cli_js, dyadlang_artifact_dir, get_attribution, list_artifacts

end

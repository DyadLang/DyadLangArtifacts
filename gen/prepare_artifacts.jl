#!/usr/bin/env julia

# Script to prepare dyad-cli bundle artifact at a specific commit
# Usage: julia prepare_artifacts.jl [commit_hash]
#
# This script will clone the dyad-lang repository at a specific commit,
# build the CLI using esbuild, and create a bundled JS artifact.

using Pkg
Pkg.activate((@__DIR__))

using Pkg.Artifacts: bind_artifact!, create_artifact
using Pkg.GitTools: tree_hash
using TOML
using SHA
using NodeJS_22_jll

const SCRIPT_DIR = @__DIR__
const PROJECT_DIR = dirname(SCRIPT_DIR)
const DATA_DIR = joinpath(SCRIPT_DIR, "data")
const TARBALLS_DIR = joinpath(SCRIPT_DIR, "tarballs")
const ARTIFACTS_TOML = joinpath(PROJECT_DIR, "Artifacts.toml")
const PROJECT_TOML = joinpath(PROJECT_DIR, "Project.toml")
const TEMP_DIR = mktempdir()

# Default commit hash (you can change this to your desired commit)
const DEFAULT_COMMIT = "next"  # Change this to a specific commit hash
const REPO_URL = "https://github.com/juliacomputing/dyad-lang.git"

# Clone repository at specific commit
function clone_repo_at_commit(commit_hash::String)
    repo_temp = joinpath(TEMP_DIR, "dyad-lang-clone")

    println("📥 Cloning dyad-lang repository...")
    run(`git clone --no-checkout $REPO_URL $repo_temp`)

    cd(repo_temp) do
        println("   Checking out commit: $commit_hash")
        run(`git checkout $commit_hash`)
    end

    return repo_temp
end

# Create CLI bundle using esbuild
function create_cli_bundle(repo_dir::String, artifact_name::String, commit_hash::String)
    artifact_temp = joinpath(TEMP_DIR, artifact_name)
    mkpath(artifact_temp)

    cd(repo_dir) do
        # Install dependencies and bundle CLI
        npm_path = if Sys.iswindows()
            joinpath(dirname(NodeJS_22_jll.npm), "npm.cmd")
        else
            NodeJS_22_jll.npm
        end

        println("📦 Installing npm dependencies...")
        NodeJS_22_jll.node() do _
            run(`$npm_path ci`)

            println("🔨 Building internal packages (this may take a few minutes)...")
            run(`$npm_path run build`)

            println("🔨 Bundling CLI with esbuild...")
            outfile = joinpath(artifact_temp, "dyad-cli.js")
            run(`$npm_path exec -- esbuild apps/cli/src/scripts/entry.ts --bundle --platform=node --outfile=$outfile`)
        end
    end

    # Create ATTRIBUTION.md
    attribution_content = """
    # Dyad CLI Bundle

    This artifact contains the bundled Dyad CLI from dyad-lang at commit: $commit_hash

    ## Source
    Repository: $REPO_URL
    Commit: $commit_hash

    ## Usage
    Run with Node.js: `node dyad-cli.js [command] [options]`

    ## License
    Please refer to the LICENSE file in the dyad-lang repository for licensing information.
    """

    write(joinpath(artifact_temp, "ATTRIBUTION.md"), attribution_content)

    # Create compressed tarball
    mkpath(TARBALLS_DIR)
    tarball_path = joinpath(TARBALLS_DIR, "$(artifact_name).tar.gz")

    println("📁 Creating tarball: $(basename(tarball_path))")
    run(`tar -czf $tarball_path -C $TEMP_DIR $artifact_name`)

    return tarball_path
end

# Get version from Project.toml
function get_project_version()
    project = TOML.parsefile(PROJECT_TOML)
    return "v" * project["version"]
end

# Get repository info for release
function get_repo_info()
    try
        repo = strip(read(`git remote get-url origin`, String))
        # Extract owner/repo from git URL
        m = match(r"github\.com[:/](.+?)(?:\.git)?$", repo)
        if m !== nothing
            return m[1]
        end
    catch
    end
    return "OWNER/REPO"  # Fallback - user should update this
end

# Custom add_artifact! that uses local directory and tarball
function add_local_artifact!(
    artifacts_toml::String,
    name::String,
    data_dir::String,
    tarball_path::String;
    force::Bool = false,
    lazy::Bool = false
)
    # Create artifact from the tarball to ensure consistency
    git_tree_sha1 = create_artifact() do artifact_dir
        # Extract the tarball we just created into the artifact directory
        run(`tar -xzf $tarball_path -C $artifact_dir --strip-components=1`)
        # Compute the git-tree-sha1 using Pkg.GitTools.tree_hash
        return Base.SHA1(tree_hash(artifact_dir))
    end

    sha256 = Pkg.Artifacts.archive_artifact(git_tree_sha1, tarball_path)

    # Get GitHub URL for this artifact
    version = get_project_version()
    repo = get_repo_info()
    github_url = "https://github.com/$(repo)/releases/download/$(version)/$(basename(tarball_path))"

    # Bind artifact with GitHub URL
    bind_artifact!(
        artifacts_toml,
        name,
        git_tree_sha1;
        download_info = [(github_url, sha256)],
        lazy = lazy,
        force = force
    )

    if lazy
        println("   Marked as lazy artifact")
    end

    return git_tree_sha1
end

# Main processing function
function process_dyad_cli_artifact(commit_hash::String = DEFAULT_COMMIT; lazy::Bool = false)
    println("🚀 Processing dyad-cli bundle artifact")
    println("   Commit: $commit_hash")

    # Clone repository at specific commit
    repo_dir = clone_repo_at_commit(commit_hash)

    artifact_name = "dyad-cli"

    println("📦 Creating artifact: $artifact_name")

    # Create CLI bundle
    tarball_path = create_cli_bundle(repo_dir, artifact_name, commit_hash)
    println("   Created tarball: $(basename(tarball_path))")

    # Add artifact using local directory and tarball
    artifact_id = add_local_artifact!(
        ARTIFACTS_TOML,
        artifact_name,
        repo_dir,
        tarball_path,
        force=true,
        lazy=lazy
    )
    println("   Artifact ID: $artifact_id")

    println("\n✅ Successfully created artifact: $artifact_name")
    println("📄 Updated: $ARTIFACTS_TOML")

    println("\n🎯 Next steps:")
    println("   1. Run: julia gen/create_release.jl")
    println("   2. The artifact can be accessed using:")
    println("      using DyadLangArtifacts")
    println("      path = dyad_cli_js()")
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    # Check if commit hash was provided as argument
    commit_hash = length(ARGS) > 0 ? ARGS[1] : DEFAULT_COMMIT
    lazy = "--lazy" in ARGS

    process_dyad_cli_artifact(commit_hash; lazy=lazy)
end

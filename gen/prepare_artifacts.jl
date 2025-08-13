#!/usr/bin/env julia

# Script to prepare dyad-lang repository artifact at a specific commit
# Usage: julia prepare_artifacts.jl [commit_hash]
#
# This script will clone the dyad-lang repository at a specific commit
# and create an artifact from it

using Pkg
Pkg.activate((@__DIR__))

using Pkg.Artifacts: bind_artifact!, create_artifact
using Pkg.GitTools: tree_hash
using TOML
using SHA

const SCRIPT_DIR = @__DIR__
const PROJECT_DIR = dirname(SCRIPT_DIR)
const DATA_DIR = joinpath(SCRIPT_DIR, "data")
const TARBALLS_DIR = joinpath(SCRIPT_DIR, "tarballs")
const ARTIFACTS_TOML = joinpath(PROJECT_DIR, "Artifacts.toml")
const PROJECT_TOML = joinpath(PROJECT_DIR, "Project.toml")
const TEMP_DIR = mktempdir()

# Default commit hash (you can change this to your desired commit)
const DEFAULT_COMMIT = "main"  # Change this to a specific commit hash
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

# Create tarball with repository contents
function create_artifact_tarball(repo_dir::String, artifact_name::String, commit_hash::String)
    # Create temporary directory for this artifact
    artifact_temp = joinpath(TEMP_DIR, artifact_name)
    mkpath(artifact_temp)
    
    # Copy repository contents (excluding .git directory)
    for (root, dirs, files) in walkdir(repo_dir)
        # Skip .git directory
        if occursin(".git", root)
            continue
        end
        
        rel_path = relpath(root, repo_dir)
        dest_dir = joinpath(artifact_temp, rel_path)
        mkpath(dest_dir)
        
        for file in files
            src = joinpath(root, file)
            dst = joinpath(dest_dir, file)
            cp(src, dst)
        end
    end
    
    # Create ATTRIBUTION.md file
    attribution_content = """
    # Dyad Language Repository Artifact
    
    This artifact contains the dyad-lang repository at commit: $commit_hash
    
    ## Source
    Repository: $REPO_URL
    Commit: $commit_hash
    
    ## License
    Please refer to the LICENSE file in the repository for licensing information.
    
    ## Attribution
    This is a snapshot of the dyad-lang repository for use as a Julia artifact.
    """
    
    write(joinpath(artifact_temp, "ATTRIBUTION.md"), attribution_content)
    
    # Create compressed tarball using command line tar
    mkpath(TARBALLS_DIR)
    tarball_path = joinpath(TARBALLS_DIR, "$(artifact_name).tar.gz")
    
    # Use tar command to create compressed tarball
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
function process_dyad_lang_artifact(commit_hash::String = DEFAULT_COMMIT; lazy::Bool = false)
    println("🚀 Processing dyad-lang repository artifact")
    println("   Commit: $commit_hash")
    
    # Clone repository at specific commit
    repo_dir = clone_repo_at_commit(commit_hash)
    
    # Always use 'dyad-lang' as the artifact name
    artifact_name = "dyad-lang"
    
    println("📦 Creating artifact: $artifact_name")
    
    # Create tarball
    tarball_path = create_artifact_tarball(repo_dir, artifact_name, commit_hash)
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
    println("   1. Update the commit hash in this script if needed")
    println("   2. Run: julia gen/create_release.jl")
    println("   3. The artifact can be accessed using:")
    println("      using DyadLangArtifacts")
    println("      path = dyadlang_artifact_dir(\"$artifact_name\")")
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    # Check if commit hash was provided as argument
    commit_hash = length(ARGS) > 0 ? ARGS[1] : DEFAULT_COMMIT
    lazy = "--lazy" in ARGS
    
    process_dyad_lang_artifact(commit_hash; lazy=lazy)
end
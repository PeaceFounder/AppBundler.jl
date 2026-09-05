using Documenter
import AppBundler

# Setting README as index

index_path = joinpath(@__DIR__, "src", "index.md")
readme_path = joinpath(@__DIR__, "..", "README.md")


readme_content = read(readme_path)

index_content = join([
    """
    ```@meta
    EditURL = "../../README.md"
    ```
    """,
    String(readme_content)
], "\n")

index_content = replace(index_content, r"!\[\]\(docs/src/([^)]+)\)" => s"![](\1)")

if !isfile(index_path) || String(read(index_path)) != index_content
    rm(index_path, force=true)
    write(index_path, index_content)
end

include("llms.jl")

const PAGES = [
    "Overview" => "index.md",
    "Customization" => "customization.md",
    "Deployment" => "deployment.md", # codesigning, GitHub CI,
    "Juliaup" => "juliaup.md",
    "Troubleshooting" => "troubleshooting.md",
    "Reference" => "reference.md" # Here I could also give an overview of the internal API on how it composes. Perhaps I shall madke that as documentation for the module here.
]

makedocs(
    sitename = "AppBundler.jl",
    repo = Documenter.Remotes.GitHub("PeaceFounder", "AppBundler.jl"),
    format = Documenter.HTML(),
    warnonly = true,
    checkdocs = :public,
    modules = [AppBundler],
    checkdocs_ignored_modules = [AppBundler.DSStore, AppBundler.HFS],
    pages = PAGES
)

generate_llms_txt(joinpath(@__DIR__, "build"), joinpath(@__DIR__, "src"), PAGES)

deploydocs(repo = "github.com/PeaceFounder/AppBundler.jl.git")


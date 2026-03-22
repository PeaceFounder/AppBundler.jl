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

if String(read(index_path)) != index_content
    rm(index_path, force=true)
    write(index_path, index_content)
end

makedocs(
    sitename = "AppBundler.jl",
    repo = Documenter.Remotes.GitHub("PeaceFounder", "AppBundler.jl"),
    format = Documenter.HTML(),
    warnonly = true,
    checkdocs = :public,
    modules = [AppBundler, AppBundler.JuliaC, AppBundler.JuliaImg],
    checkdocs_ignored_modules = [AppBundler.DSStore, AppBundler.HFS],
    pages = [
        "Overview" => "index.md",
        "Customization" => "customization.md",
        "Deployment" => "deployment.md", # codesigning, GitHub CI,
        "Troubleshooting" => "troubleshooting.md",
        "Reference" => "reference.md" # Here I could also give an overview of the internal API on how it composes. Perhaps I shall madke that as documentation for the module here.
    ]
)

deploydocs(repo = "github.com/PeaceFounder/AppBundler.jl.git")


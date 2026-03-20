dirname(@__DIR__) in LOAD_PATH || Base.push!(LOAD_PATH, dirname(@__DIR__)) # Since dev path is not present in Project.toml
(@isdefined Revise) && Revise.retry() # 

using Literate
using Documenter
using CryptoGroups

LITERATE_DIR = joinpath(@__DIR__, "src", "generated")
mkpath(LITERATE_DIR)
EXAMPLES_DIR = joinpath(dirname(@__DIR__), "examples")

function include_example(fname)
    name, _ = splitext(fname)

    src = joinpath(EXAMPLES_DIR, fname)
    dst = joinpath(LITERATE_DIR, "$name.md")

    Literate.markdown(src, dirname(dst); name)

    return joinpath("generated", "$name.md")
end

# Setting README as index

index_path = joinpath(@__DIR__, "src", "index.md")
readme_path = joinpath(@__DIR__, "..", "README.md")

rm(index_path, force=true)

readme_content = read(readme_path)

index_content = join([
    """
    ```@meta
    EditURL = "../../README.md"
    ```
    """,
    String(readme_content)
], "\n")


write(index_path, index_content)




makedocs(
    sitename = "CryptoGroups.jl",
    repo = Documenter.Remotes.GitHub("PeaceFounder", "CryptoGroups.jl"),
    format = Documenter.HTML(),
    modules = [CryptoGroups, CryptoGroups.Fields, CryptoGroups.Curves, CryptoGroups.Utils],
    warnonly = true,
    pages = [
        "Overview" => "index.md",
        "Group Examples" => [
            "Digital Signature Algorithm" => include_example("dsa.jl"),  
            "Key Encapsulation Mechanism" => include_example("kem.jl"),
            "ElGamal Cryptosystem" => include_example("elgamal.jl"),
            "Proof of Knowledge" => include_example("knowledge_proof.jl")
        ],
        "Field Examples" => [
            "Lagrange Polynomials" => include_example("lagrange.jl"),
            "Reed-Solomon EC" => include_example("reed-solomon.jl"),
            "Field Subtyping" => include_example("external_fields.jl")
        ],
        "Reference" => [
            "Groups" => "groups.md",
            "Curves" => "curves.md",
            "Fields" => "fields.md",
            "Utils" => "utils.md"
        ]
    ]
)


deploydocs(repo = "github.com/PeaceFounder/CryptoGroups.jl.git")


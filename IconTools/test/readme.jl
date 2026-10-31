# IconTools/test/readme.jl
using Test

const README = joinpath(@__DIR__, "..", "README.md")

# Extract the body of every ```julia fenced block from the README.
function readme_snippets(path)
    text = read(path, String)
    pat = r"^```julia[ \t]*\r?\n(.*?)^```"ms
    return [String(m.captures[1]) for m in eachmatch(pat, text)]
end

# REPL transcripts can't be run as scripts: julia>, pkg>, shell>, help?>
is_repl_snippet(code) = occursin(r"^\s*(julia>|\(.*\) pkg>|pkg>|shell>|help\?>)"m, code)

@testset "README examples" begin
    snippets = readme_snippets(README)
    @test !isempty(snippets)   # the regex must actually match something

    sandbox = Module(:ReadmeExamples)   # shared global environment for all snippets

    cd(@__DIR__) do                     # relative paths in snippets resolve against test/

        #isdir("build") && rm("build"; recursive = true)   # start clean; README must create it
        mkpath("build")                 # output directory the snippets write into; left in place

        for (i, code) in enumerate(snippets)
            occursin("# notest", code) && continue
            is_repl_snippet(code) && continue

            @testset "snippet $i" begin
                err = nothing
                try
                    include_string(sandbox, code, "README.md snippet $i")
                catch e
                    err = e
                    @error "README snippet $i failed" code exception = (e, catch_backtrace())
                end
                @test err === nothing
            end
        end
    end
end


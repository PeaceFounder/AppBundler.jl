import AppBundler.JuliaC: JuliaCBundle, stage

project = joinpath(dirname(@__DIR__), "examples/CmdApp")
spec = JuliaCBundle(project; trim = true)

if isfile(spec.juliac_cmd.exec[1])
    builddir = mktempdir()
    stage(spec, builddir)
    
    cmdapp_cmd = joinpath(builddir, "bin/cmdapp")
    run(`$cmdapp_cmd $(@__FILE__)`)
else
    @warn "JuliaC tests are skipped because juliac can't be found in ~/.julia/juliac"
end

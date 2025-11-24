module SysImgTools

import ..TerminalSpinners

macro monitor_oom(ex)
    quote
        lowest_free_mem = Sys.free_memory()
        mem_monitor = Timer(0, interval = 1) do t
            lowest_free_mem = min(lowest_free_mem, Sys.free_memory())
        end
        try
            $(esc(ex))
        catch
            if lowest_free_mem < 512 * 1024 * 1024 # Less than 512 MB
                @warn """
                Free system memory dropped to $(Base.format_bytes(lowest_free_mem)) during sysimage compilation.
                If the reason the subprocess errored isn't clear, it may have been OOM-killed.
                """
            end
            rethrow()
        finally
            close(mem_monitor)
        end
    end
end

function get_julia_cmd()
    julia_path = joinpath(Sys.BINDIR, Base.julia_exename())
    color = Base.have_color === nothing ? "auto" : Base.have_color ? "yes" : "no"
    if isdefined(Base, :Linking) # pkgimage support feature flag
        `$julia_path --color=$color --startup-file=no`
    else
        `$julia_path --color=$color --startup-file=no`
    end
end

function create_sysimg_object_file(script::String,
                                   object_file::String;
                                   project::Union{String, Nothing},
                                   base_sysimg::String,
                                   sysimg_args::Cmd,
                                   cpu_target::String,
                                   julia_cmd = get_julia_cmd()
                            )


    julia_code_buffer = IOBuffer()
    # include all packages into the sysimg
    print(julia_code_buffer, """
            Base.reinit_stdio()
            @eval Sys BINDIR = ccall(:jl_get_julia_bindir, Any, ())::String
            @eval Sys STDLIB = abspath(Sys.BINDIR, "../share/julia/stdlib", string('v', VERSION.major, '.', VERSION.minor))

            push!(LOAD_PATH, "@", Sys.STDLIB)
            push!(DEPOT_PATH, joinpath(Sys.BINDIR, "../share/julia"))

            # Load path lacks extension fix
            # perhaps here I can simply relly on adding project to the load path itself without any drawbacks
        """)

    print(julia_code_buffer, script)

    print(julia_code_buffer, """
        empty!(LOAD_PATH)
        empty!(DEPOT_PATH)
        """)

    julia_code = String(take!(julia_code_buffer))
    outputo_file = tempname()
    write(outputo_file, julia_code)
    # Read the input via stdin to avoid hitting the maximum command line limit
    cmd = `$julia_cmd --startup-file=no --cpu-target=$cpu_target $sysimg_args
                --sysimage=$base_sysimg --project=$project --pkgimages=no --output-o=$(object_file)
                $outputo_file`

    @debug "running $cmd"

    spinner = TerminalSpinners.Spinner(msg = "Compiling system image")
    @monitor_oom TerminalSpinners.@spin spinner run(cmd)
    return
end

function compile_sysimage(script::String, sysimage_path::String;
                         base_sysimg::String = unsafe_string(Base.JLOptions().image_file), 
                         project::String=dirname(active_project()),
                         sysimg_args::Cmd=``,
                         cpu_target::String="native",
                         julia_cmd = get_julia_cmd()
                         )


    # Create the sysimage
    object_file = tempname() * "-o.a"

    create_sysimg_object_file(script, object_file;
                              project,
                              base_sysimg,
                              sysimg_args,
                              cpu_target,
                              julia_cmd
                              )

    # There may be use for running this on the julia process itself to avoid arch mismatches
    object_files = [object_file]
    Base.Linking.link_image(object_files, sysimage_path)
    
    rm(object_file; force=true)

    # Do we need this one?
    if Sys.isapple()
        cd(dirname(abspath(sysimage_path))) do
            sysimage_file = basename(sysimage_path)
            cmd = `install_name_tool -id @rpath/$(sysimage_file) $sysimage_file`
            @debug "running $cmd"
            run(cmd)
        end
    end

    return
end

end

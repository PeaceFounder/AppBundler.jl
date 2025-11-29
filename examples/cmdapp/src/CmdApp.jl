module CmdApp

function (@main)(ARGS::Vector{String})
    # Check if file argument provided

    println(Core.stdout, "Sys.STDLIB = $(Sys.STDLIB)")
    println(Core.stdout, "Sys.BINDIR = $(Sys.BINDIR)")
    println(Core.stdout, "LOAD_PATH = $(LOAD_PATH[1])")
    println(Core.stdout, "LOAD_PATH = $(LOAD_PATH[2])")
    println(Core.stdout, "LOAD_PATH = $(LOAD_PATH[3])")

    println(Core.stdout, "pkgdir = $(pkgdir(@__MODULE__))") # This works!!!

    if isempty(ARGS)
        println(Core.stdout, "Usage: julia script.jl <filename>")
        return 1
    end
    
    filename = ARGS[1]
    
    # Check if file exists
    if !isfile(filename)
        println(Core.stdout, "Error: File '$filename' not found!")
        return 1
    end

    # Count words - without do block
    word_count = 0
    io = open(filename, "r")
    try
        for line in eachline(io)
            words = split(line)
            word_count += length(words)
        end
    finally
        close(io)
    end

    # Display result
    println(Core.stdout, "$filename: $word_count words")
    
    return 0

end

export main

end # module CmdApp

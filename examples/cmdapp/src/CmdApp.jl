module CmdApp

function (@main)(ARGS)
    # Check if file argument provided
    if isempty(ARGS)
        println("Usage: julia script.jl <filename>")
        return 1
    end
    
    filename = ARGS[1]
    
    # Check if file exists
    if !isfile(filename)
        println("Error: File '$filename' not found!")
        return 1
    end
    
    # Count words
    word_count = 0
    open(filename, "r") do io
        for line in eachline(io)
            words = split(line)
            word_count += length(words)
        end
    end
    
    # Display result
    println("$filename: $word_count words")
    
    return 0
end

export main

end # module CmdApp

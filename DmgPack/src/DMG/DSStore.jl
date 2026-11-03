"""
    DSStore.jl

A Julia wrapper for the Python `ds_store` package using PyCall.
This module provides functionality to read and write .DS_Store files on macOS.

## Example usage:
```julia
using DSStore

# Read and modify a .DS_Store file
open_dsstore("/path/to/.DS_Store", "w+") do ds
    # Position the icon for "foo.txt" at (128, 128)
    ds["foo.txt", "Iloc"] = (128, 128)
    
    # Display the plists for this folder
    println(ds[".", "bwsp"])
    println(ds[".", "icvp"])
end
```
"""
module DSStore

using PyCall

# Import the Python ds_store module
function __init__()
    try
        py"""
        import ds_store
        from ds_store import DSStore as PyDSStore
        """
    catch e
        error("Failed to import Python module 'ds_store'. Make sure it's installed: $e")
    end
end

# Wrapper for the DSStore class
mutable struct DSStoreFile
    pyobj::PyObject
    path::String
    mode::String
    
    function DSStoreFile(path::String, mode::String="r")
        pyobj = py"PyDSStore.open($path, $mode)" # initial_entries
        new(pyobj, path, mode)
    end
end


"""
    open_dsstore(path::String, mode::String="r")

Open a .DS_Store file at the given path with the specified mode.
Available modes: "r" (read-only), "w" (write), "r+" (read/write).

Returns a `DSStoreFile` object.
"""
function open_dsstore(path::String, mode::String="r")
    DSStoreFile(path, mode)
end

"""
    open_dsstore(f::Function, path::String, mode::String="r")

Open a .DS_Store file, perform operations with it, and automatically close it.

Example:
```julia
open_dsstore("/path/to/.DS_Store", "r+") do ds
    ds["file.txt", "Iloc"] = (128, 128)
end
```
"""
function open_dsstore(f::Function, path::String, mode::String="r")
    ds = open_dsstore(path, mode)
    try
        f(ds)
    finally
        close(ds)
    end
end

"""
    close(ds::DSStoreFile)

Close the .DS_Store file, flushing any changes to disk.
"""
function Base.close(ds::DSStoreFile)
    ds.pyobj.close()
end


# Get a specific property of a file
function Base.getindex(ds::DSStoreFile, file::String, property::String)
    #py_value = ds.pyobj[file][property]

    fhandle = PyCall.pycall(PyCall.getproperty(ds.pyobj, :__getitem__), PyObject, file)

    prophandle = PyCall.pycall(PyCall.getproperty(fhandle, :__getitem__), PyObject, property)

    # Convert Python objects to Julia types where appropriate
    return prophandle
end


function Base.setindex!(ds::DSStoreFile, value, file::String, property::String)
    # Get the file handle
    fhandle = PyCall.pycall(PyCall.getproperty(ds.pyobj, :__getitem__), PyObject, file)
    
    # Use Python's __setitem__ to modify the property
    PyCall.pycall(PyCall.getproperty(fhandle, :__setitem__), PyObject, property, value)
    
    return value
end


function print_tree(io::IO, ds::DSStoreFile)
    for item in ds
        #println("Item $(item.index)/$(item.total):")
        println(io, "  File: $(item.filename)")
        println(io, "  Code: $(item.code)")
        println(io, "  Value: $(item.value)")
        println(io, "-" ^ 40)  # Separator for readability
    end
    return
end

# Pretty printing
function Base.show(io::IO, ds::DSStoreFile)
    print(io, "DSStoreFile($(ds.path), mode=$(ds.mode))")

    println(io, "\n")
    println(io, "-" ^ 40)  
    print_tree(io, ds)

    return
end


# ToDo use length attribute to check py_iter state

# Define the iterator interface for DSStoreFile
function Base.iterate(ds::DSStoreFile, state=nothing)
    # Initialize state on first call
    if state === nothing
        # Create Python iterator
        py_iter = PyCall.pybuiltin("iter")(ds.pyobj)
        state = py_iter
    else
        py_iter = state
    end

    # Try to get the next item
    try
        # Get next item from iterator
        item = PyCall.pybuiltin("next")(py_iter)
        
        # Create a named tuple with the relevant fields
        result = (
            filename = convert(String, item.filename),
            code = convert(String, item.code),
            value = item.value  # Keep as PyObject for flexibility
        )
        
        # Return current item and updated state
        return (result, py_iter)
    catch e
        # If we hit StopIteration, signal end of iteration
        if isa(e, PyCall.PyError) && occursin("StopIteration", string(e))
            return nothing
        else
            # Reraise unexpected errors
            rethrow(e)
        end
    end
end


Base.length(ds::DSStoreFile) = convert(Int, PyCall.pycall(PyCall.getproperty(ds.pyobj, :__len__), PyObject))

# Define eltype to help other Julia functions
Base.eltype(::Type{DSStoreFile}) = NamedTuple{(:filename, :code, :value), Tuple{String, String, PyObject}}

function Base.convert(::Type{Dict}, ds::DSStoreFile)

    result = Dict{String, Any}()
    
    # Iterate through all items in the DS Store
    for item in ds
        filename = item.filename
        code = item.code
        value = item.value
        
        # Initialize inner dictionary if needed
        if !haskey(result, filename)
            result[filename] = Dict{String, Any}()
        end

        if code == "icvl"
            result[filename][code] = ("type", "icnv")
        elseif code == "vSrn"
            result[filename][code] = ("long", 1)
        elseif value isa Dict
            result[filename][code] = convert(Dict{String, Any}, value)
        else
            result[filename][code] = value #julia_value
        end
    end
    
    return result    
end

end # module

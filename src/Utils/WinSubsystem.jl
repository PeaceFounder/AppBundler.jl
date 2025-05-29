module WinSubsystem

# using Printf

# PE subsystem constants
const SUBSYSTEM_CONSOLE = 0x0003
const SUBSYSTEM_WINDOWS_GUI = 0x0002

# DOS header signature
const DOS_SIGNATURE = b"MZ"
const PE_SIGNATURE = b"PE\x00\x00"

struct DOSHeader
    e_magic::UInt16      # Magic number
    e_cblp::UInt16       # Bytes on last page of file
    e_cp::UInt16         # Pages in file
    e_crlc::UInt16       # Relocations
    e_cparhdr::UInt16    # Size of header in paragraphs
    e_minalloc::UInt16   # Minimum extra paragraphs needed
    e_maxalloc::UInt16   # Maximum extra paragraphs needed
    e_ss::UInt16         # Initial relative SS value
    e_sp::UInt16         # Initial SP value
    e_csum::UInt16       # Checksum
    e_ip::UInt16         # Initial IP value
    e_cs::UInt16         # Initial relative CS value
    e_lfarlc::UInt16     # File address of relocation table
    e_ovno::UInt16       # Overlay number
    e_res::NTuple{4, UInt16}  # Reserved words
    e_oemid::UInt16      # OEM identifier
    e_oeminfo::UInt16    # OEM information
    e_res2::NTuple{10, UInt16} # Reserved words
    e_lfanew::UInt32     # File address of new exe header
end

function read_dos_header(io::IO)
    # Read DOS header (64 bytes)
    data = read(io, 64)
    if length(data) < 64
        error("File too small to contain DOS header")
    end
    
    # Check DOS signature
    if data[1:2] != DOS_SIGNATURE
        error("Invalid DOS signature")
    end
    
    # Extract e_lfanew (offset to PE header) - last 4 bytes of DOS header
    e_lfanew = reinterpret(UInt32, data[61:64])[1]
    
    return e_lfanew
end

function find_pe_header_offset(io::IO)
    seekstart(io)
    e_lfanew = read_dos_header(io)
    
    # Seek to PE header
    seek(io, e_lfanew)
    
    # Verify PE signature
    pe_sig = read(io, 4)
    if pe_sig != PE_SIGNATURE
        error("Invalid PE signature at offset $(e_lfanew)")
    end
    
    return e_lfanew + 4  # Return offset after PE signature
end

function get_subsystem_offset(io::IO)
    pe_offset = find_pe_header_offset(io)
    
    # COFF header is 20 bytes after PE signature
    # Optional header starts after COFF header
    coff_header_offset = pe_offset
    
    # Read COFF header to get size of optional header
    seek(io, coff_header_offset)
    coff_data = read(io, 20)
    
    # Extract SizeOfOptionalHeader (bytes 16-17 of COFF header)
    size_of_optional_header = reinterpret(UInt16, coff_data[17:18])[1]
    
    if size_of_optional_header == 0
        error("No optional header found")
    end
    
    # Optional header starts after COFF header (20 bytes)
    optional_header_offset = coff_header_offset + 20
    
    # Subsystem is at offset 68 (0x44) in the optional header for PE32
    # or offset 68 (0x44) in the optional header for PE32+
    subsystem_offset = optional_header_offset + 68
    
    return subsystem_offset
end

function read_current_subsystem(filename::String)
    open(filename, "r") do io
        try
            subsystem_offset = get_subsystem_offset(io)
            seek(io, subsystem_offset)
            subsystem_bytes = read(io, 2)
            subsystem_value = reinterpret(UInt16, subsystem_bytes)[1]
            return subsystem_value, subsystem_offset
        catch e
            error("Error reading subsystem: $(e)")
        end
    end
end

function change_subsystem(input_file::String, output_file::String, new_subsystem::UInt16)
    # Read the current subsystem first
    current_subsystem, subsystem_offset = read_current_subsystem(input_file)
    
    println("Current subsystem: $(current_subsystem) (0x$(string(current_subsystem, base=16, pad=4)))")
    println("Subsystem offset: $(subsystem_offset) (0x$(string(subsystem_offset, base=16)))")
    
    # Copy the file
    cp(input_file, output_file, force=true)
    
    # Modify the subsystem value
    open(output_file, "r+") do io
        seek(io, subsystem_offset)
        write(io, reinterpret(UInt8, [new_subsystem]))
    end
    
    # Verify the change
    new_current_subsystem, _ = read_current_subsystem(output_file)
    
    println("New subsystem: $(new_current_subsystem) (0x$(string(new_current_subsystem, base=16, pad=4)))")
    
    if new_current_subsystem == new_subsystem
        println("✓ Subsystem successfully changed!")
        return true
    else
        println("✗ Subsystem change failed!")
        return false
    end
end

function subsystem_to_string(subsystem::UInt16)
    if subsystem == SUBSYSTEM_CONSOLE
        return "Console Application"
    elseif subsystem == SUBSYSTEM_WINDOWS_GUI
        return "Windows GUI Application"
    else
        return "Unknown ($(subsystem))"
    end
end

function change_subsystem_debug(input_file, output_file; subsystem_flag = SUBSYSTEM_WINDOWS_GUI)
    
    if !isfile(input_file)
        error("Input file not found: $(input_file)")
    end
    
    println("Modifying Windows PE subsystem...")
    println("Input file:  $(input_file)")
    println("Output file: $(output_file)")
    println()
    

    # Read current subsystem info
    current_subsystem, _ = read_current_subsystem(input_file)
    current_desc = subsystem_to_string(current_subsystem)
    new_desc = subsystem_to_string(SUBSYSTEM_WINDOWS_GUI)
    
    println("Current: $(current_desc)")
    println("Target:  $(new_desc)")
    println()
    
    if current_subsystem == SUBSYSTEM_WINDOWS_GUI
        println("⚠ File is already a GUI application!")
        return
    elseif current_subsystem != SUBSYSTEM_CONSOLE
        println("⚠ Warning: File is not a console application (subsystem=$(current_subsystem))")
        print("Continue anyway? (y/N): ")
        response = readline()
        if lowercase(strip(response)) != "y"
            println("Aborted.")
            return
        end
    end
    
    # Perform the modification
    success = change_subsystem(input_file, output_file, subsystem_flag)
    
    if success
        println()
        println("🎉 Successfully converted $(input_file) to GUI application!")
        println("   Output saved as: $(output_file)")
        println()
        println("Note: The application will no longer show a console window,")
        println("      but any console output will be lost unless redirected.")
    end
    
end

function change_subsystem_inplace(dest; Ssubsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)

    orig = joinpath(tempdir(), basename(dest))
    mv(dest, orig; force=true)
    WinSubsystem.change_subsystem(orig, dest, subsystem_flag)

    return
end

end

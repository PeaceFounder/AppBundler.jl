module MSIXIcons

# Use minimal focused packages instead of the full Images.jl umbrella
using FileIO              # For loading/saving images
using ImageCore           # Core image types and utilities (lightweight)
using ImageTransformations # Just for imresize function (focused functionality)

"""
Generate all required icons for Windows App Package from a single source icon.
This creates the complete set of icons including all scale factors and target sizes.
"""
function generate_app_icons(source_path::String, output_dir::String)
    # Create output directory if it doesn't exist
    mkpath(output_dir)
    
    # Load the source image using FileIO
    println("Loading source image: $source_path")
    source_img = load(source_path)
    
    # Define all the icon specifications
    icon_specs = [
        # BadgeLogo variants
        ("BadgeLogo.scale-100.png", 24, 24),
        ("BadgeLogo.scale-125.png", 30, 30),
        ("BadgeLogo.scale-150.png", 36, 36),
        ("BadgeLogo.scale-200.png", 48, 48),
        ("BadgeLogo.scale-400.png", 96, 96),
        
        # SplashScreen variants (620x300 base size)
        ("SplashScreen.scale-100.png", 620, 300),
        ("SplashScreen.scale-125.png", 775, 375),
        ("SplashScreen.scale-150.png", 930, 450),
        ("SplashScreen.scale-200.png", 1240, 600),
        ("SplashScreen.scale-400.png", 2480, 1200),
        
        # Square150x150Logo variants
        ("Square150x150Logo.scale-100.png", 150, 150),
        ("Square150x150Logo.scale-125.png", 188, 188),
        ("Square150x150Logo.scale-150.png", 225, 225),
        ("Square150x150Logo.scale-200.png", 300, 300),
        ("Square150x150Logo.scale-400.png", 600, 600),
        
        # Square30x30Logo variant
        ("Square30x30Logo.scale-100.png", 30, 30),
        
        # Square310x310Logo variants
        ("Square310x310Logo.scale-100.png", 310, 310),
        ("Square310x310Logo.scale-125.png", 388, 388),
        ("Square310x310Logo.scale-150.png", 465, 465),
        ("Square310x310Logo.scale-200.png", 620, 620),
        ("Square310x310Logo.scale-400.png", 1240, 1240),
        
        # Square310x310Logo1 variants
        ("Square310x310Logo1.scale-100.png", 310, 310),
        ("Square310x310Logo1.scale-125.png", 388, 388),
        ("Square310x310Logo1.scale-150.png", 465, 465),
        ("Square310x310Logo1.scale-200.png", 620, 620),
        ("Square310x310Logo1.scale-400.png", 1240, 1240),
        
        # Square44x44Logo scale variants
        ("Square44x44Logo.scale-100.png", 44, 44),
        ("Square44x44Logo.scale-125.png", 55, 55),
        ("Square44x44Logo.scale-150.png", 66, 66),
        ("Square44x44Logo.scale-200.png", 88, 88),
        ("Square44x44Logo.scale-400.png", 176, 176),
        
        # Square44x44Logo targetsize variants
        ("Square44x44Logo.targetsize-16.png", 16, 16),
        ("Square44x44Logo.targetsize-16_altform-lightunplated.png", 16, 16),
        ("Square44x44Logo.targetsize-16_altform-unplated.png", 16, 16),
        ("Square44x44Logo.targetsize-24.png", 24, 24),
        ("Square44x44Logo.targetsize-24_altform-lightunplated.png", 24, 24),
        ("Square44x44Logo.targetsize-24_altform-unplated.png", 24, 24),
        ("Square44x44Logo.targetsize-256.png", 256, 256),
        ("Square44x44Logo.targetsize-256_altform-lightunplated.png", 256, 256),
        ("Square44x44Logo.targetsize-256_altform-unplated.png", 256, 256),
        ("Square44x44Logo.targetsize-32.png", 32, 32),
        ("Square44x44Logo.targetsize-32_altform-lightunplated.png", 32, 32),
        ("Square44x44Logo.targetsize-32_altform-unplated.png", 32, 32),
        ("Square44x44Logo.targetsize-48.png", 48, 48),
        ("Square44x44Logo.targetsize-48_altform-lightunplated.png", 48, 48),
        ("Square44x44Logo.targetsize-48_altform-unplated.png", 48, 48),
        
        # Square70x70Logo variant
        ("Square70x70Logo.scale-100.png", 70, 70),
        
        # Square71x71Logo variants
        ("Square71x71Logo.scale-100.png", 71, 71),
        ("Square71x71Logo.scale-125.png", 89, 89),
        ("Square71x71Logo.scale-150.png", 107, 107),
        ("Square71x71Logo.scale-200.png", 142, 142),
        ("Square71x71Logo.scale-400.png", 284, 284),
        
        # StoreLogo variant
        ("StoreLogo.scale-100.png", 50, 50),
    ]
    
    # Wide logo variants
    wide_specs = [
        ("Wide310x150Logo.scale-100.png", 310, 150),
        ("Wide310x150Logo.scale-125.png", 388, 188),
        ("Wide310x150Logo.scale-150.png", 465, 225),
        ("Wide310x150Logo.scale-200.png", 620, 300),
        ("Wide310x150Logo.scale-400.png", 1240, 600),
    ]
    
    println("Generating square and rectangular icons...")
    total_icons = length(icon_specs) + length(wide_specs)
    current = 0
    
    # Generate all square icons and splash screens
    for (filename, width, height) in icon_specs
        current += 1
        output_path = joinpath(output_dir, filename)
        
        if contains(filename, "SplashScreen")
            resized_img = create_splash_screen(source_img, width, height)
        else
            # Use ImageTransformations.imresize for high-quality resizing
            resized_img = imresize(source_img, (height, width))
        end
        
        save(output_path, resized_img)
        println("  ✓ [$current/$total_icons] Created $filename ($(width)×$(height))")
    end
    
    # Generate wide tiles
    println("Generating wide tile variants...")
    for (filename, width, height) in wide_specs
        current += 1
        output_path = joinpath(output_dir, filename)
        wide_img = create_wide_tile(source_img, width, height)
        save(output_path, wide_img)
        println("  ✓ [$current/$total_icons] Created $filename ($(width)×$(height))")
    end
    
    println("\nAll $total_icons icons generated successfully in '$output_dir' directory!")
    
    # Print summary
    println("\nGenerated icon categories:")
    println("  • BadgeLogo: 5 variants")
    println("  • SplashScreen: 5 variants") 
    println("  • Square150x150Logo: 5 variants")
    println("  • Square30x30Logo: 1 variant")
    println("  • Square310x310Logo: 5 variants (+ 5 duplicates as Logo1)")
    println("  • Square44x44Logo: 5 scale + 15 targetsize variants")
    println("  • Square70x70Logo: 1 variant")
    println("  • Square71x71Logo: 5 variants")
    println("  • StoreLogo: 1 variant")
    println("  • Wide310x150Logo: 5 variants")
end

"""
Create a splash screen by centering the icon on a background.
"""
function create_splash_screen(source_img, target_width::Int, target_height::Int)
    icon_size = div(target_height, 4)
    resized_icon = imresize(source_img, (icon_size, icon_size))
    
    # Create background with Windows blue theme
    background_color = RGBA{Float32}(0.01, 0.45, 0.78, 1.0)  # Windows blue
    splash_img = fill(background_color, target_height, target_width)
    
    # Calculate center position
    start_row = div(target_height - icon_size, 2) + 1
    start_col = div(target_width - icon_size, 2) + 1
    
    # Convert resized icon to RGBA if needed and place it
    resized_rgba = RGBA.(resized_icon)
    splash_img[start_row:start_row+icon_size-1, start_col:start_col+icon_size-1] = resized_rgba
    
    return splash_img
end

"""
Create a wide tile by centering the icon on a transparent background.
"""
function create_wide_tile(source_img, target_width::Int, target_height::Int)
    icon_size = Int(round(target_height * 0.6))
    resized_icon = imresize(source_img, (icon_size, icon_size))
    
    # Create transparent background
    background_color = RGBA{Float32}(0.0, 0.0, 0.0, 0.0)  # Transparent
    wide_img = fill(background_color, target_height, target_width)
    
    # Calculate center position
    start_row = div(target_height - icon_size, 2) + 1
    start_col = div(target_width - icon_size, 2) + 1
    
    # Convert resized icon to RGBA if needed and place it
    resized_rgba = RGBA.(resized_icon)
    wide_img[start_row:start_row+icon_size-1, start_col:start_col+icon_size-1] = resized_rgba
    
    return wide_img
end

"""
Generate basic icons with minimal dependencies.
"""
function generate_basic_app_icons(source_path::String, output_dir::String="assets"; use_bilinear::Bool=true)
    mkpath(output_dir)
    source_img = load(source_path)
    
    resize_func = use_bilinear ? bilinear_resize : simple_resize
    
    basic_specs = [
        ("Square44x44Logo.png", 44, 44),
        ("Square71x71Logo.png", 71, 71),
        ("Square150x150Logo.png", 150, 150),
        ("Square310x310Logo.png", 310, 310),
        ("Wide310x150Logo.png", 310, 150),
        ("logo.png", 512, 512),
    ]
    
    println("Generating basic icon set...")
    for (filename, width, height) in basic_specs
        output_path = joinpath(output_dir, filename)
        if width == height
            resized_img = resize_func(source_img, (height, width))
        else
            resized_img = create_wide_tile(source_img, width, height, resize_func)
        end
        save(output_path, resized_img)
        println("  ✓ Created $filename ($(width)×$(height))")
    end
end

end

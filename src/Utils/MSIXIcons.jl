module MSIXIcons

using Images, FileIO, ImageTransformations

"""
Generate all required icons for Windows App Package from a single source icon.
This creates the complete set of icons including all scale factors and target sizes.
"""
function generate_app_icons(source_path::String, output_dir::String)
    # Create output directory if it doesn't exist
    mkpath(output_dir)
    
    # Load the source image
    println("Loading source image: $source_path")
    source_img = load(source_path)
    
    # Define all the icon specifications based on your file listing
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
        
        # Square310x310Logo1 variants (duplicates for some reason)
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
    
    # Wide logo variants (need special handling for rectangular aspect ratio)
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
            # Create splash screen with icon centered on transparent/colored background
            resized_img = create_splash_screen(source_img, width, height)
        else
            # Regular square resize
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
    
    # Print summary by category
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
For splash screens, we typically want the icon smaller and centered.
"""
function create_splash_screen(source_img, target_width::Int, target_height::Int)
    # Make the icon take up about 1/4 of the splash screen height
    icon_size = div(target_height, 4)
    
    # Resize the source icon
    resized_icon = imresize(source_img, (icon_size, icon_size))
    
    # Create background - you can customize this color
    # Using a subtle background color or transparent
    if eltype(source_img) <: RGB
        background_color = RGBA{Float32}(0.01, 0.45, 0.78, 1.0)  # Windows blue theme
        splash_img = fill(background_color, target_height, target_width)
        resized_rgba = RGBA.(resized_icon)
    else
        background_color = RGBA{Float32}(0.01, 0.45, 0.78, 1.0)
        splash_img = fill(background_color, target_height, target_width)
        resized_rgba = resized_icon
    end
    
    # Calculate position to center the icon
    start_row = div(target_height - icon_size, 2) + 1
    start_col = div(target_width - icon_size, 2) + 1
    
    # Place the resized icon in the center
    splash_img[start_row:start_row+icon_size-1, start_col:start_col+icon_size-1] = resized_rgba
    
    return splash_img
end

"""
Create a wide tile by centering the icon on a transparent or colored background.
"""
function create_wide_tile(source_img, target_width::Int, target_height::Int)
    # For wide tiles, make the icon fit nicely within the height
    icon_size = Int(round(target_height * 0.6))  # 60% of height
    
    # Resize the source icon to be square
    resized_icon = imresize(source_img, (icon_size, icon_size))
    
    # Create transparent background
    if eltype(source_img) <: RGB
        background_color = RGBA{Float32}(0.0, 0.0, 0.0, 0.0)  # Transparent
        wide_img = fill(background_color, target_height, target_width)
        resized_rgba = RGBA.(resized_icon)
    else
        background_color = RGBA{Float32}(0.0, 0.0, 0.0, 0.0)
        wide_img = fill(background_color, target_height, target_width)
        resized_rgba = resized_icon
    end
    
    # Calculate position to center the icon
    start_row = div(target_height - icon_size, 2) + 1
    start_col = div(target_width - icon_size, 2) + 1
    
    # Place the resized icon in the center
    wide_img[start_row:start_row+icon_size-1, start_col:start_col+icon_size-1] = resized_rgba
    
    return wide_img
end

"""
Helper function to generate just the basic icons needed for AppxManifest.xml
if you don't need all the scale variants.
"""
function generate_basic_app_icons(source_path::String, output_dir::String="assets")
    mkpath(output_dir)
    source_img = load(source_path)
    
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
            resized_img = imresize(source_img, (height, width))
        else
            # Wide tile
            resized_img = create_wide_tile(source_img, width, height)
        end
        save(output_path, resized_img)
        println("  ✓ Created $filename ($(width)×$(height))")
    end
end

end

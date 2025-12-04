# AppEnv.jl

A Julia package for instantiating the environment in bundled/distributed Julia applications. AppEnv.jl configures Julia's load paths, depot paths, and package origins to ensure your application runs correctly when packaged as MSIX (Windows), DMG (macOS), or Snap (Linux).

## Purpose

When distributing Julia applications as standalone bundles, the standard Julia environment needs reconfiguration. AppEnv.jl handles this automatically, managing platform-specific sandboxing requirements and ensuring proper module loading.

## Usage

Call `AppEnv.init()` at the start of your application:
```julia
using AppEnv

AppEnv.init()
```

When no arguments are passed, AppEnv uses its default parameters that are baked in during compilation from environment variables or reads them from the environment at runtime. The following environment variables are available:

- **`RUNTIME_MODE`** - Sets the runtime mode: `INTERACTIVE` (default), `MIN`, `COMPILATION`, or `SANDBOX`
- **`MODULE_NAME`** - Name of your main application module (default: `MainEnv`)
- **`APP_NAME`** - Application name, required for `SANDBOX` mode
- **`BUNDLE_IDENTIFIER`** - Bundle identifier (e.g., `com.example.myapp`), required for `SANDBOX` mode
- **`USER_DATA`** - Custom path for user data directory (overrides platform defaults)
- **`STDLIB`** - Relative path to the standard library location (default: relative path from Julia binary to stdlib)

These variables can be set either at compilation time (baked into either sysimage or pkgimage) or at runtime before calling `init()`.

## User Data Directory

After initialization, access the user data directory via:
```julia
AppEnv.USER_DATA
```

This provides a persistent location for storing application data, respecting platform conventions and sandboxing requirements. The location can be customized by setting the `USER_DATA` environment variable before calling `init()`.

## Example
```julia
module MyApp

using AppEnv

function (@main)(ARGS)
    AppEnv.init()
    
    # Use the user data directory
    config_file = joinpath(AppEnv.USER_DATA, "config.toml")
    println("Config location: ", config_file)
end

export main

end # module
```

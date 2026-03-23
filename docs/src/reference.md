# Reference

AppBundler is structured around two methods `stage` that stages the specified artifiact into destinations and `bundle` that performs bundling of compilation product into bundles. The API is fairly simple to use manually:
```
spec = JuliaImgBundle(project; kwargs...)
```
which specifies that the bundle is to be created from the project located at `app_dir` and kwargs specify varios overrides for the defauts. 

The product specification can be staged manually in platform agnostic way via `stage(spec, destination; platform = HostPlatform())` where the platform denotes the target platofrm for which the artifact is staged. It is possible to stage the artifact accross platofrms as long as one does not need to compile it by setting `precompile=false` and `sysimg_packages = []`. The result of staging `spec` is a julia image that contains all project dependencies.

An alternative application staging strategy is with JuliaC. That can be accomplished with:
```
spec = JuliaCBundle(project; kwargs...)
```
This one can be staged sthe same platform agnostic way via `stage(spec, destination)` where the platform here is fixed to the host platform fixed by `juliac` platform in the path. 

To deploy thoose applications we can bundle them into `DMG`, `MSIX` and `Snap` formats. The bundles can be instantiated with:
```
dmg = DMG(project; arch = Sys.ARCH, kwargs...)
```
where from the project it reads out overrides that shall be used from the `project/meta/dmg` directory. The bundle format also contains arhitecture information where the resoning behind that is that the bundle spec decides the destination platform. 

The bundle can be staged in an application direcotory as `stage(dmg, destination)` which creates a an bundle directory structure before it is being compressed where application is staged. The main API however is through the bundle methods, being:
```
bundle(dmg; password = "") do app_stage
    # install application in the app_stage
end
```
where the password is the certifacte password `dmg.pfx_cert` that is used to decrypt the ceritifactae and perform codesigning. This API can be used agnostically packageing also non-julia applications given that the user takes care of building the code project themselves. 

The `bundle` API is then abstracted on top with method:
```
bundle(spec, dmg, destination; password = "")
```
which is specilaized on each bundle type in this case `JuliaImgBundle` and `JuliaCBundle`. This function is one that is exposed to the command line API where command line parameters simply configure the `spec` and `dmg` fields. 

## Types
```@docs
AppBundler.DMG
AppBundler.MSIX
AppBundler.Snap
AppBundler.JuliaImgBundle
AppBundler.JuliaCBundle
```

## Functions

```@autodocs
Modules = [AppBundler]
Order = [:function]
Public  = true
Private = false
```

```@docs
AppBundler.stage(::AppBundler.JuliaImg.JuliaImgBundle, ::String)
```

# AppBundler.jl

![](docs/assets/appbundler.png)

From the dawn of time the software developers have been concerned about distribution of the their software. At the begining executables distributed over floppy disks were sufficient. However as time progressed we needed nicer installers, integrations with the desktop launching nad uninstalling and hence installers were born. As time progressed the hard lessons were learnt that acess to all system resources is a security nightmare and sandboxing of what applications had been intriduced in all major operating systems.

Every operating system is different and had made unique design choices. On MacOS applications are simply put within the applications folder from a dmg containers. Windows uses many formats with MSIX one being most modern approach and Linux uses Snap and Flatpak for external software distribution. To create installler in each of thoose platforms there are a list of common task that one needs to perform individually:

- Make icon assets in a form that installer/operating systems understands
- Specify the needed capabilities for the application
- Setting launching endpooint whether it is a GUI or a terminal application
- Bundle all configutation files with appplication into installer 
- Do a codesigning of the installer and possibly application

Maintaining all theese configuration nuances is hard. AppBundler resolves theese issues with defaults that enable to ship GUI appplication effortlessly while also enables for the developer to simply configure the installer with their own configuration overlay in places where they need it making the process much earier to debug and communicate about. 

The AppBundler in contrast to other solution is only using open source tools for making the installers that are available accross platforms and are compiled in cross platform way with Julia BinaryBuilder infrastructure. This makes it easy to see what sources were used in making the installers, maintain them and be sure they don't contain malware as you can reproduce the binaries yourself. The most important reason though to use the open source tools is that they can be bundled with the AppBundler project in reproducable way accrooss all operating systems that can be installed in reproducable accross all platforms way as a simple Julia package.


> I could have DMG, MSIX, Snap format app bundle formats. That could contain locations for configuration sources transparently.

`pfx_cert, pfx_passwd`


> Setup could be a post processing
```
DMG(
    icon = ...;
    config = ...; # Info.plist
    entitlements = ...;
    main_redirect = true|false # platform specified at build
    pfx_cert = nothing;
    #notary = nothing;
)

#nothing|:x86_64|:aarch64 # perhaps it would be better to take it from parameters
```

```
Snap(
    icon = ...;
    config = ...; # snap.yaml
    launcher = ...; app_name.desktop
)
```

```
MSIX(
    icon = ...; # set to nothing if you want to create the icon on your own
    config = ...; AppxManifest.xml
    installer_config = ...; 
    resources_pri = ...;
    pfx_cert = nothing;
    path_length_threshold::Int = 260;
    skip_long_paths::Bool = false;
)
```
The usage of theese installer formats is as simple as:
```
    build(destination[, appformat], compress = true|false|:lzma,  pfx_password = "", parameters = ...) do bundle
        # Add your application files here
    end
```

```
    build(MSIX(), dest, compress = true|false|:lzma, pfx_password = "", parameters = ..., platform = :x86_64) do

    end


    build(MSIX(dest=...), dest, compress = true|false|:lzma, pfx_password = "", parameters = ...) do

    end

```



The problem here is that appformat is refering to specific files. Furthermore parameters apply the template which may be a better suited here. 



Something like `MSIX(overlay)` may be an interesting alternative I could explore `MSIX(overlay)` and `MSIX()`. One can then do `MSIX(overlay; icon = ...)` or `MSIX(icon = ...)` which is most of the things that one may wish to have in practice with defaults provided from the setup. 

`MSIX(overlay)` is the one where it is used as an overlay that sets the default variables and MSIX() would be with defaults only. 

Perhaps source can override the configuration files. If one wants to configure appformat one can do so with `MSIX(origin, overlay)` to initialize the desired format. One can specify `appformat = :msix|:snap|:dmg` and compress false when needed. 


```
PkgImage

SysImage

Trim
```



```
    build(product::Union{PkgImage, SysImage, Trim}, destination[, appformat], compress = true|false|:lzma, pfx_cert = ..., pfx_password = ...)
```




### Old Docs



`AppBundler.jl` offers recipes for building Julia GUI applications in modern desktop application installer formats. It uses Snap for Linux, MSIX for Windows, and DMG for MacOS as targets. It bundles full Julia within the app, which, together with artifact caching stored in scratch space, allows the bundling to be done quickly, significantly shortening the feedback loop.

The build product of `AppBundler.jl` is a bundle that can be conveniently finalised with a shell script on the corresponding host system without an internet connection. This allows me to avoid maintaining multiple Julia installations for different hosts and reduces failures due to a misconfigured system state. It is ideal for a Virtualbox setup where the bundle together with bundling script is sent over SSH after which the finalised installer is retrieved.

The configuration options for each installer bundle vary greatly and are virtually limitless; thus, creating a single bundling configuration file for all systems is impractical. To resolve this, the AppBundler recipie system comes into the picture. AppBundler provides default configuration files which substitute a few set variables specified at the `Project.toml` in a dedicated `[bundle]` section. This shall cover plenty of use cases. In case the application needs more control, like interfacing web camera, speaker, host network server, etc., the user can place a custom `snap.yaml`, `AppxManifest.xml` and `Entitlements.plist` in the application `meta` folder, overloading the defaults. Additional files can be provided easily for the bundle by placing them in a corresponding folder hierarchy. For instance, this can be useful for providing custom-sized icon sizes. To see how that works, explore [AppBundler.jl/examples](https://github.com/PeaceFounder/AppBundler.jl/tree/main/examples) and [PeaceFounderClient](https://github.com/PeaceFounder/PeaceFounderClient/releases/tag/v0.0.2) where you can check out the releases page to see what one can expect.

All recipes define a `USER_DATA` environment variable where apps can store their data. On Linux and Windows those are designated application locations which get removed with the uninstallation of the app, whereas on MacOS, apps use `~/.config/myapp` and `~/.cache/myapp` folders unless one manages to get an app running from a sandbox in which case the `$HOME/Library/Application Support/Local` folder will be used.

Thought has also been put into improving the precompilation experience to reduce start-up time for the first run. For MacOS, precompilation can be done before bundling in the `/Applications` folder by running `MyApp.app/Contents/MacOS/precompile`. For Linux, precompilation is hooked into the snap `configure` hook executed after installation. For Windows, a splash screen is shown during the first run, providing user feedback that something is happening. Hopefully, the cache relocability fix in Julia 1.11 will allow us to precompile the Windows bundle as well.

## Usage

AppBundler expects an application folder which contains `main.jl`, `Project.toml` and `Manifest.toml`. The application entry point is the `main.jl,` which allows starting the application with `julia --project=. main.jl` from the project directory. A `Project.toml` contains many adjustable template variables under a `[bundle]` section. The configuration of the `bundle` sits in a `meta` folder from where files take precedence over the AppBunlder `recepies` folder. Thus, it is straightforward to copy a template from the recipes folder, modify and place it in the `meta` folder if the default configuration does not suffice. See the `examples` folder to see ways to configure. 

A bundle can be created with `AppBundler.build_app` function as follows:

```julia
import AppBundler
import Pkg.BinaryPlatforms: Linux, MacOS, Windows
AppBundler.build_app(MacOS(:x86_64), "MyApp", "build/MyApp-x64.app")
```

The first argument is a platform for which the bundle is being made; in this case, MacOS; `MyApp` is the location for the project, and `build/MyApp-x64.app` is the location where the bundles will be stored. If extension `.snap`, `.msix`, `.dmg` is detected for corepsonding platform the full application installer is created. This behaviour can be overriden by `compress=false` in the keyword arguments. 

The resulting bundles can be easily tested on the resulting platforms. The testing phase works without any postprocessing as follows:

- **MacOS:** Double-click on the resulting app bundle to open the application. 
- **Linux:** the snap can be installed from a command line `snap install --classic --dangerous app.snap`
- **Windows:** the bundle can be tried from the application directory with the PowerShell command  `Add-AppPackage -register AppxManifest.xml`

The precompilation is enabled automatically but will error if not done on host system. Hence `precompile=false` shall be used when host platform differs from the target platform. All AppBundler functionality is available on POSIX systems. On Windows only MSIX bundling is available.

## Platform Specific Instructions

### MacOS

MacOS bundling has been fully automated with the `build_app` function, which handles bundling, precompilation, code signing, and DMG creation in one step:

```julia
import AppBundler
import Pkg.BinaryPlatforms: MacOS

# Create a .app bundle
AppBundler.build_app(MacOS(:x86_64), "MyApp", "build/MyApp.app")

# Create a .dmg installer with automatic LZMA compression
AppBundler.build_app(MacOS(:x86_64), "MyApp", "build/MyApp.dmg")
```
The function automatically detects whether to create a DMG based on the destination file extension. For code signing, the function looks for a certificate at `MyApp/meta/macos/certificate.pfx` and uses the `MACOS_PFX_PASSWORD` environment variable for the password if available.

For custom DMG appearance, you can provide: A custom DS_Store file at `MyApp/meta/macos/DS_Store`, or A `DS_Store` configuration in TOML format at `MyApp/meta/macos/DS_Store.toml` Custom entitlements can be specified at `MyApp/meta/macos/Entitlements.plist`. 

The precompilation is is enabled by default and errors if it can not be performed on the host system. For cross-platform building, you can disable precompilation with the `precompile=false` option. In future, Julia may implement crosss compilation which would make this option redundant.

The signing certificate can be obtained from Apple by subscribing to its developer program. Alternatively, for development purposes, you can generate a self-signing certificate. One time signing certificate is generated automatically if `MyApp/meta/macos/certificate.pfx` file is not found. For convinience `AppBundler` also offers ability to generate self signing certificate via:

```julia
import AppBundler
AppBundler.generate_macos_signing_certificate("$appdir/meta"; person_name = "JanisErdmanis", country = "LV")
```
which will generate a certificate at `$appdir/meta/macos/certificate.pfx` and print out generated password.

### Linux

1. If the application is compressed into the snap, use `unsquashfs myapp.snap`
2. Run precompilation with `myapp/bin/precompile,` which will create `myapp/lib/compiled` 
3. Squash the folder back into a snap with the command `mksquashfs myapp myapp.snap -noappend -comp xz`

For snap, it is also worth mentioning the `snap try myapp` command, which allows one to install an application without squashing. There is also `snap run --shell myapp`, which is a valuable command for entering into the snap confinement shell. 

### Windows

Windows bundling has been fully automated with `build_app` function which handles bundling, precompilation, code signing, and DMG creation in one step:

```julia
import AppBundler
import Pkg.BinaryPlatforms: Windows

# Create a MSIX structured directory
AppBundler.build_app(Windows(:x86_64), "MyApp", "build/MyApp")

# Create a MSIX installer 
AppBundler.build_app(Windows(:x86_64), "MyApp", "build/MyApp.msix")
```
The function automatically detects whether to create a MSIX installer by destination extension. For code signing, the function looks for a certificate at `MyApp/meta/windows/certificate.pfx` and uses the `WINDOWS_PFX_PASSWORD` environment variable for the password if available.

The precompilation is is enabled by default and errors if it can not be performed on the host system. For cross-platform building, you can disable precompilation with the `precompile=false` option. In future, Julia may implement crosss compilation which would make this option redundant.

A legitimate signing certificate can be obtained from various sources. Alternatively, for development purposes, you can generate a self-signing certificate. One time signing certificate is generated automatically if `MyApp/meta/windows/certificate.pfx` file is not found. For convinience `AppBundler` also offers ability to generate self signing certificate via:

```julia
import AppBundler
AppBundler.generate_windows_signing_certificate("$appdir/meta"; person_name = "JanisErdmanis", country = "LV")
```
which will generate a certificate at `$appdir/meta/windows/certificate.pfx` and print out generated password.

#### Legacy approach

Previously the AppBundler reliead on manual postprocessing that should be done on the Windows host system. Theese steps can still be performed manually on the host by bundling application directory using `build_app(Windows(:x86_64), appdir, "build/staging_dir")` where destination would be a bundled in MSIX directory structure. This shall only be necessary in case of debugging purposes when `AppBundler.MSIXPack.pack2msix` that wraps `makemsix` and `opensslsigncode` is suspected to have a bug.

For Windows, one has to install `MakeAppx`, `SignTool`, and `EditBin` installed with WindowsSDK. Installation of Windows SDK fails. Thus, one needs to install Visual Studio Code, adding a few more gigabytes to download and install. For those who run Windows from Parallels, don't run the `Add-Package -register AppxManifest.xml` from a network drive, but copy the files to the home directory instead, as otherwise, Julia crashes. Also, running an executable from installation location `C:\ProgramFiles\WindowsApps\<app folder>` with admin privileges will run the application within the containerised environment specified with `AppxManifest.xml`. 

**Generation of Self-Signing Certificate**

It must be signed to test and install the `.msix` bundle on the Windows S platform. We can do that with self-signing, where the certificate is added to the system's store. An alternative is to exit from `Windows S` and enable side loading under developer tools, which is only available after buying the Windows license. The procedure here should be easily adaptable with a codesigning certificate from a trusted provider. 

A self-signing certificate can be made from a PowerShell with the following command:

```powershell
New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=YourName" -KeyAlgorithm RSA -KeyLength 2048 -CertStoreLocation "Cert:\CurrentUser\My" -FriendlyName "YourCertificateName"
```

The critical part is `CN=YourName`, which must match the `Publisher` entry in `AppxManifest.xml` for the package to be correctly signed.  The output generates a thumbprint for the certificate, which you place in the following command, which will create your private key signed with the certificate:

```
Export-PfxCertificate -cert "Cert:\CurrentUser\My\[Thumbprint]" -FilePath JanisErdmanis.pfx -Password (ConvertTo-SecureString -String "YourPassword" -Force -AsPlainText)
```

which generates a pfx certificate and adds password protection. 

**Bundling Procedure for MSIX**

After installation of Visual Studio Code, find the relevant tools (best to do that with Windows Finder) and either add them to a path or make an alias like:

```powershell
New-Alias -Name makeappx -Value "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\MakeAppx.exe"
New-Alias -Name signtool -Value "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
New-Alias -Name editbin -Value "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.37.32822\bin\Hostx64\x64\editbin.exe"
```

1. If the bundle is compressed, unzip it.
2. Run the precompilation script `myapp\julia\bin\julia.exe --startup-file=no --eval="__precompile__()"` which will generate `myapp\compiled` 
3. Set `julia.exe` to be Windows application `editbin /SUBSYSTEM:WINDOWS myapp\julia\bin\julia.exe` so the console is not shown when the app is run.
4. Make a bundle `makeappx pack /d myapp /p myapp.msix`
5. Sign the bundle `signtool sign /fd SHA256 /a /f JanisErdmanis.pfx /p "PASSWORD" myapp.msix`

When self-signed, the resulting bundle can not immediately be installed as the certificate is not binding to the trusted anchors of the system. This can be resolved by installing the certificate to the system from the MSIX package itself, which is described in https://www.advancedinstaller.com/install-test-certificate-from-msix.html


## Acknowledgments

This work is supported by the European Union in the Next Generation Internet initiative ([NGI0 Entrust](https://ngi.eu/ngi-projects/ngi-zero-entrust/)), via NLnet [Julia-AppBundler](https://nlnet.nl/project/Julia-AppBundler/) project.

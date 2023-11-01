# AppBundler.jl

Bundling a Julia application by hand is a hassle, as running a program assumes an environment stored in `.julia`. So, one needs to bundle it together while ensuring that other environment dependencies are not included and set the environment variables to make the application bundle immutable when running. 

Another issue is that after forming, the application bundle can be distributed in commonly used packager formats, which offer security from containerisation and a convenient uninstallation procedure where all application and user data is guaranteed not to affect the system on which it is being run. Each package format has nuances that must be resolved when Julia applications are being run.

Julia, as for now, has a limitation in that it cannot cross-compile its compilation cache for other operating system platforms. It would be unacceptable for a user to wait a few minutes without any indication of action being taken. Thus, one needs to ensure at least one of the steps:

- During the first start of the application, a splash screen is shown when precompilation is running.
- Precompile the software on the destination platform and put that in the bundle.
- Use post-installation scripts like snap configure hook that allows precompilation when the application is installed.

Programming splash screen needs to be done at a very low level to avoid precompilation delay. Ideally, one would use ModernGL exclusively, which does not add any new binary dependencies for GUI applications and is thus cheap to use. Currently, a `GLAbstraction` is used, which unfortunately does have a significant cold start. To reduce that, the splash screen is started with `julia --compiled-modules=no --compile=min`. After the splash screen is run, one needs to ensure that the application has not lost its desktop icon, for instance. 

Currently, precompilation can be done only on the destination platform, and thus, one needs to finish the bundles on these platforms, which one would nevertheless do when signing them. Thus, those platforms would need some final packaging/polishing scripts. The AppBundler includes a `precompilation` script which already sets relevant environment variables and can be run without environment variables. On top of that, there is no need for an internet connection when one does precompilation, which increases reliability and makes it possible to set up your Windows box for the time to come, reducing maintenance burden. 

On top of that, AppBundler is concerned with making bundles fast, allowing swift debugging and identification of issues. This is supported by caching all downloaded artifacts into AppBundler scratch space, and Julia programs do not need to be compiled in a traditional sense. Also, AppBundler recognises the need to customise many aspects of the bundle, which the user can do by providing overriding templates in the application `meta` directory. 

AppBundler targets all desktop platforms and architectures using modern package bundle formats. On macOS `.app`, for Linux `.snap` and Windows `.msix` bundles are made. That can provide opportunities to be distributed in corresponding marketplaces, offer security guarantees for the user and provide designated places for user data. However, for that, one needs to figure out a way to run GUI apps in snap confinement without `fullTrust` capability on Windows, and it is yet to be seen what happens if an application is sandboxed on macOS. 

## Usage

App bundler expects an application folder which contains `main.jl`, `Project.toml` and `Manifest.toml`. The application entry point is the `main.jl,` which allows starting the application with `julia --project=. main.jl` from the project directory. A `Project.toml` contains many adjustable template variables under a `[bundle]` section. The configuration of the `bundle` sits in a `meta` folder from where files take precedence over the AppBunlder `templates` folder. Thus, it is straightforward to copy a template from the templates folder, modify and place it in the `meta` folder if the default configuration does not suffice. See the `examples` folder to see ways to configure. 

A bundle can be created with `AppBundler.bundle_app` function as follows:

```julia
import AppBundler
import Pkg.BinaryPlatforms: Linux, MacOS, Windows
bundle_app(MacOS(:x86_64), APP_DIR, "$BUILD_DIR/gtkapp-x64.app")
```

The first argument is a platform for which the bundle is being made; in this case, MacOS; the second `APP_DIR` is the location for the project, and lastly, `BUILD_DIR` is the location where the bundles will be stored. For Linux, the extension `.snap` and Windows `.zip` for destination determines whether the output is compressed, which can be overridden by `compress=false` in the keyword arguments. 

The resulting bundles can be easily tested on the resulting platforms, for instance, it opens the application and works as expected. The testing phase works without any postprocessing as follows:

- **MacOS:** Double-click on the resulting app bundle to open the application. 
- **Linux:** the snap can be installed from a command line `snap install --classic --dangerous app.snap`
- **Windows:** the bundle can be tried from the application directory with the PowerShell command  `Add-AppPackage -register AppxManifest.xml`

Note that you will face difficulties when using `AppBundler` from Windows for Linux, macOS and other UNIX operating systems, as Windows does not have a concept of execution bit. By hand, you could set `chmod +x` to every executable on the resulting platform. Technically, this can be resolved by directly bundling files into a tar archive and processing the incoming archives without extraction, but this will not happen. Thus, it is better to use WSL when bundling for other platforms on Windows.

## Post Processing

After the bundle is created, it needs to be finalised on the host system, where precompilation and usually bundle signing must be performed.

### MacOS

1. Precompilation can be done `myapp.app/Contents/MacOS/precompile`, which will generate a compilation cache in `myapp.app/Contents/Frameworks/compiled` folder.
2. Code signing can be performed with `codesign` (untested)
3. Creation of compressed archive `.dmg` can be done with `create-dmg` (untested)

### Linux

1. If the application is compressed into the snap, use `unsquashfs myapp.snap`
2. Run precompilation with `myapp/bin/precompile,` which will create `myapp/lib/compiled` 
3. Squash the folder back into a snap with the command `mksquashfs myapp myapp.snap -noappend -comp xz`

For snap, it is also worth mentioning the `snap try myapp` command, which allows one to install an application without squashing. There is also `snap run --shell myapp`, which is a valuable command for entering into the snap confinement shell. 

### Windows

For Windows, one has to install `makappx`, `signtool`, and `editbin` installed with WindowsSDK. Installation of Windows SDK fails. Thus, one needs to install Visual Studio Code, adding a few more gigabytes to download and install. For those who run Windows from Parallels, don't run the `Add-Package -register AppxManifest.xml` from a network drive, but copy the files to the home directory instead, as otherwise, Julia crashes. Also, running an executable from installation location `C:\ProgramFiles\WindowsApps\<app folder>` with admin privileges will run the application within the containerised environment specified with `AppxManifest.xml`. 

**Generation of Self-Signing Certificate**

It must be signed to test and install the `.msix` bundle on the Windows S platform. We can do that with self-signing, where the certificate is added to the system's store. An alternative is to exit from `Windows S` and enable side loading under developer tools, which is only available after buying the Windows license. The procedure here should be easily adaptable with a codesigning certificate from a trusted provider. 

A self-signing certificate can be made from a PowerShell with the following command:

```powershell
New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=YourName" -KeyAlgorithm RSA -KeyLength 2048 -CertStoreLocation "Cert:\CurrentUser\My" -FriendlyName "YourCertificateName"
```

The critical part is `CN=YourName`, which must match the `Publisher` entry in `AppxManifest.xml` for the package to be correctly signed.  The output generates a thumbprint for the certificate, which you place in the following command, which will create your private key signed with the certificate:

```
Export-PfxCertificate -cert "Cert:\CurrentUser\My\[Thumbprint]" -FilePath mykey.pfx -Password (ConvertTo-SecureString -String "YourPassword" -Force -AsPlainText)
```

which generates a pfx certificate and adds password protection. 

**Bundling Procedure for MSIX**

After installation of Visual Studio Code, find the relevant tools (best to do that with Windows Finder) and either add them to a path or make an alias like:

```powershell
New-Alias -Name makeappx -Value "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\makeappx.exe"
New-Alias -Name signtool -Value "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
New-Alias -Name editbin -Value "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.37.32822\bin\Hostx64\x64\editbin.exe"
```

1. If the bundle is compressed, unzip it.
2. Run the precompilation script `myapp\precompile.ps1` which will generate `myapp\compiled` 
3. Set `julia.exe` to be Windows application `editbin /SUBSYSTEM:WINDOWS myapp\julia\bin\julia.exe` so the console is not shown when the app is run.
4. Make a bundle `makeappx pack /d myapp /p myapp.msix`
5. Sign the bundle `signtool sign /fd SHA256 /a /f mykey.pfx /p "PASSWORD" myapp.msix`

When self-signed, the resulting bundle can not immediately be installed as the certificate is not binding to the trusted anchors of the system. This can be resolved by installing the certificate to the system from the MSIX package itself, which is described in https://www.advancedinstaller.com/install-test-certificate-from-msix.html

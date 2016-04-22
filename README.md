### Introduction
A PackageManagement provider to discover, install and inventory windows server app packages. 

### Supported Platforms
Currently, the provider is supported on Nano Server Only

### Cmdlets
```
Find-AppxPackage [[-Name] <string[]>] [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Architecture <string>] [-ResourceId <string>] [-Source <string[]>] [<CommonParameters>]

```
### How to Install
```powershell
Install-PackageProvider -Name WSAProvider -Source <Source>
Import-PackageProvider WSAProvider
```
List all installed Providers
```powershell
Get-PackageProvider
```

### How to use
Register a package source for WSA packages. It can either be a local folder or a network share
```powershell
Register-PackageSource -ProviderName WSAProvider -Name WSAPackageSource -Location <WSAPackageLocation>
```
Discover available Appx Packages
```powershell
Find-Package -ProviderName WSAProvider -source <WSAPackageSource>
```
or
```powershell
Find-AppxPackage -Source <WSAPackageSource>
```
Install wsa package
```powershell
Install-Package -ProviderName WSAProvider -Name <WSAPackage.appx>
```
Get list of installed packages
```powershell
Get-Package -ProviderName WSAProvider
```

UnInstall wsa Package
```powershell
 UnInstall-Package -Name <WSAPackage> -ProviderName WSAProvider
```

### More examples
Register local package source
```powershell
 Register-PackageSource -Name Local -ProviderName WSAProvider -Location C:\temp\
 ```
Register network share as package source
```powershell
 New-PSDrive -Name Z -PSProvider FileSystem -Root \\Mydevbox2\WSAPackages -Credential mytestuser
 Register-PackageSource -Name dev2 -ProviderName WSAProvider -Location Z:\
```
Find wsa packages from all registered sources
```powershell
	Find-Package -ProviderName WSAProvider
```
Find wsa package with the given name(with or without extension)
```powershell	
	Find-Package -ProviderName WSAProvider -Name TestPackage
	Find-Package -ProviderName WSAProvider -Name TestPackage.appx
```
Find wsa packages with given Resource Id
```powershell	
	Find-Package -ProviderName WSAProvider -ResourceId NorthAmerica
```
Find wsa packages with given Architecture
```powershell	
	Find-Package -ProviderName WSAProvider -Architecture x64
```	
Find wsa package that have the given version
```powershell	
	Find-Package -ProviderName WSAProvider -RequiredVersion 1.4.0.0 -Name TestPackage.appx
```
Installing wsa package with the given name(with or without extension)
```powershell	
	Install-Package -providername WSAProvider -Name testpackage
	Install-Package -providername WSAProvider -Name testpackage.appx
```	
Install wsa package that have the given version
```powershell 
	Install-Package -Name TestPackage.appx -requiredVersion 1.4.0.0 -Source Local
```	
Install all the results of find
```powershell	
	Find-package -ProviderName WSAProvider | Install-Package
```
Save the latest version of wsa package to the directory that matches the LiteralPath
```powershell	
	Save-Package -ProviderName WSAProvider -Name TestPackage -LiteralPath C:\temp\
```	
All results of the find will be saved in the given LiteralPath
```powershell	
 Find-AppxPackage | Save-Package -LiteralPath C:\temp\
```

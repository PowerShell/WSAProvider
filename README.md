### Introduction
A PackageManagement provider to discover, install and inventory Windows Server App (WSA) packages. WSA is an APPX based installer for Windows Server. It is the only installer available on Nano Server.  For more information on WSA, please read this <a href="http://blogs.technet.com/b/nanoserver/archive/2015/11/18/installing-windows-server-apps-on-nano-server.aspx">blog</a>.

### Supported Platforms
Currently, the provider is supported on Nano Server Only

### Cmdlets
Module introduces Find-AppxPackage cmdlet
```powershell
Find-AppxPackage [[-Name] <string[]>] [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Architecture <string>] [-ResourceId <string>] [-Source <string[]>] [<CommonParameters>]
```
It also supports following PackageManagement cmdlets
```powershell
Find-Package
Get-Package
Install-Package
Save-Package
Uninstall-Package
Register-PackageSource
UnRegister-PackageSource
Get-PackageSource
Set-PackageSource
```

### How to Install
```powershell
Install-PackageProvider -Name WSAProvider 
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
Discover available WSA Packages. Wildcard is supported for the WSA package name.
```powershell
Find-Package -Provider WSAProvider 
```
or
```powershell
Find-AppxPackage
```
Install WSA package. Pipeline from find-package is supported.
```powershell
Install-Package -ProviderName WSAProvider -Name <WSAPackageName>
```
Get list of installed packages
```powershell
Get-Package -ProviderName WSAProvider
```

UnInstall WSA Package
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
Find WSA packages from a specific source
```powershell
	Find-Package -ProviderName WSAProvider -Source dev2
```
Find WSA package with the given name(with or without extension)
```powershell	
	Find-Package -ProviderName WSAProvider -Name TestPackage
	Find-Package -ProviderName WSAProvider -Name TestPackage.appx
	Find-Package -source dev2 -name TestP*
```
Find WSA packages with given Resource Id
```powershell	
	Find-Package -ProviderName WSAProvider -ResourceId NorthAmerica
```
Find WSA packages with given Architecture
```powershell	
	Find-Package -ProviderName WSAProvider -Architecture x64
```	
Find WSA package that have the given version
```powershell	
	Find-Package -ProviderName WSAProvider -RequiredVersion 1.4.0.0 -Name TestPackage.appx
```
Installing WSA package with the given name(with or without extension)
```powershell	
	Install-Package -providername WSAProvider -Name testpackage
	Install-Package -providername WSAProvider -Name testpackage.appx
```	
Install WSA package that have the given version
```powershell 
	Install-Package -Name TestPackage.appx -requiredVersion 1.4.0.0 -Source Local
```	
Install all the WSA package from the search result
```powershell	
	Find-package -ProviderName WSAProvider | Install-Package
```
Save the latest version of WSA package to the directory that matches the LiteralPath
```powershell	
	Save-Package -ProviderName WSAProvider -Name TestPackage -LiteralPath C:\temp\
```	
All results of the find will be saved in the given LiteralPath
```powershell	
 Find-AppxPackage | Save-Package -LiteralPath C:\temp\
```

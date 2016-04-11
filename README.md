# Introduction

A PackageManagement provider to discover, install and inventory appx based packages. 

Supported Platforms
======================
Currently, the provider is supported on Nano Server Only

Cmdlets
======================
```
Find-AppxPackage [[-Name] <string[]>] [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Architecture <string>] [-ResourceId <string>] [-Source <string[]>] [<CommonParameters>]

```

How to Install
======================

```powershell
Install-PackageProvider -Name AppxProvider -Source <Source>
Import-PackageProvider AppxProvider
```

List all installed Providers
```powershell
Get-PackageProvider
```

How to use
======================
Register a package source for appx packages. It can either be a local folder or a network share

```powershell
Register-PackageSource -ProviderName appxProvider -Name AppxPackageSource -Location <AppxPackageLocation>
```

Discover available Appx Packages
```powershell
Find-Package -ProviderName AppxProvider -source <AppxPackageSource>
```
or
```powershell
Find-AppxPackage -Source <AppxPackageSource>
```

Install appx package
```powershell
Install-Package -ProviderName AppxProvider -Name <AppxPackage.appx>
```

Get list of installed packages
```powershell
Get-Package -ProviderName AppxProvider
```

UnInstall appx Package
```powershell
 UnInstall-Package -Name <AppxPackage> -ProviderName AppxProvider
```

#########################################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
#
# Appx Provider Module
#
#########################################################################################

$script:ProviderName = "AppxProvider"
$script:AppxPackageExtension = ".appx"
$script:AppxManifestFile = "AppxManifest.xml"
$script:AppxPkgZipFile = "AppxPkg.zip"
$script:Architecture = "Architecture"
$script:ResourceId = "ResourceId"
$script:AppxPackageSources = $null
$script:AppxLocalPath="$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\AppxProvider"
$script:AppxPackageSourcesFilePath = Microsoft.PowerShell.Management\Join-Path -Path $script:AppxLocalPath -ChildPath "AppxPackageSources.xml"
$Script:ResponseUri = "ResponseUri"
$Script:StatusCode = "StatusCode"
# Wildcard pattern matching configuration.
$script:wildcardOptions = [System.Management.Automation.WildcardOptions]::CultureInvariant -bor `
                          [System.Management.Automation.WildcardOptions]::IgnoreCase
#Localized Data
Microsoft.PowerShell.Utility\Import-LocalizedData  LocalizedData -filename AppxProvider.Resource.psd1
$script:isNanoServer = $null -ne ('System.Runtime.Loader.AssemblyLoadContext' -as [Type])



if(-not($script:isNanoServer))
{
    throw 'AppxProvider is only supported on nano server'
}


function Find-AppxPackage 
{
    <#
    .ExternalHelp PSGet.psm1-help.xml
    #>    
    [outputtype("PSCustomObject[]")]
    Param
    (
        [Parameter(ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Name,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [Version]
        $MinimumVersion,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [Version]
        $MaximumVersion,
        
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [Version]
        $RequiredVersion,
                
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Architecture,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ResourceId,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Source
    )

    Begin
    {
    }

    Process
    {   
        $PSBoundParameters["ProviderName"] = $script:ProviderName         
        PackageManagement\Find-Package @PSBoundParameters 
    }
}

#region Appx Provider APIs Implementation
function Get-PackageProviderName
{ 
    return $script:ProviderName
}

function Initialize-Provider{ 
  param(
  )
}

function Get-DynamicOptions
{
    param
    (
        [Microsoft.PackageManagement.MetaProvider.PowerShell.OptionCategory] 
        $category
    )

    Write-Debug ($LocalizedData.ProviderApiDebugMessage -f ('Get-DynamicOptions'))
               
    switch($category)
    {
        Install {
                    Write-Output -InputObject (New-DynamicOption -Category $category -Name Architecture -ExpectedType String -IsRequired $false)
                    Write-Output -InputObject (New-DynamicOption -Category $category -Name ResourceId -ExpectedType String -IsRequired $false)
                }
        Package {
                    Write-Output -InputObject (New-DynamicOption -Category $category -Name Architecture -ExpectedType String -IsRequired $false)
                    Write-Output -InputObject (New-DynamicOption -Category $category -Name ResourceId -ExpectedType String -IsRequired $false)
                }
    }
}

function Find-Package
{ 
    [CmdletBinding()]
    param
    (
        [string[]]
        $names,

        [Version]
        $requiredVersion,

        [Version]
        $minimumVersion,

        [Version]
        $maximumVersion
    )   

    Write-Debug ($LocalizedData.ProviderApiDebugMessage -f ('Find-Package'))    

    $ResourceId = $null
    $Architecture = $null
    $Sources = @()    
    $streamedResults = @()    
    $namesParameterEmpty = (-not $names) -or (($names.Count -eq 1) -and ($names[0] -eq ''))

    Set-PackageSourcesVariable

    if($RequiredVersion -and $MinimumVersion)
    {

        ThrowError -ExceptionName "System.ArgumentException" `
                   -ExceptionMessage $LocalizedData.VersionRangeAndRequiredVersionCannotBeSpecifiedTogether `
                   -ErrorId "VersionRangeAndRequiredVersionCannotBeSpecifiedTogether" `
                   -CallerPSCmdlet $PSCmdlet `
                   -ErrorCategory InvalidArgument
    }    
    if($RequiredVersion -or $MinimumVersion)
    {
        if(-not $names -or $names.Count -ne 1 -or (Test-WildcardPattern -Name $names[0]))
        {
            ThrowError -ExceptionName "System.ArgumentException" `
                       -ExceptionMessage $LocalizedData.VersionParametersAreAllowedOnlyWithSinglePackage `
                       -ErrorId "VersionParametersAreAllowedOnlyWithSinglePackage" `
                       -CallerPSCmdlet $PSCmdlet `
                       -ErrorCategory InvalidArgument
        }
    }    

    $options = $request.Options            
    if($options)
    {
        foreach( $o in $options.Keys )
        {
            Write-Debug ( "OPTION: {0} => {1}" -f ($o, $options[$o]) )
        }

        if($options.ContainsKey('Source'))
        {        
            $SourceNames = $($options['Source'])
            Write-Verbose ($LocalizedData.SpecifiedSourceName -f ($SourceNames))        
            foreach($sourceName in $SourceNames)
            {            
                if($script:AppxPackageSources.Contains($sourceName))
                {
                    $Sources += $script:AppxPackageSources[$sourceName]                
                }
                else
                {
                    $sourceByLocation = Get-SourceName -Location $sourceName
                    if ($sourceByLocation -ne $null)
                    {
                        $Sources += $script:AppxPackageSources[$sourceByLocation]                                        
                    }
                    else
                    {
                            $message = $LocalizedData.PackageSourceNotFound -f ($sourceName)
                            ThrowError -ExceptionName "System.ArgumentException" `
                                -ExceptionMessage $message `
                                -ErrorId "PackageSourceNotFound" `
                                -CallerPSCmdlet $PSCmdlet `
                                -ErrorCategory InvalidArgument `
                                -ExceptionObject $sourceName
                    }
                }
            }
        }
        else
        {
            Write-Verbose $LocalizedData.NoSourceNameIsSpecified        
            $script:AppxPackageSources.Values | Microsoft.PowerShell.Core\ForEach-Object { $Sources += $_ }
        }        

        if($options.ContainsKey($script:Architecture))
        {
            $Architecture = $options[$script:Architecture]     
        }
        if($options.ContainsKey($script:ResourceId))
        {
            $ResourceId = $options[$script:ResourceId]
        }
    }             
        
    #allow searching for package with packagename and packagename.appx extension
    $pkgNames = @()
    if(-not($namesParameterEmpty))
    {        
        foreach($name in $names)
        {            
            if(-not($name.EndsWith(".appx")))
            {
                $pkgNames += ($name+".appx")
            }
            else
            {
                $pkgNames+=$name
            }
        }
    }
    
    foreach($source in $Sources)
    {
        $location = $source.SourceLocation
        if($request.IsCanceled)
        {
            return
        }
        if(-not(Test-Path $location))
        {
            $message = $LocalizedData.PathNotFound -f ($Location)
            Write-Verbose $message            
            continue
        }

        $packages = Get-AppxPackagesFromPath -path $location   
           
        foreach($pkg in  $packages)
        {
            if($request.IsCanceled)
            {
                return
            }
            
            $pkgName = $pkg.Name
            $pkgManifest = Get-PackageManfiestData -PackageFullPath $pkg.FullName
            if(-not $pkgManifest)
            {               
                continue            
            }

            # $pkgName has to match any of the supplied names, using PowerShell wildcards
            if(-not($namesParameterEmpty))
            {
                if(-not(($pkgNames | Microsoft.PowerShell.Core\ForEach-Object {if ($pkgName -like $_){return $true; break} } -End {return $false})))
                {
                    continue
                }
            }

            # Version            
            if($RequiredVersion)
            {
                if($RequiredVersion -ne $pkgManifest.Version)
                {
                    continue
                }
            }                

            if($minimumVersion)
            {

                if(-not($pkgManifest.Version -ge $minimumVersion))
                {
                    continue
                }
            }             

            if($maximumVersion)
            {
                if(-not($pkgManifest.Version -le $maximumVersion))
                {
                    continue
                }                
            }             
              
            if($Architecture)
            {                
                $wildcardPattern = New-Object System.Management.Automation.WildcardPattern $Architecture, $script:wildcardOptions
                if(-not($wildcardPattern.IsMatch($pkgManifest.Architecture)))
                {
                    continue
                }                
            }                        
            if($ResourceId)
            {                
                $wildcardPattern = New-Object System.Management.Automation.WildcardPattern $ResourceId, $script:wildcardOptions
                if(-not($wildcardPattern.IsMatch($pkgManifest.ResourceId)))
                {
                    continue
                }                
            }           
            $sid = New-SoftwareIdentityPackageManifestData -PackageManifest $pkgManifest -Source $source.Name -pkgName $pkgName
            $fastPackageReference = $sid.fastPackageReference            
            if($streamedResults -notcontains $fastPackageReference)
            {
                $streamedResults += $fastPackageReference
                Write-Output -InputObject $sid
            }
        }
    }
}

function Get-InstalledPackage
{ 
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string]
        $Name,

        [Parameter()]
        [string]
        $RequiredVersion,

        [Parameter()]
        [string]
        $MinimumVersion,

        [Parameter()]
        [string]
        $MaximumVersion
    )

    Write-Debug -Message ($LocalizedData.ProviderApiDebugMessage -f ('Get-InstalledPackage'))
    
    $Architecture = $null
    $ResourceId = $null

    $options = $request.Options
    if($options)
    {
        if($options.ContainsKey($script:Architecture))
        {
            $Architecture = $options[$script:Architecture]
        }
        if($options.ContainsKey($script:ResourceId))
        {
            $ResourceId = $options[$script:ResourceId]
        }
    }

    $params = @{}
    if($Name)
    {
        $params.Add("Name", $Name)
    }
    $packages = Appx\Get-AppxPackage @params

	foreach($package in $packages)
	{
        if($RequiredVersion)
        {
            if($RequiredVersion -ne $package.Version)
            {
                continue
            }
        }
        else
        {
            if(-not((-not $MinimumVersion -or ($MinimumVersion -le $package.Version)) -and 
                    (-not $MaximumVersion -or ($MaximumVersion -ge $package.Version))))
            {
                continue
            }
        }

        if($Architecture)
        {            
            $wildcardPattern = New-Object System.Management.Automation.WildcardPattern $Architecture, $script:wildcardOptions
            if(-not($wildcardPattern.IsMatch($package.Architecture)))
            {
                continue
            }                
        }
        if($ResourceId)
        {            
            $wildcardPattern = New-Object System.Management.Automation.WildcardPattern $ResourceId,$script:wildcardOptions
            if(-not($wildcardPattern.IsMatch($package.ResourceId)))                
            {
                continue
            }
        }        
		$sid = New-SoftwareIdentityFromPackage -Package $package
        write-Output $sid
	}
}

function Install-Package
{ 
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $fastPackageReference
    )

    Write-Debug -Message ($LocalizedData.ProviderApiDebugMessage -f ('Install-Package'))
    Write-Debug -Message ($LocalizedData.FastPackageReference -f $fastPackageReference)
	
	Appx\Add-AppxPackage -Path $fastPackageReference
}

function Download-Package
{ 
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FastPackageReference,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Location
    )
        
    Write-Debug -Message ($LocalizedData.ProviderApiDebugMessage -f ('Download-Package'))
    Write-Debug -Message ($LocalizedData.FastPackageReference -f $fastPackageReference)    

    $copyItemSuccedded = Copy-Item -Path $FastPackageReference -Destination $Location -PassThru
    if($copyItemSuccedded)
    {
        $pkgManifest = Get-PackageManfiestData -PackageFullPath $FastPackageReference
        $sid = New-SoftwareIdentityPackageManifestData -PackageManifest $pkgManifest -pkgName (Get-Item $FastPackageReference).Name
        Write-Output -InputObject $sid
    }
}


function UnInstall-Package
{ 
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $fastPackageReference
    )

    Write-Debug -Message ($LocalizedData.ProviderApiDebugMessage -f ('Uninstall-Package'))
    Write-Debug -Message ($LocalizedData.FastPackageReference -f $fastPackageReference)

	Appx\Remove-AppxPackage -Package $fastPackageReference
}

function Add-PackageSource
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name,
         
        [string]
        $Location,

        [bool]
        $Trusted
    )     
    
    Write-Debug ($LocalizedData.ProviderApiDebugMessage -f ('Add-PackageSource'))

    Set-PackageSourcesVariable -Force

    if(-not (Microsoft.PowerShell.Management\Test-Path $Location) -and
       -not (Test-WebUri -uri $Location))
    {
        $LocationUri = [Uri]$Location
        if($LocationUri.Scheme -eq 'file')
        {
            $message = $LocalizedData.PathNotFound -f ($Location)
            ThrowError -ExceptionName "System.ArgumentException" `
                       -ExceptionMessage $message `
                       -ErrorId "PathNotFound" `
                       -CallerPSCmdlet $PSCmdlet `
                       -ErrorCategory InvalidArgument `
                       -ExceptionObject $Location
        }
        else
        {
            $message = $LocalizedData.InvalidWebUri -f ($Location, "Location")
            ThrowError -ExceptionName "System.ArgumentException" `
                       -ExceptionMessage $message `
                       -ErrorId "InvalidWebUri" `
                       -CallerPSCmdlet $PSCmdlet `
                       -ErrorCategory InvalidArgument `
                       -ExceptionObject $Location
        }
    }

    if(Test-WildcardPattern $Name)
    {
        $message = $LocalizedData.PackageSourceNameContainsWildCards -f ($Name)
        ThrowError -ExceptionName "System.ArgumentException" `
                    -ExceptionMessage $message `
                    -ErrorId "PackageSourceNameContainsWildCards" `
                    -CallerPSCmdlet $PSCmdlet `
                    -ErrorCategory InvalidArgument `
                    -ExceptionObject $Name
    }

    $LocationString = Get-ValidPackageLocation -LocationString $Location -ParameterName "Location"
           
    # Check if Location is already registered with another Name
    $existingSourceName = Get-SourceName -Location $LocationString

    if($existingSourceName -and 
       ($Name -ne $existingSourceName))
    {
        $message = $LocalizedData.PackageSourceAlreadyRegistered -f ($existingSourceName, $Location, $Name)
        ThrowError -ExceptionName "System.ArgumentException" `
                   -ExceptionMessage $message `
                   -ErrorId "PackageSourceAlreadyRegistered" `
                   -CallerPSCmdlet $PSCmdlet `
                   -ErrorCategory InvalidArgument
    }
        
    # Check if Name is already registered
    if($script:AppxPackageSources.Contains($Name))
    {
        $currentSourceObject = $script:AppxPackageSources[$Name]
        $null = $script:AppxPackageSources.Remove($Name)
    }
  
    # Add new package source
    $packageSource = Microsoft.PowerShell.Utility\New-Object PSCustomObject -Property ([ordered]@{
            Name = $Name
            SourceLocation = $LocationString
            Trusted=$Trusted
            Registered= $true
        })    

    $script:AppxPackageSources.Add($Name, $packageSource)
    $message = $LocalizedData.SourceRegistered -f ($Name, $LocationString)
    Write-Verbose $message

    # Persist the package sources
    Save-PackageSources

    # return the package source object.
    Write-Output -InputObject (New-PackageSourceFromSource -Source $packageSource)

}

function Resolve-PackageSource
{ 
    Write-Debug ($LocalizedData.ProviderApiDebugMessage -f ('Resolve-PackageSource'))

    Set-PackageSourcesVariable

    $SourceName = $request.PackageSources

    if(-not $SourceName)
    {
        $SourceName = "*"
    }

    foreach($src in $SourceName)
    {
        if($request.IsCanceled)
        {
            return
        }

        $wildcardPattern = New-Object System.Management.Automation.WildcardPattern $src,$script:wildcardOptions
        $sourceFound = $false

        $script:AppxPackageSources.GetEnumerator() | 
            Microsoft.PowerShell.Core\Where-Object {$wildcardPattern.IsMatch($_.Key)} | 
                Microsoft.PowerShell.Core\ForEach-Object {
                    $source = $script:AppxPackageSources[$_.Key]
                    $packageSource = New-PackageSourceFromSource -Source $source
                    Write-Output -InputObject $packageSource
                    $sourceFound = $true
                }

        if(-not $sourceFound)
        {
            $sourceName  = Get-SourceName -Location $src
            if($sourceName)
            {
                $source = $script:AppxPackageSources[$sourceName]
                $packageSource = New-PackageSourceFromSource -Source $source
                Write-Output -InputObject $packageSource
            }
            elseif( -not (Test-WildcardPattern $src))
            {
                $message = $LocalizedData.PackageSourceNotFound -f ($src)
                Write-Error -Message $message -ErrorId "PackageSourceNotFound" -Category InvalidOperation -TargetObject $src
            }
        }
    }
}

function Remove-PackageSource
{ 
    param
    (
        [string]
        $Name
    )

    Write-Debug ($LocalizedData.ProviderApiDebugMessage -f ('Remove-PackageSource'))

    Set-PackageSourcesVariable -Force

    $SourcesToBeRemoved = @()

    foreach ($sourceName in $Name)
    {
        if($request.IsCanceled)
        {
            return
        }

        # Check if $Name contains any wildcards
        if(Test-WildcardPattern $sourceName)
        {
            $message = $LocalizedData.PackageSourceNameContainsWildCards -f ($sourceName)
            Write-Error -Message $message -ErrorId "PackageSourceNameContainsWildCards" -Category InvalidOperation -TargetObject $sourceName
            continue
        }

        # Check if the specified package source name is in the registered package sources
        if(-not $script:AppxPackageSources.Contains($sourceName))
        {
            $message = $LocalizedData.PackageSourceNotFound -f ($sourceName)
            Write-Error -Message $message -ErrorId "PackageSourceNotFound" -Category InvalidOperation -TargetObject $sourceName
            continue
        }

        $SourcesToBeRemoved += $sourceName
        $message = $LocalizedData.PackageSourceUnregistered -f ($sourceName)
        Write-Verbose $message
    }

    # Remove the SourcesToBeRemoved
    $SourcesToBeRemoved | Microsoft.PowerShell.Core\ForEach-Object { $null = $script:AppxPackageSources.Remove($_) }

    # Persist the package sources
    Save-PackageSources
}
#endregion

#region Common functions

function Get-AppxPackagesFromPath
{
    param
    (
        [Parameter(Mandatory=$true)]
        $Path
    )

    $filterAppxPackages = "*"+$script:AppxPackageExtension
    $packages = Get-ChildItem -path $Path -filter $filterAppxPackages

    return $packages

}


function ZipFileApisAvailable
{
    $ZipFileApisAvailable = $false
    try 
    {
        [System.IO.Compression.ZipFile]
        $ZipFileApisAvailable = $true
    } 
    catch 
    {
    }
    return $ZipFileApisAvailable
}

function Expand-ZIPFile($file, $destination)
{
    try
    {
        if(-not(Test-Path $destination))
        {
            New-Item -ItemType directory -Path $Destination
        } 
        if(ZipFileApisAvailable)
        {         
            [System.IO.Compression.ZipFile]::ExtractToDirectory($file, $destination)
            return true
        }
        else
        {      
            Copy-Item -Path $file -Destination "$destination\$script:AppxPkgZipFile" -Force
            $shell = new-object -com shell.application
            $zip = $shell.NameSpace("$destination\$script:AppxPkgZipFile")
            foreach($item in $zip.items())
            {
                if($item.Path -eq "$destination\$script:AppxPkgZipFile\$script:AppxManifestFile")
                {
                    $shell.Namespace($destination).copyhere($item)
                }
            }
            return $true
        }
    }
    catch
    {
        return $false
    }
}

function Get-PackageManfiestData
{
    param
    (
        [Parameter(Mandatory=$true)]
        $PackageFullPath
    )        
    $guid = [System.Guid]::NewGuid().toString()    
    $destination = "$env:TEMP\$guid"
    Expand-ZIPFile -file $PackageFullPath -destination $destination
    [xml] $packageManifest = Get-Content "$destination\$script:AppxManifestFile" -ErrorAction SilentlyContinue    
    if($packageManifest)
    {
        $Identity = $packageManifest.Package.Identity   
        $manifestData = new-object psobject -Property @{pkgName=$Identity.Name; Architecture=$Identity.ProcessorArchitecture; Publisher=$Identity.Publisher; Version=$Identity.Version; ResourceId=$Identity.resourceId; PackageFullName=$PackageFullPath}
        Remove-Item -Path "$env:TEMP\$guid" -Recurse -Force -ErrorAction SilentlyContinue
        return $manifestData
    }
    else
    {        
        Write-Verbose ($LocalizedData.MetaDataExtractionFailed -f ($PackageFullPath) )
    }
    return $null    
}

function New-FastPackageReference
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]
        $PackageFullName
    )
    return "$PackageFullName"
}

function New-SoftwareIdentityPackageManifestData
{
    param
    (
        [Parameter(Mandatory=$true)]
        $PackageManifest,

        [string]
        $Source,

        [Parameter(Mandatory=$true)]
        $pkgName

    )        
    $fastPackageReference = New-FastPackageReference -PackageFullName $PackageManifest.PackageFullName    
    if(-not($Source))
    {
        $Source = $PackageManifest.Publisher
    }    

    $details =  @{
                    Publisher = $PackageManifest.Publisher
                    Architecture = $PackageManifest.Architecture
                    ResourceId = $PackageManifest.ResourceId
                    PackageFullName = $PackageManifest.PackageFullName
                    PackageName = $PackageManifest.pkgName
                 }

    $params = @{    
                FastPackageReference = $fastPackageReference;
                Name = $pkgName;
                Version = $PackageManifest.Version;
                versionScheme  = "MultiPartNumeric";
                Source = $source;
                Details = $details;
    }
    
    $sid = New-SoftwareIdentity @params
    return $sid       
}


function New-SoftwareIdentityFromPackage
{
    param
    (
        [Parameter(Mandatory=$true)]
        $Package,

        [string]
        $Source

    )    
    $fastPackageReference = New-FastPackageReference -PackageFullName $Package.PackageFullName                                         
    if(-not($Source))
    {
        $Source = $Package.Publisher
    }    
    $details =  @{
                    Publisher = $Package.Publisher
                    Architecture = $Package.Architecture
                    ResourceId = $Package.ResourceId
                    PackageFullName = $Package.PackageFullName
                 }

    $params = @{    
                FastPackageReference = $fastPackageReference;
                Name = $Package.Name;
                Version = $Package.Version;
                versionScheme  = "MultiPartNumeric";
                Source = $source;
                Details = $details;
    }
    
    $sid = New-SoftwareIdentity @params
    return $sid       
}

function Test-WebUri
{
    [CmdletBinding()]
    [OutputType([bool])]
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Uri]
        $uri
    )

    return ($uri.AbsoluteURI -ne $null) -and ($uri.Scheme -match '[http|https]')
}

function Test-WildcardPattern
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Name
    )

    return [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Name)    
}

function DeSerialize-PSObject
{
    [CmdletBinding(PositionalBinding=$false)]    
    Param
    (
        [Parameter(Mandatory=$true)]        
        $Path
    )
    $filecontent = Microsoft.PowerShell.Management\Get-Content -Path $Path
    [System.Management.Automation.PSSerializer]::Deserialize($filecontent)    
}

function Get-SourceName
{
    [CmdletBinding()]
    [OutputType("string")]
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Location
    )

    Set-PackageSourcesVariable

    foreach($source in $script:AppxPackageSources.Values)
    {
        if($source.SourceLocation -eq $Location)
        {
            return $source.Name
        }
    }
}

function WebRequestApisAvailable
{
    $webRequestApiAvailable = $false
    try 
    {
        [System.Net.WebRequest]
        $webRequestApiAvailable = $true
    } 
    catch 
    {
    }
    return $webRequestApiAvailable
}

function Ping-Endpoint
{
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Endpoint
    )   
        
    $results = @{}

    if(WebRequestApisAvailable)
    {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::Create()
        $iss.types.clear()
        $iss.formats.clear()
        $iss.LanguageMode = "FullLanguage"

        $WebRequestcmd =  @'
            try
            {{
                $request = [System.Net.WebRequest]::Create("{0}")
                $request.Method = 'GET'
                $request.Timeout = 30000
                $response = [System.Net.HttpWebResponse]$request.GetResponse()             
                $response
                $response.Close()
            }}
            catch [System.Net.WebException]
            {{
                "Error:System.Net.WebException"
            }} 
'@ -f $EndPoint

        $ps = [powershell]::Create($iss).AddScript($WebRequestcmd)
        $response = $ps.Invoke()
        $ps.dispose()

        if ($response -ne "Error:System.Net.WebException")
        {
            $results.Add($Script:ResponseUri,$response.ResponseUri.ToString())
            $results.Add($Script:StatusCode,$response.StatusCode.value__)
        }        
    }
    else
    {
        $response = $null
        try
        {
            $httpClient = New-Object 'System.Net.Http.HttpClient'
            $response = $httpclient.GetAsync($endpoint)          
        }
        catch
        {            
        } 

        if ($response -ne $null -and $response.result -ne $null)
        {        
            $results.Add($Script:ResponseUri,$response.Result.RequestMessage.RequestUri.AbsoluteUri.ToString())
            $results.Add($Script:StatusCode,$response.result.StatusCode.value__)            
        }
    }
    return $results
}

function Get-ValidPackageLocation
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $LocationString,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ParameterName
    )

    # Get the actual Uri from the Location
    if(-not (Microsoft.PowerShell.Management\Test-Path $LocationString))
    {
        $results = Ping-Endpoint -Endpoint $LocationString
    
        if ($results.ContainsKey("Exception"))
        {
            $Exception = $results["Exception"]
            if($Exception)
            {
                $message = $LocalizedData.InvalidWebUri -f ($LocationString, $ParameterName)
                ThrowError -ExceptionName "System.ArgumentException" `
                            -ExceptionMessage $message `
                            -ErrorId "InvalidWebUri" `
                            -ExceptionObject $Exception `
                            -CallerPSCmdlet $PSCmdlet `
                            -ErrorCategory InvalidArgument
            }
        }

        if ($results.ContainsKey("ResponseUri"))
        {
            $LocationString = $results["ResponseUri"]
        }
    }

    return $LocationString
}

function Set-PackageSourcesVariable
{
    param([switch]$Force)

    if(-not $script:AppxPackageSources -or $Force)
    {
        if(Microsoft.PowerShell.Management\Test-Path $script:AppxPackageSourcesFilePath)
        {
            $script:AppxPackageSources = DeSerialize-PSObject -Path $script:AppxPackageSourcesFilePath
        }
        else
        {
            $script:AppxPackageSources = [ordered]@{}
        }
    }   
}

function Save-PackageSources
{
    if($script:AppxPackageSources)
    {
        if(-not (Microsoft.PowerShell.Management\Test-Path $script:AppxLocalPath))
        {
            $null = Microsoft.PowerShell.Management\New-Item -Path $script:AppxLocalPath `
                                                             -ItemType Directory -Force `
                                                             -ErrorAction SilentlyContinue `
                                                             -WarningAction SilentlyContinue `
                                                             -Confirm:$false -WhatIf:$false
        }        
        Microsoft.PowerShell.Utility\Out-File -FilePath $script:AppxPackageSourcesFilePath -Force -InputObject ([System.Management.Automation.PSSerializer]::Serialize($script:AppxPackageSources))
   }   
}

function New-PackageSourceFromSource
{
    param
    (
        [Parameter(Mandatory)]
        $Source
    )
     
    # create a new package source
    $src =  New-PackageSource -Name $Source.Name `
                              -Location $Source.SourceLocation `
                              -Trusted $Source.Trusted `
                              -Registered $Source.Registered `

    Write-Verbose ( $LocalizedData.PackageSourceDetails -f ($src.Name, $src.Location, $src.IsTrusted, $src.IsRegistered) )

    # return the package source object.
    Write-Output -InputObject $src
}
#endregion

# Utility to throw an errorrecord
function ThrowError
{
    param
    (        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCmdlet]
        $CallerPSCmdlet,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]        
        $ExceptionName,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ExceptionMessage,
        
        [System.Object]
        $ExceptionObject,
        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorCategory]
        $ErrorCategory
    )
          
    $exception = New-Object $ExceptionName $ExceptionMessage;
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $ErrorId, $ErrorCategory, $ExceptionObject    
    $CallerPSCmdlet.ThrowTerminatingError($errorRecord)    
}
#endregion

Export-ModuleMember -Function  Find-AppxPackage , `
                              Find-Package, `
                              Install-Package, `
                              Download-Package, `
                              Uninstall-Package, `
                              Get-InstalledPackage, `
                              Remove-PackageSource, `
                              Resolve-PackageSource, `
                              Add-PackageSource, `
                              Get-DynamicOptions, `
                              Initialize-Provider, `
                              Get-PackageProviderName
# SIG # Begin signature block
# MIIargYJKoZIhvcNAQcCoIIanzCCGpsCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUrDXiagT5OJQGMM1KLUgckZy6
# Hg+gghWBMIIEwjCCA6qgAwIBAgITMwAAAJJMoq9VJwgudQAAAAAAkjANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTUxMDA3MTgxNDE0
# WhcNMTcwMTA3MTgxNDE0WjCBsjELMAkGA1UEBhMCVVMxEjAQBgNVBAgTCVdhc2lu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046
# N0QyRS0zNzgyLUIwRjcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNl
# cnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC6WVT9G7wUxF8u
# /fnFTnid7MCYX4X58613PUnaf2uYaz291cpmbxNeEsx+HZ8xrgjCHkMC3U9rTUfl
# oyhWqlW3ZdZQdn97Qa++X7wXa/ybE8FeY0Qphe8K0w9hbhxRjbII4fInEEkM4GAd
# HLqPqQw+U+Ul/gAC8U64SnklxtsjxN2faP98po9YqDYGH/IGaej0Y9ojGA2aEpVh
# J6n3TezIbXNZDBZW1ODKX1W0OmKPNvTdGqFYAHCr6osCrVLyg4ROozoI9GnsvjC7
# f9ACbPJf6Xy1B2v0teYREkUmpqc+OC/rZpApjgtL2Y5ymgeuihuSUj/XaKNtDa0Z
# ERONWgyLAgMBAAGjggEJMIIBBTAdBgNVHQ4EFgQUBsPfWqqHee6gVxN8Wohmb0CT
# pgMwHwYDVR0jBBgwFoAUIzT42VJGcArtQPt2+7MrsMM1sw8wVAYDVR0fBE0wSzBJ
# oEegRYZDaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljcm9zb2Z0VGltZVN0YW1wUENBLmNybDBYBggrBgEFBQcBAQRMMEowSAYIKwYB
# BQUHMAKGPGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0VGltZVN0YW1wUENBLmNydDATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG
# 9w0BAQUFAAOCAQEAjgD2Z96da+Ze+YXIxGUX2pvvvX2etiR572Kwk6j6aXOFJrbB
# FaNelpipwJCRAY/V9qLIqUh+KfQFBKQYlRBf50WrCcXz+sx0BxyG597HjjGCmL4o
# Y0j/F0KATLMw60EcOh2I1hotO1a1W5fHB661OxD+T5KC6D9JN9TTP8vxap080i/V
# uNKyr2QubnfuOvs7jTjDJP5l5ZUEAFcxuliihARHhKnyoWxWcvje/fI463+pmRhF
# /nBuA3jTiCC5DWI3vST9I0l/BwrVDVMwvvnn5xf0vHb1U3TrJVeo2VRpHsqsoCA0
# 35Vuya6u01jEDkKhrZHuuMnxTAgCVuIFeXh9xDCCBOwwggPUoAMCAQICEzMAAAEK
# LHmu13l7pqwAAQAAAQowDQYJKoZIhvcNAQEFBQAweTELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEjMCEGA1UEAxMaTWljcm9zb2Z0IENvZGUgU2ln
# bmluZyBQQ0EwHhcNMTUwNjA0MTc0MjQ1WhcNMTYwOTA0MTc0MjQ1WjCBgzELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9QUjEe
# MBwGA1UEAxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAkvxvNrvhA7ko1kbRomG6pUb7YxY+LvlH0sfs7ceZsSZR
# db3azA8GFBGkbBmewF9NVInkTVDYjc2hYaV3E5ocp+0NdPenVnnoKPdT0rF6Y+D1
# lJe37NlH+Gw98yWIs7wKxQSnjnyFSHYcYUaqGcR6YovBwjWq+1hvxWMLk0kwgRt7
# 3398T7RHbV94HK+295YTUu+50U055XPeSE48FKqXDTnMi1HhXNE78I5n6jBgqU1a
# nUO92yO6wA/XSxCdnE3wUaKEquScpz3Wo+8KGEio+rFOpZgOS7/wFPMAyLBI1lv+
# ONeJES0FukMCTyIAliWtfTVuhGirIBg4KP4cohCxpQIDAQABo4IBYDCCAVwwEwYD
# VR0lBAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYEFIn+CjHqJs3mbceRkbmUjKIYYTc0
# MFEGA1UdEQRKMEikRjBEMQ0wCwYDVQQLEwRNT1BSMTMwMQYDVQQFEyozMTU5NSsw
# NDA3OTM1MC0xNmZhLTRjNjAtYjZiZi05ZDJiMWNkMDU5ODQwHwYDVR0jBBgwFoAU
# yxHoytK0FlgByTcuMxYWuUyaCh8wVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljQ29kU2lnUENBXzA4
# LTMxLTIwMTAuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNDb2RTaWdQQ0FfMDgtMzEt
# MjAxMC5jcnQwDQYJKoZIhvcNAQEFBQADggEBAKaoU5HfOwH+YV0GWutm8AzY99mE
# 0wBRDhDRpNEXKOeMMzgr2EPGA4t16zOS9KniZ/0C26UdTkNFXRtJ4+BPFvB+j/CI
# EcqCraT7pqlf9ZdgyHvEv3ybae0fgsHxzY54S2L11w0c11MS1pZS7zW9GY6gQJOh
# CqUtFpzCRnQI69v02KVJNlQSEVUDs3sW+0f++2j8wEVc4j8SeTOi74LF3kAZB+4V
# xQqbWQVBqdCXnoGeA1v8SuMaLgWsUEcvjPp52B4g+AX7KWsYFPpyBLcLp5pk7BFd
# T0VJjSkaLfvQtglTXzSU4BbEuepzNehX7+HrFsMYxwazO89hhOK2RImUo4YwggW8
# MIIDpKADAgECAgphMyYaAAAAAAAxMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJ
# k/IsZAEZFgNjb20xGTAXBgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMT
# JE1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0xMDA4MzEy
# MjE5MzJaFw0yMDA4MzEyMjI5MzJaMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENB
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsnJZXBkwZL8dmmAgIEKZ
# dlNsPhvWb8zL8epr/pcWEODfOnSDGrcvoDLs/97CQk4j1XIA2zVXConKriBJ9PBo
# rE1LjaW9eUtxm0cH2v0l3511iM+qc0R/14Hb873yNqTJXEXcr6094CholxqnpXJz
# VvEXlOT9NZRyoNZ2Xx53RYOFOBbQc1sFumdSjaWyaS/aGQv+knQp4nYvVN0UMFn4
# 0o1i/cvJX0YxULknE+RAMM9yKRAoIsc3Tj2gMj2QzaE4BoVcTlaCKCoFMrdL109j
# 59ItYvFFPeesCAD2RqGe0VuMJlPoeqpK8kbPNzw4nrR3XKUXno3LEY9WPMGsCV8D
# 0wIDAQABo4IBXjCCAVowDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUyxHoytK0
# FlgByTcuMxYWuUyaCh8wCwYDVR0PBAQDAgGGMBIGCSsGAQQBgjcVAQQFAgMBAAEw
# IwYJKwYBBAGCNxUCBBYEFP3RMU7TJoqV4ZhgO6gxb6Y8vNgtMBkGCSsGAQQBgjcU
# AgQMHgoAUwB1AGIAQwBBMB8GA1UdIwQYMBaAFA6sgmBAVieX5SUT/CrhClOVWeSk
# MFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
# Y3JsL3Byb2R1Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRI
# MEYwRAYIKwYBBQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljcm9zb2Z0Um9vdENlcnQuY3J0MA0GCSqGSIb3DQEBBQUAA4ICAQBZOT5/
# Jkav629AsTK1ausOL26oSffrX3XtTDst10OtC/7L6S0xoyPMfFCYgCFdrD0vTLqi
# qFac43C7uLT4ebVJcvc+6kF/yuEMF2nLpZwgLfoLUMRWzS3jStK8cOeoDaIDpVbg
# uIpLV/KVQpzx8+/u44YfNDy4VprwUyOFKqSCHJPilAcd8uJO+IyhyugTpZFOyBvS
# j3KVKnFtmxr4HPBT1mfMIv9cHc2ijL0nsnljVkSiUc356aNYVt2bAkVEL1/02q7U
# gjJu/KSVE+Traeepoiy+yCsQDmWOmdv1ovoSJgllOJTxeh9Ku9HhVujQeJYYXMk1
# Fl/dkx1Jji2+rTREHO4QFRoAXd01WyHOmMcJ7oUOjE9tDhNOPXwpSJxy0fNsysHs
# cKNXkld9lI2gG0gDWvfPo2cKdKU27S0vF8jmcjcS9G+xPGeC+VKyjTMWZR4Oit0Q
# 3mT0b85G1NMX6XnEBLTT+yzfH4qerAr7EydAreT54al/RrsHYEdlYEBOsELsTu2z
# dnnYCjQJbRyAMR/iDlTd5aH75UcQrWSY/1AWLny/BSF64pVBJ2nDk4+VyY3YmyGu
# DVyc8KKuhmiDDGotu3ZrAB2WrfIWe/YWgyS5iM9qqEcxL5rc43E91wB+YkfRzojJ
# uBj6DnKNwaM9rwJAav9pm5biEKgQtDdQCNbDPTCCBgcwggPvoAMCAQICCmEWaDQA
# AAAAABwwDQYJKoZIhvcNAQEFBQAwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5MB4XDTA3MDQwMzEyNTMwOVoXDTIxMDQwMzEz
# MDMwOVowdzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8G
# A1UEAxMYTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAn6Fssd/bSJIqfGsuGeG94uPFmVEjUK3O3RhOJA/u0afR
# TK10MCAR6wfVVJUVSZQbQpKumFwwJtoAa+h7veyJBw/3DgSY8InMH8szJIed8vRn
# HCz8e+eIHernTqOhwSNTyo36Rc8J0F6v0LBCBKL5pmyTZ9co3EZTsIbQ5ShGLies
# hk9VUgzkAyz7apCQMG6H81kwnfp+1pez6CGXfvjSE/MIt1NtUrRFkJ9IAEpHZhEn
# KWaol+TTBoFKovmEpxFHFAmCn4TtVXj+AZodUAiFABAwRu233iNGu8QtVJ+vHnhB
# MXfMm987g5OhYQK1HQ2x/PebsgHOIktU//kFw8IgCwIDAQABo4IBqzCCAacwDwYD
# VR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUIzT42VJGcArtQPt2+7MrsMM1sw8wCwYD
# VR0PBAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMIGYBgNVHSMEgZAwgY2AFA6sgmBA
# VieX5SUT/CrhClOVWeSkoWOkYTBfMRMwEQYKCZImiZPyLGQBGRYDY29tMRkwFwYK
# CZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQDEyRNaWNyb3NvZnQgUm9vdCBD
# ZXJ0aWZpY2F0ZSBBdXRob3JpdHmCEHmtFqFKoKWtTHNY9AcTLmUwUAYDVR0fBEkw
# RzBFoEOgQYY/aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVj
# dHMvbWljcm9zb2Z0cm9vdGNlcnQuY3JsMFQGCCsGAQUFBwEBBEgwRjBEBggrBgEF
# BQcwAoY4aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNyb3Nv
# ZnRSb290Q2VydC5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEF
# BQADggIBABCXisNcA0Q23em0rXfbznlRTQGxLnRxW20ME6vOvnuPuC7UEqKMbWK4
# VwLLTiATUJndekDiV7uvWJoc4R0Bhqy7ePKL0Ow7Ae7ivo8KBciNSOLwUxXdT6uS
# 5OeNatWAweaU8gYvhQPpkSokInD79vzkeJkuDfcH4nC8GE6djmsKcpW4oTmcZy3F
# UQ7qYlw/FpiLID/iBxoy+cwxSnYxPStyC8jqcD3/hQoT38IKYY7w17gX606Lf8U1
# K16jv+u8fQtCe9RTciHuMMq7eGVcWwEXChQO0toUmPU8uWZYsy0v5/mFhsxRVuid
# cJRsrDlM1PZ5v6oYemIp76KbKTQGdxpiyT0ebR+C8AvHLLvPQ7Pl+ex9teOkqHQ1
# uE7FcSMSJnYLPFKMcVpGQxS8s7OwTWfIn0L/gHkhgJ4VMGboQhJeGsieIiHQQ+kr
# 6bv0SMws1NgygEwmKkgkX1rqVu+m3pmdyjpvvYEndAYR7nYhv5uCwSdUtrFqPYmh
# dmG0bqETpr+qR/ASb/2KMmyy/t9RyIwjyWa9nR2HEmQCPS2vWY+45CHltbDKY7R4
# VAXUQS5QrJSwpXirs6CWdRrZkocTdSIvMqgIbqBbjCW/oO+EyiHW6x5PyZruSeD3
# AWVviQt9yGnI5m7qp5fOMSn/DsVbXNhNG6HY+i+ePy5VFmvJE6P9MYIElzCCBJMC
# AQEwgZAweTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEjMCEG
# A1UEAxMaTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0ECEzMAAAEKLHmu13l7pqwA
# AQAAAQowCQYFKw4DAhoFAKCBsDAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAc
# BgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUKgYp
# XFKXzyMmXGjUyfk2fNHXAvYwUAYKKwYBBAGCNwIBDDFCMECgFoAUAFAAbwB3AGUA
# cgBTAGgAZQBsAGyhJoAkaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL1Bvd2VyU2hl
# bGwgMA0GCSqGSIb3DQEBAQUABIIBAEBm10Jm7foQVRAp+oCHbU6OLo7Udj4NLEzP
# ik96HfoUsZ3uyRtY6/AekFsHaP8bcKOhJCsrZsyceAjsG1SZ348LX01qclfeIQib
# 6/strozMEA/Q4CwetishkzQQMdB5XC7KigzXLGiuojwYSuZsMJaa6G5ASGROQZUf
# rExYzdW3TOov0mC03papzIA4p5N2DY6Hv3lzARYY5Hg3AWftsCykQwq0ufPRJtpI
# 5AMjWkZR8v2+p8JTiAiZwF3K/je2/AW1nWLP4BVgEjd1b1b9mWc2QG/5Ru/LlSc6
# xCGLhjeXcONAhLKEbWZ0pB1tpCJLKLrsiDrgFdYOxXJtlStEdOGhggIoMIICJAYJ
# KoZIhvcNAQkGMYICFTCCAhECAQEwgY4wdzELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# AhMzAAAAkkyir1UnCC51AAAAAACSMAkGBSsOAwIaBQCgXTAYBgkqhkiG9w0BCQMx
# CwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0xNjA0MTEyMTQ1NTdaMCMGCSqG
# SIb3DQEJBDEWBBSLKJXO/Z9wUChQKupAgPA4RYrT4zANBgkqhkiG9w0BAQUFAASC
# AQCYIkqBycERkHNxjzJD47lRS1buXJhF2qN+H2yNlDdxUvdFA7yLsssFwRRtHtvi
# guRA36zTO4/4xi+M8QHSpR50GJ8P0WAjropa8EIFeSPNjiEzsvrcWavpzaGFI5fG
# aJGyYf2m+Qhl7iGK8TpOGH/LZvsFInNOoBaZaJS1CZeeHwGRxZ6qEtJwk8v+3JEr
# 4YE+NAs7CTV8At+zClZhZ0+XG67pSHwnrS9n9AC8objJA2mT4KceLrEl7iw+ZBwg
# qqLEh8fq2Pk+0eJnd7NVykslRnInwCC3TlnbwTcN5XRxcRew83YLDAkdbAtCu4Qw
# HQd6tK0smdVDIUc/VOVHO0v3
# SIG # End signature block

#########################################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
#
# WSA Provider Module
#
#########################################################################################

$script:ProviderName = "WSAProvider"
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
Microsoft.PowerShell.Utility\Import-LocalizedData  LocalizedData -filename WSAProvider.Resource.psd1
$script:isNanoServer = $null -ne ('System.Runtime.Loader.AssemblyLoadContext' -as [Type])



if(-not($script:isNanoServer))
{
    throw 'WSAProvider is only supported on nano server'
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
# MIIarwYJKoZIhvcNAQcCoIIaoDCCGpwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU1GcdTcBQPd+qVU4hAR1uVqDU
# HqSgghWCMIIEwzCCA6ugAwIBAgITMwAAAJb6gDHvN2RGRQAAAAAAljANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTUxMDA3MTgxNDI0
# WhcNMTcwMTA3MTgxNDI0WjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OkJCRUMtMzBDQS0yREJFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAm1pYSwjyVGa6
# tIZe8M6+zXQQ33WKYIyKYcI3oiZcZgVcxdizVjv3hKmjqmRTC5REuLtaSYbdeCuG
# bdMP2+NGWrqeWKLQIxb/Gs/BkEzrr+ewnZ+UQ7xON8jkhPhMSdT5ZiVVNdhVgo+y
# 3hvrk0tk4iDpr5Xwqk5U2W5yZkXras/mIIfO54mjfS31tKQbIsxxubm8Np9ioBit
# boqgiC1iwSxGh7/LGPp1NJVacuQc1JMuzkhRNXxwALbWbyrsUV8Aztz5eaUASLoF
# jkK43ety0X/rV9Qlws43Q2LjKhztpEaxloEr0gioCAEmkJssDjd1qqCZ6X/bht1e
# ggluXnz2tQIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFMfD/XvxW9NCtvwEw94qmvuS
# ht7IMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBADQzONHGQV0X/NPCsvaZQv26Syn1rUGW85E9wUCgtf0iWG55
# ntOcHryYkkVIkjB/vd9ixfzGlW2Bz08YdPHJc5he9ZNkfwhjHqW9r6ii06pa4kzE
# PbgYlLwVRRvxzJwLZpSe56UceM8FmEnsRUSVKzabhLjmiIAFpnNlGgYd6g0eDvxT
# FM9SOJozV4Mjyb7e+Gv//ZxUeZcTK2S/Nam+B6m/mlRVajUYotCDwziVxrm1irMt
# a15M55pT3aawt+QrwXaRUMRSRmIgXTHgFWdM3AksQGA0a77rRKGYldX0iPyH2XOw
# rTHQww9kEcX1r+2R+9QjmsljYc3ZPGnA+2YCADEwggTsMIID1KADAgECAhMzAAAB
# Cix5rtd5e6asAAEAAAEKMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBMB4XDTE1MDYwNDE3NDI0NVoXDTE2MDkwNDE3NDI0NVowgYMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIx
# HjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJL8bza74QO5KNZG0aJhuqVG+2MWPi75R9LH7O3HmbEm
# UXW92swPBhQRpGwZnsBfTVSJ5E1Q2I3NoWGldxOaHKftDXT3p1Z56Cj3U9KxemPg
# 9ZSXt+zZR/hsPfMliLO8CsUEp458hUh2HGFGqhnEemKLwcI1qvtYb8VjC5NJMIEb
# e99/fE+0R21feByvtveWE1LvudFNOeVz3khOPBSqlw05zItR4VzRO/COZ+owYKlN
# Wp1DvdsjusAP10sQnZxN8FGihKrknKc91qPvChhIqPqxTqWYDku/8BTzAMiwSNZb
# /jjXiREtBbpDAk8iAJYlrX01boRoqyAYOCj+HKIQsaUCAwEAAaOCAWAwggFcMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBSJ/gox6ibN5m3HkZG5lIyiGGE3
# NDBRBgNVHREESjBIpEYwRDENMAsGA1UECxMETU9QUjEzMDEGA1UEBRMqMzE1OTUr
# MDQwNzkzNTAtMTZmYS00YzYwLWI2YmYtOWQyYjFjZDA1OTg0MB8GA1UdIwQYMBaA
# FMsR6MrStBZYAck3LjMWFrlMmgofMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY0NvZFNpZ1BDQV8w
# OC0zMS0yMDEwLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljQ29kU2lnUENBXzA4LTMx
# LTIwMTAuY3J0MA0GCSqGSIb3DQEBBQUAA4IBAQCmqFOR3zsB/mFdBlrrZvAM2PfZ
# hNMAUQ4Q0aTRFyjnjDM4K9hDxgOLdeszkvSp4mf9AtulHU5DRV0bSePgTxbwfo/w
# iBHKgq2k+6apX/WXYMh7xL98m2ntH4LB8c2OeEti9dcNHNdTEtaWUu81vRmOoECT
# oQqlLRacwkZ0COvb9NilSTZUEhFVA7N7FvtH/vto/MBFXOI/Enkzou+Cxd5AGQfu
# FcUKm1kFQanQl56BngNb/ErjGi4FrFBHL4z6edgeIPgF+ylrGBT6cgS3C6eaZOwR
# XU9FSY0pGi370LYJU180lOAWxLnqczXoV+/h6xbDGMcGszvPYYTitkSJlKOGMIIF
# vDCCA6SgAwIBAgIKYTMmGgAAAAAAMTANBgkqhkiG9w0BAQUFADBfMRMwEQYKCZIm
# iZPyLGQBGRYDY29tMRkwFwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQD
# EyRNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMTAwODMx
# MjIxOTMyWhcNMjAwODMxMjIyOTMyWjB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSMwIQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBD
# QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJyWVwZMGS/HZpgICBC
# mXZTbD4b1m/My/Hqa/6XFhDg3zp0gxq3L6Ay7P/ewkJOI9VyANs1VwqJyq4gSfTw
# aKxNS42lvXlLcZtHB9r9Jd+ddYjPqnNEf9eB2/O98jakyVxF3K+tPeAoaJcap6Vy
# c1bxF5Tk/TWUcqDWdl8ed0WDhTgW0HNbBbpnUo2lsmkv2hkL/pJ0KeJ2L1TdFDBZ
# +NKNYv3LyV9GMVC5JxPkQDDPcikQKCLHN049oDI9kM2hOAaFXE5WgigqBTK3S9dP
# Y+fSLWLxRT3nrAgA9kahntFbjCZT6HqqSvJGzzc8OJ60d1ylF56NyxGPVjzBrAlf
# A9MCAwEAAaOCAV4wggFaMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFMsR6MrS
# tBZYAck3LjMWFrlMmgofMAsGA1UdDwQEAwIBhjASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBT90TFO0yaKleGYYDuoMW+mPLzYLTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTAfBgNVHSMEGDAWgBQOrIJgQFYnl+UlE/wq4QpTlVnk
# pDBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEE
# SDBGMEQGCCsGAQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY3Jvc29mdFJvb3RDZXJ0LmNydDANBgkqhkiG9w0BAQUFAAOCAgEAWTk+
# fyZGr+tvQLEytWrrDi9uqEn361917Uw7LddDrQv+y+ktMaMjzHxQmIAhXaw9L0y6
# oqhWnONwu7i0+Hm1SXL3PupBf8rhDBdpy6WcIC36C1DEVs0t40rSvHDnqA2iA6VW
# 4LiKS1fylUKc8fPv7uOGHzQ8uFaa8FMjhSqkghyT4pQHHfLiTviMocroE6WRTsgb
# 0o9ylSpxbZsa+BzwU9ZnzCL/XB3Nooy9J7J5Y1ZEolHN+emjWFbdmwJFRC9f9Nqu
# 1IIybvyklRPk62nnqaIsvsgrEA5ljpnb9aL6EiYJZTiU8XofSrvR4Vbo0HiWGFzJ
# NRZf3ZMdSY4tvq00RBzuEBUaAF3dNVshzpjHCe6FDoxPbQ4TTj18KUicctHzbMrB
# 7HCjV5JXfZSNoBtIA1r3z6NnCnSlNu0tLxfI5nI3EvRvsTxngvlSso0zFmUeDord
# EN5k9G/ORtTTF+l5xAS00/ss3x+KnqwK+xMnQK3k+eGpf0a7B2BHZWBATrBC7E7t
# s3Z52Ao0CW0cgDEf4g5U3eWh++VHEK1kmP9QFi58vwUheuKVQSdpw5OPlcmN2Jsh
# rg1cnPCiroZogwxqLbt2awAdlq3yFnv2FoMkuYjPaqhHMS+a3ONxPdcAfmJH0c6I
# ybgY+g5yjcGjPa8CQGr/aZuW4hCoELQ3UAjWwz0wggYHMIID76ADAgECAgphFmg0
# AAAAAAAcMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0wNzA0MDMxMjUzMDlaFw0yMTA0MDMx
# MzAzMDlaMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xITAf
# BgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJ+hbLHf20iSKnxrLhnhveLjxZlRI1Ctzt0YTiQP7tGn
# 0UytdDAgEesH1VSVFUmUG0KSrphcMCbaAGvoe73siQcP9w4EmPCJzB/LMySHnfL0
# Zxws/HvniB3q506jocEjU8qN+kXPCdBer9CwQgSi+aZsk2fXKNxGU7CG0OUoRi4n
# rIZPVVIM5AMs+2qQkDBuh/NZMJ36ftaXs+ghl3740hPzCLdTbVK0RZCfSABKR2YR
# JylmqJfk0waBSqL5hKcRRxQJgp+E7VV4/gGaHVAIhQAQMEbtt94jRrvELVSfrx54
# QTF3zJvfO4OToWECtR0Nsfz3m7IBziJLVP/5BcPCIAsCAwEAAaOCAaswggGnMA8G
# A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFCM0+NlSRnAK7UD7dvuzK7DDNbMPMAsG
# A1UdDwQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADCBmAYDVR0jBIGQMIGNgBQOrIJg
# QFYnl+UlE/wq4QpTlVnkpKFjpGEwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5ghB5rRahSqClrUxzWPQHEy5lMFAGA1UdHwRJ
# MEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRIMEYwRAYIKwYB
# BQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0Um9vdENlcnQuY3J0MBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEB
# BQUAA4ICAQAQl4rDXANENt3ptK132855UU0BsS50cVttDBOrzr57j7gu1BKijG1i
# uFcCy04gE1CZ3XpA4le7r1iaHOEdAYasu3jyi9DsOwHu4r6PCgXIjUji8FMV3U+r
# kuTnjWrVgMHmlPIGL4UD6ZEqJCJw+/b85HiZLg33B+JwvBhOnY5rCnKVuKE5nGct
# xVEO6mJcPxaYiyA/4gcaMvnMMUp2MT0rcgvI6nA9/4UKE9/CCmGO8Ne4F+tOi3/F
# NSteo7/rvH0LQnvUU3Ih7jDKu3hlXFsBFwoUDtLaFJj1PLlmWLMtL+f5hYbMUVbo
# nXCUbKw5TNT2eb+qGHpiKe+imyk0BncaYsk9Hm0fgvALxyy7z0Oz5fnsfbXjpKh0
# NbhOxXEjEiZ2CzxSjHFaRkMUvLOzsE1nyJ9C/4B5IYCeFTBm6EISXhrIniIh0EPp
# K+m79EjMLNTYMoBMJipIJF9a6lbvpt6Znco6b72BJ3QGEe52Ib+bgsEnVLaxaj2J
# oXZhtG6hE6a/qkfwEm/9ijJssv7fUciMI8lmvZ0dhxJkAj0tr1mPuOQh5bWwymO0
# eFQF1EEuUKyUsKV4q7OglnUa2ZKHE3UiLzKoCG6gW4wlv6DvhMoh1useT8ma7kng
# 9wFlb4kLfchpyOZu6qeXzjEp/w7FW1zYTRuh2Povnj8uVRZryROj/TGCBJcwggST
# AgEBMIGQMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xIzAh
# BgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBAhMzAAABCix5rtd5e6as
# AAEAAAEKMAkGBSsOAwIaBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFHNs
# WB3wAUBvNjZX/j8CapRxHOBmMFAGCisGAQQBgjcCAQwxQjBAoBaAFABQAG8AdwBl
# AHIAUwBoAGUAbABsoSaAJGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9Qb3dlclNo
# ZWxsIDANBgkqhkiG9w0BAQEFAASCAQAc3o5bn1HBYxqdkPUIb1dROY0d7gxYQUNj
# 7W/jexyidR2/FHNWHh4Pt+tqLz/sn/QTHv5DcZQF47QMFyvFVF5uZbEqOhc0PBAJ
# MhZYA265A7Gn1DPseTsJvWOFhlVyegxCRJLnP9biMBBomFNU7sR7nFVZXOhAII1N
# hgcWHx7XQgk8KHa8lpLuJ8R5TL3PJzbrre2PDVso6WaMQ/UHuIv1qmddfJ1dD7cz
# HT8jFs26BYV0Vh2Ix81mm7IJfW7Kdk8mB6FAj4Y21Vc22aL1x836pwmn1glmJ/ya
# GIeA8Ej0d6DXIMne40H8sFqMGrYpVC/ouKwWl4aHGj810FZzP0EWoYICKDCCAiQG
# CSqGSIb3DQEJBjGCAhUwggIRAgEBMIGOMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xITAfBgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QQITMwAAAJb6gDHvN2RGRQAAAAAAljAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkD
# MQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTYwNDI1MTk0NjIzWjAjBgkq
# hkiG9w0BCQQxFgQUuhEhJzDkaM7OedmGS4fs60HBoW0wDQYJKoZIhvcNAQEFBQAE
# ggEAavJmnoykIG65f9TA2KgQ58DmoxiE30QcwvohW2W1x2hISfaMhjS4Ys6XTh7s
# C5TVGAejEjSpvvcDL9Jp/xYx5RnKc4bEHfIL7vlpXnAl+yITbL+GKa2NXnYCx4dD
# 7MLsGtDCijM5AH/jGjF2OsvQz66NnLWULilSiwLn1UuPWGXA/jgZkpherhm4WT0T
# RaMR/XNzJEVYmiLm31u/JetXeKR84iL+30hJVNPhTEEwrGpNsODfbAoIbtkAT8b8
# vzCTONKuvH/wMlm3O13VS8Q+1YxhwgPoTgkD4nz8FJBdTMNawl+yRDaPZPA43lGE
# +eHeXiR0z1vQeN3Oj4k2me1STw==
# SIG # End signature block

#!/usr/bin/env pwsh
#
# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
#

[CmdletBinding()]
param(
    [switch]
    $Clean,

    [switch]
    $Bootstrap,

    [switch]
    $Test,

    [switch]
    $NoBuild,

    [string]
    $Configuration = "Debug"
)

#Requires -Version 6.0

Import-Module "$PSScriptRoot/tools/helper.psm1" -Force

# Bootstrap step
if ($Bootstrap.IsPresent) {
    Write-Log "Validate and install missing prerequisits for building ..."
    Install-Dotnet

    if (-not (Get-Module -Name PSDepend -ListAvailable)) {
        Write-Log -Warning "Module 'PSDepend' is missing. Installing 'PSDepend' ..."
        Install-Module -Name PSDepend -Scope CurrentUser -Force
    }
    if (-not (Get-Module -Name Pester -ListAvailable)) {
        Write-Log -Warning "Module 'Pester' is missing. Installing 'Pester' ..."
        Install-Module -Name Pester -Scope CurrentUser -Force
    }
    if (-not (Get-Module -Name platyPS -ListAvailable)) {
        Write-Log -Warning "Module 'platyPS' is missing. Installing 'platyPS' ..."
        Install-Module -Name platyPS -Scope CurrentUser -Force
    }
}

# Clean step
if($Clean.IsPresent) {
    Push-Location $PSScriptRoot
    git clean -fdX
    Pop-Location
}

# Common step required by both build and test
Find-Dotnet

# Build step
if(!$NoBuild.IsPresent) {
    if (-not (Get-Module -Name PSDepend -ListAvailable)) {
        throw "Cannot find the 'PSDepend' module. Please specify '-Bootstrap' to install build dependencies."
    }

    # Generate C# files for resources
    Start-ResGen

    # Generate csharp code from protobuf if needed
    New-gRPCAutoGenCode

    $requirements = "$PSScriptRoot/src/requirements.psd1"
    $modules = Import-PowerShellDataFile $requirements

    Write-Log "Install modules that are bundled with PowerShell Language worker, including"
    foreach ($entry in $modules.GetEnumerator()) {
        Write-Log -Indent "$($entry.Name) $($entry.Value.Version)"
    }

    Invoke-PSDepend -Path $requirements -Force

    Write-Log "Deleting fullclr folder from PackageManagement module if the folder exists ..."
    Get-Item "$PSScriptRoot/src/Modules/PackageManagement/1.1.7.0/fullclr" -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # TODO: Remove this once the SDK properly bundles modules
    Get-WebFile -Url 'https://raw.githubusercontent.com/PowerShell/PowerShell/master/src/Modules/Windows/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1' `
        -OutFile "$PSScriptRoot/src/Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1"
    Get-WebFile -Url 'https://raw.githubusercontent.com/PowerShell/PowerShell/master/src/Modules/Windows/Microsoft.PowerShell.Management/Microsoft.PowerShell.Management.psd1' `
        -OutFile "$PSScriptRoot/src/Modules/Microsoft.PowerShell.Management/Microsoft.PowerShell.Management.psd1" 

    dotnet publish -c $Configuration $PSScriptRoot
    dotnet pack -c $Configuration "$PSScriptRoot/package"
}

# Test step
if($Test.IsPresent) {
    if (-not (Get-Module -Name Pester -ListAvailable)) {
        throw "Cannot find the 'Pester' module. Please specify '-Bootstrap' to install build dependencies."
    }

    dotnet test "$PSScriptRoot/test/Unit"
    if ($LASTEXITCODE -ne 0) { throw "xunit tests failed." }

    Invoke-Tests -Path "$PSScriptRoot/test/Unit/Modules" -OutputFile UnitTestsResults.xml

    if (-not (Get-Module -Name platyPS -ListAvailable)) {
        throw "Cannot find the 'platyPS' module. Please specify '-Bootstrap' to install build dependencies."
    }
    elseif (-not (Get-Command -Name git -CommandType Application)) {
        throw "Cannot find 'git'. Please make sure it's in the 'PATH'."
    }

    # Cmdlet help docs should be up-to-date.
    # PlatyPS needs the module to be imported.
    Import-Module -Force (Join-Path $PSScriptRoot src Modules Microsoft.Azure.Functions.PowerShellWorker)
    try {
        # Update the help and diff the result.
        $docsPath = Join-Path $PSScriptRoot docs cmdlets
        Update-MarkdownHelp -Path $docsPath
        $diff = git diff $docsPath
        if ($diff) {
            throw "Cmdlet help docs are not up-to-date, run Update-MarkdownHelp.`n$diff`n"
        }
        Write-Host "Help is up-to-date."
    } finally {
        # Clean up.
        Remove-Module Microsoft.Azure.Functions.PowerShellWorker -Force
    }
}

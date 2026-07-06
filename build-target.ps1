param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Target,

    [ValidateSet("Release", "RelWithDebInfo", "Debug")]
    [string]$BuildType = "Release",

    [string]$BuildDir = "",

    [switch]$List,
    [switch]$Clean,
    [switch]$ConfigureOnly,
    [switch]$Reconfigure
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $RepoRoot

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $suffix = switch ($BuildType) {
        "Release" { "release" }
        "RelWithDebInfo" { "relwithdebinfo" }
        "Debug" { "debug" }
    }
    $BuildDir = Join-Path $RepoRoot "build-$suffix"
}

function Convert-ToCMakePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return $Path.Replace("\", "/")
}

function Resolve-CommandPath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Candidates = @()
    )

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    throw "Could not find $Name. Install it first, then rerun this script."
}

function Remove-BuildDir {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $resolvedBuild = (Resolve-Path -LiteralPath $Path).Path
    $resolvedRepo = (Resolve-Path -LiteralPath $RepoRoot).Path
    if (-not $resolvedBuild.StartsWith($resolvedRepo, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a build directory outside the repo: $resolvedBuild"
    }

    Remove-Item -LiteralPath $resolvedBuild -Recurse -Force
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$cmakePath = Resolve-CommandPath "cmake.exe" @(
    "C:\Program Files\CMake\bin\cmake.exe"
)
$ninjaPath = Resolve-CommandPath "ninja.exe" @(
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe\ninja.exe"
)
$rubyPath = Resolve-CommandPath "ruby.exe" @(
    "C:\Ruby34-x64\bin\ruby.exe"
)

$toolchainBin = Join-Path $RepoRoot "tools\arm-gnu-toolchain-13.2.rel1\bin"
$toolchainGcc = Join-Path $toolchainBin "arm-none-eabi-gcc.exe"

$cmakeDir = Split-Path -Parent $cmakePath
$ninjaDir = Split-Path -Parent $ninjaPath
$rubyDir = Split-Path -Parent $rubyPath

# Keep PATH minimal for generated cmake -E env commands. The build invokes
# CMake, Ninja and Ruby by absolute path; ARM binutils are the only tools that
# need PATH lookup inside target build rules.
$env:Path = $toolchainBin

$cmakeProgramPath = @(
    (Convert-ToCMakePath $toolchainBin),
    (Convert-ToCMakePath $rubyDir)
) -join ";"

$cacheFile = Join-Path $BuildDir "CMakeCache.txt"
$expectedCompiler = Convert-ToCMakePath $toolchainGcc
$configureRequired = $true

if ($Reconfigure) {
    Remove-BuildDir $BuildDir
}

if (Test-Path -LiteralPath $cacheFile) {
    $cache = Get-Content -LiteralPath $cacheFile -Raw
    $hasExpectedCompiler = $cache.Contains($expectedCompiler)
    $hasExpectedBuildType = $cache.Contains("CMAKE_BUILD_TYPE:STRING=$BuildType")
    if ($hasExpectedCompiler -and $hasExpectedBuildType) {
        $configureRequired = $false
    } else {
        Write-Host "Existing CMake cache uses a different compiler or build type; regenerating $BuildDir"
        Remove-BuildDir $BuildDir
    }
}

if ($configureRequired) {
    $cmakeArgs = @(
        "-S", ".",
        "-B", $BuildDir,
        "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=$BuildType",
        "-DCMAKE_MAKE_PROGRAM:FILEPATH=$(Convert-ToCMakePath $ninjaPath)",
        "-DCMAKE_PROGRAM_PATH=$cmakeProgramPath",
        "-DCMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=FALSE"
    )

    if (Test-Path -LiteralPath $toolchainGcc) {
        $cmakeArgs += "-Dgcc:FILEPATH=$expectedCompiler"
    }

    Invoke-Native $cmakePath $cmakeArgs
}

if ($ConfigureOnly) {
    Write-Host "Configured $BuildDir"
    exit 0
}

if ($List) {
    $targetLines = & $ninjaPath -C $BuildDir -t targets all
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    $targetLines |
        Where-Object { $_ -match "^[A-Z0-9_]+:\s+phony$" } |
        ForEach-Object { ($_ -split ":")[0] } |
        Sort-Object
    exit 0
}

if (-not $Target -or $Target.Count -eq 0) {
    throw "No target specified. Use -List to see available targets, for example: .\build-target.ps1 -List"
}

$buildTargets = if ($Clean) {
    @($Target) | ForEach-Object { "clean_$_" }
} else {
    @($Target)
}

$buildArgs = @("--build", $BuildDir, "--target") + $buildTargets
Invoke-Native $cmakePath $buildArgs

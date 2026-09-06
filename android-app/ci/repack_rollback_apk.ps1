[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputApk,

    [Parameter(Mandatory = $true)]
    [string]$OutputApk,

    [Parameter(Mandatory = $true)]
    [int]$SourceVersionCode,

    [Parameter(Mandatory = $true)]
    [int]$CurrentInstalledVersionCode,

    [Parameter(Mandatory = $true)]
    [int]$InstallVersionCode
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $bundledJava = 'C:\Program Files\Android\Android Studio\jbr'
    if (Test-Path -LiteralPath (Join-Path $bundledJava 'bin\java.exe')) {
        $env:JAVA_HOME = $bundledJava
    }
}

function Fail([string]$Message) {
    throw "rollback repack failed: $Message"
}

if ($SourceVersionCode -le 0) { Fail 'SourceVersionCode must be positive' }
if ($CurrentInstalledVersionCode -le 0) { Fail 'CurrentInstalledVersionCode must be positive' }
if ($InstallVersionCode -le $SourceVersionCode) {
    Fail "InstallVersionCode $InstallVersionCode must be greater than source $SourceVersionCode"
}
if ($InstallVersionCode -le $CurrentInstalledVersionCode) {
    Fail "InstallVersionCode $InstallVersionCode must be greater than current $CurrentInstalledVersionCode"
}

$inputPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InputApk).Path)
$outputPath = [System.IO.Path]::GetFullPath($OutputApk)
if ($inputPath -eq $outputPath) { Fail 'OutputApk must be different from InputApk' }
if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) { Fail "input APK does not exist: $inputPath" }
$outputParent = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}

$appDir = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $appDir 'android'
$keyPropertiesPath = Join-Path $androidDir 'key.properties'
if (-not (Test-Path -LiteralPath $keyPropertiesPath -PathType Leaf)) {
    Fail "release signing key.properties is missing: $keyPropertiesPath"
}
$keyValues = Get-Content -LiteralPath $keyPropertiesPath -Raw | ConvertFrom-StringData
foreach ($required in @('storePassword', 'keyPassword', 'keyAlias', 'storeFile')) {
    if ([string]::IsNullOrWhiteSpace([string]$keyValues[$required])) {
        Fail "key.properties is missing $required"
    }
}
$keystorePath = [string]$keyValues['storeFile']
if (-not [System.IO.Path]::IsPathRooted($keystorePath)) {
    $keystorePath = Join-Path $androidDir $keystorePath
}
$keystorePath = [System.IO.Path]::GetFullPath($keystorePath)
if (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
    Fail "release keystore does not exist: $keystorePath"
}

function Find-BuildTool([string]$Name) {
    $roots = @()
    foreach ($candidate in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $roots += $candidate }
    }
    foreach ($root in $roots) {
        $found = Get-ChildItem -LiteralPath (Join-Path $root 'build-tools') -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $Name -or $_.Name -ieq "$Name.exe" -or $_.Name -ieq "$Name.bat" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($null -ne $found) { return $found.FullName }
    }
    Fail "$Name was not found in Android SDK build-tools"
}

$aapt = Find-BuildTool 'aapt'
$zipalign = Find-BuildTool 'zipalign'
$apksigner = Find-BuildTool 'apksigner'

function Read-U16([byte[]]$Bytes, [int]$Offset) {
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Read-U32([byte[]]$Bytes, [int]$Offset) {
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Read-StringPool([byte[]]$Bytes, [int]$ChunkOffset) {
    $stringCount = [int](Read-U32 $Bytes ($ChunkOffset + 8))
    $flags = Read-U32 $Bytes ($ChunkOffset + 16)
    $stringsStart = [int](Read-U32 $Bytes ($ChunkOffset + 20))
    $isUtf8 = (($flags -band 0x100) -ne 0)
    $result = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $stringCount; $index++) {
        $offset = [int](Read-U32 $Bytes ($ChunkOffset + 28 + ($index * 4)))
        $position = $ChunkOffset + $stringsStart + $offset
        if ($isUtf8) {
            $lengthByte = $Bytes[$position]
            $position++
            if (($lengthByte -band 0x80) -ne 0) { $position++ }
            $byteLength = $Bytes[$position]
            $position++
            if (($byteLength -band 0x80) -ne 0) { $position++ }
            $result.Add([Text.Encoding]::UTF8.GetString($Bytes, $position, $byteLength -band 0x7f))
        } else {
            $length = [int](Read-U16 $Bytes $position)
            $position += 2
            if (($length -band 0x8000) -ne 0) {
                $length = (($length -band 0x7fff) -shl 16) -bor (Read-U16 $Bytes $position)
                $position += 2
            }
            $result.Add([Text.Encoding]::Unicode.GetString($Bytes, $position, $length * 2))
        }
    }
    return $result
}

function Patch-ManifestVersionCode([byte[]]$bytes, [int]$ExpectedOld, [int]$NewCode) {
    $strings = $null
    $offset = 8
    $patched = 0
    while ($offset -lt $bytes.Length) {
        if ($offset + 8 -gt $bytes.Length) { Fail 'truncated AndroidManifest.xml chunk header' }
        $type = Read-U16 $bytes $offset
        $headerSize = [int](Read-U16 $bytes ($offset + 2))
        $chunkSize = [int](Read-U32 $bytes ($offset + 4))
        if ($chunkSize -lt $headerSize -or $chunkSize -le 0 -or $offset + $chunkSize -gt $bytes.Length) {
            Fail 'invalid AndroidManifest.xml chunk size'
        }
        # RES_STRING_POOL_TYPE
        if ($type -eq 0x0001) {
            $strings = Read-StringPool $bytes $offset
        }
        # RES_XML_START_ELEMENT_TYPE
        elseif ($type -eq 0x0102 -and $null -ne $strings) {
            if ($headerSize -lt 16 -or $offset + 36 -gt $bytes.Length) { Fail 'invalid start-element chunk' }
            $attributeStart = [int](Read-U16 $bytes ($offset + 24))
            $attributeSize = [int](Read-U16 $bytes ($offset + 26))
            $attributeCount = [int](Read-U16 $bytes ($offset + 28))
            if ($attributeSize -lt 20) { Fail 'unsupported AndroidManifest.xml attribute size' }
            # attributeStart is relative to the 16-byte XML node header (the
            # line/comment fields), not to the beginning of the chunk.
            for ($index = 0; $index -lt $attributeCount; $index++) {
                $attribute = $offset + 16 + $attributeStart + ($index * $attributeSize)
                if ($attribute + 20 -gt $offset + $chunkSize) { Fail 'truncated AndroidManifest.xml attribute' }
                $nameIndex = [int](Read-U32 $bytes ($attribute + 4))
                if ($nameIndex -lt 0 -or $nameIndex -ge $strings.Count) { continue }
                if ($strings[$nameIndex] -ne 'versionCode') { continue }
                $dataType = $bytes[$attribute + 15]
                $oldValue = [int](Read-U32 $bytes ($attribute + 16))
                if ($dataType -ne 0x10 -or $oldValue -ne $ExpectedOld) {
                    Fail "versionCode attribute is type 0x$('{0:X2}' -f $dataType) value $oldValue, expected $ExpectedOld"
                }
                $newBytes = [BitConverter]::GetBytes([int]$NewCode)
                [Array]::Copy($newBytes, 0, $bytes, $attribute + 16, 4)
                $patched++
            }
        }
        $offset += $chunkSize
    }
    if ($patched -ne 1) { Fail "expected exactly one versionCode attribute, patched $patched" }
    return ,$bytes
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("feimiao-rollback-" + [Guid]::NewGuid().ToString('N'))
$extractDir = Join-Path $tempRoot 'apk'
$unsignedApk = Join-Path $tempRoot 'unsigned.apk'
$alignedApk = Join-Path $tempRoot 'aligned.apk'
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    # Do not extract to NTFS: Flutter APKs contain resource names that differ
    # only by case (for example res/9N.9.png and res/9n.9.png), which collide
    # on Windows even though they are distinct ZIP entries.  Copy entries
    # directly between archives so their names and order remain intact.
    $inputArchive = [IO.Compression.ZipFile]::OpenRead($inputPath)
    $outputArchive = [IO.Compression.ZipFile]::Open($unsignedApk, [IO.Compression.ZipArchiveMode]::Create)
    $manifestSeen = $false
    try {
        foreach ($entry in $inputArchive.Entries) {
            if ($entry.FullName -like 'META-INF/*') { continue }
            $newEntry = $outputArchive.CreateEntry($entry.FullName, [IO.Compression.CompressionLevel]::Optimal)
            $inputStream = $entry.Open()
            $outputStream = $newEntry.Open()
            try {
                if ($entry.FullName -eq 'AndroidManifest.xml') {
                    $memory = New-Object IO.MemoryStream
                    try {
                        $inputStream.CopyTo($memory)
                        $manifest = Patch-ManifestVersionCode $memory.ToArray() $SourceVersionCode $InstallVersionCode
                        $outputStream.Write($manifest, 0, $manifest.Length)
                        $manifestSeen = $true
                    } finally {
                        $memory.Dispose()
                    }
                } else {
                    $inputStream.CopyTo($outputStream)
                }
            } finally {
                $outputStream.Dispose()
                $inputStream.Dispose()
            }
        }
    } finally {
        $outputArchive.Dispose()
        $inputArchive.Dispose()
    }
    if (-not $manifestSeen) { Fail 'APK has no AndroidManifest.xml' }
    & $zipalign -p -f 16 $unsignedApk $alignedApk | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'zipalign failed' }

    $env:FEIMIAO_ROLLBACK_STORE_PASSWORD = [string]$keyValues['storePassword']
    $env:FEIMIAO_ROLLBACK_KEY_PASSWORD = [string]$keyValues['keyPassword']
    try {
        & $apksigner sign `
            --ks $keystorePath `
            --ks-key-alias ([string]$keyValues['keyAlias']) `
            --ks-pass env:FEIMIAO_ROLLBACK_STORE_PASSWORD `
            --key-pass env:FEIMIAO_ROLLBACK_KEY_PASSWORD `
            --out $outputPath `
            $alignedApk
        if ($LASTEXITCODE -ne 0) { Fail 'apksigner sign failed' }
    } finally {
        Remove-Item Env:FEIMIAO_ROLLBACK_STORE_PASSWORD -ErrorAction SilentlyContinue
        Remove-Item Env:FEIMIAO_ROLLBACK_KEY_PASSWORD -ErrorAction SilentlyContinue
    }

    & $apksigner verify --verbose --print-certs $outputPath
    if ($LASTEXITCODE -ne 0) { Fail 'apksigner verification failed' }
    $badging = (& $aapt dump badging $outputPath) -join "`n"
    if ($LASTEXITCODE -ne 0) { Fail 'aapt could not inspect repacked APK' }
    if ($badging -notmatch "package: name='com\.qingji\.qingji\.codex'") {
        Fail 'repacked APK package name is not com.qingji.qingji.codex'
    }
    if ($badging -notmatch "versionCode='$InstallVersionCode'") {
        Fail "repacked APK versionCode is not $InstallVersionCode"
    }
    Write-Output "repacked rollback APK: $outputPath"
    Write-Output "sourceVersionCode=$SourceVersionCode installVersionCode=$InstallVersionCode"
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

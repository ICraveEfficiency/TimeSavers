# ========================================================
#                    THE MIDDEN MINER
# ========================================================
#
# A non-destructive Windows Recycle Bin recovery utility.
#
# This script searches all local Recycle Bins, reads the
# original deletion metadata from the $I files, and then
# allows you to recover files based on:
#
#   1. File type
#   2. Date the item was deleted
#
# Nothing is removed from the Recycle Bin by this script.
# Files are COPIED to a recovery folder.
#
# The script supports:
#
#   1. New Scan
#      - Scan only
#      - Scan and recover
#   2. Recover from a previous scan CSV
#
# Scan CSVs act as recovery manifests and record the
# Recycle Bin $I and $R paths needed for later recovery.
#
# Use in conjunction with other TimeSavers utilities, like
# the HOLLOW FOLDER EXPUNGER!
#
# THE MIDDEN MINER.ps1                    Copyright © 2026
# Contact me on GitHub https://github.com/ICraveEfficiency
#
# This script is free to use, redistribute, or modify, for
# personal or commercial use, with attribute and adherence
# to the GNU General Public License v3.0 (GPL-3.0).
#
# This script was developed collaboratively with ChatGPT.
# Approximate creation time: 4 hours.
#
# ========================================================
#                      SETTINGS
# ========================================================


# --------------------------------------------------------
# CSV REPORT
# --------------------------------------------------------
#
# $true  = automatically save a CSV after the scan/recovery.
# $false = ask whether you want a CSV report.
#
$CreateCsvAutomatically = $false

# --------------------------------------------------------
# RECOVERY RUN TIMESTAMP
# --------------------------------------------------------
#
# One timestamp is created for the entire run.
#
# Example recovery folder:
#
#   THE MIDDEN 2026-10-08 05.16.32
#
# Example CSV:
#
#   2026-10-08 05.16 TMM Recovery Pictures Older than 6 months.csv
#
$RunTimestamp = Get-Date

$RunTimestampFolder = $RunTimestamp.ToString(
    'yyyy-MM-dd HH.mm.ss'
)

$RunTimestampFile = $RunTimestamp.ToString(
    'yyyy-MM-dd HH.mm'
)

$RecoveryRoot = Join-Path `
    $env:USERPROFILE `
    "Desktop\THE MIDDEN $RunTimestampFolder"


# ========================================================
# FILE TYPE CATEGORIES
# ========================================================

$FileCategories = [ordered]@{

    'Pictures' = @(
        '.jpg'
        '.jpeg'
        '.png'
        '.gif'
        '.bmp'
        '.tif'
        '.tiff'
        '.webp'
        '.heic'
        '.heif'
        '.avif'
        '.ico'
    )

    'Videos' = @(
        '.mp4'
        '.avi'
        '.mkv'
        '.mov'
        '.wmv'
        '.mpg'
        '.mpeg'
        '.m4v'
        '.webm'
        '.flv'
        '.3gp'
        '.mts'
        '.m2ts'
        '.ts'
    )

    'Audio' = @(
        '.mp3'
        '.wav'
        '.flac'
        '.m4a'
        '.aac'
        '.ogg'
        '.oga'
        '.opus'
        '.wma'
        '.aiff'
        '.ape'
    )

    'Text' = @(
        '.txt'
        '.csv'
        '.log'
        '.ini'
        '.cfg'
        '.conf'
        '.xml'
        '.json'
        '.md'
        '.markdown'
        '.rtf'
    )

    'Documents' = @(
        '.doc'
        '.docx'
        '.pdf'
        '.xls'
        '.xlsx'
        '.xlsm'
        '.ppt'
        '.pptx'
        '.odt'
        '.ods'
        '.odp'
    )

    'Archives' = @(
        '.zip'
        '.rar'
        '.7z'
        '.tar'
        '.gz'
        '.bz2'
        '.xz'
        '.cab'
        '.iso'
    )
}


# ========================================================
# ADMINISTRATOR CHECK
# ========================================================

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()

$principal = New-Object `
    Security.Principal.WindowsPrincipal(
        $currentIdentity
    )

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {

    Write-Host ""
    Write-Host "Administrator privileges are required to inspect"
    Write-Host "all Windows Recycle Bins." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Restarting script as Administrator..."
    Write-Host ""

    Start-Process powershell.exe `
        -Verb RunAs `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""

    exit
}


# ========================================================
# HELPER FUNCTIONS
# ========================================================


function Wait-BeforeExit {

    Write-Host ""
    Read-Host "Press Enter to exit"
}


function Get-FileExtensionSafe {

    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    # Do NOT use [System.IO.Path]::GetExtension().
    #
    # Historical Recycle Bin paths can contain characters
    # which cause .NET Path methods to throw exceptions.

    $lastSlash = $Path.LastIndexOf('\')

    $lastForwardSlash = $Path.LastIndexOf('/')

    $lastSeparator = [Math]::Max(
        $lastSlash,
        $lastForwardSlash
    )

    $lastDot = $Path.LastIndexOf('.')

    if ($lastDot -le $lastSeparator) {
        return ''
    }

    return $Path.Substring(
        $lastDot
    ).ToLowerInvariant()
}


function Test-FileExtension {

    param(
        [string]$Path,
        [string[]]$AllowedExtensions
    )

    $extension = Get-FileExtensionSafe $Path

    if ([string]::IsNullOrWhiteSpace($extension)) {
        return $false
    }

    return $AllowedExtensions -contains $extension
}


function ConvertTo-SafePathComponent {

    param(
        [string]$Name
    )

    if ($null -eq $Name) {
        return '_'
    }

    $invalidCharacters = '<>:"/\|?*'

    foreach ($character in $invalidCharacters.ToCharArray()) {

        $Name = $Name.Replace(
            [string]$character,
            '_'
        )
    }

    $Name = $Name -replace '[\x00-\x1F]', '_'

    $Name = $Name.TrimEnd(
        [char]' ',
        [char]'.'
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = '_'
    }

    $reservedNames = @(
        'CON'
        'PRN'
        'AUX'
        'NUL'
        'COM1'
        'COM2'
        'COM3'
        'COM4'
        'COM5'
        'COM6'
        'COM7'
        'COM8'
        'COM9'
        'LPT1'
        'LPT2'
        'LPT3'
        'LPT4'
        'LPT5'
        'LPT6'
        'LPT7'
        'LPT8'
        'LPT9'
    )

    if ($reservedNames -contains $Name.ToUpperInvariant()) {
        $Name = "_$Name"
    }

    return $Name
}


# ========================================================
# RECOVERY PATH
# ========================================================
#
# IMPORTANT:
#
# Windows drive identifiers are handled separately from
# ordinary path components.
#
# C:\Users\JohnDoe\File.txt
#
# becomes:
#
# THE MIDDEN <timestamp>\
#     C\
#         Users\
#             JohnDoe\
#                 File.txt
#
# The drive letter is deliberately extracted as ONLY "C".
# It is never passed through ConvertTo-SafePathComponent.
#
# This prevents malformed drive folders such as:
#
#     #_E
#     %_E
#     &_E
#
# from being created.
#
# ========================================================

function Get-RecoveryPath {

    param(
        [string]$OriginalPath
    )

    if ([string]::IsNullOrWhiteSpace($OriginalPath)) {
        return $null
    }

    # ----------------------------------------------------
    # NORMALIZE PATH SEPARATORS
    # ----------------------------------------------------

    $normalizedPath = $OriginalPath.Replace(
        '/',
        '\'
    )

    # ----------------------------------------------------
    # EXTRACT THE DRIVE LETTER
    # ----------------------------------------------------
    #
    # Windows Recycle Bin metadata normally gives us:
    #
    #     E:\Some\Path\File.jpg
    #
    # However, some historical / unusual metadata can
    # contain characters before the drive specification.
    #
    # We deliberately ignore everything before the actual
    # drive letter.
    #
    # Examples:
    #
    #     E:\...
    #     #E:\...
    #     %E:\...
    #     &E:\...
    #
    # All of these become:
    #
    #     E\...
    #
    # This prevents strange characters from becoming the
    # name of the top-level recovery folder.
    # ----------------------------------------------------

    $driveMatch = [regex]::Match(
        $normalizedPath,
        '(?i)([A-Z]):'
    )

    if ($driveMatch.Success) {

        $driveLetter = (
            $driveMatch.Groups[1].Value.ToUpperInvariant()
        )

        # Everything after the drive specification.
        $pathAfterDrive = $normalizedPath.Substring(
            $driveMatch.Index + 2
        )

        # Start the reconstructed path with ONLY the
        # actual drive letter.
        $destination = Join-Path `
            $RecoveryRoot `
            $driveLetter

        # Remove leading separators from the remainder.
        $pathAfterDrive = $pathAfterDrive.TrimStart(
            '\'
        )

        if ([string]::IsNullOrWhiteSpace($pathAfterDrive)) {
            return $destination
        }

        $parts = $pathAfterDrive -split '\\'

        foreach ($part in $parts) {

            if ([string]::IsNullOrWhiteSpace($part)) {
                continue
            }

            $safePart = ConvertTo-SafePathComponent `
                $part

            if (-not [string]::IsNullOrWhiteSpace($safePart)) {

                $destination = Join-Path `
                    $destination `
                    $safePart
            }
        }

        return $destination
    }


    # ----------------------------------------------------
    # UNC / NON-DRIVE PATH FALLBACK
    # ----------------------------------------------------
    #
    # If there is no recognizable drive letter, fall back
    # to reconstructing the path normally.
    #
    # This keeps the function useful for unusual metadata
    # without allowing arbitrary punctuation to masquerade
    # as a drive name.
    # ----------------------------------------------------

    $parts = $normalizedPath -split '\\'

    $safeParts = New-Object `
        System.Collections.Generic.List[string]

    foreach ($part in $parts) {

        if ([string]::IsNullOrWhiteSpace($part)) {
            continue
        }

        $safePart = ConvertTo-SafePathComponent `
            $part

        if (-not [string]::IsNullOrWhiteSpace($safePart)) {

            $safeParts.Add($safePart)
        }
    }

    if ($safeParts.Count -eq 0) {
        return $null
    }

    $destination = $RecoveryRoot

    foreach ($part in $safeParts) {

        $destination = Join-Path `
            $destination `
            $part
    }

    return $destination
}

function Get-UniqueDestinationPath {

    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $directory = Split-Path `
        -Parent `
        $Path

    $filename = Split-Path `
        -Leaf `
        $Path

    $extension = Get-FileExtensionSafe $filename

    if ($extension) {

        $baseName = $filename.Substring(
            0,
            $filename.Length - $extension.Length
        )
    }
    else {
        $baseName = $filename
    }

    $counter = 2

    while ($true) {

        if ($extension) {

            $candidateName = (
                "$baseName ($counter)$extension"
            )
        }
        else {

            $candidateName = (
                "$baseName ($counter)"
            )
        }

        $candidate = Join-Path `
            $directory `
            $candidateName

        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }

        $counter++
    }
}


function Get-RecycleBinMetadata {

    param(
        [System.IO.FileInfo]$MetadataFile
    )

    try {

        $bytes = [System.IO.File]::ReadAllBytes(
            $MetadataFile.FullName
        )

        # Modern Windows $I format:
        #
        # Offset 0  = version
        # Offset 8  = original size
        # Offset 16 = deletion FILETIME
        # Offset 24 = original path, UTF-16LE

        if ($bytes.Length -lt 25) {
            return $null
        }

        $originalSize = [BitConverter]::ToInt64(
            $bytes,
            8
        )

        $fileTime = [BitConverter]::ToInt64(
            $bytes,
            16
        )

        try {

            $deletionDate = [DateTime]::FromFileTime(
                $fileTime
            )
        }
        catch {

            return $null
        }

        $originalPath = (
            [System.Text.Encoding]::Unicode.GetString(
                $bytes,
                24,
                $bytes.Length - 24
            )
        )

        $originalPath = $originalPath.TrimEnd(
            [char]0
        )

        return [PSCustomObject]@{

            MetadataFile = $MetadataFile

            OriginalSize = $originalSize

            DeletionDate = $deletionDate

            OriginalPath = $originalPath
        }
    }
    catch {

        return $null
    }
}


function Process-RecycleBinMetadata {

    param(
        [System.IO.FileInfo]$MetadataFile
    )

    $metadata = Get-RecycleBinMetadata `
        $MetadataFile

    if ($null -eq $metadata) {
        return $null
    }

    # Match:
    #
    # $I123456
    #
    # with:
    #
    # $R123456

    if ($MetadataFile.Name.Length -lt 3) {
        return $null
    }

    $rName = (
        '$R' +
        $MetadataFile.Name.Substring(2)
    )

    $rPath = Join-Path `
        $MetadataFile.Directory.FullName `
        $rName

    if (-not (Test-Path -LiteralPath $rPath)) {
        return $null
    }

    try {

        $rItem = Get-Item `
            -LiteralPath $rPath `
            -Force `
            -ErrorAction Stop

        if ($rItem.PSIsContainer) {
            return $null
        }

        return [PSCustomObject]@{

            MetadataFile = $MetadataFile.FullName

            RecyclePath = $rPath

            OriginalPath = $metadata.OriginalPath

            OriginalSize = $metadata.OriginalSize

            DeletionDate = $metadata.DeletionDate

            Extension = Get-FileExtensionSafe `
                $metadata.OriginalPath
        }
    }
    catch {

        return $null
    }
}


function Get-RecycleBinItems {

    param(
        [string]$RecycleBinRoot
    )

    $results = New-Object `
        System.Collections.Generic.List[object]

    if (-not (Test-Path -LiteralPath $RecycleBinRoot)) {
        return $results
    }

    # ----------------------------------------------------
    # Standard layout:
    #
    # C:\$Recycle.Bin\<SID>\$I...
    # C:\$Recycle.Bin\<SID>\$R...
    # ----------------------------------------------------

    try {

        $sidDirectories = Get-ChildItem `
            -LiteralPath $RecycleBinRoot `
            -Directory `
            -Force `
            -ErrorAction SilentlyContinue

        foreach ($sidDirectory in $sidDirectories) {

            $metadataFiles = Get-ChildItem `
                -LiteralPath $sidDirectory.FullName `
                -File `
                -Force `
                -Filter '$I*' `
                -ErrorAction SilentlyContinue

            foreach ($metadataFile in $metadataFiles) {

                $item = Process-RecycleBinMetadata `
                    $metadataFile

                if ($null -ne $item) {
                    $results.Add($item)
                }
            }
        }
    }
    catch {
        # Continue scanning.
    }


    # ----------------------------------------------------
    # Direct-root layout:
    #
    # E:\$Recycle.Bin\$I...
    # E:\$Recycle.Bin\$R...
    # ----------------------------------------------------

    try {

        $directMetadataFiles = Get-ChildItem `
            -LiteralPath $RecycleBinRoot `
            -File `
            -Force `
            -Filter '$I*' `
            -ErrorAction SilentlyContinue

        foreach ($metadataFile in $directMetadataFiles) {

            $item = Process-RecycleBinMetadata `
                $metadataFile

            if ($null -ne $item) {
                $results.Add($item)
            }
        }
    }
    catch {
        # Continue.
    }

    return $results
}


# ========================================================
# OPERATION MENU
# ========================================================

function Select-Operation {

    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host "           THE MIDDEN MINER"

    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host ""

    Write-Host "  1. New scan"
    Write-Host "  2. Recover from previous scan CSV"
    Write-Host "  3. Cancel"

    Write-Host ""

    while ($true) {

        $choice = Read-Host "Choose an option"

        switch ($choice) {

            '1' {
                return 'NewScan'
            }

            '2' {
                return 'PreviousCsv'
            }

            '3' {
                return $null
            }

            default {

                Write-Host ""
                Write-Host "Please enter a number from 1 to 3." `
                    -ForegroundColor Yellow
            }
        }
    }
}


# ========================================================
# NEW SCAN MODE MENU
# ========================================================

function Select-ScanMode {

    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host "             NEW SCAN"

    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host ""

    Write-Host "  1. Scan only"
    Write-Host "  2. Scan and recover"
    Write-Host "  3. Cancel"

    Write-Host ""

    while ($true) {

        $choice = Read-Host "Choose an option"

        switch ($choice) {

            '1' {
                return 'ScanOnly'
            }

            '2' {
                return 'Recover'
            }

            '3' {
                return $null
            }

            default {

                Write-Host ""
                Write-Host "Please enter a number from 1 to 3." `
                    -ForegroundColor Yellow
            }
        }
    }
}


# ========================================================
# FILE TYPE MENU
# ========================================================

function Select-FileTypes {

    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host " WHAT WOULD YOU LIKE TO RECOVER?"

    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host ""

    $menuItems = @(
        'Pictures'
        'Videos'
        'Audio'
        'Text'
        'Documents'
        'Archives'
        'Everything'
        'Custom'
        'Cancel'
    )

    for ($i = 0; $i -lt $menuItems.Count; $i++) {

        Write-Host (
            "  {0}. {1}" -f
            ($i + 1),
            $menuItems[$i]
        )
    }

    Write-Host ""

    while ($true) {

        $choice = Read-Host "Choose an option"

        switch ($choice) {

            '1' {

                return [PSCustomObject]@{
                    Name = 'Pictures'
                    Extensions = $FileCategories['Pictures']
                }
            }

            '2' {

                return [PSCustomObject]@{
                    Name = 'Videos'
                    Extensions = $FileCategories['Videos']
                }
            }

            '3' {

                return [PSCustomObject]@{
                    Name = 'Audio'
                    Extensions = $FileCategories['Audio']
                }
            }

            '4' {

                return [PSCustomObject]@{
                    Name = 'Text'
                    Extensions = $FileCategories['Text']
                }
            }

            '5' {

                return [PSCustomObject]@{
                    Name = 'Documents'
                    Extensions = $FileCategories['Documents']
                }
            }

            '6' {

                return [PSCustomObject]@{
                    Name = 'Archives'
                    Extensions = $FileCategories['Archives']
                }
            }

            '7' {

                return [PSCustomObject]@{
                    Name = 'Everything'
                    Extensions = $null
                }
            }

            '8' {

                Write-Host ""
                Write-Host "Enter file extensions separated by commas."
                Write-Host "Examples:"
                Write-Host "  .jpg,.png,.gif"
                Write-Host "  mp3,wav,flac"
                Write-Host ""

                $inputExtensions = Read-Host "Extensions"

                if ([string]::IsNullOrWhiteSpace(
                    $inputExtensions
                )) {

                    Write-Host ""
                    Write-Host "No extensions entered." `
                        -ForegroundColor Yellow

                    continue
                }

                $extensions = @(
                    $inputExtensions -split ',' |
                        ForEach-Object {

                            $extension = (
                                $_.Trim().ToLowerInvariant()
                            )

                            if (
                                $extension -and
                                -not $extension.StartsWith('.')
                            ) {

                                $extension = ".$extension"
                            }

                            if ($extension) {
                                $extension
                            }
                        } |
                        Select-Object -Unique
                )

                if ($extensions.Count -eq 0) {

                    Write-Host ""
                    Write-Host "No valid extensions were entered." `
                        -ForegroundColor Yellow

                    continue
                }

                return [PSCustomObject]@{
                    Name = 'Custom'
                    Extensions = $extensions
                }
            }

            '9' {
                return $null
            }

            default {

                Write-Host ""
                Write-Host "Please enter a number from 1 to 9." `
                    -ForegroundColor Yellow
            }
        }
    }
}


# ========================================================
# DATE RANGE MENU
# ========================================================

function Select-DateRange {

    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host " WHEN WERE THEY DELETED?"

    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host ""

    Write-Host "  1. Older than a certain age"
    Write-Host "  2. Newer than a certain age"
    Write-Host "  3. Between two dates"
    Write-Host "  4. Everything"
    Write-Host "  5. Cancel"

    Write-Host ""

    while ($true) {

        $choice = Read-Host "Choose an option"

        switch ($choice) {

            '1' {

                while ($true) {

                    $monthsText = Read-Host `
                        "How many months old? (example: 6)"

                    [double]$months = 0

                    if (-not [double]::TryParse(
                        $monthsText,
                        [ref]$months
                    )) {

                        Write-Host ""
                        Write-Host "Please enter a number." `
                            -ForegroundColor Yellow

                        continue
                    }

                    if ($months -le 0) {

                        Write-Host ""
                        Write-Host "The age must be greater than zero." `
                            -ForegroundColor Yellow

                        continue
                    }

                    $cutoff = (
                        Get-Date
                    ).AddMonths(
                        -$months
                    )

                    return [PSCustomObject]@{

                        Name = (
                            "Older than $months months"
                        )

                        MinimumDate = $null

                        MaximumDate = $cutoff
                    }
                }
            }


            '2' {

                while ($true) {

                    $monthsText = Read-Host `
                        "How many months old or newer? (example: 6)"

                    [double]$months = 0

                    if (-not [double]::TryParse(
                        $monthsText,
                        [ref]$months
                    )) {

                        Write-Host ""
                        Write-Host "Please enter a number." `
                            -ForegroundColor Yellow

                        continue
                    }

                    if ($months -le 0) {

                        Write-Host ""
                        Write-Host "The age must be greater than zero." `
                            -ForegroundColor Yellow

                        continue
                    }

                    $cutoff = (
                        Get-Date
                    ).AddMonths(
                        -$months
                    )

                    return [PSCustomObject]@{

                        Name = (
                            "Newer than $months months"
                        )

                        MinimumDate = $cutoff

                        MaximumDate = $null
                    }
                }
            }


            '3' {

                while ($true) {

                    Write-Host ""
                    Write-Host "Enter dates in this format:"
                    Write-Host "  YYYY-MM-DD"
                    Write-Host ""

                    $startText = Read-Host "Starting date"

                    $endText = Read-Host "Ending date"

                    [DateTime]$startDate = (
                        [DateTime]::MinValue
                    )

                    [DateTime]$endDate = (
                        [DateTime]::MinValue
                    )

                    $startValid = [DateTime]::TryParse(
                        $startText,
                        [ref]$startDate
                    )

                    $endValid = [DateTime]::TryParse(
                        $endText,
                        [ref]$endDate
                    )

                    if (
                        -not $startValid -or
                        -not $endValid
                    ) {

                        Write-Host ""
                        Write-Host "One or both dates could not be understood." `
                            -ForegroundColor Yellow

                        continue
                    }

                    $startDate = $startDate.Date

                    $endDate = (
                        $endDate.Date
                    ).AddDays(1)

                    if ($endDate -le $startDate) {

                        Write-Host ""
                        Write-Host "The ending date must be after the starting date." `
                            -ForegroundColor Yellow

                        continue
                    }

                    return [PSCustomObject]@{

                        Name = (
                            "$($startDate.ToString('yyyy-MM-dd')) " +
                            "through " +
                            "$($endDate.AddDays(-1).ToString('yyyy-MM-dd'))"
                        )

                        MinimumDate = $startDate

                        MaximumDate = $endDate
                    }
                }
            }


            '4' {

                return [PSCustomObject]@{

                    Name = 'Everything'

                    MinimumDate = $null

                    MaximumDate = $null
                }
            }


            '5' {

                return $null
            }


            default {

                Write-Host ""
                Write-Host "Please enter a number from 1 to 5." `
                    -ForegroundColor Yellow
            }
        }
    }
}


# ========================================================
# SELECT PREVIOUS CSV
# ========================================================

function Select-PreviousScanCsv {

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object `
        System.Windows.Forms.OpenFileDialog

    $dialog.Title = (
        "Select a THE MIDDEN MINER scan CSV"
    )

    $dialog.Filter = (
        "THE MIDDEN MINER CSV (*.csv)|*.csv|" +
        "All files (*.*)|*.*"
    )

    $dialog.InitialDirectory = (
        Join-Path `
            $env:USERPROFILE `
            'Desktop'
    )

    $dialog.Multiselect = $false

    $result = $dialog.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    return $dialog.FileName
}


# ========================================================
# LOAD PREVIOUS SCAN CSV
# ========================================================

function Import-PreviousScanCsv {

    param(
        [string]$CsvPath
    )

    try {

        $rows = @(
            Import-Csv `
                -LiteralPath $CsvPath `
                -ErrorAction Stop
        )

        if ($rows.Count -eq 0) {

            Write-Host ""
            Write-Host "The selected CSV contains no records." `
                -ForegroundColor Yellow

            return $null
        }

        $requiredColumns = @(
            'OriginalPath'
            'RecyclePath'
            'MetadataPath'
            'DeletionDate'
            'OriginalSize'
            'Extension'
        )

        $properties = (
            $rows[0].PSObject.Properties.Name
        )

        foreach ($column in $requiredColumns) {

            if ($properties -notcontains $column) {

                Write-Host ""
                Write-Host "This CSV is not a compatible"
                Write-Host "THE MIDDEN MINER recovery manifest."
                Write-Host ""
                Write-Host "Missing column: $column" `
                    -ForegroundColor Red

                return $null
            }
        }

        return $rows
    }
    catch {

        Write-Host ""
        Write-Host "Could not read the selected CSV." `
            -ForegroundColor Red

        Write-Host ""
        Write-Host $_.Exception.Message `
            -ForegroundColor Red

        return $null
    }
}


# ========================================================
# VALIDATE PREVIOUS SCAN RECORD
# ========================================================

function Test-PreviousScanRecord {

    param(
        [object]$Record
    )

    $result = [PSCustomObject]@{

        Valid = $false

        Reason = ''

        RecyclePath = $null

        MetadataPath = $null
    }

    if (
        [string]::IsNullOrWhiteSpace(
            $Record.RecyclePath
        )
    ) {

        $result.Reason = 'Missing RecyclePath'

        return $result
    }

    if (
        [string]::IsNullOrWhiteSpace(
            $Record.MetadataPath
        )
    ) {

        $result.Reason = 'Missing MetadataPath'

        return $result
    }

    if (
        -not (
            Test-Path `
                -LiteralPath $Record.RecyclePath `
                -PathType Leaf
        )
    ) {

        $result.Reason = (
            'Recycle Bin file no longer exists'
        )

        return $result
    }

    if (
        -not (
            Test-Path `
                -LiteralPath $Record.MetadataPath `
                -PathType Leaf
        )
    ) {

        $result.Reason = (
            'Recycle Bin metadata no longer exists'
        )

        return $result
    }

    try {

        $metadataFile = Get-Item `
            -LiteralPath $Record.MetadataPath `
            -Force `
            -ErrorAction Stop

        $metadata = Get-RecycleBinMetadata `
            $metadataFile

        if ($null -eq $metadata) {

            $result.Reason = (
                'Current metadata could not be read'
            )

            return $result
        }

        if (
            $metadata.OriginalPath -ne
            $Record.OriginalPath
        ) {

            $result.Reason = (
                'Original path no longer matches metadata'
            )

            return $result
        }

        if (
            [int64]$metadata.OriginalSize -ne
            [int64]$Record.OriginalSize
        ) {

            $result.Reason = (
                'Original file size no longer matches metadata'
            )

            return $result
        }

        $result.Valid = $true

        $result.Reason = 'Verified'

        $result.RecyclePath = $Record.RecyclePath

        $result.MetadataPath = $Record.MetadataPath

        return $result
    }
    catch {

        $result.Reason = (
            "Validation error: $($_.Exception.Message)"
        )

        return $result
    }
}


# ========================================================
# CREATE RECOVERY RESULT OBJECT
# ========================================================

function New-RecoveryResult {

    param(
        [object]$Item,
        [string]$Destination,
        [string]$Status,
        [string]$OperationMode,
        [string]$FileTypeSelection,
        [string]$DateSelection,
        [string]$SourceScanCsv
    )

    return [PSCustomObject]@{

        OriginalPath = $Item.OriginalPath

        RecyclePath = $Item.RecyclePath

        MetadataPath = $Item.MetadataFile

        DeletionDate = $Item.DeletionDate

        OriginalSize = $Item.OriginalSize

        Extension = $Item.Extension

        Destination = $Destination

        Status = $Status

        OperationMode = $OperationMode

        FileTypeSelection = $FileTypeSelection

        DateSelection = $DateSelection

        SourceScanCsv = $SourceScanCsv
    }
}


# ========================================================
# SAVE CSV REPORT
# ========================================================

function Save-RecoveryCsv {

    param(
        [System.Collections.Generic.List[object]]$Results,
        [string]$FileTypeName,
        [string]$DateName,
        [string]$OperationMode,
        [string]$SourceScanCsv
    )

    if ($null -eq $Results -or $Results.Count -eq 0) {
        return $null
    }

    if ($CreateCsvAutomatically) {

        $saveCsv = 'Y'
    }
    else {

        Write-Host ""
        Write-Host "Would you like to save a CSV report"
        Write-Host "of this operation to your Desktop?"
        Write-Host ""

        $saveCsv = Read-Host "Save CSV report? (Y/N)"
    }

    if ($saveCsv -notmatch '^(Y|YES)$') {
        return $null
    }

    $safeFileTypeName = ConvertTo-SafePathComponent `
        $FileTypeName

    $safeDateName = ConvertTo-SafePathComponent `
        $DateName

    if (
        $OperationMode -eq 'Previous Scan Recovery' -and
        $FileTypeName -eq 'Previous Scan'
    ) {

        $csvFileName = (
            "$RunTimestampFile " +
            "TMM Recovery Previous Scan.csv"
        )
    }
    else {

        $csvFileName = (
            "$RunTimestampFile " +
            "TMM Recovery " +
            "$safeFileTypeName " +
            "$safeDateName.csv"
        )
    }

    $csvPath = Join-Path `
        $env:USERPROFILE `
        "Desktop\$csvFileName"

    # Avoid overwriting a report if the same timestamp is
    # somehow used more than once.

    $csvPath = Get-UniqueDestinationPath `
        $csvPath

    $Results |
        Export-Csv `
            -Path $csvPath `
            -NoTypeInformation `
            -Encoding UTF8

    Write-Host ""
    Write-Host "CSV report saved to:"
    Write-Host "  $csvPath" `
        -ForegroundColor Green

    return $csvPath
}


# ========================================================
# RECOVER ITEM
# ========================================================

function Recover-RecycleItem {

    param(
        [object]$Item,
        [string]$OperationMode,
        [string]$FileTypeSelection,
        [string]$DateSelection,
        [string]$SourceScanCsv
    )

    $destinationPath = Get-RecoveryPath `
        $Item.OriginalPath

    if ($null -eq $destinationPath) {

        return New-RecoveryResult `
            -Item $Item `
            -Destination '' `
            -Status 'FAILED - Invalid recovery path' `
            -OperationMode $OperationMode `
            -FileTypeSelection $FileTypeSelection `
            -DateSelection $DateSelection `
            -SourceScanCsv $SourceScanCsv
    }

    $destinationDirectory = Split-Path `
        -Parent `
        $destinationPath

    try {

        if (
            -not (
                Test-Path `
                    -LiteralPath $destinationDirectory
            )
        ) {

            New-Item `
                -ItemType Directory `
                -Path $destinationDirectory `
                -Force |
                Out-Null
        }

        $finalDestination = Get-UniqueDestinationPath `
            $destinationPath

        Copy-Item `
            -LiteralPath $Item.RecyclePath `
            -Destination $finalDestination `
            -Force `
            -ErrorAction Stop

        Write-Host "RECOVERED:" `
            -ForegroundColor Green

        Write-Host "  $($Item.OriginalPath)"

        Write-Host "  -> $finalDestination"

        Write-Host ""

        return New-RecoveryResult `
            -Item $Item `
            -Destination $finalDestination `
            -Status 'Recovered' `
            -OperationMode $OperationMode `
            -FileTypeSelection $FileTypeSelection `
            -DateSelection $DateSelection `
            -SourceScanCsv $SourceScanCsv
    }
    catch {

        Write-Host "FAILED:" `
            -ForegroundColor Red

        Write-Host "  $($Item.OriginalPath)"

        Write-Host "  $($_.Exception.Message)"

        Write-Host ""

        return New-RecoveryResult `
            -Item $Item `
            -Destination '' `
            -Status "FAILED - $($_.Exception.Message)" `
            -OperationMode $OperationMode `
            -FileTypeSelection $FileTypeSelection `
            -DateSelection $DateSelection `
            -SourceScanCsv $SourceScanCsv
    }
}


# ========================================================
# MAIN PROGRAM
# ========================================================

try {

    Clear-Host

    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host "           THE MIDDEN MINER"

    Write-Host "========================================" `
        -ForegroundColor Cyan

    Write-Host ""

    Write-Host "A non-destructive Windows Recycle Bin"
    Write-Host "scanning and recovery utility."

    Write-Host ""

    Write-Host "The original Recycle Bin contents are"
    Write-Host "never deleted or modified."

    Write-Host ""


    # ====================================================
    # SELECT OPERATION
    # ====================================================

    $operation = Select-Operation

    if ($null -eq $operation) {

        Write-Host ""
        Write-Host "Operation cancelled."

        exit
    }


    # ====================================================
    # NEW SCAN
    # ====================================================

    if ($operation -eq 'NewScan') {

        $scanMode = Select-ScanMode

        if ($null -eq $scanMode) {

            Write-Host ""
            Write-Host "Operation cancelled."

            exit
        }


        # ------------------------------------------------
        # FILE TYPE
        # ------------------------------------------------

        $fileSelection = Select-FileTypes

        if ($null -eq $fileSelection) {

            Write-Host ""
            Write-Host "Operation cancelled."

            exit
        }


        # ------------------------------------------------
        # DATE RANGE
        # ------------------------------------------------

        $dateSelection = Select-DateRange

        if ($null -eq $dateSelection) {

            Write-Host ""
            Write-Host "Operation cancelled."

            exit
        }


        # ------------------------------------------------
        # DISPLAY SELECTION
        # ------------------------------------------------

        Write-Host ""
        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host " SEARCH SELECTION"

        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host ""

        Write-Host "Mode:         $scanMode"

        Write-Host "File type:    $($fileSelection.Name)"

        Write-Host "Date range:   $($dateSelection.Name)"

        Write-Host ""

        if ($fileSelection.Extensions) {

            Write-Host "Extensions:"

            Write-Host (
                "  " +
                ($fileSelection.Extensions -join ', ')
            )

            Write-Host ""
        }


        # ------------------------------------------------
        # FIND FILESYSTEM DRIVES
        # ------------------------------------------------

        Write-Host "Searching for Recycle Bins..." `
            -ForegroundColor Cyan

        Write-Host ""

        $drives = Get-PSDrive `
            -PSProvider FileSystem |
            Where-Object {
                $_.Root -match '^[A-Z]:\\$'
            }

        $allItems = New-Object `
            System.Collections.Generic.List[object]

        foreach ($drive in $drives) {

            $recycleBinRoot = Join-Path `
                $drive.Root `
                '$Recycle.Bin'

            Write-Host (
                "Checking $recycleBinRoot ..."
            )

            $items = Get-RecycleBinItems `
                $recycleBinRoot

            foreach ($item in $items) {
                $allItems.Add($item)
            }
        }


        # ------------------------------------------------
        # APPLY FILTERS
        # ------------------------------------------------

        $matchingItems = @(
            $allItems | Where-Object {

                $typeMatches = $false

                if ($null -eq $fileSelection.Extensions) {

                    $typeMatches = $true
                }
                else {

                    $typeMatches = Test-FileExtension `
                        $_.OriginalPath `
                        $fileSelection.Extensions
                }


                $dateMatches = $true

                if ($null -ne $dateSelection.MinimumDate) {

                    if (
                        $_.DeletionDate -lt
                        $dateSelection.MinimumDate
                    ) {

                        $dateMatches = $false
                    }
                }

                if ($null -ne $dateSelection.MaximumDate) {

                    if (
                        $_.DeletionDate -ge
                        $dateSelection.MaximumDate
                    ) {

                        $dateMatches = $false
                    }
                }

                return (
                    $typeMatches -and
                    $dateMatches
                )
            }
        )


        # ------------------------------------------------
        # RESULTS
        # ------------------------------------------------

        Write-Host ""
        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host " MATCHING FILES"

        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host ""

        if ($matchingItems.Count -eq 0) {

            Write-Host "No matching files were found." `
                -ForegroundColor Yellow

            Write-Host ""
            Write-Host "Nothing was changed."

            exit
        }


        $totalBytes = 0

        foreach ($item in $matchingItems) {

            $totalBytes += $item.OriginalSize

            Write-Host "----------------------------------------"

            Write-Host (
                "Original:  $($item.OriginalPath)"
            )

            Write-Host (
                "Deleted:   $($item.DeletionDate)"
            )

            Write-Host (
                "Size:      $($item.OriginalSize) bytes"
            )

            Write-Host (
                "Type:      $($item.Extension)"
            )
        }

        Write-Host "----------------------------------------"
        Write-Host ""

        $totalMB = [Math]::Round(
            $totalBytes / 1MB,
            2
        )

        Write-Host (
            "Found $($matchingItems.Count) matching file(s)."
        ) -ForegroundColor Green

        Write-Host (
            "Total original size: $totalMB MB"
        )

        Write-Host ""


        # ------------------------------------------------
        # SCAN ONLY
        # ------------------------------------------------

        if ($scanMode -eq 'ScanOnly') {

            Write-Host "SCAN ONLY MODE" `
                -ForegroundColor Yellow

            Write-Host ""

            Write-Host "No files will be copied."

            Write-Host "The results can be saved as a"
            Write-Host "recovery manifest CSV."

            Write-Host ""

            $scanResults = New-Object `
                System.Collections.Generic.List[object]

            foreach ($item in $matchingItems) {

                $scanResults.Add(
                    (New-RecoveryResult `
                        -Item $item `
                        -Destination '' `
                        -Status 'Scan Only' `
                        -OperationMode 'Scan Only' `
                        -FileTypeSelection $fileSelection.Name `
                        -DateSelection $dateSelection.Name `
                        -SourceScanCsv '')
                )
            }

            $csvPath = Save-RecoveryCsv `
                -Results $scanResults `
                -FileTypeName $fileSelection.Name `
                -DateName $dateSelection.Name `
                -OperationMode 'Scan Only' `
                -SourceScanCsv ''

            Write-Host ""
            Write-Host "Scan complete."
            Write-Host ""

            exit
        }


        # ------------------------------------------------
        # RECOVERY PREVIEW
        # ------------------------------------------------

        Write-Host "Recovery destination:"
        Write-Host "  $RecoveryRoot"

        Write-Host ""

        Write-Host "The original Recycle Bin items"
        Write-Host "will NOT be deleted."

        Write-Host "Recovered files will be COPIED"
        Write-Host "to the destination."

        Write-Host ""


        # ------------------------------------------------
        # FINAL CONFIRMATION
        # ------------------------------------------------

        Write-Host "========================================" `
            -ForegroundColor Red

        Write-Host "        READY TO RECOVER FILES"

        Write-Host "========================================" `
            -ForegroundColor Red

        Write-Host ""

        Write-Host "You are about to COPY"
        Write-Host "$($matchingItems.Count) file(s)"
        Write-Host "to:"
        Write-Host ""
        Write-Host "  $RecoveryRoot"

        Write-Host ""

        Write-Host "The original files in the Recycle Bin"
        Write-Host "will remain untouched."

        Write-Host ""

        $confirmation = Read-Host `
            "Type YES to begin recovery"

        if ($confirmation -ne 'YES') {

            Write-Host ""
            Write-Host "Recovery cancelled."
            Write-Host "Nothing was changed."

            exit
        }


        # ------------------------------------------------
        # CREATE RECOVERY ROOT
        # ------------------------------------------------

        if (
            -not (
                Test-Path `
                    -LiteralPath $RecoveryRoot
            )
        ) {

            New-Item `
                -ItemType Directory `
                -Path $RecoveryRoot `
                -Force |
                Out-Null
        }


        # ------------------------------------------------
        # RECOVER FILES
        # ------------------------------------------------

        Write-Host ""
        Write-Host "Recovering files..." `
            -ForegroundColor Cyan

        Write-Host ""

        $recoveryResults = New-Object `
            System.Collections.Generic.List[object]

        $recoveredCount = 0

        $failedCount = 0

        foreach ($item in $matchingItems) {

            $result = Recover-RecycleItem `
                -Item $item `
                -OperationMode 'New Scan Recovery' `
                -FileTypeSelection $fileSelection.Name `
                -DateSelection $dateSelection.Name `
                -SourceScanCsv ''

            $recoveryResults.Add($result)

            if ($result.Status -eq 'Recovered') {

                $recoveredCount++
            }
            else {

                $failedCount++
            }
        }


        # ------------------------------------------------
        # SUMMARY
        # ------------------------------------------------

        Write-Host ""
        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host "             RECOVERY COMPLETE"

        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host ""

        Write-Host (
            "Files found:       $($matchingItems.Count)"
        )

        Write-Host (
            "Files recovered:   $recoveredCount"
        )

        Write-Host (
            "Files failed:      $failedCount"
        )

        Write-Host ""

        Write-Host "Recovered files are located at:"
        Write-Host ""
        Write-Host "  $RecoveryRoot"

        Write-Host ""

        Write-Host "The original Recycle Bin contents"
        Write-Host "were not deleted."

        Write-Host ""


        # ------------------------------------------------
        # CSV
        # ------------------------------------------------

        $csvPath = Save-RecoveryCsv `
            -Results $recoveryResults `
            -FileTypeName $fileSelection.Name `
            -DateName $dateSelection.Name `
            -OperationMode 'New Scan Recovery' `
            -SourceScanCsv ''

        Write-Host ""
        Write-Host "Recovery operation finished."

        exit
    }


    # ====================================================
    # RECOVER FROM PREVIOUS CSV
    # ====================================================

    if ($operation -eq 'PreviousCsv') {

        Write-Host ""
        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host "    RECOVER FROM PREVIOUS SCAN"

        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host ""

        Write-Host "Select a THE MIDDEN MINER scan CSV."
        Write-Host ""

        $previousCsv = Select-PreviousScanCsv

        if ([string]::IsNullOrWhiteSpace($previousCsv)) {

            Write-Host ""
            Write-Host "No CSV selected."
            Write-Host "Operation cancelled."

            exit
        }

        Write-Host ""
        Write-Host "Selected:"
        Write-Host "  $previousCsv"

        Write-Host ""

        $previousRows = Import-PreviousScanCsv `
            -CsvPath $previousCsv

        if ($null -eq $previousRows) {

            exit
        }


        # ------------------------------------------------
        # READ SELECTION INFORMATION
        # ------------------------------------------------

        $previousFileType = 'Previous Scan'

        $previousDate = 'Previous Scan'

        if (
            $previousRows[0].PSObject.Properties.Name `
            -contains 'FileTypeSelection'
        ) {

            if (
                -not [string]::IsNullOrWhiteSpace(
                    $previousRows[0].FileTypeSelection
                )
            ) {

                $previousFileType = (
                    $previousRows[0].FileTypeSelection
                )
            }
        }

        if (
            $previousRows[0].PSObject.Properties.Name `
            -contains 'DateSelection'
        ) {

            if (
                -not [string]::IsNullOrWhiteSpace(
                    $previousRows[0].DateSelection
                )
            ) {

                $previousDate = (
                    $previousRows[0].DateSelection
                )
            }
        }


        # ------------------------------------------------
        # VALIDATE EACH RECORD
        # ------------------------------------------------

        Write-Host "Rechecking Recycle Bin contents..." `
            -ForegroundColor Cyan

        Write-Host ""

        $validPreviousItems = New-Object `
            System.Collections.Generic.List[object]

        $missingCount = 0

        foreach ($row in $previousRows) {

            $validation = Test-PreviousScanRecord `
                -Record $row

            if ($validation.Valid) {

                $validPreviousItems.Add(
                    [PSCustomObject]@{

                        RecyclePath = (
                            $validation.RecyclePath
                        )

                        MetadataFile = (
                            $validation.MetadataPath
                        )

                        OriginalPath = (
                            $row.OriginalPath
                        )

                        OriginalSize = (
                            [int64]$row.OriginalSize
                        )

                        DeletionDate = (
                            [DateTime]$row.DeletionDate
                        )

                        Extension = (
                            $row.Extension
                        )
                    }
                )
            }
            else {

                $missingCount++
            }
        }


        # ------------------------------------------------
        # VALIDATION SUMMARY
        # ------------------------------------------------

        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host "       PREVIOUS SCAN VALIDATION"

        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host ""

        Write-Host (
            "Records in CSV:       $($previousRows.Count)"
        )

        Write-Host (
            "Still recoverable:    $($validPreviousItems.Count)"
        )

        Write-Host (
            "No longer available:  $missingCount"
        )

        Write-Host ""

        if ($validPreviousItems.Count -eq 0) {

            Write-Host "None of the files in this manifest"
            Write-Host "are still available in the Recycle Bin."

            Write-Host ""
            Write-Host "Nothing was changed."

            exit
        }


        # ------------------------------------------------
        # DISPLAY VALID ITEMS
        # ------------------------------------------------

        Write-Host "Files still available:"
        Write-Host ""

        foreach ($item in $validPreviousItems) {

            Write-Host "----------------------------------------"

            Write-Host (
                "Original:  $($item.OriginalPath)"
            )

            Write-Host (
                "Deleted:   $($item.DeletionDate)"
            )

            Write-Host (
                "Size:      $($item.OriginalSize) bytes"
            )

            Write-Host (
                "Type:      $($item.Extension)"
            )
        }

        Write-Host "----------------------------------------"
        Write-Host ""


        # ------------------------------------------------
        # RECOVERY PREVIEW
        # ------------------------------------------------

        Write-Host "Recovery destination:"
        Write-Host "  $RecoveryRoot"

        Write-Host ""

        Write-Host "The original Recycle Bin items"
        Write-Host "will NOT be deleted."

        Write-Host "Recovered files will be COPIED"
        Write-Host "to the destination."

        Write-Host ""

        Write-Host "========================================" `
            -ForegroundColor Red

        Write-Host "      READY TO RECOVER FROM CSV"

        Write-Host "========================================" `
            -ForegroundColor Red

        Write-Host ""

        Write-Host "You are about to COPY"
        Write-Host "$($validPreviousItems.Count) file(s)"
        Write-Host "from the previous scan."

        Write-Host ""

        Write-Host "Type YES to begin recovery."

        Write-Host ""

        $confirmation = Read-Host `
            "Confirm recovery"

        if ($confirmation -ne 'YES') {

            Write-Host ""
            Write-Host "Recovery cancelled."
            Write-Host "Nothing was changed."

            exit
        }


        # ------------------------------------------------
        # CREATE RECOVERY ROOT
        # ------------------------------------------------

        if (
            -not (
                Test-Path `
                    -LiteralPath $RecoveryRoot
            )
        ) {

            New-Item `
                -ItemType Directory `
                -Path $RecoveryRoot `
                -Force |
                Out-Null
        }


        # ------------------------------------------------
        # RECOVER VALID ITEMS
        # ------------------------------------------------

        Write-Host ""
        Write-Host "Recovering files..." `
            -ForegroundColor Cyan

        Write-Host ""

        $recoveryResults = New-Object `
            System.Collections.Generic.List[object]

        $recoveredCount = 0

        $failedCount = 0

        foreach ($item in $validPreviousItems) {

            $result = Recover-RecycleItem `
                -Item $item `
                -OperationMode 'Previous Scan Recovery' `
                -FileTypeSelection $previousFileType `
                -DateSelection $previousDate `
                -SourceScanCsv $previousCsv

            $recoveryResults.Add($result)

            if ($result.Status -eq 'Recovered') {

                $recoveredCount++
            }
            else {

                $failedCount++
            }
        }


        # ------------------------------------------------
        # SUMMARY
        # ------------------------------------------------

        Write-Host ""
        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host "       PREVIOUS SCAN RECOVERY COMPLETE"

        Write-Host "========================================" `
            -ForegroundColor Cyan

        Write-Host ""

        Write-Host (
            "CSV records:       $($previousRows.Count)"
        )

        Write-Host (
            "Still available:   $($validPreviousItems.Count)"
        )

        Write-Host (
            "Files recovered:   $recoveredCount"
        )

        Write-Host (
            "Files failed:      $failedCount"
        )

        Write-Host ""

        Write-Host "Recovered files are located at:"
        Write-Host ""
        Write-Host "  $RecoveryRoot"

        Write-Host ""

        Write-Host "The original Recycle Bin contents"
        Write-Host "were not deleted."

        Write-Host ""


        # ------------------------------------------------
        # CSV
        # ------------------------------------------------

        $csvPath = Save-RecoveryCsv `
            -Results $recoveryResults `
            -FileTypeName $previousFileType `
            -DateName $previousDate `
            -OperationMode 'Previous Scan Recovery' `
            -SourceScanCsv $previousCsv

        Write-Host ""
        Write-Host "Recovery operation finished."

        exit
    }
}
catch {

    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Red

    Write-Host "              SCRIPT ERROR"

    Write-Host "========================================" `
        -ForegroundColor Red

    Write-Host ""

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    Write-Host ""

    Write-Host "No intentional deletion operation was performed."
}
finally {

    Wait-BeforeExit
}

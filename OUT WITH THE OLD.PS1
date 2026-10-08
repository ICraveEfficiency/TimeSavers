# ========================================================
#                   OUT WITH THE OLD
# ========================================================
#
# Do you like to keep the Windows Storage Sense setting on
# NEVER? Me too. Do you want to have more options than the 
# ones Windows provides? Me too. This script searches your
# local drive Recycle Bins for anything deleted outside of
# the retention period, which is configured at the start. 
#
# THREE MODES:
# 1. Review & Clean Up
# 2. Scan Only
# 3. Clean Up Using Saved Scan Report
#
# Use in conjuction with other TimeSavers, like the HOLLOW
# FOLDER EXPUNGER utility!
#
#
# OUT WITH THE OLD.ps1                    Copyright © 2026
# Contact me on GitHub https://github.com/ICraveEfficiency
#
# This script is free to use, redistribute, or modify, for
# personal or commercial use, with attribute and adherence
# to the GNU General Public License v3.0 (GPL-3.0).
#
# This script was developed collaboratively with ChatGPT.
# Approximate creation time: 5 hours.
#
# ========================================================
#                      CODE BEGINS
# ========================================================


$ErrorActionPreference = "Stop"

# ========================================================
# PAUSE BEFORE EXIT
# ========================================================

function Wait-BeforeExit {
Write-Host ""
Read-Host "Press Enter to close"
}

# ========================================================
# ADMINISTRATOR ELEVATION
# ========================================================

try {

$currentIdentity =
    [Security.Principal.WindowsIdentity]::GetCurrent()

$currentPrincipal =
    New-Object Security.Principal.WindowsPrincipal(
        $currentIdentity
    )

if (-not $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {

    Write-Host ""
    Write-Host "Administrator privileges are required." -ForegroundColor Yellow
    Write-Host "Restarting the script with Administrator privileges..."
    Write-Host ""

    $scriptPath = $MyInvocation.MyCommand.Path

    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw "The script path could not be determined. Run this script from a saved .ps1 file."
    }

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy"
            "Bypass"
            "-File"
            "`"$scriptPath`""
        ) `
        -Verb RunAs

    exit
}

}
catch {

Write-Host ""
Write-Host "Unable to obtain Administrator privileges." -ForegroundColor Red
Write-Host $_.Exception.Message -ForegroundColor Red

Wait-BeforeExit
exit

}

# ========================================================
# MODE SELECTION
# ========================================================

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "                     OUT WITH THE OLD" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Choose what you would like to do:"
Write-Host ""

Write-Host "  1. REVIEW & CLEAN UP" -ForegroundColor Yellow
Write-Host "     Scan, review the results, optionally save a CSV,"
Write-Host "     and optionally permanently delete the old items."
Write-Host ""

Write-Host "  2. SCAN ONLY" -ForegroundColor Green
Write-Host "     Scan and review the results; never delete items."
Write-Host ""

Write-Host "  3. CLEAN UP USING PREVIOUS REPORT CSV" -ForegroundColor Magenta
Write-Host "     Select a previous scan/review CSV and use it"
Write-Host "     as the starting point for a cleanup."
Write-Host ""

do {

$ModeInput = Read-Host "Enter 1, 2, or 3"

switch ($ModeInput) {

    '1' {
        $Mode = "Review"
        $validMode = $true
    }

    '2' {
        $Mode = "ScanOnly"
        $validMode = $true
    }

    '3' {
        $Mode = "PreviousCsv"
        $validMode = $true
    }

    default {
        Write-Host ""
        Write-Host "Please enter 1, 2, or 3." -ForegroundColor Yellow
        Write-Host ""
        $validMode = $false
    }
}

} while (-not $validMode)

# ========================================================
# RETENTION PERIOD
#
# Modes 1 and 2 establish a new scan.
#
# Mode 3 gets its retention period and cutoff date from
# the selected CSV so that the cleanup reproduces the
# criteria of the original scan.
# ========================================================

if ($Mode -ne "PreviousCsv") {

Write-Host ""
Write-Host "How many months should have elapsed since an"
Write-Host "item was deleted before it is eligible for a"
Write-Host "permanent deletion?"
Write-Host ""

Write-Host "Examples:"
Write-Host "  1  = one month"
Write-Host "  3  = three months"
Write-Host "  6  = six months"
Write-Host "  12 = one year"
Write-Host "  36 = three years"
Write-Host ""

do {

    $AgeInput = Read-Host "Enter number of months:"

    $AgeInMonths = 0

    $validNumber =
        [int]::TryParse(
            $AgeInput,
            [ref]$AgeInMonths
        )

    if (-not $validNumber -or $AgeInMonths -le 0) {

        Write-Host ""
        Write-Host "Please enter a whole number greater than zero." -ForegroundColor Yellow
        Write-Host ""
    }

} while (-not $validNumber -or $AgeInMonths -le 0)

$CutoffDate = (Get-Date).AddMonths(-$AgeInMonths)

}

# ========================================================
# FUNCTION: READ $I METADATA
# ========================================================

function Read-RecycleBinMetadata {

param (
    [Parameter(Mandatory = $true)]
    [string]$MetadataPath
)

$stream = $null
$reader = $null

try {

    $stream = [System.IO.File]::Open(
        $MetadataPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )

    $reader = New-Object System.IO.BinaryReader($stream)

    # Modern Windows $I format:
    #
    # Offset 0   = format/version
    # Offset 8   = original file size
    # Offset 16  = deletion FILETIME
    # Offset 24  = original path, UTF-16LE

    if ($stream.Length -lt 24) {
        return $null
    }

    $version = $reader.ReadInt64()
    $sizeBytes = $reader.ReadInt64()
    $deletionFileTime = $reader.ReadInt64()

    if ($deletionFileTime -le 0) {
        return $null
    }

    try {

        $deletionDate =
            [DateTime]::FromFileTimeUtc(
                $deletionFileTime
            ).ToLocalTime()

    }
    catch {

        return $null
    }

    $pathBytes =
        $reader.ReadBytes(
            [int]($stream.Length - 24)
        )

    $originalPath =
        [System.Text.Encoding]::Unicode.GetString(
            $pathBytes
        ).TrimEnd([char]0)

    if ([string]::IsNullOrWhiteSpace($originalPath)) {
        return $null
    }

    return [PSCustomObject]@{
        Version        = $version
        SizeBytes      = $sizeBytes
        DeletionDate   = $deletionDate
        OriginalPath   = $originalPath
    }

}
catch {

    return $null
}
finally {

    if ($reader) {
        $reader.Dispose()
    }
    elseif ($stream) {
        $stream.Dispose()
    }
}

}

# ========================================================
# FUNCTION: PROCESS ONE $I FILE
# ========================================================

function Get-RecycleBinItem {

param (
    [Parameter(Mandatory = $true)]
    [System.IO.FileInfo]$MetadataFile
)

try {

    if (-not $MetadataFile.Name.StartsWith('$I')) {
        return $null
    }

    $metadata =
        Read-RecycleBinMetadata `
            -MetadataPath $MetadataFile.FullName

    if ($null -eq $metadata) {
        return $null
    }

    # $Iabcdef... pairs with $Rabcdef...

    $rName =
        '$R' + $MetadataFile.Name.Substring(2)

    $rPath =
        Join-Path `
            -Path $MetadataFile.DirectoryName `
            -ChildPath $rName

    if (-not (Test-Path -LiteralPath $rPath)) {
        return $null
    }

    $rItem =
        Get-Item `
            -LiteralPath $rPath `
            -Force `
            -ErrorAction Stop

    if ($rItem.PSIsContainer) {
        $type = "Folder"
    }
    else {
        $type = "File"
    }

    $sizeMB =
        [Math]::Round(
            ($metadata.SizeBytes / 1MB),
            2
        )

    return [PSCustomObject]@{
        Type          = $type
        OriginalPath  = $metadata.OriginalPath
        DeletedFile   = $rPath
        MetadataFile  = $MetadataFile.FullName
        DeletionDate  = $metadata.DeletionDate
        SizeBytes     = $metadata.SizeBytes
        SizeMB        = $sizeMB
    }

}
catch {

    return $null
}

}

# ========================================================
# FUNCTION: SCAN ONE RECYCLE BIN
# ========================================================

function Get-RecycleBinItems {

param (
    [Parameter(Mandatory = $true)]
    [string]$RecycleBinPath
)

$results = @()

if (-not (Test-Path -LiteralPath $RecycleBinPath)) {
    return $results
}

try {

    # ------------------------------------------------
    # Scan $I files directly in the Recycle Bin root.
    # ------------------------------------------------

    $rootMetadataFiles =
        Get-ChildItem `
            -LiteralPath $RecycleBinPath `
            -File `
            -Force `
            -Filter '$I*' `
            -ErrorAction SilentlyContinue

    foreach ($metadataFile in $rootMetadataFiles) {

        $item =
            Get-RecycleBinItem `
                -MetadataFile $metadataFile

        if ($null -ne $item) {
            $results += $item
        }
    }

    # ------------------------------------------------
    # Scan SID directories.
    # ------------------------------------------------

    $sidDirectories =
        Get-ChildItem `
            -LiteralPath $RecycleBinPath `
            -Directory `
            -Force `
            -ErrorAction SilentlyContinue

    foreach ($sidDirectory in $sidDirectories) {

        $metadataFiles =
            Get-ChildItem `
                -LiteralPath $sidDirectory.FullName `
                -File `
                -Force `
                -Filter '$I*' `
                -ErrorAction SilentlyContinue

        foreach ($metadataFile in $metadataFiles) {

            $item =
                Get-RecycleBinItem `
                    -MetadataFile $metadataFile

            if ($null -ne $item) {
                $results += $item
            }
        }
    }

}
catch {

    Write-Host ""
    Write-Host "Could not completely scan:" -ForegroundColor Yellow
    Write-Host $RecycleBinPath -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor DarkYellow
    Write-Host ""
}

return $results

}

# ========================================================
# FUNCTION: SAFE DELETION OF ONE ITEM
# ========================================================

function Remove-RecycleBinItemSafely {

param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Item,

    [Parameter(Mandatory = $true)]
    [DateTime]$CutoffDate
)

try {

    # ------------------------------------------------
    # Verify both records still exist.
    # ------------------------------------------------

    if (-not (Test-Path -LiteralPath $Item.DeletedFile)) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $Item.DeletionDate
            OriginalPath = $Item.OriginalPath
            SizeMB       = $Item.SizeMB
            Status       = "Skipped - item no longer exists"
            Details      = "The matching $R item could not be found."
        }
    }

    if (-not (Test-Path -LiteralPath $Item.MetadataFile)) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $Item.DeletionDate
            OriginalPath = $Item.OriginalPath
            SizeMB       = $Item.SizeMB
            Status       = "Skipped - metadata missing"
            Details      = "The matching $I metadata file could not be found."
        }
    }

    # ------------------------------------------------
    # Re-read the $I metadata.
    # ------------------------------------------------

    $currentMetadata =
        Read-RecycleBinMetadata `
            -MetadataPath $Item.MetadataFile

    if ($null -eq $currentMetadata) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $Item.DeletionDate
            OriginalPath = $Item.OriginalPath
            SizeMB       = $Item.SizeMB
            Status       = "Skipped - metadata changed"
            Details      = "The $I metadata could not be read again."
        }
    }

    # ------------------------------------------------
    # Confirm that the item STILL qualifies.
    # ------------------------------------------------

    if ($currentMetadata.DeletionDate -ge $CutoffDate) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $currentMetadata.DeletionDate
            OriginalPath = $currentMetadata.OriginalPath
            SizeMB       = [Math]::Round(
                ($currentMetadata.SizeBytes / 1MB),
                2
            )
            Status       = "Skipped - no longer qualifies"
            Details      = "The item no longer falls beyond the selected retention period."
        }
    }

    # ------------------------------------------------
    # Confirm the metadata still points to the same
    # original path that was recorded in the report.
    # ------------------------------------------------

    if ($currentMetadata.OriginalPath -ne $Item.OriginalPath) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $currentMetadata.DeletionDate
            OriginalPath = $currentMetadata.OriginalPath
            SizeMB       = [Math]::Round(
                ($currentMetadata.SizeBytes / 1MB),
                2
            )
            Status       = "Skipped - metadata changed"
            Details      = "The original path changed after the report was created."
        }
    }

    # ------------------------------------------------
    # Confirm the deletion date is the same as the
    # date recorded in the report.
    # ------------------------------------------------

    if ($currentMetadata.DeletionDate -ne $Item.DeletionDate) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $currentMetadata.DeletionDate
            OriginalPath = $currentMetadata.OriginalPath
            SizeMB       = [Math]::Round(
                ($currentMetadata.SizeBytes / 1MB),
                2
            )
            Status       = "Skipped - deletion date changed"
            Details      = "The current $I record has a different deletion date than the report."
        }
    }

    # ------------------------------------------------
    # Confirm the $I/$R filename relationship.
    # ------------------------------------------------

    $metadataName =
        Split-Path `
            -Leaf `
            -Path $Item.MetadataFile

    $expectedRName =
        '$R' + $metadataName.Substring(2)

    $actualRName =
        Split-Path `
            -Leaf `
            -Path $Item.DeletedFile

    if ($actualRName -ne $expectedRName) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $currentMetadata.DeletionDate
            OriginalPath = $currentMetadata.OriginalPath
            SizeMB       = [Math]::Round(
                ($currentMetadata.SizeBytes / 1MB),
                2
            )
            Status       = "Skipped - pair mismatch"
            Details      = "The $I and $R records no longer form the expected pair."
        }
    }

    # ------------------------------------------------
    # Re-read the actual $R item and verify its type.
    # ------------------------------------------------

    $currentRItem =
        Get-Item `
            -LiteralPath $Item.DeletedFile `
            -Force `
            -ErrorAction Stop

    $currentType =
        if ($currentRItem.PSIsContainer) {
            "Folder"
        }
        else {
            "File"
        }

    if ($currentType -ne $Item.Type) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $currentMetadata.DeletionDate
            OriginalPath = $currentMetadata.OriginalPath
            SizeMB       = [Math]::Round(
                ($currentMetadata.SizeBytes / 1MB),
                2
            )
            Status       = "Skipped - type changed"
            Details      = "The item changed between the report and deletion."
        }
    }

    # ------------------------------------------------
    # DELETE THE $R ITEM FIRST.
    # ------------------------------------------------

    if ($currentRItem.PSIsContainer) {

        Remove-Item `
            -LiteralPath $Item.DeletedFile `
            -Recurse `
            -Force `
            -ErrorAction Stop
    }
    else {

        Remove-Item `
            -LiteralPath $Item.DeletedFile `
            -Force `
            -ErrorAction Stop
    }

    # ------------------------------------------------
    # Confirm the $R item is gone.
    # ------------------------------------------------

    if (Test-Path -LiteralPath $Item.DeletedFile) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $currentMetadata.DeletionDate
            OriginalPath = $currentMetadata.OriginalPath
            SizeMB       = [Math]::Round(
                ($currentMetadata.SizeBytes / 1MB),
                2
            )
            Status       = "Partial - metadata remains"
            Details      = "The $R item was not confirmed as removed. The $I metadata was deliberately retained."
        }
    }

    # ------------------------------------------------
    # NOW DELETE THE $I METADATA.
    # ------------------------------------------------

    Remove-Item `
        -LiteralPath $Item.MetadataFile `
        -Force `
        -ErrorAction Stop

    # ------------------------------------------------
    # Confirm the metadata is gone.
    # ------------------------------------------------

    if (Test-Path -LiteralPath $Item.MetadataFile) {

        return [PSCustomObject]@{
            Type         = $Item.Type
            DeletionDate = $currentMetadata.DeletionDate
            OriginalPath = $currentMetadata.OriginalPath
            SizeMB       = [Math]::Round(
                ($currentMetadata.SizeBytes / 1MB),
                2
            )
            Status       = "Partial - metadata remains"
            Details      = "The $R item was removed, but the $I metadata remains."
        }
    }

    # ------------------------------------------------
    # SUCCESS
    # ------------------------------------------------

    return [PSCustomObject]@{
        Type         = $Item.Type
        DeletionDate = $currentMetadata.DeletionDate
        OriginalPath = $currentMetadata.OriginalPath
        SizeMB       = [Math]::Round(
            ($currentMetadata.SizeBytes / 1MB),
            2
        )
        Status       = "Deleted"
        Details      = "$R item and matching $I metadata were removed."
    }

}
catch {

    return [PSCustomObject]@{
        Type         = $Item.Type
        DeletionDate = $Item.DeletionDate
        OriginalPath = $Item.OriginalPath
        SizeMB       = $Item.SizeMB
        Status       = "Failed"
        Details      = $_.Exception.Message
    }
}

}

# ========================================================
# FUNCTION: GET PREVIOUS CSV
# ========================================================

function Select-PreviousCsv {

$desktopPath =
    [Environment]::GetFolderPath(
        "Desktop"
    )

if ([string]::IsNullOrWhiteSpace($desktopPath)) {
    $desktopPath = $env:USERPROFILE
}

# Only SCAN and REVIEW reports are valid cleanup
# source reports. CLEANED reports are deliberately
# excluded.

$csvFiles =
    @(
        Get-ChildItem `
            -LiteralPath $desktopPath `
            -File `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^\d{4}-\d{2}-\d{2} \d{2}\.\d{2} OWTO (Scan|Review) \d+mo\.csv$'
        } |
        Sort-Object LastWriteTime -Descending
    )

if ($csvFiles.Count -eq 0) {

    Write-Host ""
    Write-Host "No compatible OWTO Scan or Review CSV reports were found on the Desktop." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Run SCAN ONLY or REVIEW & CLEAN UP first and save a CSV report."
    Write-Host ""

    Wait-BeforeExit
    exit
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Magenta
Write-Host "SELECT PREVIOUS CSV REPORT" -ForegroundColor Magenta
Write-Host "========================================================" -ForegroundColor Magenta
Write-Host ""

Write-Host "The following OWTO Scan and Review reports were found:"
Write-Host ""

$number = 1

foreach ($csv in $csvFiles) {

    Write-Host "  $number. $($csv.Name)"
    Write-Host "     Modified: $($csv.LastWriteTime)"
    Write-Host ""

    $number++
}

do {

    $selection =
        Read-Host "Enter the number of the report to use"

    $selectionNumber = 0

    $validSelection =
        [int]::TryParse(
            $selection,
            [ref]$selectionNumber
        )

    if (
        -not $validSelection -or
        $selectionNumber -lt 1 -or
        $selectionNumber -gt $csvFiles.Count
    ) {

        Write-Host ""
        Write-Host "Please enter one of the listed numbers." -ForegroundColor Yellow
        Write-Host ""
        $validSelection = $false
    }

} while (-not $validSelection)

return $csvFiles[$selectionNumber - 1]

}

# ========================================================
# FUNCTION: LOAD PREVIOUS CSV
# ========================================================

function Load-PreviousCsv {

param (
    [Parameter(Mandatory = $true)]
    [System.IO.FileInfo]$CsvFile
)

try {

    $rows =
        @(
            Import-Csv `
                -LiteralPath $CsvFile.FullName `
                -ErrorAction Stop
        )

    if ($rows.Count -eq 0) {
        throw "The selected CSV contains no records."
    }

    # ------------------------------------------------
    # Validate that this looks like one of our reports.
    # ------------------------------------------------

    $requiredColumns = @(
        "ReportType"
        "RetentionMonths"
        "CutoffDate"
        "Type"
        "DeletionDate"
        "OriginalPath"
        "DeletedFile"
        "MetadataFile"
        "SizeMB"
        "Status"
        "Details"
    )

    $headers =
        $rows[0].PSObject.Properties.Name

    foreach ($requiredColumn in $requiredColumns) {

        if ($requiredColumn -notin $headers) {

            throw @"

The selected CSV is not a compatible OUT WITH THE OLD report.

Missing column:
$requiredColumn

Only reports generated by the current version of OUT WITH THE OLD
can be used with CLEAN UP FROM PREVIOUS CSV.
"@
        }
    }

    # ------------------------------------------------
    # Only Review and ScanOnly reports may be used
    # as deletion source reports.
    #
    # A cleanup-result CSV is deliberately rejected.
    # ------------------------------------------------

    $reportType =
        [string]$rows[0].ReportType

    if (
        $reportType -ne "Review" -and
        $reportType -ne "ScanOnly"
    ) {

        throw "The selected CSV is not a scan/review report. Cleanup-result reports cannot be used as deletion source reports."
    }

    # ------------------------------------------------
    # Convert report values back into objects suitable
    # for Remove-RecycleBinItemSafely.
    # ------------------------------------------------

    $items = @()

    foreach ($row in $rows) {

        if ([string]::IsNullOrWhiteSpace($row.DeletedFile)) {
            throw "A report row is missing its DeletedFile value."
        }

        if ([string]::IsNullOrWhiteSpace($row.MetadataFile)) {
            throw "A report row is missing its MetadataFile value."
        }

        try {

            $deletionDate =
                [DateTime]::Parse(
                    $row.DeletionDate
                )

        }
        catch {

            throw "A report row contains an invalid DeletionDate."
        }

        $sizeBytes = 0

        if (-not [decimal]::TryParse(
            [string]$row.SizeMB,
            [ref]$sizeBytes
        )) {
            $sizeBytes = 0
        }

        $items += [PSCustomObject]@{
            Type          = [string]$row.Type
            OriginalPath  = [string]$row.OriginalPath
            DeletedFile   = [string]$row.DeletedFile
            MetadataFile  = [string]$row.MetadataFile
            DeletionDate  = $deletionDate
            SizeBytes     = [double]$sizeBytes * 1MB
            SizeMB        = [string]$row.SizeMB
        }
    }

    # ------------------------------------------------
    # Read the original retention settings.
    # ------------------------------------------------

    $firstRow = $rows[0]

    $AgeInMonths = 0

    if (-not [int]::TryParse(
        [string]$firstRow.RetentionMonths,
        [ref]$AgeInMonths
    )) {

        throw "The selected report does not contain a valid retention period."
    }

    if ($AgeInMonths -le 0) {
        throw "The selected report contains an invalid retention period."
    }

    try {

        $CutoffDate =
            [DateTime]::Parse(
                $firstRow.CutoffDate
            )

    }
    catch {

        throw "The selected report does not contain a valid cutoff date."
    }

    return [PSCustomObject]@{
        Items        = $items
        AgeInMonths  = $AgeInMonths
        CutoffDate   = $CutoffDate
        ReportType   = $reportType
        ReportFile   = $CsvFile.FullName
    }

}
catch {

    throw $_
}

}

# ========================================================
# MODE 3: SELECT AND LOAD PREVIOUS CSV
# ========================================================

if ($Mode -eq "PreviousCsv") {

try {

    $selectedCsv =
        Select-PreviousCsv

    $previousReport =
        Load-PreviousCsv `
            -CsvFile $selectedCsv

    $oldItems =
        @(
            $previousReport.Items
        )

    $AgeInMonths =
        $previousReport.AgeInMonths

    $CutoffDate =
        $previousReport.CutoffDate

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Magenta
    Write-Host "PREVIOUS REPORT LOADED" -ForegroundColor Magenta
    Write-Host "========================================================" -ForegroundColor Magenta
    Write-Host ""

    Write-Host "Report:"
    Write-Host "  $($selectedCsv.Name)"
    Write-Host ""

    Write-Host "Original report type:"
    Write-Host "  $($previousReport.ReportType)"
    Write-Host ""

    Write-Host "Original retention period:"
    Write-Host "  $AgeInMonths month(s)"
    Write-Host ""

    Write-Host "Original cutoff date:"
    Write-Host "  $CutoffDate"
    Write-Host ""

    Write-Host "Items recorded in report:"
    Write-Host "  $($oldItems.Count)"
    Write-Host ""

    if ($oldItems.Count -eq 0) {

        Write-Host "The selected report contains no items." -ForegroundColor Yellow

        Wait-BeforeExit
        exit
    }

}
catch {

    Write-Host ""
    Write-Host "Could not use the selected CSV report." -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    Wait-BeforeExit
    exit
}

}

# ========================================================
# SETTINGS SUMMARY
# ========================================================

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "SELECTED SETTINGS" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

switch ($Mode) {

"Review" {
    Write-Host "Mode:             REVIEW & CLEAN UP" -ForegroundColor Yellow
}

"ScanOnly" {
    Write-Host "Mode:             SCAN ONLY" -ForegroundColor Green
}

"PreviousCsv" {
    Write-Host "Mode:             CLEAN UP FROM PREVIOUS CSV" -ForegroundColor Magenta
}

}

Write-Host "Retention period: $AgeInMonths month(s)"
Write-Host "Cutoff date:      $CutoffDate"
Write-Host ""

if ($Mode -eq "ScanOnly") {

Write-Host "Nothing will be deleted during this run." -ForegroundColor Green

}
elseif ($Mode -eq "Review") {

Write-Host "The scan will happen only once. If you choose to" -ForegroundColor Green
Write-Host "delete them, each item will be revalidated prior"
Write-Host "to its permanent removal and skipped if changed." -ForegroundColor Green

}
else {

Write-Host "The selected CSV is being used as the starting list." -ForegroundColor Magenta
Write-Host "Every item will be revalidated against the current"
Write-Host "Recycle Bin before anything is permanently removed." -ForegroundColor Green

}

Write-Host ""

# ========================================================
# MAIN SCAN
#
# Modes 1 and 2 perform a new scan.
#
# Mode 3 already has its list from the CSV.
# ========================================================

try {

if ($Mode -ne "PreviousCsv") {

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "SCANNING RECYCLE BINS" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Cutoff date:" -NoNewline
    Write-Host " $CutoffDate" -ForegroundColor Yellow
    Write-Host ""

    $allItems = @()

    # ------------------------------------------------
    # Find all local filesystem drives.
    # ------------------------------------------------

    $filesystemDrives =
        Get-PSDrive `
            -PSProvider FileSystem `
            -ErrorAction Stop |
        Where-Object {
            $_.Root -match '^[A-Z]:\\$'
        }

    foreach ($drive in $filesystemDrives) {

        $recycleBinPath =
            Join-Path `
                -Path $drive.Root `
                -ChildPath '$Recycle.Bin'

        if (Test-Path -LiteralPath $recycleBinPath) {

            Write-Host "Scanning $recycleBinPath ..." -ForegroundColor DarkGray

            $binItems =
                Get-RecycleBinItems `
                    -RecycleBinPath $recycleBinPath

            if ($binItems.Count -gt 0) {
                $allItems += $binItems
            }
        }
    }

    # ------------------------------------------------
    # Filter by deletion date.
    # ------------------------------------------------

    $oldItems =
        @(
            $allItems |
            Where-Object {
                $_.DeletionDate -lt $CutoffDate
            } |
            Sort-Object DeletionDate
        )

    # ====================================================
    # SCAN RESULTS
    # ====================================================

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "SCAN COMPLETE" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Total Recycle Bin records found: $($allItems.Count)"
    Write-Host "Records older than cutoff:        $($oldItems.Count)"
    Write-Host ""

    if ($oldItems.Count -eq 0) {

        Write-Host "No items meet the selected retention period." -ForegroundColor Green
        Write-Host ""
        Write-Host "Nothing needs to be deleted."

        Wait-BeforeExit
        exit
    }
}

# ====================================================
# DISPLAY QUALIFYING ITEMS
# ====================================================

Write-Host "The following items qualify:" -ForegroundColor Yellow
Write-Host ""

$displayNumber = 1

foreach ($item in $oldItems) {

    Write-Host "[$displayNumber]" -ForegroundColor Cyan
    Write-Host "Type:          $($item.Type)"
    Write-Host "Deleted:       $($item.DeletionDate)"
    Write-Host "Size:          $($item.SizeMB) MB"
    Write-Host "Original path: $($item.OriginalPath)"
    Write-Host ""

    $displayNumber++
}

# ====================================================
# MODE 3: CONFIRM BEFORE DELETION
#
# No new CSV is created at this point. The selected
# report is the source list.
# ====================================================

if ($Mode -eq "PreviousCsv") {

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Magenta
    Write-Host "READY TO CLEAN UP FROM PREVIOUS CSV" -ForegroundColor Magenta
    Write-Host "========================================================" -ForegroundColor Magenta
    Write-Host ""

    Write-Host "The above items were recorded in:"
    Write-Host ""
    Write-Host "  $($previousReport.ReportFile)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "The CSV is only the starting list." -ForegroundColor Yellow
    Write-Host "Each item will be checked against the current"
    Write-Host "Recycle Bin before it can be deleted."
    Write-Host ""

    Write-Host "Anything that was restored, moved, changed,"
    Write-Host "replaced, or otherwise no longer matches the"
    Write-Host "report will be skipped."
    Write-Host ""

    $confirmation =
        Read-Host "Type YES to permanently delete these items:"

    if ($confirmation -cne "YES") {

        Write-Host ""
        Write-Host "Deletion cancelled." -ForegroundColor Green
        Write-Host ""
        Write-Host "Nothing was deleted."

        Wait-BeforeExit
        exit
    }

}
else {


  # ====================================================
  # PREPARE REVIEW CSV
  # ====================================================

  $reviewLog = @()

  foreach ($item in $oldItems) {
  
      $reviewLog += [PSCustomObject]@{
          ReportType      = if ($Mode -eq "ScanOnly") {
              "ScanOnly"
          }
          else {
              "Review"
          }
          RetentionMonths = $AgeInMonths
          CutoffDate      = $CutoffDate
          Type            = $item.Type
          DeletionDate    = $item.DeletionDate
          OriginalPath    = $item.OriginalPath
          DeletedFile     = $item.DeletedFile
          MetadataFile    = $item.MetadataFile
          SizeMB          = $item.SizeMB
          Status          = "Would be deleted"
          Details         = "Review scan - no changes made."
      }
  }


    # ====================================================
    # OPTIONAL CSV BEFORE DELETION
    # ====================================================

    Write-Host ""
    Write-Host "Would you like to save a CSV report"
    Write-Host "of these qualifying items to your Desktop?"
    Write-Host ""
    Write-Host "(This is a review report. Nothing has been deleted yet.)"
    Write-Host ""

    $saveReviewCsv =
        Read-Host "Save CSV report? (Y/N)"

    if ($saveReviewCsv -match '^(Y|y)$') {

        $desktopPath =
            [Environment]::GetFolderPath(
                "Desktop"
            )

        if ([string]::IsNullOrWhiteSpace($desktopPath)) {
            $desktopPath = $env:USERPROFILE
        }

        # Human-readable, sortable Windows-safe timestamp.
        #
        # Example:
        # 2026-10-07 23.14 OWTO Scan 6mo.csv
        #
        $timestamp =
            Get-Date -Format "yyyy-MM-dd HH.mm"

        if ($Mode -eq "ScanOnly") {

            $csvPath =
                Join-Path `
                    -Path $desktopPath `
                    -ChildPath "$($timestamp) OWTO Scan $($AgeInMonths)mo.csv"
        }
        else {

            $csvPath =
                Join-Path `
                    -Path $desktopPath `
                    -ChildPath "$($timestamp) OWTO Review $($AgeInMonths)mo.csv"
        }

        $reviewLog |
            Export-Csv `
                -LiteralPath $csvPath `
                -NoTypeInformation `
                -Encoding UTF8

        Write-Host ""
        Write-Host "CSV report saved:" -ForegroundColor Green
        Write-Host $csvPath -ForegroundColor Green
    }
    else {

        Write-Host ""
        Write-Host "No CSV report was saved." -ForegroundColor DarkGray
    }

    # ====================================================
    # SCAN ONLY MODE
    # ====================================================

    if ($Mode -eq "ScanOnly") {

        Write-Host ""
        Write-Host "========================================================" -ForegroundColor Green
        Write-Host "SCAN ONLY COMPLETE" -ForegroundColor Green
        Write-Host "========================================================" -ForegroundColor Green
        Write-Host ""

        Write-Host "No files or folders were deleted." -ForegroundColor Green
        Write-Host "No Recycle Bin metadata was changed." -ForegroundColor Green
        Write-Host ""

        Wait-BeforeExit
        exit
    }

    # ====================================================
    # REVIEW & CLEAN UP MODE
    # ====================================================

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Yellow
    Write-Host "READY FOR CLEANUP" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "You are about to permanently delete:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  $($oldItems.Count) item(s)"
    Write-Host ""

    $totalBytes =
        ($oldItems |
            Measure-Object `
                -Property SizeBytes `
                -Sum).Sum

    $totalMB =
        [Math]::Round(
            ($totalBytes / 1MB),
            2
        )

    Write-Host "Total reported size: $totalMB MB"
    Write-Host ""

    Write-Host "IMPORTANT:" -ForegroundColor Red
    Write-Host "These items will be permanently removed."
    Write-Host "They will NOT remain recoverable via the Recycle Bin."
    Write-Host ""
    Write-Host "The script will revalidate each item immediately"
    Write-Host "before deleting it."
    Write-Host ""

    $confirmation =
        Read-Host "Type YES to permanently delete these items:"

    if ($confirmation -cne "YES") {

        Write-Host ""
        Write-Host "Deletion cancelled." -ForegroundColor Green
        Write-Host ""
        Write-Host "Nothing was deleted."

        Wait-BeforeExit
        exit
    }
}

# ====================================================
# DELETE FROM THE SELECTED LIST
#
# For Mode 1, this is the list from the current scan.
#
# For Mode 3, this is the list loaded from the selected
# previous CSV.
#
# In BOTH cases, each item is revalidated immediately
# before deletion.
# ====================================================

Write-Host ""
Write-Host "========================================================" -ForegroundColor Red
Write-Host "PERFORMING CLEANUP" -ForegroundColor Red
Write-Host "========================================================" -ForegroundColor Red
Write-Host ""

$log = @()

$deleted = 0
$partial = 0
$skipped = 0
$failed = 0

$counter = 1

foreach ($item in $oldItems) {

    Write-Host "[$counter / $($oldItems.Count)]" -ForegroundColor Cyan
    Write-Host $item.OriginalPath -ForegroundColor DarkGray

    $result =
        Remove-RecycleBinItemSafely `
            -Item $item `
            -CutoffDate $CutoffDate

    $log += $result

    switch -Wildcard ($result.Status) {

        "Deleted" {
            $deleted++
            Write-Host "  Deleted." -ForegroundColor Green
        }

        "Partial*" {
            $partial++
            Write-Host "  PARTIAL: $($result.Details)" -ForegroundColor Yellow
        }

        "Skipped*" {
            $skipped++
            Write-Host "  SKIPPED: $($result.Details)" -ForegroundColor Yellow
        }

        "Failed" {
            $failed++
            Write-Host "  FAILED: $($result.Details)" -ForegroundColor Red
        }
    }

    Write-Host ""

    $counter++
}

# ====================================================
# CLEANUP SUMMARY
# ====================================================

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "CLEANUP COMPLETE" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Successfully deleted: $deleted" -ForegroundColor Green
Write-Host "Partial operations:   $partial" -ForegroundColor Yellow
Write-Host "Skipped:              $skipped" -ForegroundColor Yellow
Write-Host "Failed:               $failed" -ForegroundColor Red
Write-Host ""

if ($partial -gt 0) {

    Write-Host "WARNING:" -ForegroundColor Yellow
    Write-Host "One or more items were only partially removed."
    Write-Host "The script deliberately avoids removing metadata"
    Write-Host "when deletion of the corresponding $R item cannot"
    Write-Host "be validated."
    Write-Host ""
}

# ====================================================
# OPTIONAL FINAL CSV
# ====================================================

Write-Host "Would you like to save a CSV report of the"
Write-Host "actual cleanup results to your Desktop?"
Write-Host ""
Write-Host "(This reports completed, skipped, partial,"
Write-Host "and failed items.)"
Write-Host ""

$saveFinalCsv =
    Read-Host "Save cleanup CSV report? (Y/N)"

if ($saveFinalCsv -match '^(Y|y)$') {

    $desktopPath =
        [Environment]::GetFolderPath(
            "Desktop"
        )

    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        $desktopPath = $env:USERPROFILE
    }

    # Human-readable, sortable Windows-safe timestamp.
    #
    # Example:
    # 2026-10-07 23.14 OWTO Cleaned 6mo.csv
    #
    $timestamp =
        Get-Date -Format "yyyy-MM-dd HH.mm"

    $csvPath =
        Join-Path `
            -Path $desktopPath `
            -ChildPath "$($timestamp) OWTO Cleaned $($AgeInMonths)mo.csv"

    $log |
        Export-Csv `
            -LiteralPath $csvPath `
            -NoTypeInformation `
            -Encoding UTF8

    Write-Host ""
    Write-Host "Cleanup CSV report saved:" -ForegroundColor Green
    Write-Host $csvPath -ForegroundColor Green
}
else {

    Write-Host ""
    Write-Host "No final CSV report was saved." -ForegroundColor DarkGray
}

# ====================================================
# FINISHED
# ====================================================

Write-Host ""
Write-Host "No further action is required." -ForegroundColor Green

Wait-BeforeExit

}
catch {

Write-Host ""
Write-Host "========================================================" -ForegroundColor Red
Write-Host "AN ERROR OCCURRED" -ForegroundColor Red
Write-Host "========================================================" -ForegroundColor Red
Write-Host ""

Write-Host $_.Exception.Message -ForegroundColor Red
Write-Host ""

Write-Host "No additional cleanup was attempted after the error."
Write-Host ""

Wait-BeforeExit

}

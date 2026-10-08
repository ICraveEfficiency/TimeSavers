# ========================================================
#                  HOLLOW FOLDER EXPUNGER
# ========================================================
#
# Have you ever wanted to search through your recycle bin,
# but found it crowded with too many files? Well, no more!
# Say goodbye to useless empty folders and zero byte files 
# with this handy little script that removes pesky clutter
# from your Recycle Bin, allowing you to see what might be
# worth restoring. Use in conjuction with other TimeSavers
# like the OUT WITH THE OLD utility!
#
# HOLLOW FOLDER EXPUNGER.ps1              Copyright © 2026
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
#                    CONFIGURATION
# ========================================================

$DryRun = $false

# ========================================================
#               ADMINISTRATOR ELEVATION
# ========================================================

$currentIdentity =
    [Security.Principal.WindowsIdentity]::GetCurrent()

$currentPrincipal =
    New-Object Security.Principal.WindowsPrincipal($currentIdentity)

if (-not $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {

    Write-Host ""
    Write-Host "Administrator privileges are required." `
        -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Requesting Administrator access..." `
        -ForegroundColor Yellow
    Write-Host ""

    try {

        $scriptPath = $MyInvocation.MyCommand.Path

        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            throw "Could not determine the script path."
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
    catch {

        Write-Host ""
        Write-Host "Could not restart the script as Administrator." `
            -ForegroundColor Red
        Write-Host ""
        Write-Host $_.Exception.Message `
            -ForegroundColor Red
        Write-Host ""

        Read-Host "Press Enter to close"
        exit
    }
}

# ========================================================
#                    HELPER FUNCTIONS
# ========================================================

function Wait-BeforeExit {

    Write-Host ""
    Read-Host "Press Enter to close"
}

# ========================================================
#                READ RECYCLE BIN METADATA
# ========================================================

function Get-RecycleBinMetadata {

    param (
        [Parameter(Mandatory = $true)]
        [string]$MetadataPath
    )

    if ([string]::IsNullOrWhiteSpace($MetadataPath)) {
        return $null
    }

    try {

        if (-not (
            Test-Path `
                -LiteralPath $MetadataPath `
                -PathType Leaf `
                -ErrorAction SilentlyContinue
        )) {
            return $null
        }

        $bytes =
            [System.IO.File]::ReadAllBytes($MetadataPath)

        if ($bytes.Length -lt 24) {
            return $null
        }

        # ------------------------------------------------
        # Windows Recycle Bin $I metadata:
        #
        #   Offset 0  = metadata version
        #   Offset 8  = original file size
        #   Offset 16 = deletion FILETIME
        #   Offset 24 = original path
        # ------------------------------------------------

        $version =
            [BitConverter]::ToInt64($bytes, 0)

        $originalSize =
            [BitConverter]::ToInt64($bytes, 8)

        $deletedTime = $null

        $fileTime =
            [BitConverter]::ToInt64($bytes, 16)

        try {

            $deletedTime =
                [DateTime]::FromFileTimeUtc($fileTime)
        }
        catch {

            $deletedTime = $null
        }

        # ------------------------------------------------
        # Read original path.
        #
        # The path is UTF-16 little-endian text beginning
        # at byte 24 and terminated by null characters.
        # ------------------------------------------------

        $originalPath = $null

        if ($bytes.Length -gt 24) {

            try {

                $pathByteCount =
                    $bytes.Length - 24

                $originalPath =
                    [System.Text.Encoding]::Unicode.GetString(
                        $bytes,
                        24,
                        $pathByteCount
                    )

                # Remove only trailing null characters.
                # Do not use Split(), as that can produce
                # an incorrect result through PowerShell's
                # overload resolution.
                $originalPath =
                    $originalPath.TrimEnd([char]0)

                if (
                    [string]::IsNullOrWhiteSpace(
                        $originalPath
                    )
                ) {
                    $originalPath = $null
                }
            }
            catch {

                $originalPath = $null
            }
        }

        return [PSCustomObject]@{
            Version      = $version
            OriginalSize = $originalSize
            DeletedTime  = $deletedTime
            OriginalPath = $originalPath
            MetadataPath = $MetadataPath
        }
    }
    catch {

        Write-Host ""
        Write-Host "Could not read metadata:" `
            -ForegroundColor Yellow
        Write-Host "  $MetadataPath" `
            -ForegroundColor Yellow
        Write-Host "  $($_.Exception.Message)" `
            -ForegroundColor Yellow
        Write-Host ""

        return $null
    }
}

# ========================================================
#             PROCESS ONE RECYCLE BIN ITEM
# ========================================================

function Process-RecycleBinItem {

    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$DeletedItem,

        [Parameter(Mandatory = $true)]
        [string]$ParentDirectory
    )

    if ([string]::IsNullOrWhiteSpace($DeletedItem.Name)) {
        return $null
    }

    # Only process $R recycle-bin records.
    if ($DeletedItem.Name -notlike '$R*') {
        return $null
    }

    if ($DeletedItem.Name.Length -lt 3) {
        return $null
    }

    # ------------------------------------------------
    # Convert:
    #
    #   $RABC123
    #
    # into:
    #
    #   $IABC123
    # ------------------------------------------------

    $iName =
        '$I' + $DeletedItem.Name.Substring(2)

    $metadataPath =
        Join-Path `
            -Path $ParentDirectory `
            -ChildPath $iName

    if ([string]::IsNullOrWhiteSpace($metadataPath)) {
        return $null
    }

    $metadata =
        Get-RecycleBinMetadata `
            -MetadataPath $metadataPath

    if ($null -eq $metadata) {

        if ($DryRun) {

            Write-Host "    No matching metadata:"
            Write-Host "      $iName" `
                -ForegroundColor Yellow
        }

        return $null
    }

    $isDirectory =
        [bool]$DeletedItem.PSIsContainer

    # ------------------------------------------------
    # Zero-byte file
    # ------------------------------------------------

    if (
        (-not $isDirectory) -and
        ($metadata.OriginalSize -eq 0)
    ) {

        return [PSCustomObject]@{
            Type         = "Zero-byte file"
            OriginalPath = $metadata.OriginalPath
            DeletedFile  = $DeletedItem.FullName
            MetadataFile = $metadataPath
            SizeBytes    = $metadata.OriginalSize
            DeletedTime  = $metadata.DeletedTime
        }
    }

    # ------------------------------------------------
    # Originally empty folder
    #
    # The Recycle Bin metadata reports zero original
    # size for an originally empty directory.
    # ------------------------------------------------

    if (
        $isDirectory -and
        ($metadata.OriginalSize -eq 0)
    ) {

        return [PSCustomObject]@{
            Type         = "Empty folder"
            OriginalPath = $metadata.OriginalPath
            DeletedFile  = $DeletedItem.FullName
            MetadataFile = $metadataPath
            SizeBytes    = $metadata.OriginalSize
            DeletedTime  = $metadata.DeletedTime
        }
    }

    return $null
}

# ========================================================
#             PROCESS A RECYCLE BIN DIRECTORY
# ========================================================

function Process-RecycleBinDirectory {

    param (
        [Parameter(Mandatory = $true)]
        [string]$RecycleBinPath
    )

    $foundItems = @()

    try {

        $rootContents = @(
            Get-ChildItem `
                -LiteralPath $RecycleBinPath `
                -Force `
                -ErrorAction Stop
        )
    }
    catch {

        Write-Host ""
        Write-Host "Could not access:" `
            -ForegroundColor Yellow
        Write-Host "  $RecycleBinPath" `
            -ForegroundColor Yellow
        Write-Host "  $($_.Exception.Message)" `
            -ForegroundColor Yellow
        Write-Host ""

        return $foundItems
    }

    # ------------------------------------------------
    # Normal Windows layout:
    #
    #   $Recycle.Bin
    #       S-1-5-21-...
    #           $R...
    #           $I...
    #
    # Some volumes can also expose $R records directly
    # beneath the Recycle Bin root, so those are handled
    # separately below.
    # ------------------------------------------------

    $sidDirectories = @(
        $rootContents |
            Where-Object {
                $_.PSIsContainer -and
                $_.Name -notlike '$R*' -and
                $_.Name -notlike '$I*'
            }
    )

    $directRecycleItems = @(
        $rootContents |
            Where-Object {
                $_.Name -like '$R*'
            }
    )

    # ------------------------------------------------
    # Process SID directories
    # ------------------------------------------------

    foreach ($sidDirectory in $sidDirectories) {

        Write-Host "  User:"
        Write-Host "    $($sidDirectory.Name)"

        try {

            $deletedItems = @(
                Get-ChildItem `
                    -LiteralPath $sidDirectory.FullName `
                    -Force `
                    -ErrorAction Stop
            )
        }
        catch {

            Write-Host "    Unable to access this Recycle Bin user." `
                -ForegroundColor Yellow
            Write-Host "    Skipping:" `
                -ForegroundColor Yellow
            Write-Host "      $($sidDirectory.FullName)" `
                -ForegroundColor Yellow
            Write-Host ""

            continue
        }

        foreach ($deletedItem in $deletedItems) {

            $result =
                Process-RecycleBinItem `
                    -DeletedItem $deletedItem `
                    -ParentDirectory $sidDirectory.FullName

            if ($null -ne $result) {
                $foundItems += $result
            }
        }
    }

    # ------------------------------------------------
    # Process direct $R records
    # ------------------------------------------------

    foreach ($deletedItem in $directRecycleItems) {

        Write-Host "  Direct Recycle Bin item:"
        Write-Host "    $($deletedItem.Name)"

        $result =
            Process-RecycleBinItem `
                -DeletedItem $deletedItem `
                -ParentDirectory $RecycleBinPath

        if ($null -ne $result) {
            $foundItems += $result
        }
    }

    return $foundItems
}

# ========================================================
#                      MAIN PROGRAM
# ========================================================

try {

    Write-Host ""
    Write-Host "======================================"
    Write-Host "WELCOME TO THE HOLLOW FOLDER EXPUNGER!"
    Write-Host "======================================"
    Write-Host ""

    Write-Host "Running with Administrator privileges." `
        -ForegroundColor Green
    Write-Host ""

    if ($DryRun) {

        Write-Host "DRY-RUN MODE ENABLED" `
            -ForegroundColor Yellow
        Write-Host "Nothing will be deleted."
        Write-Host ""
    }

    # ------------------------------------------------
    # Find Recycle Bins on all local filesystem drives
    # ------------------------------------------------

    $RecycleBinPaths =
        Get-PSDrive -PSProvider FileSystem |
        Where-Object {
            $_.Root -match '^[A-Z]:\\$'
        } |
        ForEach-Object {
            Join-Path $_.Root '$Recycle.Bin'
        }

    $ExistingRecycleBins = @(
        $RecycleBinPaths |
        Where-Object {
            Test-Path -LiteralPath $_
        }
    )

    if ($ExistingRecycleBins.Count -eq 0) {
        throw "Could not find any Recycle Bin directories."
    }

    Write-Host "Recycle Bins found:"

    foreach ($RecycleBin in $ExistingRecycleBins) {
        Write-Host "  $RecycleBin"
    }

    Write-Host ""

    # ------------------------------------------------
    # Scan
    # ------------------------------------------------

    Write-Host "Scanning Recycle Bins..."
    Write-Host ""

    $itemsToDelete = @()

    foreach ($RecycleBin in $ExistingRecycleBins) {

        Write-Host "Scanning:"
        Write-Host "  $RecycleBin"

        $results =
            Process-RecycleBinDirectory `
                -RecycleBinPath $RecycleBin

        if ($null -ne $results) {

            $itemsToDelete += $results
        }
    }

    # ------------------------------------------------
    # Categorize results
    # ------------------------------------------------

    $zeroByteFiles = @(
        $itemsToDelete |
            Where-Object {
                $_.Type -eq "Zero-byte file"
            }
    )

    $emptyFolders = @(
        $itemsToDelete |
            Where-Object {
                $_.Type -eq "Empty folder"
            }
    )

    $zeroByteFileCount =
        $zeroByteFiles.Count

    $emptyFolderCount =
        $emptyFolders.Count

    # ------------------------------------------------
    # Scan summary
    # ------------------------------------------------

    Write-Host ""
    Write-Host "========================================"
    Write-Host " SCAN COMPLETE"
    Write-Host "========================================"
    Write-Host ""

    Write-Host "Originally zero-byte files found:"
    Write-Host "  $zeroByteFileCount"
    Write-Host ""

    Write-Host "Originally empty folders found:"
    Write-Host "  $emptyFolderCount"
    Write-Host ""

    if ($itemsToDelete.Count -eq 0) {

        Write-Host "Nothing to clean up."
        Write-Host ""

        Wait-BeforeExit
        exit
    }

    # ====================================================
    #              DISPLAY QUALIFYING FILES
    # ====================================================

    if ($zeroByteFileCount -gt 0) {

        Write-Host "Zero-byte files that qualify:"
        Write-Host ""

        foreach ($item in $zeroByteFiles) {

            if ($null -ne $item.OriginalPath) {

                Write-Host "  $($item.OriginalPath)"
            }
            else {

                Write-Host "  [Original path unavailable]" `
                    -ForegroundColor Yellow

                Write-Host "    + Recycle Bin item: $($item.DeletedFile)"
            }

            Write-Host "    + original size: $($item.SizeBytes) bytes"

            if ($null -ne $item.DeletedTime) {

                Write-Host "    + deleted: $($item.DeletedTime.ToLocalTime())"
            }
        }

        Write-Host ""
    }

    if ($emptyFolderCount -gt 0) {

        Write-Host "Originally empty folders that qualify:"
        Write-Host ""

        foreach ($item in $emptyFolders) {

            if ($null -ne $item.OriginalPath) {

                Write-Host "  $($item.OriginalPath)"
            }
            else {

                Write-Host "  [Original path unavailable]" `
                    -ForegroundColor Yellow

                Write-Host "    + Recycle Bin item: $($item.DeletedFile)"
            }

            Write-Host "    + original size: $($item.SizeBytes) bytes"

            if ($null -ne $item.DeletedTime) {

                Write-Host "    + deleted: $($item.DeletedTime.ToLocalTime())"
            }
        }

        Write-Host ""
    }

    # ====================================================
    #                      DRY RUN
    # ====================================================

    if ($DryRun) {

        Write-Host "========================================"
        Write-Host " DRY-RUN COMPLETE"
        Write-Host "========================================"
        Write-Host ""

        Write-Host "Nothing was deleted."
        Write-Host ""

        Write-Host "Zero-byte files that WOULD be deleted:"
        Write-Host "  $zeroByteFileCount"
        Write-Host ""

        Write-Host "Originally empty folders that WOULD be deleted:"
        Write-Host "  $emptyFolderCount"
        Write-Host ""

        Write-Host "Total items that WOULD be removed:"
        Write-Host "  $($itemsToDelete.Count)"
        Write-Host ""

        Write-Host "To actually delete these items, change:"
        Write-Host ""
        Write-Host '    $DryRun = $true'
        Write-Host ""
        Write-Host "to:"
        Write-Host ""
        Write-Host '    $DryRun = $false'
        Write-Host ""

        Wait-BeforeExit
        exit
    }

    # ====================================================
    #                  FINAL CONFIRMATION
    # ====================================================

    Write-Host "========================================" `
        -ForegroundColor Red
    Write-Host " WARNING" `
        -ForegroundColor Red
    Write-Host "========================================" `
        -ForegroundColor Red
    Write-Host ""

    Write-Host "This will permanently remove:"
    Write-Host "  Zero-byte files: $zeroByteFileCount"
    Write-Host "  Empty folders:   $emptyFolderCount"
    Write-Host ""

    Write-Host "Items to be removed:"
    Write-Host ""

    foreach ($item in $itemsToDelete) {

        Write-Host "  [$($item.Type)]" `
            -ForegroundColor Yellow

        if ($null -ne $item.OriginalPath) {

            Write-Host "    $($item.OriginalPath)"
        }
        else {

            Write-Host "    [Original path unavailable]" `
                -ForegroundColor Yellow

            Write-Host "    Recycle Bin item: $($item.DeletedFile)"
        }
    }

    Write-Host ""

    Write-Host "These items will NOT be recoverable"
    Write-Host "through the normal Recycle Bin afterward."
    Write-Host ""

    $confirmation =
        Read-Host "Type YES to continue"

    if ($confirmation -ne "YES") {

        Write-Host ""
        Write-Host "Nothing was deleted."
        Write-Host ""

        Wait-BeforeExit
        exit
    }

    # ====================================================
    #                       DELETE
    # ====================================================

    Write-Host ""
    Write-Host "Removing qualifying Recycle Bin items..."
    Write-Host ""

    $deletedFiles = 0
    $deletedFolders = 0
    $failedFiles = 0
    $failedFolders = 0

    $log = @()

    foreach ($item in $itemsToDelete) {

        try {

            # ------------------------------------------------
            # Delete the actual $R item.
            # ------------------------------------------------

            if (
                Test-Path `
                    -LiteralPath $item.DeletedFile `
                    -ErrorAction SilentlyContinue
            ) {

                Remove-Item `
                    -LiteralPath $item.DeletedFile `
                    -Force `
                    -Recurse `
                    -ErrorAction Stop

                if ($item.Type -eq "Zero-byte file") {

                    $deletedFiles++
                }
                elseif ($item.Type -eq "Empty folder") {

                    $deletedFolders++
                }

                $log +=
                    [PSCustomObject]@{
                        Type         = $item.Type
                        OriginalPath = $item.OriginalPath
                        RecyclePath  = $item.DeletedFile
                        Status       = "Deleted"
                    }

                Write-Host "Deleted:"
                Write-Host "  $($item.OriginalPath)"
            }

            # ------------------------------------------------
            # Delete the matching $I metadata.
            # ------------------------------------------------

            if (
                Test-Path `
                    -LiteralPath $item.MetadataFile `
                    -ErrorAction SilentlyContinue
            ) {

                Remove-Item `
                    -LiteralPath $item.MetadataFile `
                    -Force `
                    -ErrorAction Stop

                $log +=
                    [PSCustomObject]@{
                        Type         = "Metadata"
                        OriginalPath = $item.OriginalPath
                        RecyclePath  = $item.MetadataFile
                        Status       = "Deleted"
                    }
            }
        }
        catch {

            if ($item.Type -eq "Zero-byte file") {

                $failedFiles++
            }
            elseif ($item.Type -eq "Empty folder") {

                $failedFolders++
            }

            $log +=
                [PSCustomObject]@{
                    Type         = $item.Type
                    OriginalPath = $item.OriginalPath
                    RecyclePath  = $item.DeletedFile
                    Status       = "FAILED: $($_.Exception.Message)"
                }

            Write-Host ""
            Write-Host "FAILED:" `
                -ForegroundColor Red

            if ($null -ne $item.OriginalPath) {

                Write-Host "  $($item.OriginalPath)" `
                    -ForegroundColor Red
            }
            else {

                Write-Host "  $($item.DeletedFile)" `
                    -ForegroundColor Red
            }

            Write-Host "  $($_.Exception.Message)" `
                -ForegroundColor Red
            Write-Host ""
        }
    }

    # ====================================================
    #                    FINAL SUMMARY
    # ====================================================

    Write-Host ""
    Write-Host "========================================"
    Write-Host " COMPLETE"
    Write-Host "========================================"
    Write-Host ""

    Write-Host "Zero-byte files found:"
    Write-Host "  $zeroByteFileCount"
    Write-Host ""

    Write-Host "Zero-byte files deleted:"
    Write-Host "  $deletedFiles"
    Write-Host ""

    Write-Host "Empty folders found:"
    Write-Host "  $emptyFolderCount"
    Write-Host ""

    Write-Host "Empty folders deleted:"
    Write-Host "  $deletedFolders"
    Write-Host ""

    Write-Host "File deletion failures:"
    Write-Host "  $failedFiles"
    Write-Host ""

    Write-Host "Folder deletion failures:"
    Write-Host "  $failedFolders"
    Write-Host ""

    Write-Host "No qualifying non-empty files were touched."
    Write-Host ""

    # ====================================================
    #                 OPTIONAL CSV REPORT
    # ====================================================

    Write-Host "Would you like to save a CSV report"
    Write-Host "of this cleanup to your Desktop?"
    Write-Host ""

    $reportChoice =
        Read-Host "Save CSV report? (Y/N)"

    if ($reportChoice -match '^(Y|YES)$') {

        try {

            $Desktop =
                [Environment]::GetFolderPath("Desktop")

            $LogFile =
                Join-Path `
                    $Desktop `
                    "RecycleBin_Empty_Items_Removed.csv"

            if ($log.Count -gt 0) {

                $log |
                    Export-Csv `
                        -LiteralPath $LogFile `
                        -NoTypeInformation `
                        -Encoding UTF8

                Write-Host ""
                Write-Host "CSV report saved to:"
                Write-Host "  $LogFile" `
                    -ForegroundColor Green
                Write-Host ""
            }
            else {

                Write-Host ""
                Write-Host "There was nothing to report."
                Write-Host ""
            }
        }
        catch {

            Write-Host ""
            Write-Host "Could not create the CSV report." `
                -ForegroundColor Red
            Write-Host ""
            Write-Host $_.Exception.Message `
                -ForegroundColor Red
            Write-Host ""
        }
    }
    else {

        Write-Host ""
        Write-Host "No CSV report was created."
        Write-Host ""
    }

    Wait-BeforeExit
}
catch {

    # ====================================================
    #                    ERROR HANDLER
    # ====================================================

    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Red
    Write-Host " SCRIPT ERROR" `
        -ForegroundColor Red
    Write-Host "========================================"
    Write-Host ""

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    Write-Host ""
    Write-Host "The script stopped."
    Write-Host ""

    Wait-BeforeExit
}

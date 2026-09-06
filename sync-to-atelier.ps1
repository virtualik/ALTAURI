# sync-to-atelier.ps1
 $rootSource = "$PSScriptRoot"
 $rootTarget = "$PSScriptRoot\..\ATELIER"

Write-Host "Synchronizing ALTAURI -> ATELIER..." -ForegroundColor Green

# 1. Synchronizing the project.xml
Write-Host "  -> Copying project.xml..." -ForegroundColor Cyan
Copy-Item -Path "$rootSource\project.xml" -Destination "$rootTarget\project.xml" -Force

# 2. Synchronizing the assets folder
Write-Host "  -> Copying Assets folder..." -ForegroundColor Cyan
if (Test-Path "$rootSource\assets") {
    robocopy "$rootSource\assets" "$rootTarget\Assets" /MIR /XD .git /NFL /NDL /NJH /NJS /nc /ns /np
} else {
    Write-Host "     Warning: Assets folder not found in ALTAURI root. Creating empty one." -ForegroundColor Yellow
    if (-Not (Test-Path "$rootTarget\assets")) {
        New-Item -ItemType Directory -Path "$rootTarget\assets" -Force | Out-Null
    }
}

# 2.5. Synchronizing the libs/usb-serial-extracted folder (usb-serial drivers for Android build)
Write-Host "  -> Copying libs/usb-serial-extracted folder..." -ForegroundColor Cyan
if (Test-Path "$rootSource\libs\usb-serial-extracted") {
    robocopy "$rootSource\libs\usb-serial-extracted" "$rootTarget\libs\usb-serial-extracted" /MIR /XD .git /NFL /NDL /NJH /NJS /nc /ns /np
} else {
    Write-Host "     Warning: libs/usb-serial-extracted folder not found in ALTAURI root." -ForegroundColor Yellow
}

# 2.6. Synchronizing the libs/ (Java-WebSocket (for WebSocket) driver for Android build)
Write-Host "  -> Copying libs/ folder..." -ForegroundColor Cyan
if (Test-Path "$rootSource\libs\") {
    robocopy "$rootSource\libs\" "$rootTarget\libs\" /MIR /XD .git /NFL /NDL /NJH /NJS /nc /ns /np
} else {
    Write-Host "     Warning: libs/ folder not found in ALTAURI root." -ForegroundColor Yellow
}

# 2.7. Synchronizing the templates folder 
#Write-Host "  -> Copying templates folder..." -ForegroundColor Cyan
#if (Test-Path "$rootSource\templates") {
#    robocopy "$rootSource\templates" "$rootTarget\templates" /MIR /XD .git /NFL /NDL /NJH /NJS /nc /ns /np
#} else {
#    Write-Host "     Warning: templates folder not found in ALTAURI root. Creating empty one." -ForegroundColor Yellow
#    if (-Not (Test-Path "$rootTarget\templates")) {
#        New-Item -ItemType Directory -Path "$rootTarget\templates" -Force | Out-Null
#    }
#}

# =========================================================================
# Synchronizing site folder (main page + styles)
# =========================================================================
Write-Host "  -> Copying site folder..." -ForegroundColor Cyan
if (Test-Path "$rootSource\site") {
    robocopy "$rootSource\site" "$rootTarget\site" /MIR /XD .git /NFL /NDL /NJH /NJS /nc /ns /np
} else {
    Write-Host "     Warning: site folder not found in ALTAURI root. Creating empty one." -ForegroundColor Yellow
    if (-Not (Test-Path "$rootTarget\site")) {
        New-Item -ItemType Directory -Path "$rootTarget\site" -Force | Out-Null
    }
}

# 3. Synchronizing src folder
 $sourceSrc = "$rootSource\src"
 $targetSrc = "$rootTarget\src"
Write-Host "  -> Copying src folder..." -ForegroundColor Cyan
robocopy $sourceSrc $targetSrc /MIR /XD .git bin obj Export /XF *.cpp *.h /NFL /NDL /NJH /NJS /nc /ns /np

# =========================================================================
# 4. Copying the main page to the local bin/ folder (for local assembly)
# =========================================================================
 $html5BinPath = "$rootSource\bin\html5\bin"
 $sitePath = "$rootSource\site"

Write-Host "  -> Copying website landing page to local HTML5 output..." -ForegroundColor Cyan

if (Test-Path $html5BinPath) {
    # -------------------------------------------------------------------------
    # I inserted this block to copy index.html into the build folder.
    if (Test-Path "$sitePath\index.html") {
        Copy-Item -Path "$sitePath\index.html" -Destination "$html5BinPath\index.html" -Force
        Write-Host "     ✓ site/index.html copied to bin/" -ForegroundColor Gray
    }
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # I inserted this block to copy Earth_EU_Dawn.png into the build folder 
    if (Test-Path "$sitePath\Earth_EU_Dawn.png") {
        Copy-Item -Path "$sitePath\Earth_EU_Dawn.png" -Destination "$html5BinPath\Earth_EU_Dawn.png" -Force
        Write-Host "     ✓ site/Earth_EU_Dawn.png copied to bin/" -ForegroundColor Gray
    }
    # -------------------------------------------------------------------------

    # --- Copying css folder ----------------------------------------------
    if (Test-Path "$sitePath\css") {
        if (-Not (Test-Path "$html5BinPath\css")) {
        New-Item -ItemType Directory -Path "$html5BinPath\css" -Force | Out-Null
        }
        Copy-Item -Path "$sitePath\css\*" -Destination "$html5BinPath\css\" -Recurse -Force
        Write-Host "     ✓ site/css/ copied to bin/" -ForegroundColor Gray
    }
    # ---------------------------------------------------------------------
    # --- Copying blueprints folder ---------------------------------------
    if (Test-Path "$sitePath\blueprints") {
        if (-Not (Test-Path "$html5BinPath\blueprints")) {
            New-Item -ItemType Directory -Path "$html5BinPath\blueprints" -Force | Out-Null
        }
        Copy-Item -Path "$sitePath\blueprints\*" -Destination "$html5BinPath\blueprints\" -Recurse -Force
        Write-Host "     ✓ site/blueprints/ copied to bin/" -ForegroundColor Gray
    }
    # ---------------------------------------------------------------------
       # --- Copying js folder --------------------------------------------
    if (Test-Path "$sitePath\js") {
        if (-Not (Test-Path "$html5BinPath\js")) {
            New-Item -ItemType Directory -Path "$html5BinPath\js" -Force | Out-Null
        }
        Copy-Item -Path "$sitePath\js\*" -Destination "$html5BinPath\js\" -Recurse -Force
        Write-Host "     ✓ site/js/ copied to bin/" -ForegroundColor Gray
    }
} else {
    Write-Host "     Note: HTML5 build folder not found. Skipping local copy." -ForegroundColor Gray
}

# Checking the result
if ($LASTEXITCODE -le 3) {
    Write-Host "✓ Sync completed successfully" -ForegroundColor Green
} else {
    Write-Host "⚠ Warning during sync (code: $LASTEXITCODE). Check if paths are correct." -ForegroundColor Yellow
}
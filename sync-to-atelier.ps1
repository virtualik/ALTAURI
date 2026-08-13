# sync-to-atelier.ps1
$rootSource = "$PSScriptRoot"
$rootTarget = "$PSScriptRoot\..\ATELIER"

Write-Host "Synchronizing ALTAURI -> ATELIER..." -ForegroundColor Green

# 1. Синхронизация project.xml
Write-Host "  -> Copying project.xml..." -ForegroundColor Cyan
Copy-Item -Path "$rootSource\project.xml" -Destination "$rootTarget\project.xml" -Force

# 2. Синхронизация папки assets
Write-Host "  -> Copying Assets folder..." -ForegroundColor Cyan
if (Test-Path "$rootSource\assets") {
    robocopy "$rootSource\assets" "$rootTarget\Assets" /MIR /XD .git /NFL /NDL /NJH /NJS /nc /ns /np
} else {
    Write-Host "     Warning: Assets folder not found in ALTAURI root. Creating empty one." -ForegroundColor Yellow
    if (-Not (Test-Path "$rootTarget\assets")) {
        New-Item -ItemType Directory -Path "$rootTarget\assets" -Force | Out-Null
    }
}

# 2.5. Синхронизация папки templates
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
# Синхронизация папки site (главная страница + стили)
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

# 3. Синхронизация папки src
$sourceSrc = "$rootSource\src"
$targetSrc = "$rootTarget\src"
Write-Host "  -> Copying src folder..." -ForegroundColor Cyan
robocopy $sourceSrc $targetSrc /MIR /XD .git bin obj Export /XF *.cpp *.h /NFL /NDL /NJH /NJS /nc /ns /np

# =========================================================================
# 4. Копирование главной страницы в локальную папку bin/ (для локальной сборки)
# =========================================================================
$html5BinPath = "$rootSource\bin\html5\bin"
$sitePath = "$rootSource\site"

Write-Host "  -> Copying website landing page to local HTML5 output..." -ForegroundColor Cyan

if (Test-Path $html5BinPath) {
	# -------------------------------------------------------------------------
	# этот блок я вставил что бы копировать index.html в build папку 
    if (Test-Path "$sitePath\index.html") {
        Copy-Item -Path "$sitePath\index.html" -Destination "$html5BinPath\index.html" -Force
        Write-Host "     ✓ site/index.html copied to bin/" -ForegroundColor Gray
    }

	# -------------------------------------------------------------------------
	# этот блок я вставил что бы копировать index.ru.html в build папку 
    if (Test-Path "$sitePath\index.ru.html") {
        Copy-Item -Path "$sitePath\index.ru.html" -Destination "$html5BinPath\index.ru.html" -Force
        Write-Host "     ✓ site/index.ru.html copied to bin/" -ForegroundColor Gray
    }

	# -------------------------------------------------------------------------
	# этот блок я вставил что бы копировать index.zh.html в build папку 
    if (Test-Path "$sitePath\index.zh.html") {
        Copy-Item -Path "$sitePath\index.zh.html" -Destination "$html5BinPath\index.zh.html" -Force
        Write-Host "     ✓ site/index.zh.html copied to bin/" -ForegroundColor Gray
    }

	# -------------------------------------------------------------------------
	# этот блок я вставил что бы копировать demo.zh.html в build папку 
    if (Test-Path "$sitePath\demo.zh.html") {
        Copy-Item -Path "$sitePath\demo.zh.html" -Destination "$html5BinPath\demo.zh.html" -Force
        Write-Host "     ✓ site/demo.zh.html copied to bin/" -ForegroundColor Gray
    }
	# -------------------------------------------------------------------------
	# -------------------------------------------------------------------------
	# этот блок я вставил что бы копировать demo.ru.html в build папку 
    if (Test-Path "$sitePath\demo.ru.html") {
        Copy-Item -Path "$sitePath\demo.ru.html" -Destination "$html5BinPath\demo.ru.html" -Force
        Write-Host "     ✓ site/demo.ru.html copied to bin/" -ForegroundColor Gray
    }
	# -------------------------------------------------------------------------
	# -------------------------------------------------------------------------
	# этот блок я вставил что бы копировать demo.html в build папку 
    if (Test-Path "$sitePath\demo.html") {
        Copy-Item -Path "$sitePath\demo.html" -Destination "$html5BinPath\demo.html" -Force
        Write-Host "     ✓ site/demo.html copied to bin/" -ForegroundColor Gray
    }
	# -------------------------------------------------------------------------
	# --- Копирование папки css -------------------------------------------
	if (Test-Path "$sitePath\css") {
		if (-Not (Test-Path "$html5BinPath\css")) {
		New-Item -ItemType Directory -Path "$html5BinPath\css" -Force | Out-Null
		}
		Copy-Item -Path "$sitePath\css\*" -Destination "$html5BinPath\css\" -Recurse -Force
		Write-Host "     ✓ site/css/ copied to bin/" -ForegroundColor Gray
    }
    # ---------------------------------------------------------------------
	# --- Копирование папки blueprints ------------------------------------
    if (Test-Path "$sitePath\blueprints") {
        if (-Not (Test-Path "$html5BinPath\blueprints")) {
            New-Item -ItemType Directory -Path "$html5BinPath\blueprints" -Force | Out-Null
        }
        Copy-Item -Path "$sitePath\blueprints\*" -Destination "$html5BinPath\blueprints\" -Recurse -Force
        Write-Host "     ✓ site/blueprints/ copied to bin/" -ForegroundColor Gray
    }
    # ---------------------------------------------------------------------
   	# --- Копирование папки js --------------------------------------------
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

# Проверка результата
if ($LASTEXITCODE -le 3) {
    Write-Host "✓ Sync completed successfully" -ForegroundColor Green
} else {
    Write-Host "⚠ Warning during sync (code: $LASTEXITCODE). Check if paths are correct." -ForegroundColor Yellow
}
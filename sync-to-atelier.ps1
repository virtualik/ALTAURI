# sync-to-atelier.ps1
$rootSource = "$PSScriptRoot"
$rootTarget = "$PSScriptRoot\..\ATELIER"

Write-Host "Synchronizing ALTAURI -> ATELIER..." -ForegroundColor Green

# 1. Синхронизация project.xml
# Write-Host "  -> Copying project.xml..." -ForegroundColor Cyan
# Copy-Item -Path "$rootSource\project.xml" -Destination "$rootTarget\project.xml" -Force

# 2. Синхронизация папки assets (ВАЖНО: с маленькой буквы, как в project.xml!)
# Linux на GitHub Actions чувствителен к регистру: Assets != assets
Write-Host "  -> Copying Assets folder..." -ForegroundColor Cyan
if (Test-Path "$rootSource\assets") {
    robocopy "$rootSource\assets" "$rootTarget\Assets" /MIR /XD .git /NFL /NDL /NJH /NJS /nc /ns /np
} else {
    Write-Host "     Warning: Assets folder not found in ALTAURI root. Creating empty one." -ForegroundColor Yellow
    if (-Not (Test-Path "$rootTarget\assets")) {
        New-Item -ItemType Directory -Path "$rootTarget\assets" -Force | Out-Null
    }
}

# 2.5. Синхронизация папки templates (с вложенной html5 и содержимым)
# Копируется рекурсивно через /MIR — подпапка html5 и все файлы внутри переносятся автоматически
Write-Host "  -> Copying templates folder..." -ForegroundColor Cyan
if (Test-Path "$rootSource\templates") {
    robocopy "$rootSource\templates" "$rootTarget\templates" /MIR /XD .git /NFL /NDL /NJH /NJS /nc /ns /np
} else {
    Write-Host "     Warning: templates folder not found in ALTAURI root. Creating empty one." -ForegroundColor Yellow
    if (-Not (Test-Path "$rootTarget\templates")) {
        New-Item -ItemType Directory -Path "$rootTarget\templates" -Force | Out-Null
    }
}

# 3. Синхронизация папки src
$sourceSrc = "$rootSource\src"
$targetSrc = "$rootTarget\src"
Write-Host "  -> Copying src folder..." -ForegroundColor Cyan
robocopy $sourceSrc $targetSrc /MIR /XD .git bin obj Export /XF *.cpp *.h /NFL /NDL /NJH /NJS /nc /ns /np

# Проверка результата (код 0-3 в robocopy означает успех)
if ($LASTEXITCODE -le 3) {
    Write-Host "✓ Sync completed successfully" -ForegroundColor Green
} else {
    Write-Host "⚠ Warning during sync (code: $LASTEXITCODE). Check if paths are correct." -ForegroundColor Yellow
}
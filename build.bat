@echo off
set "HAXE_PATH=%~1"
set "TARGET=%~2"
set "CONFIG=%~3"

if "%TARGET%"=="windows" (
    :: Передаем флаг статической линковки для windows target
    "%HAXE_PATH%\haxelib" run lime build "project.xml" windows -%CONFIG% -static -Dfdb
) else (
    "%HAXE_PATH%\haxelib" run lime build "project.xml" %TARGET% -%CONFIG% -Dfdb
)

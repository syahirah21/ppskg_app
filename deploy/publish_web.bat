@echo off
rem Builds the PPSKG website on this PC and uploads only the finished files
rem to the "web-release" branch on GitHub. The server then pulls that
rem branch, so it needs Git but not Flutter.
rem
rem Usage (from the project folder):
rem   deploy\publish_web.bat            site at the root of its address
rem   deploy\publish_web.bat /ppskg/    site in a sub-folder, e.g.
rem                                     https://geoinfo.risda.gov.my/ppskg/
setlocal

set BASE=%~1
if "%BASE%"=="" set BASE=/

cd /d "%~dp0.."
for /f "delims=" %%u in ('git remote get-url origin') do set REMOTE=%%u
rem Lets a test publish to another repository instead of GitHub.
if defined PUBLISH_REMOTE set REMOTE=%PUBLISH_REMOTE%

echo.
echo [1/3] Building the website for %BASE% (about 2 minutes)...
rem --no-web-resources-cdn keeps every file on our server, so the offline
rem copy of the site (web\offline_sw.js) has everything it needs.
call flutter build web --release --no-web-resources-cdn --base-href %BASE% || goto :error

echo.
echo [2/3] Preparing the files...
copy /y deploy\server_update.bat build\web\update.bat >nul || goto :error
rem Flutter's incremental build has occasionally left these out; put back
rem any that are missing.
for %%f in (favicon.png manifest.json web.config offline_sw.js) do (
  if not exist build\web\%%f copy /y web\%%f build\web\ >nul
)
xcopy /d /i /q /y web\icons build\web\icons >nul
cd build\web
if exist .git rmdir /s /q .git
git init -q || goto :error
git checkout -q -b web-release || goto :error
git add -A || goto :error
git commit -q -m "Website build %date% %time%" || goto :error

echo.
echo [3/3] Uploading to GitHub (branch web-release)...
git push -q -f "%REMOTE%" web-release || goto :error
rmdir /s /q .git

echo.
echo Done! Now on the server run:  update
exit /b 0

:error
echo.
echo Something went wrong above. Read the error lines, or send a screenshot
echo for help. Nothing on the server has changed.
if exist "%~dp0..\build\web\.git" rmdir /s /q "%~dp0..\build\web\.git"
exit /b 1

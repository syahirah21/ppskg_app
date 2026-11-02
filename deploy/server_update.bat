@echo off
rem Runs ON THE SERVER, inside the website folder (it is copied there as
rem update.bat by publish_web.bat). Replaces the website with the newest
rem build from the "web-release" branch on GitHub.

cd /d "%~dp0"

echo Downloading the newest website from GitHub...
git fetch -q origin web-release || goto :error
git reset -q --hard origin/web-release || goto :error

echo.
echo Done! The website is updated. Users just refresh the page.
exit /b 0

:error
echo.
echo Something went wrong above. The old website is still running.
exit /b 1

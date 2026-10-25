@echo off
setlocal
set "PATH=%ProgramFiles%\Git\cmd;%ProgramFiles%\nodejs;%APPDATA%\npm;%PATH%"

where git >nul 2>&1 || winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements || exit /b 1
where npm >nul 2>&1 || winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements || exit /b 1

call npm install -g wrangler@latest || exit /b 1
call wrangler whoami 2>&1 | findstr /c:"You are logged in" >nul || call wrangler login

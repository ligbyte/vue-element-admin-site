@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title vue-element-admin-site - 本地开发预览

echo ==========================================================
echo   vue-element-admin-site 一键启动 (VuePress 文档站)
echo ==========================================================
echo.

rem ============ 可配置项 ============
set "PORT=8080"
if not "%~1"=="" set "PORT=%~1"
rem 设为 1 可禁止自动打开浏览器
if "!NO_OPEN!"=="" set "NO_OPEN=0"

rem ============ 1. 环境检查 ============
where node >nul 2>nul
if errorlevel 1 (
  echo [错误] 未检测到 Node.js，请先安装 LTS 版本：https://nodejs.org/
  echo.
  pause
  exit /b 1
)
where npm >nul 2>nul
if errorlevel 1 (
  echo [错误] 未检测到 npm，请重新安装 Node.js 并确保 npm 已加入 PATH
  echo.
  pause
  exit /b 1
)

for /f "delims=" %%v in ('node -p "process.versions.node"') do set "NODE_VER=%%v"
for /f "delims=" %%v in ('node -p "process.versions.node.split('.')[0]"') do set "NODE_MAJOR=%%v"
echo [信息] Node.js 版本：v!NODE_VER!

rem ============ 2. Node 17+ 兼容处理 ============
rem 本项目使用 vuepress@0.14 / webpack 3，编译期依赖 MD4 哈希，
rem 而 Node 17+ 的 OpenSSL 3 默认禁用 MD4（ERR_OSSL_EVP_UNSUPPORTED），
rem 冷启动编译会直接失败，这里统一开启 legacy provider。
if !NODE_MAJOR! GEQ 17 (
  set "NODE_OPTIONS=--openssl-legacy-provider !NODE_OPTIONS!"
  echo [信息] 检测到 Node 17+，已启用 --openssl-legacy-provider 兼容模式
)

rem ============ 3. 依赖安装 ============
if not exist "node_modules\vuepress\package.json" (
  echo [信息] 未检测到依赖，正在执行 npm install ^(首次较慢，请耐心等待^)...
  echo.
  call npm install
  if errorlevel 1 (
    echo.
    echo [错误] npm install 执行失败，请检查网络或 npm 镜像配置
    echo        可尝试：npm config set registry https://registry.npmmirror.com
    echo.
    pause
    exit /b 1
  )
  echo.
  echo [信息] 依赖安装完成
) else (
  echo [信息] 依赖已就绪，跳过安装
)

rem ============ 4. 端口可用性探测 ============
rem VuePress 会占用 port 与 port+1 两个端口（后者给 ws 用），
rem 且端口被占用时它会自动换端口，导致提示地址与实际不符。
rem 这里先自己找到一对空闲端口，保证提示地址、浏览器地址、服务端口一致。
set "TRIES=0"
:checkport
set /a PORT2=!PORT!+1
set "BUSY=0"
netstat -ano | findstr /c:"LISTENING" | findstr /c:":!PORT! " >nul 2>nul
if not errorlevel 1 set "BUSY=1"
netstat -ano | findstr /c:"LISTENING" | findstr /c:":!PORT2! " >nul 2>nul
if not errorlevel 1 set "BUSY=1"
if "!BUSY!"=="0" goto :portok
echo [警告] 端口 !PORT! 已被占用，尝试 !PORT2! ...
set /a PORT=!PORT!+1
set /a TRIES=!TRIES!+1
if !TRIES! GEQ 20 (
  echo [错误] 连续 20 个端口均被占用，请手动指定：start.bat 9000
  echo.
  pause
  exit /b 1
)
goto :checkport

:portok
set "BASE=/vue-element-admin-site/"
set "SITE_URL=http://localhost:!PORT!!BASE!"

rem ============ 5. 启动开发服务（前台运行） ============
echo.
echo [信息] 本地地址：!SITE_URL!
echo [信息] 首次编译约需 10-20 秒，编译完成后浏览器会自动打开
echo [提示] 停止服务请按 Ctrl+C
echo.
echo ----------------------------------------------------------
echo.

rem 后台轮询站点，真正可访问后再打开浏览器（避免打开白页/报错页）
if "!NO_OPEN!"=="1" goto :runserver
where curl >nul 2>nul
if errorlevel 1 goto :open_delayed
start "" /min powershell -NoProfile -WindowStyle Hidden -Command "$u='!SITE_URL!'; for($i=0;$i -lt 120;$i++){ curl.exe -s --noproxy * -o NUL --max-time 2 $u; if($LASTEXITCODE -eq 0){ Start-Process $u; break }; Start-Sleep -Milliseconds 800 }"
goto :runserver

:open_delayed
start "" /min powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 25; Start-Process '!SITE_URL!'"

:runserver
call npm run dev -- -p !PORT!
set "EXIT_CODE=!errorlevel!"

echo.
echo ----------------------------------------------------------
rem 0 = 正常退出；130 / 3221225786 / -1073741510 = 用户 Ctrl+C 中断
if "!EXIT_CODE!"=="0" goto :stopped
if "!EXIT_CODE!"=="130" goto :stopped
if "!EXIT_CODE!"=="3221225786" goto :stopped
if "!EXIT_CODE!"=="-1073741510" goto :stopped

echo [错误] 服务异常退出，退出码：!EXIT_CODE!
echo [排查] 1^) 执行 npm install 重装依赖
echo        2^) 检查是否有其他 Node 进程占用端口 !PORT!
echo        3^) 删除 node_modules\.cache 后重试
echo.
pause
exit /b !EXIT_CODE!

:stopped
echo [信息] 开发服务已停止
echo.
pause
exit /b 0

@echo off
cd /d "%~dp0board_case"
call "xvlog.bat" ..\..\..\src\recognition\rtl\c3_udp_engine.v ..\..\..\src\recognition\rtl\udp_axi_endpoint.v ..\..\..\src\recognition\sim\tb_c3x2.v
findstr /C:"ERROR:" xvlog.log >nul
if not errorlevel 1 exit /b 1
call "xelab.bat" tb_c3x2 -s c3x2_sim -log sim_elab.log
findstr /C:"Built simulation snapshot c3x2_sim" sim_elab.log >nul
if errorlevel 1 exit /b 1
call "xsim.bat" c3x2_sim -runall -log simulation.log
findstr /C:"PASS all 15 convolutions" simulation.log >nul
if errorlevel 1 exit /b 1

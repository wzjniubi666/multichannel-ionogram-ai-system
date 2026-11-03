@echo off
cd /d "%~dp0board_case"
call "xvlog.bat" ..\..\..\src\recognition\rtl\arp.v ..\..\..\src\recognition\rtl\arp_rx.v ..\..\..\src\recognition\rtl\arp_tx.v ..\..\..\src\recognition\rtl\crc32.v ..\..\..\src\recognition\rtl\fifo_4096x32.v ..\..\..\src\recognition\rtl\gmii_to_rgmii.v ..\..\..\src\recognition\rtl\mdio_dri.v ..\..\..\src\recognition\rtl\mii_byte_bridge.v ..\..\..\src\recognition\rtl\net_ctrl.v ..\..\..\src\recognition\rtl\net_loop_udp.v ..\..\..\src\recognition\rtl\rgmii_rx.v ..\..\..\src\recognition\rtl\rgmii_tx.v ..\..\..\src\recognition\rtl\udp.v ..\..\..\src\recognition\rtl\udp_mdio_bridge.v ..\..\..\src\recognition\rtl\udp_rx.v ..\..\..\src\recognition\rtl\udp_tx.v ..\..\..\src\recognition\rtl\c3_udp_engine.v ..\..\..\src\recognition\rtl\udp_axi_endpoint.v ..\..\..\src\recognition\sim\tb_full.v ..\..\..\src\recognition\sim\jtag_stub.v "%XILINX_VIVADO%\data\verilog\src\glbl.v"
findstr /C:"ERROR:" xvlog.log >nul
if not errorlevel 1 exit /b 1
call "xelab.bat" tb_full glbl -L unisims_ver -s full_sim -log full_elab.log
findstr /C:"Built simulation snapshot full_sim" full_elab.log >nul
if errorlevel 1 exit /b 1
call "xsim.bat" full_sim -runall -log full_simulation.log
findstr /C:"PASS full RGMII UDP" full_simulation.log >nul
if errorlevel 1 exit /b 1

@echo off
rem IONFALL dedicated server launcher (Windows). Arguments go to the server, e.g.
rem   ionfall_server.bat --name "Office LAN" --map spire --mode tdm --bots 6
rem To stop it gracefully (players are told), run stop_server.bat or create
rem the file ionfall_server.stop next to this script.
cd /d "%~dp0"
if exist ionfall_server.stop del ionfall_server.stop
ionfall_server.exe --headless -- --stop-file "%~dp0ionfall_server.stop" %*

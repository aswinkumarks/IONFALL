@echo off
rem Asks the IONFALL server in this folder to shut down gracefully.
type nul > "%~dp0ionfall_server.stop"

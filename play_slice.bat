@echo off
rem Rue Saint-Paul vertical slice. First run: .venv\Scripts\python -m pipeline.slice_assets
start "" "%~dp0tools\godot\godot.exe" --path "%~dp0game" res://slice/slice.tscn

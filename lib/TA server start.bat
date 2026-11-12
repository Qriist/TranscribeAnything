if "%~1"=="" (
    set "PORT=8765"
) else (
    set "PORT=%~1"
)


title TA Server %PORT%
wsl -e bash -lic "source ~/miniconda3/etc/profile.d/conda.sh && conda activate ta-wsl && transcribe-anything serve --port %PORT% --model large-v3 --device whisperx --allow-client-model"
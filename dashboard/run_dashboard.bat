@echo off
echo ==============================================================================
echo Launching Insurance Medallion Live Semantic Dashboard (Streamlit)
echo ==============================================================================
cd /d "%~dp0"

echo Checking and installing required packages...
pip install -r requirements.txt

echo.
echo Starting Streamlit web application on http://localhost:8501...
streamlit run app.py
pause


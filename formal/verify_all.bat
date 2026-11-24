@echo off
setlocal
set NUSMV=C:\NuSMV\NuSMV-2.6.0-win64\bin\NuSMV.exe
if not exist "%NUSMV%" (
    echo NuSMV executable not found at %NUSMV%
    exit /b 1
)

echo ========================================================
echo Step 1: Toy Model (step1_hello.smv)
echo ========================================================
"%NUSMV%" step1_hello.smv

echo.
echo ========================================================
echo Step 2: Arbiter without Aging (step2_arbiter.smv)
echo ========================================================
"%NUSMV%" -dcx step2_arbiter.smv

echo.
echo ========================================================
echo Step 3: Complete Golden Arbiter with Aging (step3_aging.smv)
echo ========================================================
"%NUSMV%" step3_aging.smv

echo.
echo ========================================================
echo Step 4: Quantitative Bounds Verification (step4_bounds.smv)
echo ========================================================
"%NUSMV%" step4_bounds.smv

echo.
echo ========================================================
echo Step 5a: PATIENCE=4 Starvation Test (step5a_patience4.smv)
echo ========================================================
"%NUSMV%" -dcx step5a_patience4.smv

echo.
echo ========================================================
echo Step 5b: Background Priority Test (step5b_bg_priority.smv)
echo ========================================================
"%NUSMV%" -dcx step5b_bg_priority.smv

echo.
echo ========================================================
echo Verification suite completed successfully.
echo ========================================================

@echo off
setlocal

REM Find crate root by walking up from this script folder until Cargo.toml is found
set "CARGO_ROOT=%~dp0"

:find_cargo_root
if exist "%CARGO_ROOT%Cargo.toml" goto cargo_root_found
for %%I in ("%CARGO_ROOT%..") do set "NEXT_ROOT=%%~fI\"
if /i "%NEXT_ROOT%"=="%CARGO_ROOT%" goto cargo_root_not_found
set "CARGO_ROOT=%NEXT_ROOT%"
goto find_cargo_root

:cargo_root_found
cd /d "%CARGO_ROOT%"

REM Set parameters for the LED timing test. These can be overridden by environment variables
set "LED_DECODE_MODE=sparse"


if /i "%~1"=="--streaming" (
	set "LED_DECODE_MODE=streaming"
	shift
)
if /i "%~1"=="--sparse" (
	set "LED_DECODE_MODE=sparse"
	shift
)

REM LED test video path: first arg wins, otherwise use existing env var
if not "%~1"=="" set "LED_TEST_VIDEO=%~1"

if "%LED_TEST_VIDEO%"=="" (
	echo [ERROR] LED_TEST_VIDEO is not set.
	echo.
	echo Usage:
	echo   %~nx0 "D:\absolute\path\to\video.mp4"
	echo.
	echo Or set once in this shell:
	echo   set "LED_TEST_VIDEO=D:\absolute\path\to\video.mp4"
	exit /b 1
)

echo [INFO] LED_TEST_VIDEO=%LED_TEST_VIDEO%
echo [INFO] LED_DECODE_MODE=%LED_DECODE_MODE%
echo [INFO] Running: cargo test --release test_extract_led_timings -- --ignored --nocapture

cargo test --release test_extract_led_timings -- --ignored --nocapture
exit /b %ERRORLEVEL%

:cargo_root_not_found
echo [ERROR] Could not find Cargo.toml by walking up from: %~dp0
exit /b 1
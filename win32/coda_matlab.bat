 @ECHO OFF

SETLOCAL

REM User definable settings

SET MATLAB_DIR=C:\MATLAB6p5
REM Supported releases are: R11, R11.1, R12, R12.1, R13, R14, R2006a, R2006b, R2007a
SET MATLAB_RELEASE=R13

REM End of user definable settings

IF NOT "%1"=="" SET MATLAB_DIR=%1
IF NOT "%2"=="" SET MATLAB_RELEASE=%2
 
SET OUTDIR=.\matlab
SET INTDIR=.\build
SET CODASRCDIR=..\matlab
SET LIBCODADIR=Release

IF NOT EXIST "%MATLAB_DIR%\extern\include\mex.h" GOTO NO_MEX_H
IF NOT EXIST "%LIBCODADIR%\withhdf\libcoda.lib" GOTO NO_CODA_LIB
IF NOT EXIST "%HDF4_LIB%" GOTO NO_HDF4
IF NOT EXIST "%HDF5_LIB%" GOTO NO_HDF5

SET MEXFLAGS=-I. -I..\libcoda -I"%CODASRCDIR%" -DWIN32_LEAN_AND_MEAN -DWIN32 -DHAVE_CONFIG_H -v


SET COMMON_CODA_OBJECTS=


IF "%MATLAB_RELEASE%"=="R11" GOTO MATLAB_R11
IF "%MATLAB_RELEASE%"=="R11.1" GOTO MATLAB_R11
IF "%MATLAB_RELEASE%"=="R12" GOTO MATLAB_R12
IF "%MATLAB_RELEASE%"=="R12.1" GOTO MATLAB_R12
IF "%MATLAB_RELEASE%"=="R13" GOTO MATLAB_R13
IF "%MATLAB_RELEASE%"=="R14" GOTO MATLAB_R13
IF "%MATLAB_RELEASE%"=="R2006a" GOTO MATLAB_R13

GOTO UNSUPPORTED_MATLAB_RELEASE

:MATLAB_R11

SET MEX=call "%MATLAB_DIR%\bin\mex.bat"
SET MEXFLAGS=%MEXFLAGS% -DMATLAB_R11
SET COMMON_CODA_OBJECTS=%COMMON_CODA_OBJECTS% "%INTDIR%\mxCreateDoubleScalar.obj" "%INTDIR%\mxCreateNumericMatrix.obj"
SET BUILD_MXCREATEDOUBLESCALAR=1
SET BUILD_MXCREATENUMERICMATRIX=1

GOTO MATLAB_RELEASE_END

:MATLAB_R12

SET MEX=call "%MATLAB_DIR%\bin\win32\mex.bat"
SET MEXFLAGS=%MEXFLAGS% -DMATLAB_R12
SET COMMON_CODA_OBJECTS=%COMMON_CODA_OBJECTS% "%INTDIR%\mxCreateDoubleScalar.obj"
SET BUILD_MXCREATEDOUBLESCALAR=1

GOTO MATLAB_RELEASE_END

:MATLAB_R13

SET MEX=call "%MATLAB_DIR%\bin\win32\mex.bat"
SET MEXFLAGS=%MEXFLAGS% -DMATLAB_R13

:MATLAB_RELEASE_END

IF NOT EXIST "%OUTDIR%" mkdir "%OUTDIR%"
IF NOT EXIST "%INTDIR%" mkdir "%INTDIR%"

IF NOT "%BUILD_MXCREATEDOUBLESCALAR%"=="1" GOTO NO_MXCREATEDOUBLESCALAR
ECHO Compiling mxCreateDoubleScalar.c
%MEX% %MEXFLAGS% -outdir "%INTDIR%" -c "%CODASRCDIR%\mxCreateDoubleScalar.c"
:NO_MXCREATEDOUBLESCALAR

IF NOT "%BUILD_MXCREATENUMERICMATRIX%"=="1" GOTO NO_MXCREATENUMERICMATRIX
ECHO Compiling mxCreateNumericMatrix.c
%MEX% %MEXFLAGS% -outdir "%INTDIR%" -c "%CODASRCDIR%\mxCreateNumericMatrix.c"
:NO_MXCREATENUMERICMATRIX

ECHO Compiling coda-matlab-getdata.c
COPY "%CODASRCDIR%\coda-matlab-getdata.c" "%INTDIR%\codagetdata.c" > NUL
%MEX% %MEXFLAGS% -outdir "%INTDIR%" -c "%INTDIR%\codagetdata.c"

ECHO Compiling coda-matlab-traverse.c
COPY "%CODASRCDIR%\coda-matlab-traverse.c" "%INTDIR%\codatraverse.c" > NUL
%MEX% %MEXFLAGS% -outdir "%INTDIR%" -c "%INTDIR%\codatraverse.c"

ECHO Creating coda_matlab.dll
%MEX% %MEXFLAGS% -outdir "%OUTDIR%" "%CODASRCDIR%\coda_matlab.c" "%INTDIR%\codagetdata.obj" "%INTDIR%\codatraverse.obj" %COMMON_CODA_OBJECTS% "%HDF4_LIB%\hd423.lib" "%HDF4_LIB%\hm423.lib" "%JPEG_LIB%\libjpeg.lib" "%SZIP_LIB%\szlib.lib" "%ZLIB_LIB%\zlib.lib" "%HDF5_LIB%\hdf5.lib" "%LIBCODADIR%\withhdf\libcoda.lib" ws2_32.lib

ECHO Copying .m files
COPY "%CODASRCDIR%\*.m" "%OUTDIR%" > NUL

GOTO END

:NO_MEX_H
ECHO.
ECHO Unable to locate %MATLAB_DIR%\extern\include\mex.h.
ECHO.
GOTO END

:NO_CODA_LIB
ECHO.
ECHO Unable to locate %LIBCODADIR%\withhdf\libcoda.lib.
ECHO.
GOTO END

:UNSUPPORTED_MATLAB_RELEASE
ECHO.
ECHO Release %MATLAB_RELEASE% is not supported.
ECHO.
GOTO END

:NO_HDF4
ECHO.
ECHO HDF4 directory not found. Make sure HDF4 is installed and that
ECHO the system variable HDF4_LIB is properly set.
ECHO.
GOTO END

:NO_HDF5
ECHO.
ECHO HDF5 directory not found. Make sure HDF5 is installed and that
ECHO the system variable HDF5_LIB is properly set.
ECHO.
GOTO END

:END

ENDLOCAL

@echo off

cd keen4-6\static

echo Deploying Keen4E 1.4 data files.
copy /Y ..\..\K4E-14\*.CK4 .
copy /Y ..\..\K4E-14\*.EXE .

echo Trying to extract data from KEEN 4 ...
..\..\CKPATCH\ck4patch ripck4.pat
echo.

echo Trying to extract data from KEEN 5 ...
..\..\CKPATCH\ck5patch ripck5.pat
echo.

echo Trying to extract data from KEEN 6 ...
..\..\CKPATCH\ck6patch ripck6.pat
echo.

echo Converting data files to .OBJ ...
call make.bat

cd ..\..
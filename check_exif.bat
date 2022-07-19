REM Shows the exif that this script uses of all your photos
REM To use: Place this .bat file in the folder your want to test and double-click it

FOR %%i IN (*.raf) DO (
	exiftool -AutoDynamicRange %%i
	exiftool -DevelopmentDynamicRange %%i
	exiftool -RawImageAspectRatio %%i
	exiftool -FilmMode %%i
	exiftool -Saturation %%i
	)
pause
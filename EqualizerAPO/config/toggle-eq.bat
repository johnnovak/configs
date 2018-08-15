set SNARL="C:\Program Files (x86)\full phat\Snarl\tools\heysnarl.exe"

if exist config.txt goto configexists
copy config.bak config.txt
%SNARL% "notify?text=Equalizer ON&icon=!system-yes&timeout=2.5"
exit

:configexists
del config.txt
%SNARL% "notify?text=Equalizer OFF&icon=!system-no&timeout=2.5"

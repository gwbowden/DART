#!/bin/bash
# Generate obs_seq.out files for multiple dependent jobs

module load intel-compiler
module load openmpi
module load netcdf/4.7.3

year=2018
day1=305
day2=314
ndays=$(( 1+day2-day1 ))
basedir=/scratch/n23/gwb112/swm_project/GOLD_Data

dayl=152610
dayf=$((dayl-1))
secl=1800
secf=84601

input=input.nml
inputtemp=input.nml.tmp

for (( day=$day1; day<=$day2; day++ ))
#for (( day=$day1; day<=$day1; day++ ))
do
    for (( hour=0; hour<=23; hour++ ))
    #for (( hour=0; hour<=0; hour++ ))
    do
	oldfno=$(grep '\<filename_out\>' $input)
	oldfod=$(grep '\<first_obs_days\>' $input)
	oldfos=$(grep '\<first_obs_seconds\>' $input)
	oldlod=$(grep '\<last_obs_days\>' $input)
	oldlos=$(grep '\<last_obs_seconds\>' $input)
	#echo $oldfno
	#echo $oldfod
	#echo $oldfos
	#echo $oldlod
	#echo $oldlos
	
	osoname=`printf obs_seq.%04d%03d%02d.out $year $day $hour`
	newfno="filename_out       = $osoname"
	newfod="first_obs_days     = $dayf"
	newfos="first_obs_seconds  = $secf"
	newlod="last_obs_days      = $dayl"
	newlos="last_obs_seconds   = $secl"
	#echo $newfno
	#echo $newfod
	#echo $newfos
	#echo $newlod
	#echo $newlos
	#echo 's|'"$oldfno"'|'"$newfno"'|'
	sed \
	    -e 's|'"$oldfno"'|'"$newfno"'|' \
	    -e 's|'"$oldfod"'|'"$newfod"'|' \
	    -e 's|'"$oldfos"'|'"$newfos"'|' \
	    -e 's|'"$oldlod"'|'"$newlod"'|' \
	    -e 's|'"$oldlos"'|'"$newlos"'|' \
	    $input > $inputtemp
	mv $inputtemp $input
	./obs_sequence_tool
	secl=$((secl+3600))
	secf=$((secf+3600))
	if [ $hour -eq 0 ]
	then
	    echo "Wrote $osoname"
	    dayf=$((dayf+1))
	    secf=$((secf-86400))
	elif [ $hour -eq 23 ] 
	then
	    echo "Wrote $osoname"
	    dayl=$((dayl+1))
	    secl=$((secl-86400))
	else
	    echo "Wrote $osoname"
	fi
    done
done

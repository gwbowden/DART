#!/bin/bash
# Generate tiegcm ensemble

module load intel-compiler
module load openmpi
module load netcdf/4.7.3

year=2018
day1=305
day2=314
ndays=$(( 1+day2-day1 ))
basedir=/scratch/n23/gwb112/swm_project/GOLD_Data

input=input.nml
inputtemp=input.nml.tmp

nameswarm=obs_seq.out.Swarm_305_to_314_18

rm gold_list.txt
:>| gold_list.txt

for (( day=$day1; day<=$day2; day++ ))
do
    curdir=$basedir/$year/$day
#    nemaxnc=$curdir/`printf "GOLD_L2_NMAX_%04d_%03d_v01_r01_c01.nc" $year $day`
#    on2nc=$curdir/`printf "GOLD_L2_ON2_%04d_%03d_v02_r01_c01.nc" $year $day`
#    tdisknc=$curdir/`printf "GOLD_L2_TDISK_%04d_%03d_v02_r01_c01.nc" $year $day`
    nemaxnc=`ls $curdir/GOLD_L2_NMAX_*.nc`
    on2nc=`ls $curdir/GOLD_L2_ON2_*.nc`
    tdisknc=`ls $curdir/GOLD_L2_TDISK_*.nc`
    newnemax="gold_netcdf_file = '"$nemaxnc"'"
    newon2="gold_netcdf_file = '"$on2nc"'"
    newtdisk="gold_netcdf_file = '"$tdisknc"'"
    oldnemax=$(grep '\<gold_netcdf_file.*NMAX.*\>' $input)
    oldon2=$(grep '\<gold_netcdf_file.*ON2.*\>' $input)
    oldtdisk=$(grep '\<gold_netcdf_file.*TDISK.*\>' $input)
#    echo $oldnemax
#    echo $newnemax
    sed \
	-e 's,'"$oldnemax"','"$newnemax"',' \
	-e 's,'"$oldon2"','"$newon2"',' \
	-e 's,'"$oldtdisk"','"$newtdisk"',' \
	$input > $inputtemp
#    echo $nemaxnc
#    echo $on2nc
#    echo $tdisknc
    mv $inputtemp $input
    ./convert_gold_nemax
    ./convert_gold_on2
    ./convert_gold_tdisk
    namenemax=`printf "obs_seq.out.gold.nemax.%04d_%03d" $year $day`
    nameon2=`printf "obs_seq.out.gold.on2.%04d_%03d" $year $day`
    nametdisk=`printf "obs_seq.out.gold.tdisk.%04d_%03d" $year $day`
    mv obs_seq.out.gold.nemax $namenemax
    mv obs_seq.out.gold.on2 $nameon2
    mv obs_seq.out.gold.tdisk $nametdisk
    echo $namenemax >> gold_list.txt
    echo $nameon2 >> gold_list.txt
    echo $nametdisk >> gold_list.txt
done
echo $nameswarm >> gold_list.txt
./obs_sequence_tool

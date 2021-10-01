#!/bin/csh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
#==========================================================================
#
# This utility is designed to be run interactively from the CENTRALDIR
#PBS -P n23
#PBS -l walltime=0:05:00
#PBS -l wd
#PBS -l ncpus=1
#PBS -l mem=100mb
#PBS -N submit_multiple_cycles
#PBS -v NCYCLES,NCYCLE
#PBS -j oe
#PBS -q express

set noglob

cd /scratch/n23/gwb112/swm_project/DART/dart_tiegcm/run_tiegcm_self_submit/job_tiegcm_rundir_20210923190819

if (! $?NCYCLES ) then
    $ECHO "NCYCLES (total number of jobs in sequence) is not set - defaulting to 1"
    setenv NCYCLES 1
endif
  
if (! $?NCYCLE) then
    $ECHO "NCYCLE (current job number in sequence) is not set - defaulting to 1"
    setenv NCYCLE 1
endif

#
# Quick termination of job sequence - look for a specific file 
#
if (-f STOP_SEQUENCE) then
    $ECHO  "Terminating sequence at job number $NCYCLE of $NCYCLES"
    exit 1
endif

if ( -e DART_params.csh ) then
   source DART_params.csh
else
   echo "ERROR: resource file 'DART_params.csh' not found."
   echo "       need one in "`pwd`
   exit 2
endif

#--------------------------------------------------------------------------
# Overall strategy is to fire off a series of dependent jobs.
# Successful completion of the first filter job will free the queued model
# advances. That successful completion of that job array will free the
# next filter job ... and so on.
#--------------------------------------------------------------------------

set ensjob = ""
set i = 1

set ENSEMBLESTRING = `grep -A 42 filter_nml input.nml | grep ens_size`
set NUM_ENS = `echo $ENSEMBLESTRING[3] | sed -e "s#,##"`

#-----------------------------------------------------------------------
# launch job array of ensemble advances and capture job ID for dependency
#-----------------------------------------------------------------------

while ( $i <= $NUM_ENS )

   echo "queueing ensemble member $i, cycle $NCYCLE of $NCYCLES"

   set submissionstring = `qsub -v PBS_ARRAY_INDEX=$i ./advance_tiegcm.csh`
   echo $submissionstring
   set ensjob = $ensjob":"`echo $submissionstring | awk '{print($1)}'`

   @ i++

end

echo $ensjob

exit 0


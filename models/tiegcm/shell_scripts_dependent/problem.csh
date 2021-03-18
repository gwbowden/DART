#!/bin/csh
#PBS -P n23
#PBS -l walltime=0:01:00
#PBS -l wd
#PBS -l ncpus=8
#PBS -l mem=32GB
#PBS -N tiegcm_advance
#PBS -m ae
##PBS -M g.bowden@adfa.edu.au
#PBS -j oe
#PBS -r y
#PBS -J 1-2

set noglob

echo "STEP 1: Set the environment (modules, variables, etc.) for this experiment."

# This string gets replaced by stage_experiment when it get copies into place.
# We need to be in the right directory before we can source DART_params.csh
cd /scratch/n23/gwb112/swm_project/DART/dart_tiegcm/run_tiegcm_dependent/job_tiegcm_rundir_20210317

if ( -e DART_params.csh ) then
   source DART_params.csh
else
   echo "ERROR: resource file 'DART_params.csh' not found."
   echo "       need one in "`pwd`
   exit 1
endif

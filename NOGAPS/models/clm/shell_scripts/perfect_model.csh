#!/bin/csh
#
# DART software - Copyright 2004 - 2013 UCAR. This open source software is
# provided by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id$

# This block is an attempt to localize all the machine-specific
# changes to this script such that the same script can be used
# on multiple platforms. This will help us maintain the script.

echo "`date` -- BEGIN GENERATE TRUE STATE"

set nonomatch       # suppress "rm" warnings if wildcard does not match anything

# The FORCE options are not optional.
# The VERBOSE options are useful for debugging though
# some systems don't like the -v option to any of the following 
switch ("`hostname`")
   case be*:
      # NCAR "bluefire"
      set   MOVE = '/usr/local/bin/mv -fv'
      set   COPY = '/usr/local/bin/cp -fv --preserve=timestamps'
      set   LINK = '/usr/local/bin/ln -fvs'
      set REMOVE = '/usr/local/bin/rm -fr'

      set BASEOBSDIR = /glade/proj3/image/Observations/FluxTower
      set DARTDIR    = ${HOME}/svn/DART/dev
   breaksw

   case ys*:
      # NCAR "yellowstone"
      set   MOVE = 'mv -fv'
      set   COPY = 'cp -fv --preserve=timestamps'
      set   LINK = 'ln -fvs'
      set REMOVE = 'rm -fr'

      set BASEOBSDIR = /glade/p/image/Observations/FluxTower
      set DARTDIR    = ${HOME}/svn/DART/dev
   breaksw

   default:
      # NERSC "hopper"
      set   MOVE = 'mv -fv'
      set   COPY = 'cp -fv --preserve=timestamps'
      set   LINK = 'ln -fvs'
      set REMOVE = 'rm -fr'

      set BASEOBSDIR = /scratch/scratchdirs/nscollin/ACARS
      set DARTDIR    = ${HOME}/devel
   breaksw
endsw

# Create temporary working directory for the assimilation
set temp_dir = assimilate_clm
echo "temp_dir is $temp_dir"

# Create a clean temporary directory and go there
if ( -d $temp_dir ) then
   ${REMOVE} $temp_dir/*
else
   mkdir -p $temp_dir
endif
cd $temp_dir

#-------------------------------------------------------------------------
# Determine time of model state ... from file name of first member
# of the form "./${CASE}.clm2_${ensemble_member}.r.2000-01-06-00000.nc"
#
# Piping stuff through 'bc' strips off any preceeding zeros.
#-------------------------------------------------------------------------

set FILE = `head -1 ../rpointer.lnd`
set FILE = $FILE:t
set FILE = $FILE:r
set MYCASE = `echo $FILE | sed -e "s#\..*##"`
set LND_DATE_EXT = `echo $FILE:e`
set LND_DATE     = `echo $FILE:e | sed -e "s#-# #g"`
set LND_YEAR     = `echo $LND_DATE[1] | bc`
set LND_MONTH    = `echo $LND_DATE[2] | bc`
set LND_DAY      = `echo $LND_DATE[3] | bc`
set LND_SECONDS  = `echo $LND_DATE[4] | bc`
set LND_HOUR     = `echo $LND_DATE[4] / 3600 | bc`

echo "valid time of model is $LND_YEAR $LND_MONTH $LND_DAY $LND_SECONDS (seconds)"
echo "valid time of model is $LND_YEAR $LND_MONTH $LND_DAY $LND_HOUR (hours)"

#-----------------------------------------------------------------------------
# Get observation sequence file ... or die right away.
# The observation file names have a time that matches the stopping time of CLM.
# The contents of the file must match the history file contents if one is using 
# the obs_def_tower_mod or could be the 'traditional' +/- 12Z ... or both.
# Since the history file contains the previous days' history ... so must the obs file.
#-----------------------------------------------------------------------------

set YYYYMMDD = `printf %04d%02d%02d ${LND_YEAR} ${LND_MONTH} ${LND_DAY}`
set YYYYMM   = `printf %04d%02d     ${LND_YEAR} ${LND_MONTH}`
set OBSFNAME = `printf obs_seq.%04d-%02d-%02d-%05d ${LND_YEAR} ${LND_MONTH} ${LND_DAY} ${LND_SECONDS}`
set OBS_FILE = ${BASEOBSDIR}/${YYYYMM}/${OBSFNAME}

if (  -e   ${OBS_FILE} ) then
   ${COPY} ${OBS_FILE} obs_seq.in
else
   echo "ERROR ... no observation file $OBS_FILE"
   echo "ERROR ... no observation file $OBS_FILE"
   exit -1
endif

#=========================================================================
# Block 1: Populate a run-time directory with the input needed to run DART.
#=========================================================================

echo "`date` -- BEGIN COPY BLOCK"

if (  -e   ${CASEROOT}/input.nml ) then
   ${COPY} ${CASEROOT}/input.nml .
else
   echo "ERROR ... DART required file ${CASEROOT}/input.nml not found ... ERROR"
   echo "ERROR ... DART required file ${CASEROOT}/input.nml not found ... ERROR"
   exit -2
endif

# Modify the DART input.nml such that casename is always correct.

ex input.nml <<ex_end
g;casename ;s;= .*;= "../$MYCASE",;
wq
ex_end

echo "`date` -- END COPY BLOCK"

#=========================================================================
# Block 2: convert 1 clm restart file to a DART initial conditions file.
# At the end of the block, we have a DART restart file  perfect_ics
# that came from the pointer file ../rpointer.lnd_0001
#
# DART namelist settings appropriate/required:
# &perfect_model_obs_nml:  restart_in_file_name    = 'perfect_ics'
# &clm_to_dart_nml:        clm_to_dart_output_file = 'dart_ics'
#=========================================================================

echo "`date` -- BEGIN CLM-TO-DART"

set member = 1

   set MYTEMPDIR = member_${member}
   mkdir -p $MYTEMPDIR
   cd $MYTEMPDIR

   set DART_IC_FILENAME = perfect_ics

   sed -e "s/dart_ics/..\/${DART_IC_FILENAME}/" < ../input.nml >! input.nml

   set POINTER_FILENAME = rpointer.lnd

   set  LND_RESTART_FILENAME = `head -1 ../../${POINTER_FILENAME}`
   set  LND_HISTORY_FILENAME = `echo ${LND_RESTART_FILENAME} | sed "s/\.r\./\.h0\./"`
   set OBS1_HISTORY_FILENAME = `echo ${LND_RESTART_FILENAME} | sed "s/\.r\./\.h1\./"`
   set OBS2_HISTORY_FILENAME = `echo ${LND_RESTART_FILENAME} | sed "s/\.r\./_0001\.h1\./"`

   ${LINK} ../../$LND_RESTART_FILENAME clm_restart.nc
   ${LINK} ../../$LND_HISTORY_FILENAME clm_history.nc

   if (-e $OBS1_HISTORY_FILENAME) then
      ${LINK} ../../$OBS1_HISTORY_FILENAME $OBS2_HISTORY_FILENAME
   endif

   # patch the CLM restart files to ensure they have the proper
   # _FillValue and missing_value attributes.
#  ncatted -O -a    _FillValue,frac_sno,o,d,1.0e+36   clm_restart.nc
#  ncatted -O -a missing_value,frac_sno,o,d,1.0e+36   clm_restart.nc
#  ncatted -O -a    _FillValue,DZSNO,o,d,1.0e+36      clm_restart.nc
#  ncatted -O -a missing_value,DZSNO,o,d,1.0e+36      clm_restart.nc
#  ncatted -O -a    _FillValue,H2OSOI_LIQ,o,d,1.0e+36 clm_restart.nc
#  ncatted -O -a missing_value,H2OSOI_LIQ,o,d,1.0e+36 clm_restart.nc
#  ncatted -O -a    _FillValue,H2OSOI_ICE,o,d,1.0e+36 clm_restart.nc
#  ncatted -O -a missing_value,H2OSOI_ICE,o,d,1.0e+36 clm_restart.nc
#  ncatted -O -a    _FillValue,T_SOISNO,o,d,1.0e+36   clm_restart.nc
#  ncatted -O -a missing_value,T_SOISNO,o,d,1.0e+36   clm_restart.nc

   ${EXEROOT}/clm_to_dart >! output.${member}.clm_to_dart

   if ($status != 0) then
      echo "ERROR ... DART died in 'clm_to_dart' ... ERROR"
      echo "ERROR ... DART died in 'clm_to_dart' ... ERROR"
      exit -3
   endif

   cd ..

echo "`date` -- END CLM-TO-DART"

#=========================================================================
# Block 3: Advance the model and harvest the synthetic observations.
# Will result in a single file : 'perfect_restart' which we don't need
# for a perfect model experiment with CESM.
#
# DART namelist settings required:
# &perfect_model_obs_nml:           async                  = 0,
# &perfect_model_obs_nml:           adv_ens_command        = "./no_model_advance.csh",
# &perfect_model_obs_nml:           restart_in_file_name   = 'perfect_ics'
# &perfect_model_obs_nml:           restart_out_file_name  = 'perfect_restart'
# &perfect_model_obs_nml:           obs_sequence_in_name   = 'obs_seq.in'
# &perfect_model_obs_nml:           obs_sequence_out_name  = 'obs_seq.out'
# &perfect_model_obs_nml:           init_time_days         = -1,
# &perfect_model_obs_nml:           init_time_seconds      = -1,
# &perfect_model_obs_nml:           first_obs_days         = -1,
# &perfect_model_obs_nml:           first_obs_seconds      = -1,
# &perfect_model_obs_nml:           last_obs_days          = -1,
# &perfect_model_obs_nml:           last_obs_seconds       = -1,
#
#=========================================================================

# clm always needs a clm_restart.nc, clm_history.nc for geometry information, etc.

set LND_RESTART_FILENAME = `head -1 ../rpointer.lnd`
set LND_HISTORY_FILENAME = `echo ${LND_RESTART_FILENAME} | sed "s/\.r\./\.h0\./"`

${LINK} ../$LND_RESTART_FILENAME clm_restart.nc
${LINK} ../$LND_HISTORY_FILENAME clm_history.nc

echo "`date` -- BEGIN PERFECT_MODEL_OBS"
${EXEROOT}/perfect_model_obs || exit -4
echo "`date` -- END PERFECT_MODEL_OBS"

${MOVE} True_State.nc    ../clm_True_State.${LND_DATE_EXT}.nc
${MOVE} obs_seq.out      ../obs_seq.${LND_DATE_EXT}.out
${MOVE} dart_log.out     ../clm_dart_log.${LND_DATE_EXT}.out

#=========================================================================
# Block 4: Update the clm restart files.
#=========================================================================

# not needed ... perfect_model_obs does not update the model state.

#-------------------------------------------------------------------------
# Cleanup
#-------------------------------------------------------------------------

echo "`date` -- END   GENERATE TRUE STATE"

exit 0

# <next few lines under version control, do not edit>
# $URL$
# $Revision$
# $Date$


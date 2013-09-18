#!/bin/csh -f
#
# DART software - Copyright 2004 - 2013 UCAR. This open source software is
# provided by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id$

# ---------------------
# Purpose
# ---------------------
#
# This script is designed to configure and build a multi-instance CESM model
# that has POP as the only active component
# and will use DART to assimilate observations at regular intervals.
#
# This script relies heavily on the information in:
# http://www.cesm.ucar.edu/models/cesm1.1/cesm/doc/usersguide/book1.html
#
# ---------------------
# How to use this script.
# ---------------------
#
# -- You will have to read and understand the script in its entirety.
#    You will have to modify things outside this script.
#    This script sets up a CESM multi-instance run as we understand them and
#    it has almost nothing to do with DART. This is intentional.
#
# -- Edit and run this script in the $DART/models/CESM/shell_scripts directory
#    or copy it to somewhere that it will be preserved and run it there.
#    It will create a CESM 'CASE' directory, where the model will be built,
#    and an execution directory, where each forecast (and assimilation) will
#    take place.  The short term archiver will use a third directory for
#    storage of model output until it can be moved to long term storage (HPSS)
#
# -- Examine the whole script to identify things to change for your experiments.
#
# -- Provide the CESM initial ensemble needed by your run.
#
# -- Run this script.
#
# -- If you want to run DART; read, understand, and execute ${CASEROOT}/CESM_DART_config
#
# -- Submit the job using ${CASEROOT}/${CASE}.submit
#
# ---------------------
# Important features
# ---------------------
#
# If you want to change something in your case other than the runtime
# settings, it is safest to delete everything and start the run from scratch.
# For the brave, read
#
# http://www.cesm.ucar.edu/models/cesm1.1/cesm/doc/usersguide/x1142.html
#
# and you may be able to salvage something with
# ./cesm_setup -clean
# ./cesm_setup
# ./${case}.clean_build
# ./${case}.build
#
# ==============================================================================
# ====  Set case options
# ==============================================================================

# the value of "case" will be used many ways;
#    directory and file names, both locally and on HPSS, and
#    script names; so consider it's length and information content.
# num_instances:  Number of ensemble members

setenv case                 pop_test2
setenv compset              GIAF
setenv resolution           T62_gx1v6
setenv cesmtag              cesm1_1_1
setenv num_instances        4

# ==============================================================================
# define machines and directories
#
# mach            Computer name
# cesmroot        Location of the cesm code base
#                 For cesm1_1_1 on yellowstone
# caseroot        Your (future) cesm case directory, where this CESM+DART will be built.
#                    Preferably not a frequently scrubbed location.
#                    This script will delete any existing caseroot, so this script,
#                    and other useful things should be kept elsewhere.
# rundir          (Future) Run-time directory; scrubbable, large amount of space needed.
# exeroot         (Future) directory for executables - scrubbable, large amount of space needed.
# archdir         (Future) Short-term archive directory
#                    until the long-term archiver moves it to permanent storage.
# dartroot        Location of _your_ DART installation
#                    This is passed on to the CESM_DART_config script.
# ==============================================================================

setenv mach         yellowstone
setenv cesmroot     /glade/p/cesm/cseg/collections/$cesmtag
setenv caseroot     /glade/p/work/${USER}/cases/${case}
setenv exeroot      /glade/scratch/${USER}/${case}/bld
setenv rundir       /glade/scratch/${USER}/${case}/run
setenv archdir      /glade/scratch/${USER}/archive/${case}
setenv dartroot     /glade/u/home/${USER}/svn/DART/trunk

# ==============================================================================
# configure settings
# The reference case has dates in it.
# For a 'hybrid' start, these may be unrelated to the refyear, refmon, refday.
# ==============================================================================

setenv run_refcase cesm_hybrid
setenv refyear     2004
setenv refmon      01
setenv refday      10
setenv run_reftod  00000
setenv run_refdate $refyear-$refmon-$refday

setenv stream_year_first 2004
setenv stream_year_last  2004
setenv stream_year_align 2004

# THIS IS THE LOCATION of the 'reference case'.

setenv stagedir /glade/p/image/CESM_initial_ensemble/rest/2004-01-10-00000

# ==============================================================================
# runtime settings
#
# resubmit      How many job steps to run on continue runs (will be 0 initially)
# stop_option   Units for determining the forecast length between assimilations
# stop_n        Number of time units in the first forecast
# assim_n       Number of time units between assimilations
#
# If the long-term archiver is off, you get a chance to examine the files before
# they get moved to long-term storage. You can always submit $CASE.l_archive
# whenever you want to free up space in the short-term archive directory.
#
# ==============================================================================

setenv short_term_archiver on
setenv long_term_archiver  off
setenv resubmit            0
setenv stop_option         ndays
setenv stop_n              3
setenv assim_n             1

# ==============================================================================
# job settings
#
# queue      can be changed during a series by changing the ${case}.run
# timewall   can be changed during a series by changing the ${case}.run
#
# TJH: Advancing 30 instances for 72 hours with 900 pes (30*15*2) with
#      an assimilation step took less than 7 minutes on yellowstone.
#
# ==============================================================================

setenv ACCOUNT      P8685xxxx
setenv queue        economy
setenv timewall     0:20

# ==============================================================================
# set these standard commands based on the machine you are running on.
# ==============================================================================

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

   breaksw
   default:
      # NERSC "hopper", NWSC "yellowstone"
      set   MOVE = '/bin/mv -fv'
      set   COPY = '/bin/cp -fv --preserve=timestamps'
      set   LINK = '/bin/ln -fvs'
      set REMOVE = '/bin/rm -fr'

   breaksw
endsw

# ==============================================================================
# Make sure the CESM directories exist.
# VAR is the shell variable name, DIR is the value
# ==============================================================================

foreach VAR ( cesmroot dartroot stagedir )
   set DIR = `eval echo \${$VAR}`
   if ( ! -d $DIR ) then
      echo "ERROR: directory '$DIR' not found"
      echo " In the setup script check the setting of: $VAR "
      exit -1
   endif
end

# ==============================================================================
# Create the case - this creates the CASEROOT directory.
#
# For list of the pre-defined cases: ./create_newcase -list
# To create a variant case, see the CESM documentation and carefully
# incorporate any needed changes into this script.
# ==============================================================================

# fatal idea to make caseroot the same dir as where this setup script is
# since the build process removes all files in the caseroot dir before
# populating it.  try to prevent shooting yourself in the foot.

if ( $caseroot == `dirname $0` ) then
   echo "ERROR: the setup script should not be located in the caseroot"
   echo "directory, because all files in the caseroot dir will be removed"
   echo "before creating the new case.  move the script to a safer place."
   exit -1
endif

echo "removing old files from ${caseroot}"
echo "removing old files from ${exeroot}"
echo "removing old files from ${rundir}"
${REMOVE} ${caseroot}
${REMOVE} ${exeroot}
${REMOVE} ${rundir}

${cesmroot}/scripts/create_newcase -case ${caseroot} -mach ${mach} \
                -res ${resolution} -compset ${compset}

if ( $status != 0 ) then
   echo "ERROR: Case could not be created."
   exit -1
endif

# ==============================================================================
# Record the DARTROOT directory and copy the DART setup script to CASEROOT.
# CESM_DART_config can be run at some later date if desired, but it presumes
# to be run from a CASEROOT directory. If CESM_DART_config does not exist locally,
# then it better exist in the expected part of the DARTROOT tree.
# ==============================================================================

if ( ! -e CESM_DART_config ) then
   ${COPY} ${dartroot}/models/POP/shell_scripts/CESM_DART_config .
endif

if (   -e CESM_DART_config ) then
   sed -e "s#BOGUS_DART_ROOT_STRING#$dartroot#" < CESM_DART_config >! temp.$$
   ${MOVE} temp.$$ ${caseroot}/CESM_DART_config
   chmod 755       ${caseroot}/CESM_DART_config
else
   echo "WARNING: the script to configure for data assimilation is not available."
   echo "         CESM_DART_config should be present locally or in"
   echo "         ${dartroot}/models/POP/shell_scripts/"
   echo "         You can stage this script later, but you must manually edit it"
   echo "         to reflect the location of the DART code tree."
endif

# ==============================================================================
# Configure the case.
# ==============================================================================

cd ${caseroot}

source ./Tools/ccsm_getenv || exit -2

@ ptile = $MAX_TASKS_PER_NODE / 2
@ nthreads = 1

# Save a copy for debug purposes
foreach FILE ( *xml )
   if ( ! -e        ${FILE}.original ) then
      ${COPY} $FILE ${FILE}.original
   endif
end

if ($num_instances < 10) then

   # This is only for the purpose of debugging the code.
   @ atm_tasks = $ptile * $num_instances
   @ lnd_tasks = $ptile * $num_instances
   @ ice_tasks = $ptile * $num_instances
   @ ocn_tasks = $ptile * $num_instances * 4
   @ cpl_tasks = $ptile * $num_instances
   @ glc_tasks = $ptile * $num_instances
   @ rof_tasks = $ptile * $num_instances

else

   # This works, but a more efficient layout should be used
   @ atm_tasks = $ptile * $num_instances
   @ lnd_tasks = $ptile * $num_instances
   @ ice_tasks = $ptile * $num_instances
   @ ocn_tasks = $ptile * $num_instances * 2
   @ cpl_tasks = $ptile * $num_instances
   @ glc_tasks = $ptile * $num_instances
   @ rof_tasks = $ptile * $num_instances

endif

# echo "task partitioning ... perhaps ... atm // ocn // lnd+ice+glc+rof"
# presently, all components run 'serially' - one after another.
echo ""
echo "ATM gets $atm_tasks"
echo "LND gets $lnd_tasks"
echo "ICE gets $ice_tasks"
echo "OCN gets $ocn_tasks"
echo "CPL gets $cpl_tasks"
echo "GLC gets $glc_tasks"
echo "ROF gets $rof_tasks"
echo ""

./xmlchange NTHRDS_ATM=$nthreads,NTASKS_ATM=$atm_tasks,NINST_ATM=$num_instances
./xmlchange NTHRDS_LND=$nthreads,NTASKS_LND=$lnd_tasks,NINST_LND=1
./xmlchange NTHRDS_ICE=$nthreads,NTASKS_ICE=$ice_tasks,NINST_ICE=$num_instances
./xmlchange NTHRDS_OCN=$nthreads,NTASKS_OCN=$ocn_tasks,NINST_OCN=$num_instances
./xmlchange NTHRDS_CPL=$nthreads,NTASKS_CPL=$cpl_tasks
./xmlchange NTHRDS_GLC=$nthreads,NTASKS_GLC=$glc_tasks,NINST_GLC=1
./xmlchange NTHRDS_ROF=$nthreads,NTASKS_ROF=$rof_tasks,NINST_ROF=1
./xmlchange ROOTPE_ATM=0
./xmlchange ROOTPE_LND=0
./xmlchange ROOTPE_ICE=0
./xmlchange ROOTPE_OCN=0
./xmlchange ROOTPE_CPL=0
./xmlchange ROOTPE_GLC=0
./xmlchange ROOTPE_ROF=0

# http://www.cesm.ucar.edu/models/cesm1.1/cesm/doc/usersguide/c1158.html#run_start_stop
# "A hybrid run indicates that CESM is initialized more like a startup, but uses
# initialization datasets from a previous case. This is somewhat analogous to a
# branch run with relaxed restart constraints. A hybrid run allows users to bring
# together combinations of initial/restart files from a previous case (specified
# by $RUN_REFCASE) at a given model output date (specified by $RUN_REFDATE).
# Unlike a branch run, the starting date of a hybrid run (specified by $RUN_STARTDATE)
# can be modified relative to the reference case. In a hybrid run, the model does not
# continue in a bit-for-bit fashion with respect to the reference case. The resulting
# climate, however, should be continuous provided that no model source code or
# namelists are changed in the hybrid run. In a hybrid initialization, the ocean
# model does not start until the second ocean coupling (normally the second day),
# and the coupler does a "cold start" without a restart file.

./xmlchange RUN_TYPE=hybrid
./xmlchange RUN_STARTDATE=$run_refdate
./xmlchange START_TOD=$run_reftod
./xmlchange RUN_REFCASE=$run_refcase
./xmlchange RUN_REFDATE=$run_refdate
./xmlchange RUN_REFTOD=$run_reftod
./xmlchange BRNCH_RETAIN_CASENAME=FALSE
./xmlchange GET_REFCASE=FALSE
./xmlchange EXEROOT=${exeroot}

./xmlchange DATM_MODE=CPLHIST3HrWx
./xmlchange DATM_CPLHIST_CASE=$case
./xmlchange DATM_CPLHIST_YR_ALIGN=$refyear
./xmlchange DATM_CPLHIST_YR_START=$refyear
./xmlchange DATM_CPLHIST_YR_END=$refyear

# The streams files were generated with a NO_LEAP calendar in mind.
# We need to test these with a GREGORIAN calendar.
./xmlchange CALENDAR=GREGORIAN
./xmlchange STOP_OPTION=$stop_option
./xmlchange STOP_N=$stop_n
./xmlchange CONTINUE_RUN=FALSE
./xmlchange RESUBMIT=$resubmit

./xmlchange PIO_TYPENAME=pnetcdf

# The river transport model ON is useful only when using an active ocean or
# land surface diagnostics. Setting ROF_GRID to 'null' turns off the RTM.
# TJH - guidance needed from Alicia

# ./xmlchange ROF_GRID='null'
# ./xmlchange ROF_GRID='r05'

if ($short_term_archiver == 'off') then
   ./xmlchange DOUT_S=FALSE
else
   ./xmlchange DOUT_S=TRUE
   ./xmlchange DOUT_S_ROOT=${archdir}
   ./xmlchange DOUT_S_SAVE_INT_REST_FILES=FALSE
endif
if ($long_term_archiver == 'off') then
   ./xmlchange DOUT_L_MS=FALSE
else
   ./xmlchange DOUT_L_MS=TRUE
   ./xmlchange DOUT_L_MSROOT="csm/${case}"
   ./xmlchange DOUT_L_HTAR=FALSE
endif

# level of debug output, 0=minimum, 1=normal, 2=more, 3=too much, valid values: 0,1,2,3 (integer)

./xmlchange DEBUG=FALSE
./xmlchange INFO_DBUG=0

# ==============================================================================
# Set up the case.
# This creates the EXEROOT and RUNDIR directories.
# ==============================================================================

./cesm_setup

if ( $status != 0 ) then
   echo "ERROR: Case could not be set up."
   exit -2
endif

# ==============================================================================
# Edit the run script to reflect queue and wallclock
# ==============================================================================

echo ''
echo 'Updating the run script to set wallclock and queue.'
echo ''

if ( ! -e  ${case}.run.original ) then
   ${COPY} ${case}.run ${case}.run.original
endif

source Tools/ccsm_getenv
set BATCH = `echo $BATCHSUBMIT | sed 's/ .*$//'`
switch ( $BATCH )
   case bsub*:
      # NCAR "bluefire", "yellowstone"
      set TIMEWALL=`grep BSUB ${case}.run | grep -e '-W' `
      set    QUEUE=`grep BSUB ${case}.run | grep -e '-q' `
      sed -e "s/$TIMEWALL[3]/$timewall/" \
          -e "s/ptile=[0-9][0-9]*/ptile=$ptile/" \
          -e "s/$QUEUE[3]/$queue/" < ${case}.run >! temp.$$
          ${MOVE} temp.$$ ${case}.run
          chmod 755       ${case}.run
   breaksw

   default:

   breaksw
endsw

# ==============================================================================
# Update source files.
#    Ideally, using DART would not require any modifications to the model source.
#    Until then, this script accesses sourcemods from a hardwired location.
#    If you have additional sourcemods, they will need to be merged into any DART
#    mods and put in the SourceMods subdirectory found in the 'case' directory.
# ==============================================================================

if (    -d     ~/${cesmtag}/SourceMods ) then
   ${COPY} -r  ~/${cesmtag}/SourceMods/* ${caseroot}/SourceMods/
else
   echo "ERROR - No SourceMods for this case."
   echo "ERROR - No SourceMods for this case."
   echo "DART requires modifications to several src files."
   echo "These files can be downloaded from:"
   echo "http://www.image.ucar.edu/pub/DART/CESM/DART_SourceMods_cesm1_1_1.tar"
   echo "untar these into your HOME directory - they will create a"
   echo "~/cesm_1_1_1  directory with the appropriate SourceMods structure."
   exit -4
endif

# The CESM multi-instance capability is relatively new and still has a few
# implementation bugs. These are known problems and will be fixed soon.
# this should be removed when the files are fixed:

echo "REPLACING BROKEN CESM FILES HERE - SHOULD BE REMOVED WHEN FIXED"
echo caseroot is ${caseroot}
if ( -d ~/${cesmtag} ) then

   # preserve the original version of the files
   if ( ! -e  ${caseroot}/Buildconf/rtm.buildnml.csh.original ) then
      ${MOVE} ${caseroot}/Buildconf/rtm.buildnml.csh \
              ${caseroot}/Buildconf/rtm.buildnml.csh.original
   endif
   if ( ! -e  ${caseroot}/preview_namelists.original ) then
      ${MOVE} ${caseroot}/preview_namelists \
              ${caseroot}/preview_namelists.original
   endif

   # patch/replace the broken files
   ${COPY} ~/${cesmtag}/rtm.buildnml.csh  ${caseroot}/Buildconf/.
   ${COPY} ~/${cesmtag}/preview_namelists ${caseroot}/.

endif

# ==============================================================================
# Modify namelist templates for each instance.
# ==============================================================================

@ inst = 1
while ($inst <= $num_instances)

   # following the CESM strategy for 'inst_string'
   set inst_string = `printf _%04d $inst`

   # ===========================================================================
   set fname = "user_nl_datm${inst_string}"
   # ===========================================================================

   echo "dtlimit  = 1.5, 1.5"               >> $fname
   echo "fillalgo = 'nn', 'nn'"             >> $fname
   echo "fillmask = 'nomask','nomask'"      >> $fname
   echo "mapalgo  = 'bilinear','bilinear'"  >> $fname
   echo "mapmask  = 'nomask','nomask'"      >> $fname
   echo "streams  = 'datm.streams.txt.CPLHIST3HrWx.Solar$inst_string             $stream_year_align $stream_year_first $stream_year_last'," >> $fname
   echo "           'datm.streams.txt.CPLHIST3HrWx.nonSolarNonPrecip$inst_string $stream_year_align $stream_year_first $stream_year_last'"  >> $fname
   echo "taxmode  = 'cycle','cycle'"        >> $fname
   echo "tintalgo = 'linear','linear'"      >> $fname
   echo "restfils = 'unset'"                >> $fname
   echo "restfilm = 'unset'"                >> $fname

   # ===========================================================================
   set fname = "user_nl_cice$inst_string"
   # ===========================================================================
   # CICE Namelists
   # this is only used for a hybrid start, else rpointers are used.

   echo "ice_ic = '${run_refcase}.cice${inst_string}.r.2004-01-10-00000.nc'" >> $fname

   # ===========================================================================
   set fname = "user_nl_pop2$inst_string"
   # ===========================================================================

   # POP Namelists
   # init_ts_suboption = 'data_assim'   for non bit-for-bit restarting (assimilation mode)
   # init_ts_suboption = 'rest'         --> default behavior
   #
   #  DEFAULT values for these are:
   #  tavg_file_freq_opt = 'nmonth' 'nmonth' 'once'
   #  tavg_freq_opt      = 'nmonth' 'nday'   'once'
   #  The  first entry indicates we get a monthly average once a month.
   #  The second entry indicates we get a monthly average as it is being created.
   #  The  third entry indicates  we get a daily timeslice
   #
   #  IFF values for these are:
   #  tavg_file_freq_opt = 'nmonth' 'never' 'never'
   #  tavg_freq_opt      = 'nmonth' 'never' 'never'
   #  The  first entry indicates we get a monthly average once a month, and thats all we get..

   echo "init_ts_suboption  = 'data_assim'"             >> $fname
   echo "tavg_file_freq_opt = 'nmonth' 'never' 'never'" >> $fname
   echo "tavg_freq_opt      = 'nmonth' 'never' 'never'" >> $fname

   @ inst ++
end

# DLND

echo "streams = 'drof.streams.txt.rof.diatren_iaf_rx1" 1 1948 2009"'" >> user_nl_drof

# ==============================================================================
# to create custom streamfiles ...
# "To modify the contents of a stream txt file, first use preview_namelists to
#  obtain the contents of the stream txt files in CaseDocs, and then place a copy
#  of the modified stream txt file in $CASEROOT with the string user_ prepended."
#
# -or-
#
# we copy a template stream txt file from the
# $dartroot/models/POP/shell_scripts directory and modify one for each instance.
#
# ==============================================================================

./preview_namelists

# This gives us a stream txt file for each instance that we can
# modify for our own purpose.

foreach FILE (CaseDocs/*streams*)
   set FNAME = $FILE:t

   switch ( ${FNAME} )
      case *presaero*:
         echo "Using default prescribed aerosol stream.txt file ${FNAME}"
         breaksw
      case *diatren*:
         echo "Using default runoff stream.txt file ${FNAME}"
         breaksw
      case *\.Precip_*:
         echo "Precipitation in nonSolarNonPrecip stream.txt file - not ${FNAME}"
         breaksw
      default:
         ${COPY} $FILE user_$FNAME
         chmod   644   user_$FNAME
         breaksw
   endsw

end

# Replace each default stream txt file with one that uses the CAM DATM
# conditions for a default year and modify the instance number.

foreach FNAME (user*streams*)
   set name_parse = `echo $FNAME | sed 's/\_/ /g'`
   @ instance_index = $#name_parse
   @ filename_index = $#name_parse - 1
   set streamname = $name_parse[$filename_index]
   set   instance = `echo $name_parse[$instance_index] | bc`

   if (-e $dartroot/models/POP/shell_scripts/user_$streamname*template) then

      echo "Copying DART template for $FNAME and changing instances."

      ${COPY} $dartroot/models/POP/shell_scripts/user_$streamname*template $FNAME

      sed s/NINST/$instance/g $FNAME >! out.$$
      ${MOVE} out.$$ $FNAME

   else
      echo "DIED Looking for a DART stream txt template for $FNAME"
      echo "DIED Looking for a DART stream txt template for $FNAME"
      exit -3
   endif

end

./preview_namelists

# ==============================================================================
# Stage the restarts now that the run directory exists
# ==============================================================================

cat << EndOfText >! stage_initial_cesm_files
#!/bin/sh

cd ${rundir}

echo ''
echo 'Copying the restart files from the staging directories'
echo 'into the CESM run directory and creating the pointer files.'
echo ''

let inst=1
while ((\$inst <= $num_instances)); do
   inst_string=\`printf _%04d \$inst\`

   echo ''
   echo "Staging restarts for instance \$inst of $num_instances"

   ${LINK} ${stagedir}/${run_refcase}.pop\${inst_string}.r.2004-01-10-00000.nc  .
   ${LINK} ${stagedir}/${run_refcase}.pop\${inst_string}.ro.2004-01-10-00000    .
#  ${LINK} ${stagedir}/${run_refcase}.pop\${inst_string}.rh.2004-01-10-00000.nc .

   #TH: The cice fname must match that in the user_nl_cice file

   ${LINK} ${stagedir}/${run_refcase}.cice\${inst_string}.r.2004-01-10-00000.nc . 

   echo "${run_refcase}.pop\${inst_string}.ro.2004-01-10-00000"   \
            >| rpointer.ocn\${inst_string}.ovf
   echo "${run_refcase}.pop\${inst_string}.r.2004-01-10-00000.nc" \
            >| rpointer.ocn\${inst_string}.restart
   echo "RESTART_FMT=nc"                                          \
            >> rpointer.ocn\${inst_string}.restart

   let inst+=1
done

exit 0

EndOfText
chmod 0755 stage_initial_cesm_files

./stage_initial_cesm_files

# ==============================================================================
# build
# ==============================================================================

echo ''
echo 'Building the case'
echo ''

./${case}.build

if ( $status != 0 ) then
   echo "ERROR: Case could not be built."
   exit -5
endif

# ==============================================================================
# What to do next
# ==============================================================================

echo ""
echo "Time to check the case."
echo ""
echo "1) cd ${rundir}"
echo "   check the compatibility between the namelists and the files that were staged."
echo ""
echo "2) cd ${caseroot}"
echo "   (on yellowstone) If the ${case}.run script still contains:"
echo '   #BSUB -R "select[scratch_ok > 0]"'
echo "   around line 9, delete it."
echo ""
echo "3) If you want to assimilate 'right away', configure and execute"
echo "   the ${caseroot}/CESM_DART_config script."
echo ""
echo "3) Verify the contents of env_run.xml and submit the CESM job:"
echo "   ./${case}.submit"
echo ""
echo "4) After the run finishes ... check the contents of the DART observation sequence file"
echo "   ${archdir}/dart/hist/obs_seq.YYYY-MM-DD-SSSSS"
echo "   to make sure there are good values in the file. (not -888888.)"
echo ""
echo "5) To extend the run in $assim_n '"$stop_option"' steps,"
echo "   change the env_run.xml variables:"
echo ""
echo "   ./xmlchange CONTINUE_RUN=TRUE"
echo "   ./xmlchange RESUBMIT=<number_of_cycles_to_run>"
echo "   ./xmlchange STOP_N=$assim_n"
echo ""
echo "Check the streams listed in the streams text files.  If more or different"
echo 'dates need to be added, then do this in the $CASEROOT/user_*files*'
echo "then invoke 'preview_namelists' so you can check the information in the"
echo "CaseDocs or ${rundir} directories."
echo ""

exit 0

# <next few lines under version control, do not edit>
# $URL$
# $Revision$
# $Date$


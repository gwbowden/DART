#!/bin/csh

# Data Assimilation Research Testbed -- DART
# Copyright 2004-2006, Data Assimilation Research Section
# University Corporation for Atmospheric Research
# Licensed under the GPL -- www.gpl.org/licenses/gpl.html
#
# <next three lines automatically updated by CVS, do not edit>
# $Id$
# $Source: /home/thoar/CVS.REPOS/DART/models/bgrid_solo/work/workshop_setup.csh,v $
# $Name:  $

#----------------------------------------------------------------------
# Script to manage the compilation of all components for this model;
# executes a known "perfect model" experiment using an existing
# observation sequence file (obs_seq.in) and initial conditions appropriate 
# for both 'perfect_model_obs' (perfect_ics) and 'filter' (filter_ics).
# There are enough initial conditions for 80 ensemble members in filter.
# Use ens_size = 81 and it WILL bomb. Guaranteed.
# The 'input.nml' file controls all facets of this execution.
#
# 'create_obs_sequence' and 'create_fixed_network_sequence' were used to
# create the observation sequence file 'obs_seq.in' - this defines 
# what/where/when we want observations. This script does not run these 
# programs - intentionally. 
#
# 'perfect_model_obs' results in a True_State.nc file that contains 
# the true state, and obs_seq.out - a file that contains the "observations"
# that will be assimilated by 'filter'.
#
# 'filter' results in three files (at least): Prior_Diag.nc - the state 
# of all ensemble members prior to the assimilation (i.e. the forecast), 
# Posterior_Diag.nc - the state of all ensemble members after the 
# assimilation (i.e. the analysis), and obs_seq.final - the ensemble 
# members' estimate of what the observations should have been.
#
# Once 'perfect_model_obs' has advanced the model and harvested the 
# observations for the assimilation experiment, 'filter' may be run 
# over and over by simply changing the namelist parameters in input.nml.
#
# The result of each assimilation can be explored in model-space with
# matlab scripts that directly read the netCDF output, or in observation-space.
# 'obs_diag' is a program that will create observation-space diagnostics
# for any result of 'filter' and results in a couple data files that can
# be explored with yet more matlab scripts.
#
#----------------------------------------------------------------------
# 'preprocess' is a program that culls the appropriate sections of the
# observation module for the observations types in 'input.nml'; the 
# resulting source file is used by all the remaining programs, 
# so this MUST be run first.
#----------------------------------------------------------------------

\rm -f preprocess create_obs_sequence create_fixed_network_seq
\rm -f perfect_model_obs filter obs_diag integrate_model
\rm -f merge_obs_seq
\rm -f *.o *.mod

csh mkmf_preprocess
make         || exit 1
\rm -f ../../../obs_def/obs_def_mod.f90
\rm -f ../../../obs_kind/obs_kind_mod.f90
./preprocess || exit 2

#----------------------------------------------------------------------

csh mkmf_create_obs_sequence
make         || exit 3
csh mkmf_create_fixed_network_seq
make         || exit 4
csh mkmf_perfect_model_obs
make         || exit 5
csh mkmf_obs_diag
make         || exit 6
csh mkmf_merge_obs_seq
make         || exit 7
csh mkmf_integrate_model
make         || exit 8

# normal compile without the MPI parallel libraries:

csh mkmf_filter
make         || exit 9

# to enable an MPI parallel version of filter for this model, comment
# out the previous 2 lines and comment in the following section:

#rm *.o *.mod
#
#csh mkmf_filter -mpi
#make
#
#if ($status != 0) then
#   echo
#   echo "If this died in mpi_utilities_mod, see code comments"
#   echo "in mpi_utilities_mod.f90 starting with 'BUILD TIP' "
#   echo
#   exit 9
#endif
#

#----------------------------------------------------------------------

./perfect_model_obs || exit 20
if ( -e using_mpi_for_filter ) then
   mpirun -np 2 ./filter            || exit 21
   # or bsub < runme_filter
   # or qsub runme_filter 
   # to make your batch system happy.
else
   ./filter            || exit 21
endif


#!/bin/csh
#
# Data Assimilation Research Testbed -- DART
# Copyright 2004-2006, Data Assimilation Research Section
# University Corporation for Atmospheric Research
# Licensed under the GPL -- www.gpl.org/licenses/gpl.html
#
# <next three lines automatically updated by CVS, do not edit>
# $Id$
# $Source$
# $Name$
#
# Standard script for use in assimilation applications
# where the model advance is executed as a separate process.
# Can be used with most low-order models and the bgrid model which
# can be advanced using the integrate_model executable.

# This script copies the necessary files into the temporary directory
# and then executes the fortran program integrate_model.

# Arguements are the process number of caller, the number of state copies
# belonging to that process, and the name of the filter_control_file for
# that process
set process = $1
set num_states = $2
set control_file = $3

# Get unique name for temporary working directory for this process's stuff
set temp_dir = 'advance_temp'$1

# Create a clean temporary directory and go there
\rm -rf  $temp_dir
mkdir -p $temp_dir
cd       $temp_dir

# Get the program and input.nml
cp ../integrate_model .
cp ../input.nml .

# Loop through each state
set state_copy = 1
set input_file_line = 1
set output_file_line = 2
while($state_copy <= $num_states)
   
   set input_file = `head -$input_file_line ../$3 | tail -1`
   set output_file = `head -$output_file_line ../$3 | tail -1`
   
   # Get the ics file for this state_copy
   cp ../$input_file temp_ic
   # Advance the model saving standard out
   ./integrate_model >! integrate_model_out_temp

   # Append the output from the advance to the file in the working directory
   #cat integrate_model_out_temp >> ../integrate_model_out_temp$process

   # Move the updated state vector back up
   mv temp_ud ../$output_file

   @ state_copy++
   @ input_file_line++
   @ input_file_line++
   @ output_file_line++
   @ output_file_line++
end

# Change back to original directory and get rid of temporary directory
cd ..
\rm -rf $temp_dir

# Remove the filter_control file to signal completeion
# Is there a need for any sleeps to avoid trouble on completing moves here?
\rm -rf $3

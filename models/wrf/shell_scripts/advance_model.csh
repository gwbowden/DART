#!/bin/csh
#
# Data Assimilation Research Testbed -- DART
# Copyright 2004, Data Assimilation Initiative, University Corporation for Atmospheric Research
# Licensed under the GPL -- www.gpl.org/licenses/gpl.html
#
# Standard script for use in assimilation applications
# where the model advance is executed as a separate process.

# This script copies the necessary files into the temporary directory
# for a model run.

# Shell script to run the WRF model from DART input.
set verbose

echo ".true." >  input_dart_to_wrf
echo ".false." >  input_wrf_to_dart

# Convert DART to wrfinput

dart_tf_wrf < input_dart_to_wrf >& out.dart_to_wrf

mv wrfinput wrfinput_d01

# Update boundary conditions

update_wrf_bc >& out.update_wrf_bc

wrf.exe >>& out_wrf_integration
mv wrf_filter* wrfinput

# we've just integrated wrf, but we're still using
# the original input data here

# save off input data 
mv dart_wrf_vector dart_wrf_vector.input

# create new input to DART (taken from "wrfinput")
dart_tf_wrf < input_wrf_to_dart >& out.wrf_to_dart

mv dart_wrf_vector temp_ud

exit

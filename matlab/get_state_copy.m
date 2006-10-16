function state_vec = get_state_copy(fname, varname, copyindex)
%GET_STATE_COPY  Gets a particular copy (one ensemble member) of state from netcdf file
% Retrieves a particular copy of a state vector from a file whose
% full or relative path is specified in the file argument.
% NEED TO DEAL WITH ERRORS.

% Data Assimilation Research Testbed -- DART
% Copyright 2004-2006, Data Assimilation Research Section
% University Corporation for Atmospheric Research
% Licensed under the GPL -- www.gpl.org/licenses/gpl.html
 
% <next three lines automatically updated by CVS, do not edit>
% $Id$
% $Source$
% $Name$

% Need to get a copy with the label copy
copy_meta_data = getnc(fname, 'CopyMetaData');

% Get some information from the truth_file
f = netcdf(fname);
model      = f.model(:);
var_atts   = dim(f{varname});     % cell array of dimensions for the var
num_times  = length(var_atts{1}); % determine # of output times
num_copies = length(var_atts{2}); % determine # of ensemble members
num_vars   = length(var_atts{3}); % determine # of state variables (of this type)
close(f);

if ( ~ strcmp( name(var_atts{1}), 'time') )                                                  
    disp( sprintf('%s first dimension ( %s ) is not ''time''',fname,name(var_atts{1})))      
end                                                                                          
if ( ~ strcmp( name(var_atts{2}), 'copy') )                                                  
    disp( sprintf('%s second dimension ( %s ) is not ''copy''',fname,name(var_atts{2})))     
end

% Get only the appropriate copy of the state and return
% Should have an error check for bad indices

state_vec = getnc(fname, varname, [-1, copyindex, -1], [-1, copyindex, -1]);

function objh = PlotPhaseSpace(fname,ens_mem_id,var1,var2,var3,ltype)
% Plots time series of ensemble members, mean and truth
%
% Example 1
% fname = 'True_State.nc';
% ens_mem_id = 1;
% var1 = 1;
% var2 = 2;
% var3 = 3;
% ltype = 'b-';
% PlotPhaseSpace(fname,ens_mem_id,var1,var2,var3,ltype)
% hold on
% fname = 'Prior_Diag.nc';
% ens_mem_id = 3;
% var1 = 1;
% var2 = 2;
% var3 = 3;
% ltype = 'r-';
% PlotPhaseSpace(fname,ens_mem_id,var1,var2,var3,ltype)
%

if ( exist(fname) ~= 2 ), error(sprintf('file %s does not exist.',fname)), end

% Get some information from the file 
f = netcdf(fname);
model      = f.model(:);
num_vars   = ncsize(f{'StateVariable'}); % determine # of state variables
num_copies = ncsize(f{'copy'}); % determine # of ensemble members
num_times  = ncsize(f{'time'}); % determine # of output times
close(f);

% rudimentary bulletproofing
if ( (ens_mem_id > num_copies) | (ens_mem_id < 1) ) 
   disp(sprintf('\n%s has %d ensemble members',fname,num_copies))
   disp(sprintf('%d  <= ''ens_mem_id'' <= %d',1,num_copies))
   error(sprintf('ens_mem_id (%d) out of range',ens_mem_id))
end

if ( (var1 > num_vars) | (var1 < 1) ) 
   disp(sprintf('\n%s has %d state variables',fname,num_vars))
   disp(sprintf('%d  <= ''var1'' <= %d',1,num_vars))
   error(sprintf('var1 (%d) out of range',var1))
end

if ( (var2 > num_vars) | (var2 < 1) ) 
   disp(sprintf('\n%s has %d state variables',fname,num_vars))
   disp(sprintf('%d  <= ''var2'' <= %d',1,num_vars))
   error(sprintf('var2 (%d) out of range',var2))
end

if ( (var3 > num_vars) | (var3 < 1) ) 
   disp(sprintf('\n%s has %d state variables',fname,num_vars))
   disp(sprintf('%d  <= ''var3'' <= %d',1,num_vars))
   error(sprintf('var3 (%d) out of range',var3))
end

x = get_var_series(fname, ens_mem_id, var1);
y = get_var_series(fname, ens_mem_id, var2);
z = get_var_series(fname, ens_mem_id, var3);

% There is no model-dependent segment ...
% As long as you have three variables, this works for all models.

h = plot3(x,y,z,ltype);
title(sprintf('model %s ensemble member %d',model,ens_mem_id),'interpreter','none')
xlabel(sprintf('state variable # %d',var1))
ylabel(sprintf('state variable # %d',var2))
zlabel(sprintf('state variable # %d',var3))

% grab existing legend and add to it
[legh, objh, outh, outm] = legend;
if (isempty(legh))
   disp('there is no legend')
   s = sprintf('%d %d %d %s %s %d',var1,var2,var3,model,fname,ens_mem_id);
   h = legend(s,0);
   [legh, objh, outh, outm] = legend;
   set(objh(1),'interpreter','none')
else
   % legh     handle to the legend axes
   % objh     handle for the text, lines, and patches in the legend
   % outh     handle for the lines and patches in the plot
   % outm     cell array for the text in the legend
   nlines = length(outm);
   outm{nlines+1} = sprintf('%d %d %d %s %s %d', var1, var2, var3, model,...
                             fname, ens_mem_id);
   [legh, objh, outh, outm] = legend([outh; h],outm,0);

   set(objh(1),'interpreter','none')
end

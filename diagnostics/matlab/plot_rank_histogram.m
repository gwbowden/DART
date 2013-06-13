function plotdat = plot_rank_histogram(fname, timeindex, varargin)
%% plot_rank_histogram plots the rank histogram of the observations - segregated by level and variable.
% Part of the observation-space diagnostics routines.
%
% 'obs_diag' produces a netcdf file containing the diagnostics.
% 'obs_diag' condenses the 'obs_seq.final' information into summaries 
%            for a few specified regions - on a level-by-level basis.
%
% USAGE: plotdat = plot_rank_histogram(fname, timeindex, [,obstypestring]);
%
% fname         : netcdf file produced by 'obs_diag'
% timeindex     : the index of the timestep of interest
% obstypestring : 'observation type' string. Optional.
%                 Must match something in the 'ObservationTypes' variable.
%                 (ncdump -v ObservationTypes obs_diag_output.nc)
%                 If specified, only this observation type will be plotted.
%                 If not specified, ALL observation types incluced in the 
%                 netCDF file will be plotted.
%
% OUTPUT: two files will result for each observation type plotted. One is a 
%         postscript file containing a page for each level - all regions.
%         The other file is a simple text file containing summary information
%         about how many obs were assimilated, how many were available, etc.
%         Both filenames contain the observation type as part of the name.
%
% EXAMPLE 1 - plot the rank histogram for ALL observation types, ALL levels
%
% fname     = 'obs_diag_output.nc'; % netcdf file produced by 'obs_diag'
% timeindex = 1;                    % plot the histogram for the first timestep 
% plotdat   = plot_rank_histogram(fname, timeindex);
%
%
% EXAMPLE 2 - rank histogram for a particular timestep of radiosonde temperature observations.
%             This requires knowledge that 'RADIOSONDE_TEMPERATURE' is an
%             observation type in the netCDF file.
%
% fname     = 'obs_diag_output.nc'; % netcdf file produced by 'obs_diag'
% timeindex = 3;                    % plot the histogram for the third timestep 
% plotdat   = plot_rank_histogram(fname, timeindex, 'RADIOSONDE_TEMPERATURE');
%
%
% EXAMPLE 3 - single rank histogram for all timesteps of radiosonde temperature observations.
%
% fname     = 'obs_diag_output.nc'; % netcdf file produced by 'obs_diag'
% timeindex = -1;                   % use ALL available timesteps
% plotdat   = plot_rank_histogram(fname, timeindex, 'RADIOSONDE_TEMPERATURE');

%% DART software - Copyright 2004 - 2013 UCAR. This open source software is
% provided by UCAR, "as is", without charge, subject to all terms of use at
% http://www.image.ucar.edu/DAReS/DART/DART_download
%
% DART $Id$

if nargin == 2
   nvars = 0;
elseif nargin == 3
   varname = varargin{1};
   nvars = 1;
else
   error('wrong number of arguments ... ')
end

% Make sure the file exists.

if (exist(fname,'file') ~= 2)
   error('file/fname <%s> does not exist',fname)
end

% Make sure the variable exists.

if (nvars > 0)
   fullvarname = BuildFullVarname(varname);
   if ( ~ nc_isvar(fname,fullvarname) )
      error('There is no %s variable in %s', fullvarname, fname)
   end
end

% Harvest plotting info/metadata from netcdf file.

plotdat.fname         = fname;
plotdat.timecenters   = nc_varget(fname,'time');
plotdat.timeedges     = nc_varget(fname,'time_bounds');
plotdat.mlevel        = local_nc_varget(fname,'mlevel');
plotdat.plevel        = local_nc_varget(fname,'plevel');
plotdat.plevel_edges  = local_nc_varget(fname,'plevel_edges');
plotdat.hlevel        = local_nc_varget(fname,'hlevel');
plotdat.hlevel_edges  = local_nc_varget(fname,'hlevel_edges');
plotdat.Nrhbins       = length(nc_varget(fname,'rank_bins'));
plotdat.ncopies       = length(nc_varget(fname,'copy'));
plotdat.nregions      = length(nc_varget(fname,'region'));
plotdat.region_names  = strtrim(nc_varget(fname,'region_names'));

% Matlab does a crazy thing with the strings for 1 region
if (plotdat.nregions == 1 && (size(plotdat.region_names,2) == 1) )
   plotdat.region_names = deblank(plotdat.region_names');
end

dimensionality             = nc_attget(fname, nc_global, 'LocationRank');
plotdat.timeseparation     = nc_attget(fname, nc_global, 'bin_separation');
plotdat.timewidth          = nc_attget(fname, nc_global, 'bin_width');
plotdat.biasconv           = nc_attget(fname, nc_global, 'bias_convention');
time_to_skip               = nc_attget(fname, nc_global, 'time_to_skip');
plotdat.outlierstring      = nc_attget(fname, nc_global, 'outliers_in_histogram');
plotdat.QCsusedstring      = nc_attget(fname, nc_global, 'DART_QCs_in_histogram');
plotdat.lonlim1            = nc_attget(fname, nc_global, 'lonlim1');
plotdat.lonlim2            = nc_attget(fname, nc_global, 'lonlim2');
plotdat.latlim1            = local_nc_attget(fname, nc_global, 'latlim1');
plotdat.latlim2            = local_nc_attget(fname, nc_global, 'latlim2');

% Make sure the time index makes sense.

if (timeindex > length(plotdat.timecenters))
   error('There are only %d time indices in the file, you asked for # %d', ...
         length(plotdat.timecenters), timeindex)
end

% Coordinate between time types and dates

calendar     = nc_attget(fname,'time','calendar');
timeunits    = nc_attget(fname,'time','units');
timebase     = sscanf(timeunits,'%*s%*s%d%*c%d%*c%d'); % YYYY MM DD
timeorigin   = datenum(timebase(1),timebase(2),timebase(3));
skip_seconds = time_to_skip(4)*3600 + time_to_skip(5)*60 + time_to_skip(6);
iskip        = time_to_skip(3) + skip_seconds/86400;

plotdat.timecenters = plotdat.timecenters + timeorigin;
plotdat.timeedges   = plotdat.timeedges   + timeorigin;
plotdat.Ntimes      = length(plotdat.timecenters);
plotdat.toff        = plotdat.timecenters(1) + iskip;

if ( timeindex < 1 )
   plotdat.timeindex = 1:plotdat.Ntimes;
   plotdat.timespan = sprintf('%s -- %s', datestr(min(plotdat.timeedges(:,1)),21), ...
                                          datestr(max(plotdat.timeedges(:,2)),21));
else
   plotdat.timeindex = timeindex;
   plotdat.timespan = sprintf('%s -- %s', datestr(plotdat.timeedges(timeindex,1),21), ...
                                          datestr(plotdat.timeedges(timeindex,2),21));
end

% set up a structure with all static plotting components

plotdat.linewidth = 2.0;

if (nvars == 0)
   [plotdat.allvarnames, plotdat.allvardims] = get_varsNdims(fname);
   [plotdat.varnames,    plotdat.vardims]    = FindTemporalVars(plotdat);
   plotdat.nvars       = length(plotdat.varnames);
else
   plotdat.varnames{1} = varname;
   plotdat.nvars       = nvars;
end

plotdat.Npossindex  = get_copy_index(fname,'Nposs');
plotdat.Nusedindex  = get_copy_index(fname,'Nused');
plotdat.NQC4index   = get_copy_index(fname,'N_DARTqc_4');
plotdat.NQC5index   = get_copy_index(fname,'N_DARTqc_5');
plotdat.NQC6index   = get_copy_index(fname,'N_DARTqc_6');
plotdat.NQC7index   = get_copy_index(fname,'N_DARTqc_7');

%----------------------------------------------------------------------
% Loop around (time-copy-level-region) observation types
%----------------------------------------------------------------------

for ivar = 1:plotdat.nvars
    
   % create the variable names of interest.
   % netCDF can only support variable names less than 41 chars.
    
   plotdat.myvarname = plotdat.varnames{ivar};  
   plotdat.guessvar  = sprintf('%s_guess',plotdat.varnames{ivar});

   plotdat.rhistvar = BuildFullVarname(plotdat.varnames{ivar});

   % remove any existing postscript file - will simply append each
   % level as another 'page' in the .ps file.
   
   psfname = sprintf('%s_rank_hist.ps',plotdat.varnames{ivar});
   fprintf('Removing %s from the current directory.\n',psfname)
   system(sprintf('rm %s',psfname));

   % remove any existing log file - 
   
   lgfname = sprintf('%s_rank_hist_obscount.txt',plotdat.varnames{ivar});
   fprintf('Removing %s from the current directory.\n',lgfname)
   system(sprintf('rm %s',lgfname));
   logfid = fopen(lgfname,'wt');
   fprintf(logfid,'%s\n',lgfname);

   % get appropriate vertical coordinate variable

   guessdims = nc_var_dims(fname, plotdat.guessvar);
   rhistdims = nc_var_dims(fname, plotdat.rhistvar);

   if ( dimensionality == 1 ) % observations on a unit circle, no level
      plotdat.level = 1;
      plotdat.level_units = [];
   elseif ( strfind(guessdims{3},'surface') > 0 )
      plotdat.level       = 1;
      plotdat.level_units = 'surface';
   elseif ( strfind(guessdims{3},'undef') > 0 )
      plotdat.level       = 1;
      plotdat.level_units = 'undefined';
   else
      plotdat.level       = nc_varget(fname, guessdims{3});
      plotdat.level_units = nc_attget(fname, guessdims{3}, 'units');
   end
   plotdat.nlevels = length(plotdat.level);

   % Here is the tricky part. Singleton dimensions are auto-squeezed ... 
   % single levels, single regions ...

   guess_raw = nc_varget(fname, plotdat.guessvar);  
   guess = reshape(guess_raw, plotdat.Ntimes,  plotdat.ncopies, ...
                              plotdat.nlevels, plotdat.nregions);

   rhist_raw = nc_varget(fname, plotdat.rhistvar); 
   rhist = reshape(rhist_raw, plotdat.Ntimes,  plotdat.Nrhbins, ...
                              plotdat.nlevels, plotdat.nregions);
                          
   % Collapse the time dimension if need be. 
   if ( timeindex < 0 )  
      guess             = sum(guess,1); 
      rhist             = sum(rhist,1); 
      plotdat.timeindex = 1;
   end

   % check to see if there is anything to plot
   nposs = sum(guess(plotdat.timeindex,plotdat.Npossindex,:,:));

   if ( sum(nposs(:)) < 1 )
      fprintf('%s no obs for %s...  skipping\n', plotdat.varnames{ivar})
      continue
   end
   
   for ilevel = 1:plotdat.nlevels

      fprintf(logfid,'\nlevel %d %f %s\n',ilevel,plotdat.level(ilevel),plotdat.level_units);
      
      plotdat.ges_Nqc4  = squeeze(guess(plotdat.timeindex,plotdat.NQC4index  ,ilevel,:));
      fprintf(logfid,'DART QC == 4, prior %d\n',sum(plotdat.ges_Nqc4(:)));

      plotdat.ges_Nqc5  = squeeze(guess(plotdat.timeindex,plotdat.NQC5index  ,ilevel,:));
      fprintf(logfid,'DART QC == 5, prior %d\n',sum(plotdat.ges_Nqc5(:)));

      plotdat.ges_Nqc6  = squeeze(guess(plotdat.timeindex,plotdat.NQC6index  ,ilevel,:));
      fprintf(logfid,'DART QC == 6, prior %d\n',sum(plotdat.ges_Nqc6(:)));

      plotdat.ges_Nqc7  = squeeze(guess(plotdat.timeindex,plotdat.NQC7index  ,ilevel,:));
      fprintf(logfid,'DART QC == 7, prior %d\n',sum(plotdat.ges_Nqc7(:)));

      plotdat.ges_Nposs = squeeze(guess(plotdat.timeindex,plotdat.Npossindex, ilevel,:));
      fprintf(logfid,'# obs poss,   prior %d\n',sum(plotdat.ges_Nposs(:)));

      plotdat.ges_Nused = squeeze(guess(plotdat.timeindex,plotdat.Nusedindex, ilevel,:));
      fprintf(logfid,'# obs used,   prior %d\n',sum(plotdat.ges_Nused(:)));

      % plot by region

      if (plotdat.nregions > 1)
         clf; orient tall
      else 
         clf; orient landscape
      end

      for iregion = 1:plotdat.nregions

         plotdat.region   = iregion;  
         plotdat.myregion = deblank(plotdat.region_names(iregion,:));
         if ( isempty(plotdat.level_units) )
            plotdat.title    = plotdat.myvarname;
         else
            plotdat.title    = sprintf('%s @ %d %s',    ...
               plotdat.myvarname,     ...
               plotdat.level(ilevel), ...
               plotdat.level_units);
         end
                          
         plotdat.rank_hist = squeeze(rhist(plotdat.timeindex, :, ilevel,iregion));
         
         myplot(plotdat);
      end

      % create a postscript file
      print(gcf,'-dpsc','-append',psfname);

      % block to go slow and look at each one ...
        disp('Pausing, hit any key to continue ...')
        pause

   end
end

%----------------------------------------------------------------------
% 'Helper' functions
%----------------------------------------------------------------------

function myplot(plotdat)

   % 6	 Rejected because of incoming data qc.
   % 5	 Not used because of namelist control.

   nobs_poss = plotdat.ges_Nposs(plotdat.region) - ...
               plotdat.ges_Nqc5( plotdat.region) - ...
               plotdat.ges_Nqc6( plotdat.region);

   % nobs_used = plotdat.ges_Nused(plotdat.region);
   nobs_used = sum(plotdat.rank_hist(:));
   obsstring = sprintf('%d obs possible, %d obs binned',nobs_poss, nobs_used);

   % Determine some quantities for the legend
   % Plot 
   
   subplot(plotdat.nregions,1,plotdat.region);
   bar(plotdat.rank_hist, 1.0);
   set(gca,'TickDir','out')

   axlims = axis;
   axlims = [0 plotdat.Nrhbins+1 0 axlims(4)];
   axis(axlims)

   h = text(plotdat.Nrhbins/2, 0.9*axlims(4),plotdat.myregion);
   set(h,'FontSize',14,'FontWeight','Bold')
   set(h,'HorizontalAlignment','center')

   xlabel({'Observation Rank (among ensemble members)',obsstring})

   if ( strcmp(plotdat.outlierstring,  'TRUE'))
      ylabel('count - including outlier observations')
   else
      ylabel('count')
   end

   % more annotation ...

   if (plotdat.region == 1)
      title({plotdat.title, plotdat.timespan}, ...
         'Interpreter', 'none', 'Fontsize', 12, 'FontWeight', 'bold')
      BottomAnnotation(plotdat.fname)
   else
      title(plotdat.timespan, 'Interpreter', 'none', ...
         'Fontsize', 12, 'FontWeight', 'bold')
   end
   
 


function BottomAnnotation(main)
% annotates the directory containing the data being plotted
subplot('position',[0.48 0.01 0.04 0.04])
axis off
fullname = which(main);   % Could be in MatlabPath
if( isempty(fullname) )
   if ( main(1) == '/' )  % must be a absolute pathname
      string1 = sprintf('data file: %s',main);
   else                   % must be a relative pathname
      mydir = pwd;
      string1 = sprintf('data file: %s/%s',mydir,main);
   end
else
   string1 = sprintf('data file: %s',fullname);
end

h = text(0.0, 0.0, string1);
set(h,'HorizontalAlignment','center', ...
      'VerticalAlignment','middle',...
      'Interpreter','none',...
      'FontSize',10)



function [y,ydims] = FindTemporalVars(x)
% Returns UNIQUE (i.e. base) temporal variable names
if ( ~(isfield(x,'allvarnames') && isfield(x,'allvardims')))
   error('Doh! no ''allvarnames'' and ''allvardims'' components')
end

j = 0;

for i = 1:length(x.allvarnames)
   indx = strfind(x.allvardims{i},'time');
   if (indx > 0) 
      j = j + 1;

      basenames{j} = ReturnBase(x.allvarnames{i});
      basedims{j}  = x.allvardims{i};
   end
end

[~,i,j] = unique(basenames);
y     = cell(length(i),1);
ydims = cell(length(i),1);
for k = 1:length(i)
   fprintf('%2d is %s\n',k,basenames{i(k)})
    y{k} = basenames{i(k)};
ydims{k} = basedims{i(k)};
end



function s = ReturnBase(string1)
inds = strfind(string1,'_guess');
if (inds > 0 )
   s = string1(1:inds-1);
end

inds = strfind(string1,'_analy');
if (inds > 0 )
   s = string1(1:inds-1);
end

inds = strfind(string1,'_VPguess');
if (inds > 0 )
   s = string1(1:inds-1);
end

inds = strfind(string1,'_VPanaly');
if (inds > 0 )
   s = string1(1:inds-1);
end



function s = BuildFullVarname(varname)
% netCDF restricts the length of a variable name to
% be 40 characters. 

rankvar = sprintf('%s_guess_RankHist',varname);
if (length(rankvar) > 40 ) 
   s = rankvar(1:40);
else
   s = rankvar;
end



function value = local_nc_varget(fname,varname)
%% If the variable exists in the file, return the contents of the variable.
% if the variable does not exist, return empty value instead of error-ing
% out.

[variable_present, varid] = nc_var_exists(fname,varname);
if (variable_present)
   ncid  = netcdf.open(fname);
   value = netcdf.getVar(ncid, varid);
else
   value = [];
end



function value = local_nc_attget(fname,varid,varname)
%% If the (global) attribute exists, return the value.
% If it does not, do not throw a hissy-fit.

value = [];
if (varid == nc_global)
   finfo = ncinfo(fname);
   for iatt = 1:length(finfo.Attributes)
      if (strcmp(finfo.Attributes(iatt).Name, deblank(varname)))
         value = finfo.Attributes(iatt).Value;
         return
      end
   end
else
   fprintf('function not supported for local variables, only global atts.\n')
end


% <next few lines under version control, do not edit>
% $URL$
% $Revision$
% $Date$


function plotdat = plot_bias_xxx_profile(fname,copystring)
% plot_bias_xxx_profile plots the vertical profile of the observation-space quantities for all possible levels, all possible variables.
% Part of the observation-space diagnostics routines.
%
% 'obs_diag' produces a netcdf file containing the diagnostics.
%
% USAGE: plotdat = plot_bias_xxx_profile(fname,copystring);
%
% fname  :  netcdf file produced by 'obs_diag'
% copystring :  'copy' string == quantity of interest. These
%            can be any of the ones available in the netcdf 
%            file 'CopyMetaData' variable.
%            (ncdump -v CopyMetaData obs_diag_output.nc)
%
% EXAMPLE:
%
% fname = 'obs_diag_output.nc';   % netcdf file produced by 'obs_diag'
% copystring = 'totalspread';   % 'copy' string == quantity of interest
% plotdat = plot_bias_xxx_profile(fname,copystring);

%% DART software - Copyright � 2004 - 2010 UCAR. This open source software is
% provided by UCAR, "as is", without charge, subject to all terms of use at
% http://www.image.ucar.edu/DAReS/DART/DART_download
%
% <next few lines under version control, do not edit>
% $URL:
% https://proxy.subversion.ucar.edu/DAReS/DART/trunk/diagnostics/matlab/plot_bias_xxx_profile.m $
% $Id$
% $Revision$
% $Date$

if (exist(fname,'file') ~= 2)
   error('file/fname <%s> does not exist',fname)
end

% Harvest plotting info/metadata from netcdf file.

plotdat.fname              = fname;
plotdat.copystring         = copystring;

plotdat.binseparation      = nc_attget(fname, nc_global, 'bin_separation');
plotdat.binwidth           = nc_attget(fname, nc_global, 'bin_width');
time_to_skip               = nc_attget(fname, nc_global, 'time_to_skip');
plotdat.rat_cri            = nc_attget(fname, nc_global, 'rat_cri');
plotdat.input_qc_threshold = nc_attget(fname, nc_global, 'input_qc_threshold');
plotdat.lonlim1            = nc_attget(fname, nc_global, 'lonlim1');
plotdat.lonlim2            = nc_attget(fname, nc_global, 'lonlim2');
plotdat.latlim1            = nc_attget(fname, nc_global, 'latlim1');
plotdat.latlim2            = nc_attget(fname, nc_global, 'latlim2');
plotdat.biasconv           = nc_attget(fname, nc_global, 'bias_convention');

plotdat.bincenters         = nc_varget(fname, 'time');
plotdat.binedges           = nc_varget(fname, 'time_bounds');
plotdat.mlevel             = nc_varget(fname, 'mlevel');
plotdat.plevel             = nc_varget(fname, 'plevel');
plotdat.plevel_edges       = nc_varget(fname, 'plevel_edges');
plotdat.hlevel             = nc_varget(fname, 'hlevel');
plotdat.hlevel_edges       = nc_varget(fname, 'hlevel_edges');

diminfo                    = nc_getdiminfo(fname,'region');
plotdat.nregions           = diminfo.Length;
region_names               = nc_varget(fname,'region_names');
plotdat.region_names       = deblank(region_names);

% Coordinate between time types and dates

calendar     = nc_attget(fname,'time','calendar');
timeunits    = nc_attget(fname,'time','units');
timebase     = sscanf(timeunits,'%*s%*s%d%*c%d%*c%d'); % YYYY MM DD
timeorigin   = datenum(timebase(1),timebase(2),timebase(3));
skip_seconds = time_to_skip(4)*3600 + time_to_skip(5)*60 + time_to_skip(6);
iskip        = time_to_skip(3) + skip_seconds/86400;

plotdat.bincenters = plotdat.bincenters + timeorigin;
plotdat.binedges   = plotdat.binedges   + timeorigin;
plotdat.Nbins      = length(plotdat.bincenters);
plotdat.toff       = plotdat.bincenters(1) + iskip;

% set up a structure with all static plotting components

plotdat.xlabel    = sprintf('bias (%s) and %s',plotdat.biasconv,copystring);
plotdat.linewidth = 2.0;

[plotdat.allvarnames, plotdat.allvardims] = get_varsNdims(fname);
[plotdat.varnames,    plotdat.vardims]    = FindVerticalVars(plotdat);

plotdat.nvars       = length(plotdat.varnames);

plotdat.copyindex   = get_copy_index(fname,copystring); 
plotdat.biasindex   = get_copy_index(fname,'bias');
plotdat.Npossindex  = get_copy_index(fname,'Nposs');
plotdat.Nusedindex  = get_copy_index(fname,'Nused');

%----------------------------------------------------------------------
% Loop around (copy-level-region) observation types
%----------------------------------------------------------------------

for ivar = 1:plotdat.nvars
    
   % create the variable names of interest.
    
   plotdat.myvarname = plotdat.varnames{ivar};
   plotdat.guessvar  = sprintf('%s_VPguess',plotdat.varnames{ivar});
   plotdat.analyvar  = sprintf('%s_VPanaly',plotdat.varnames{ivar});

   % remove any existing postscript file - will simply append each
   % level as another 'page' in the .ps file.
   
   psfname = sprintf('%s_bias_%s_profile.ps',plotdat.varnames{ivar},plotdat.copystring);
   disp(sprintf('Removing %s from the current directory.',psfname))
   system(sprintf('rm %s',psfname));

   % get appropriate vertical coordinate variable

   guessdims = nc_var_dims(  fname, plotdat.guessvar);
   analydims = nc_var_dims(  fname, plotdat.analyvar);
   varinfo   = nc_getvarinfo(fname, plotdat.analyvar);

   if ( findstr('surface',guessdims{2}) > 0 )
      fprintf('%s is a surface field.\n',plotdat.guessvar)
      fprintf('Cannot display a surface field this way.\n')
   elseif ( findstr('undef',guessdims{2}) > 0 )
      fprintf('%s has no vertical definition.\n',plotdat.guessvar)
      fprintf('Cannot display this field this way.\n')
   end

   [level_org level_units nlevels level_edges Yrange] = FindVerticalInfo(fname, plotdat.guessvar);
   plotdat.level_org   = level_org;
   plotdat.level_units = level_units;
   plotdat.nlevels     = nlevels;
   plotdat.level_edges = level_edges;
   plotdat.Yrange      = Yrange;

   % Matlab likes strictly ASCENDING order for things to be plotted,
   % then you can impose the direction. The data is stored in the original
   % order, so the sort indices are saved to reorder the data.

   if (plotdat.level_org(1) > plotdat.level_org(plotdat.nlevels))
      plotdat.YDir = 'reverse';
   else
      plotdat.YDir = 'normal';
   end
   [levels, indices]   = sort(plotdat.level_org);
   plotdat.level       = levels;
   plotdat.indices     = indices;
   level_edges         = sort(plotdat.level_edges);
   plotdat.level_edges = level_edges;
   
   guess = nc_varget(fname, plotdat.guessvar);  
   analy = nc_varget(fname, plotdat.analyvar); 
   n = size(analy);
  
   % singleton dimensions are auto-squeezed - which is unfortunate.
   % We want these things to be 3D. [copy-level-region]
   % Sometimes there is one region, sometimes one level, ...
   % To complicate matters, the stupid 'ones' function does not allow
   % the last dimension to be unity ... so you have double the size
   % of the array ...

   if ( plotdat.nregions == 1 )
       bob = NaN*ones(varinfo.Size(1),varinfo.Size(2),2);
       ted = NaN*ones(varinfo.Size(1),varinfo.Size(2),2);
       bob(:,:,1) = guess;
       ted(:,:,1) = analy;
       guess = bob; clear bob
       analy = ted; clear ted
   elseif ( plotdat.nlevels == 1 )
       bob = NaN*ones(varinfo.Size);
       ted = NaN*ones(varinfo.Size);
       bob(:,1,:) = guess;
       ted(:,1,:) = analy;
       guess = bob; clear bob
       analy = ted; clear ted
   end
   
   % check to see if there is anything to plot
   nposs = sum(guess(plotdat.Npossindex,:,:));

   if ( sum(nposs(:)) < 1 )
      fprintf('No obs for %s...  skipping\n', plotdat.varnames{ivar})
      continue
   end

   plotdat.ges_copy   = guess(plotdat.copyindex,  :, :);
   plotdat.anl_copy   = analy(plotdat.copyindex,  :, :);
   plotdat.ges_bias   = guess(plotdat.biasindex,  :, :);
   plotdat.anl_bias   = analy(plotdat.biasindex,  :, :);

   plotdat.ges_Nposs  = guess(plotdat.Npossindex, :, :);
   plotdat.anl_Nposs  = analy(plotdat.Npossindex, :, :);
   plotdat.ges_Nused  = guess(plotdat.Nusedindex, :, :);
   plotdat.anl_Nused  = guess(plotdat.Nusedindex, :, :);
   plotdat.Xrange     = FindRange(plotdat);

   % plot by region

   clf; orient tall

   for iregion = 1:plotdat.nregions
      plotdat.region = iregion;  
      plotdat.myregion = deblank(plotdat.region_names(iregion,:));

      myplot(plotdat);
   end

   if (plotdat.nregions > 2)
      CenterAnnotation(plotdat.myvarname)
   end
   % BottomAnnotation(ges)

   % create a postscript file
   print(gcf,'-dpsc','-append',psfname);

end

%----------------------------------------------------------------------
% 'Helper' functions
%----------------------------------------------------------------------

function myplot(plotdat)

   % Interlace the [ges,anl] to make a sawtooth plot.
   % By this point, the middle two dimensions are singletons.
   % The data must be sorted to match the order of the levels.
   cg = plotdat.ges_copy(:,:,plotdat.region); CG = cg(plotdat.indices);
   ca = plotdat.anl_copy(:,:,plotdat.region); CA = ca(plotdat.indices);

   mg = plotdat.ges_bias(:,:,plotdat.region); MG = mg(plotdat.indices);
   ma = plotdat.anl_bias(:,:,plotdat.region); MA = ma(plotdat.indices);

   g = plotdat.ges_Nposs(:,:,plotdat.region); G = g(plotdat.indices);
   a = plotdat.anl_Nposs(:,:,plotdat.region); A = a(plotdat.indices);
   nobs_poss   = G;
   nposs_delta = G - A;

   g = plotdat.ges_Nused(:,:,plotdat.region); G = g(plotdat.indices);
   a = plotdat.anl_Nused(:,:,plotdat.region); A = a(plotdat.indices);
   nobs_used   = G;
   nused_delta = G - A;

   % Determine some quantities for the legend
   nobs = sum(nobs_used);
   if ( nobs > 1 )
      bias_guess  = mean(MG(isfinite(MG)));   
      bias_analy  = mean(MA(isfinite(MA)));   
      other_guess = mean(CG(isfinite(CG))); 
      other_analy = mean(CA(isfinite(CA))); 
   else
      bias_guess  = NaN;
      bias_analy  = NaN;
      other_guess = NaN;
      other_analy = NaN;
   end

   str_bias_pr  = sprintf('%s pr=%.5g','bias',bias_guess);
   str_bias_po  = sprintf('%s po=%.5g','bias',bias_analy);
   str_other_pr = sprintf('%s pr=%.5g',plotdat.copystring,other_guess);
   str_other_po = sprintf('%s po=%.5g',plotdat.copystring,other_analy);

   % Plot the bias and 'xxx' on the same (bottom) axis.
   % The observation count will use the axis on the top.
   % Ultimately, we want to suppress the 'auto' feature of the
   % axis labelling, so we manually set some values that normally
   % don't need to be set.
   
   % if more then 4 regions, this will not work (well) ... 
   if ( plotdat.nregions > 2 )
       ax1 = subplot(2,2,plotdat.region);
   else
       ax1 = subplot(1,plotdat.nregions,plotdat.region);
       axpos = get(ax1,'Position');
       axpos(4) = 0.925*axpos(4);
       set(ax1,'Position',axpos);
   end

   Stripes(plotdat.Xrange, plotdat.level_edges);
   hold on;
   h1 = plot(MG,plotdat.level,'k+-',MA,plotdat.level,'k+:', ...
             CG,plotdat.level,'ro-',CA,plotdat.level,'ro:');
   hold off;
   set(h1,'LineWidth',plotdat.linewidth);
   h = legend(h1, str_bias_pr, str_bias_po, str_other_pr, str_other_po, ...
          'Location','East');
   legend(h,'boxoff')
   set(h,'Interpreter','none')

   axlims = [plotdat.Xrange plotdat.Yrange];
   axis(axlims)

   set(gca,'YDir', plotdat.YDir)
   hold on; plot([0 0],plotdat.Yrange,'k-')

   set(gca,'YTick',plotdat.level,'Ylim',plotdat.Yrange)
   ylabel(plotdat.level_units)
   
   % use same X,Y limits for all plots in this region
   nXticks = length(get(ax1,'XTick'));
   xlimits = plotdat.Xrange;
   xinc    = (xlimits(2)-xlimits(1))/(nXticks-1);
   xticks  = xlimits(1):xinc:xlimits(2);
   set(ax1,'XTick',xticks,'Xlim',xlimits)
   
   % create a separate scale for the number of observations
   ax2 = axes('position',get(ax1,'Position'), ...
           'XAxisLocation','top', ...
           'YAxisLocation','right',...
           'Color','none',...
           'XColor','b','YColor','b',...
           'YLim',plotdat.Yrange, ...
           'YDir',plotdat.YDir);
   h2 = line(nobs_poss,plotdat.level,'Color','b','Parent',ax2);
   h3 = line(nobs_used,plotdat.level,'Color','b','Parent',ax2);
   set(h2,'LineStyle','none','Marker','o');
   set(h3,'LineStyle','none','Marker','+');   

   % use same number of X ticks and the same Y ticks
  
   xlimits = get(ax2,'XLim');
   xinc   = (xlimits(2)-xlimits(1))/(nXticks-1);
   xticks = xlimits(1):xinc:xlimits(2);
   nicexticks = round(10*xticks')/10;
   set(ax2,'YTick',get(ax1,'YTick'),'YTicklabel',[], ...
           'XTick',          xticks,'XTicklabel',num2str(nicexticks))
       
   set(get(ax2,'Xlabel'),'String','# of obs (o=poss, +=used)')
   set(get(ax1,'Xlabel'),'String',plotdat.xlabel,'Interpreter','none')
   set(ax1,'Position',get(ax2,'Position'))
   grid

   if (plotdat.nregions <=2 )
      title({plotdat.myvarname, plotdat.myregion},  ...
        'Interpreter', 'none', 'Fontsize', 12, 'FontWeight', 'bold')
   else
      title(plotdat.myregion, ...
        'Interpreter', 'none', 'Fontsize', 12, 'FontWeight', 'bold')
   end



function CenterAnnotation(main)
subplot('position',[0.48 0.48 0.04 0.04])
axis off
h = text(0.5,0.5,main);
set(h,'HorizontalAlignment','center', ...
      'VerticalAlignment','bottom', ...
      'Interpreter','none', ...
      'FontSize',12, ...
      'FontWeight','bold')



function BottomAnnotation(main)
% annotates the directory containing the data being plotted
subplot('position',[0.48 0.01 0.04 0.04])
axis off
bob = which(main);
[pathstr,name,ext,versn] = fileparts(bob);
h = text(0.0,0.5,pathstr);
set(h,'HorizontalAlignment','center', ...
      'VerticalAlignment','middle',...
      'Interpreter','none',...
      'FontSize',8)



function [y,ydims] = FindVerticalVars(x)
% Returns UNIQUE (i.e. base) vertical variable names
if ( ~(isfield(x,'allvarnames') && isfield(x,'allvardims')))
   error('Doh! no ''allvarnames'' and ''allvardims'' components')
end

j = 0;

for i = 1:length(x.allvarnames)
   indx = findstr('time',x.allvardims{i});
   if (isempty(indx)) 
      j = j + 1;

      basenames{j} = ReturnBase(x.allvarnames{i});
      basedims{j}  = x.allvardims{i};
   end
end

[b,i,j] = unique(basenames);

for j = 1:length(i)
   disp(sprintf('%2d is %s',j,basenames{j}))
    y{j} = basenames{j};
ydims{j} = basedims{j};
end



function [level_org level_units nlevels level_edges Yrange] = FindVerticalInfo(fname,varname)
% Find the vertical dimension and harvest some info

varinfo  = nc_getvarinfo(fname,varname);
leveldim = [];

for i = 1:length(varinfo.Dimension)
   inds = strfind(varinfo.Dimension{i},'level');
   if ( ~ isempty(inds)), leveldim = i; end
end

if ( isempty(leveldim) )
   error('There is no level information for %s in %s',varname,fname)
end

level_org   = nc_varget(fname,varinfo.Dimension{leveldim});
level_units = nc_attget(fname,varinfo.Dimension{leveldim},'units');
nlevels     = varinfo.Size(leveldim);
edgename    = sprintf('%s_edges',varinfo.Dimension{leveldim});
level_edges = nc_varget(fname, edgename);
Yrange      = [min(level_edges) max(level_edges)];


function s = ReturnBase(string1)
inds = findstr('_guess',string1);
if (inds > 0 )
   s = string1(1:inds-1);
end

inds = findstr('_analy',string1);
if (inds > 0 )
   s = string1(1:inds-1);
end

inds = findstr('_VPguess',string1);
if (inds > 0 )
   s = string1(1:inds-1);
end

inds = findstr('_VPanaly',string1);
if (inds > 0 )
   s = string1(1:inds-1);
end



function x = FindRange(y)
% Trying to pick 'nice' limits for plotting.
% Completely ad hoc ... and not well posed.
%
% In this scope, y is bounded from below by 0.0
%
% If the numbers are very small ... 

bob  = [y.ges_copy(:) ; y.ges_bias(:); ...
        y.anl_copy(:) ; y.anl_bias(:)];
inds = find(isfinite(bob));

if ( isempty(inds) )
   x = [0 1];
else
   glommed = bob(inds);
   ymin    = min(glommed);
   ymax    = max(glommed);

   if ( ymax > 1.0 ) 
      ymin = floor(min(glommed));
      ymax =  ceil(max(glommed));
   end

   if (ymin == 0 && ymax == 0)
       ymax = 1;
   end
   
   if (ymin == ymax)
     ymin = ymin - 0.1*ymin;
     ymax = ymax + 0.1*ymax;
   end

   Yrange = [ymin ymax];

   x = sort([min([Yrange(1) 0.0]) Yrange(2)] ,'ascend');
end

function Stripes(x,edges)
% EraseMode: [ {normal} | background | xor | none ]

xc = [ x(1) x(2) x(2) x(1) x(1) ];

hold on;
for i = 1:2:(length(edges)-1)
  yc = [ edges(i) edges(i) edges(i+1) edges(i+1) edges(i) ];
  fill(xc,yc,[0.8 0.8 0.8],'EraseMode','background','EdgeColor','none');
end
hold off;

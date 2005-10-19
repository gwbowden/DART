! Data Assimilation Research Testbed -- DART
! Copyright 2004, 2005, Data Assimilation Initiative, University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html

program obs_diag

! <next five lines automatically updated by CVS, do not edit>
! $Source$
! $Revision$
! $Date$
! $Author$
! $Name$

!-----------------------------------------------------------------------
! The programs defines a series of epochs (periods of time) and geographic
! regions and accumulates statistics for these epochs and regions.
!
! All 'possible' obs_kinds are treated separately.
!-----------------------------------------------------------------------

use        types_mod, only : r8, digits12
use obs_sequence_mod, only : read_obs_seq, obs_type, obs_sequence_type, get_first_obs, &
                             get_obs_from_key, get_obs_def, get_copy_meta_data, &
                             get_obs_time_range, get_time_range_keys, get_num_obs, &
                             get_next_obs, get_num_times, get_obs_values, init_obs, &
                             assignment(=), get_num_copies, static_init_obs_sequence, &
                             get_qc, destroy_obs_sequence, read_obs_seq_header, & 
                             get_last_obs, destroy_obs
use      obs_def_mod, only : obs_def_type, get_obs_def_error_variance, get_obs_def_time, &
                             get_obs_def_location,  get_obs_kind, get_obs_name
use     obs_kind_mod, only : max_obs_kinds, get_obs_kind_var_type, get_obs_kind_name, &
                             KIND_U_WIND_COMPONENT, KIND_V_WIND_COMPONENT, &
                             KIND_SURFACE_PRESSURE, KIND_SPECIFIC_HUMIDITY
use     location_mod, only : location_type, get_location, set_location_missing, &
                             write_location, operator(/=), vert_is_surface, vert_is_pressure, &
                             vert_is_height
use time_manager_mod, only : time_type, set_date, set_time, get_time, print_time, &
                             set_calendar_type, print_date, GREGORIAN, &
                             operator(*), operator(+), operator(-), &
                             operator(>), operator(<), operator(/), &
                             operator(/=), operator(<=), operator(>=) 
use    utilities_mod, only : get_unit, open_file, close_file, register_module, &
                             file_exist, error_handler, E_ERR, E_MSG, &
                             initialize_utilities, logfileunit, timestamp, &
                             find_namelist_in_file, check_namelist_read

implicit none

! CVS Generated file description for error handling, do not edit
character(len=128) :: &
source   = "$Source$", &
revision = "$Revision$", &
revdate  = "$Date$"

type(obs_sequence_type) :: seq
type(obs_type)          :: observation, next_obs
type(obs_type)          :: obs1, obsN
type(obs_def_type)      :: obs_def
type(location_type)     :: obs_loc

!---------------------
integer :: obsindex, i, j, iunit, ierr, io, ivarcount
character(len = 129) :: obs_seq_in_file_name
character(len =  40) :: generic_obs_name   ! 8 longer than length of obs_def_mod:get_obs_name 

! Storage with fixed size for observation space diagnostics
real(r8), dimension(1) :: prior_mean, posterior_mean, prior_spread, posterior_spread
real(r8) :: pr_mean, po_mean ! same as above, without useless dimension 
real(r8) :: pr_sprd, po_sprd ! same as above, without useless dimension

!-----------------------------------------------------------------------
! We are treating winds as a vector pair, but we are handling the
! observations serially. Consequently, we exploit the fact that
! the U observations are _followed_ by the V observations.

real(r8)            :: U_obs         = 0.0_r8
real(r8)            :: U_obs_err_var = 0.0_r8
type(location_type) :: U_obs_loc
integer             :: U_type        = KIND_V_WIND_COMPONENT ! intentional mismatch
real(r8)            :: U_pr_mean     = 0.0_r8
real(r8)            :: U_pr_sprd     = 0.0_r8
real(r8)            :: U_po_mean     = 0.0_r8
real(r8)            :: U_po_sprd     = 0.0_r8

integer :: obs_index, prior_mean_index, posterior_mean_index
integer :: prior_spread_index, posterior_spread_index
integer :: key_bounds(2), flavor
integer :: num_copies, num_qc, num_obs, max_num_obs, obs_seq_file_id
character(len=129) :: obs_seq_read_format
logical :: pre_I_format

real(r8), dimension(1) :: obs, qc
real(r8) :: obs_err_var

integer,  allocatable :: keys(:)

logical :: out_of_range, is_there_one, is_this_last, keeper

!-----------------------------------------------------------------------
! Namelist with default values
!
character(len = 129) :: obs_sequence_name = "obs_seq.final"
integer, dimension(6) :: first_bin_center = (/ 2003, 1, 1, 0, 0, 0 /)
integer, dimension(6) :: last_bin_center  = (/ 2003, 1, 2, 0, 0, 0 /)
integer, dimension(6) :: bin_separation   = (/    0, 0, 0, 6, 0, 0 /)
integer, dimension(6) :: bin_width        = (/    0, 0, 0, 6, 0, 0 /)
integer, dimension(6) :: time_to_skip     = (/    0, 0, 1, 0, 0, 0 /)
integer :: max_num_bins   = 1000000  ! maximum number of bins to consider
integer :: plevel         = 500      ! pressure level (hPa)
integer :: hlevel         = 5000     ! height (meters)
integer :: obs_select     = 1        ! obs type selection: 1=all, 2 =RAonly, 3=noRA
integer :: Nregions       = 4
real(r8):: rat_cri        = 3.0_r8   ! QC ratio
real(r8):: qc_threshold   = 4.0_r8   ! maximum NCEP QC factor
logical :: print_mismatched_locs = .false.
logical :: verbose = .false.

! TJH - South Pole == lat 0   after you convert from radians.

real(r8), dimension(4) :: lonlim1 = (/   0.0_r8,   0.0_r8,   0.0_r8, 235.0_r8 /)
real(r8), dimension(4) :: lonlim2 = (/ 360.0_r8, 360.0_r8, 360.0_r8, 295.0_r8 /)
!real(r8), dimension(4) :: latlim1 = (/ 110.0_r8,  10.0_r8,  70.0_r8, 115.0_r8 /)
!real(r8), dimension(4) :: latlim2 = (/ 170.0_r8,  70.0_r8, 110.0_r8, 145.0_r8 /)
real(r8), dimension(4) :: latlim1 = (/  20.0_r8, -80.0_r8, -20.0_r8,  25.0_r8 /)
real(r8), dimension(4) :: latlim2 = (/  80.0_r8, -20.0_r8,  20.0_r8,  55.0_r8 /)

character(len = 20), dimension(4) :: reg_names = (/ 'Northern Hemisphere ', &
                                                    'Southern Hemisphere ', &
                                                    'Tropics             ', &
                                                    'North America       ' /)

namelist /obsdiag_nml/ obs_sequence_name, first_bin_center, last_bin_center, &
                       bin_separation, bin_width, time_to_skip, max_num_bins, &
                       plevel, hlevel, obs_select, Nregions, rat_cri, &
                       qc_threshold, lonlim1, lonlim2, latlim1, latlim2, reg_names, &
                       print_mismatched_locs, verbose

integer  :: iregion, iepoch, iday, ivar, ifile, num_obs_in_epoch
real(r8) :: lon0, lat0, obsloc3(3)
real(r8) :: speed_obs2, speed_ges2, speed_anl2

!-----------------------------------------------------------------------
! There are (at least) two types of vertical coordinates.
! Observations may be on pressure levels, height levels, etc.
! Since we calculate separate statistics for each observation type,
! we really don't care what kind of level they are on. BUT, since we
! are using one multidimensional array to accomodate all levels, each
! array of levels must be the same length. 
!
! The 'levels' array is a tricky beast.
! Since which_vert() is 2 for pressure and 3 for height, we 
! are designing an array to exploit that.
!-----------------------------------------------------------------------

integer, parameter :: nlev = 11
integer  :: levels(nlev,3)            ! set to 'mean' surface pressure (hPa)
integer  :: levels_int(nlev+1,3)      ! set to a bogus value ... never needed
integer  :: ivert
integer  :: which_vert(max_obs_kinds) ! need to know which kind of level for each obs kind

real(r8) :: scale_factor(max_obs_kinds)

integer  :: ilev          ! counter
integer  :: plevel_index  ! index of pressure level closest to input
integer  :: hlevel_index  ! index of height   level closest to input
integer  :: level_index   ! generic level index

data levels(:,1)     / 1013, 1013, 1013, 1013, 1013, 1013, 1013, 1013, 1013,  1013,  1013/ 
data levels(:,2)     / 1000,  925,  850,  700,  500,  400,  300,  250,  200,   150,   100/ 
data levels(:,3)     / 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000, 11000/

data levels_int(:,1) / 1025, 1025, 1025, 1025, 1025, 1025, 1000, 1000, 1000,  1000, 1000,  1000/ 
data levels_int(:,2) / 1025,  950,  900,  800,  600,  450,  350,  275,  225,  175,   125,    75/
data levels_int(:,3) /    0, 1500, 2500, 3500, 4500, 5500, 6500, 7500, 8500, 9500, 10500, 11500/

!-----------------------------------------------------------------------
! Variables used to accumulate the statistics.
! Dimension 1 is temporal, actually - these are time-by-region-by-var
!-----------------------------------------------------------------------

integer,  allocatable, dimension(:,:,:) :: num_in_level, num_ver

! statistics by time, for a particular level:  time-region-variable
real(r8), allocatable, dimension(:,:,:) :: rms_ges_mean   ! prior mean - obs
real(r8), allocatable, dimension(:,:,:) :: rms_ges_spread ! prior spread     
real(r8), allocatable, dimension(:,:,:) :: rms_anl_mean   ! posterior mean - obs
real(r8), allocatable, dimension(:,:,:) :: rms_anl_spread ! posterior spread

! statistics by level, averaged over time :  level-region-variable
real(r8), allocatable, dimension(:,:,:) ::  rms_ges_ver   ! prior mean - obs
real(r8), allocatable, dimension(:,:,:) :: bias_ges_ver   ! prior mean - obs (L1 norm)
real(r8), allocatable, dimension(:,:,:) ::  rms_anl_ver   ! posterior mean - obs
real(r8), allocatable, dimension(:,:,:) :: bias_anl_ver   ! posterior mean - obs (L1 norm)
                                           
type(time_type), allocatable, dimension(:) :: bincenter
real(digits12),  allocatable, dimension(:) :: epoch_center
integer,         allocatable, dimension(:) :: obs_used_in_epoch

!-----------------------------------------------------------------------
! General purpose variables
!-----------------------------------------------------------------------

integer  :: seconds, days
integer  :: obslevel, Nepochs
integer  :: gesUnit, anlUnit

! These pairs of variables are used when we diagnose which observations 
! are far from the background.
integer, parameter :: MaxSigmaBins = 100
integer  :: nsigma(0:MaxSigmaBins) = 0
integer  :: nsigmaUnit, indx

real(r8) :: ratio, ratioU

type(time_type) :: TimeMin, TimeMax    ! of the entire period of interest
type(time_type) :: beg_time, end_time  ! of the particular bin
type(time_type) :: binsep, binwidth, halfbinwidth 
type(time_type) :: seqT1, seqTN        ! first,last time in entire observation sequence
type(time_type) :: obs_time, skip_time

character(len =   6) :: day_num 
character(len = 129) :: gesName, anlName, msgstring
character(len =  32) :: str1, str2, str3

!-----------------------------------------------------------------------
! Some variables to keep track of who's rejected why ...
!-----------------------------------------------------------------------

integer                      :: NwrongType = 0   ! namelist discrimination
integer                      :: NbadQC     = 0   ! out-of-range QC values
integer                      :: NbadLevel  = 0   ! out-of-range pressures

integer, allocatable, dimension(:)   :: NbadW      ! V with no U, all days, regions
integer, allocatable, dimension(:)   :: NbadWvert  ! V with no U, select days, all levels
integer, allocatable, dimension(:,:) :: Nrejected  ! all days, each region, one layer

!=======================================================================
! Get the party started
!=======================================================================

call initialize_utilities('obs_diag')
call register_module(source,revision,revdate) 
call static_init_obs_sequence()  ! Initialize the obs sequence module 


write(logfileunit,*)levels
write(logfileunit,*)levels_int


scale_factor = 1.0_r8
which_vert   = -2     ! set to 'undefined' value 

! The surface pressure in the obs_sequence is in Pa, we want to convert
! from Pa to hPa for plotting. The specific humidity is a similar thing.
! In the obs_sequence file, the units are kg/kg, we want to plot
! in the g/kg world...

scale_factor(KIND_SURFACE_PRESSURE)  =    0.01_r8  
scale_factor(KIND_SPECIFIC_HUMIDITY) = 1000.0_r8

prior_mean(1)       = 0.0_r8
prior_spread(1)     = 0.0_r8
posterior_mean(1)   = 0.0_r8
posterior_spread(1) = 0.0_r8

U_obs_loc = set_location_missing()

!----------------------------------------------------------------------
! Read the namelist
!----------------------------------------------------------------------

call find_namelist_in_file("input.nml", "obsdiag_nml", iunit)
read(iunit, nml = obsdiag_nml, iostat = io)
call check_namelist_read(iunit, io, "obsdiag_nml")

! Record the namelist values used for the run ...
call error_handler(E_MSG,'obs_diag','obsdiag_nml values are',' ',' ',' ')
write(logfileunit,nml=obsdiag_nml)
write(    *      ,nml=obsdiag_nml)

! Open file for histogram of innovations, as a function of standard deviation.
nsigmaUnit = open_file('nsigma.dat',form='formatted',action='rewind')
write(nsigmaUnit,*) '  day   secs    lon    lat   level    obs   guess  ratio    key   kind'
!----------------------------------------------------------------------
! Now that we have input, do some checking and setup
!----------------------------------------------------------------------

allocate(rms_ges_ver(nlev, Nregions, max_obs_kinds), &
         rms_anl_ver(nlev, Nregions, max_obs_kinds), &
        bias_ges_ver(nlev, Nregions, max_obs_kinds), &
        bias_anl_ver(nlev, Nregions, max_obs_kinds), &
             num_ver(nlev, Nregions, max_obs_kinds))

 rms_ges_ver = 0.0_r8
 rms_anl_ver = 0.0_r8
bias_ges_ver = 0.0_r8
bias_anl_ver = 0.0_r8
num_ver      = 0

allocate(NbadW(Nregions), NbadWvert(Nregions), Nrejected(Nregions, max_obs_kinds))

NbadW      = 0
NbadWvert  = 0
Nrejected  = 0

plevel_index = GetClosestLevel(plevel, 2)  ! Set desired input level to nearest actual
hlevel_index = GetClosestLevel(hlevel, 3)  ! ditto for heights.

! Determine temporal bin characteristics.
! The user input is not guaranteed to align on bin centers. 
! So -- we will assume the start time is correct and take strides till we
! get past the last time of interest. 
! Nepochs will be the total number of time intervals of the period requested.

call set_calendar_type(GREGORIAN)

call Convert2Time(beg_time, end_time, skip_time, binsep, binwidth, halfbinwidth)

TimeMin  = beg_time
NepochLoop : do iepoch = 1,max_num_bins
   Nepochs = iepoch
   TimeMax = TimeMin + binsep
   if ( TimeMax >= end_time ) exit NepochLoop
   TimeMin = TimeMax
enddo NepochLoop

write(*,*)'Requesting ',Nepochs,' assimilation periods.'

! Define the centers of the temporal bins.

allocate(bincenter(Nepochs), epoch_center(Nepochs) ,obs_used_in_epoch(Nepochs))
obs_used_in_epoch = 0

iepoch = 1
bincenter(iepoch) = beg_time
call get_time(bincenter(iepoch),seconds,days)
epoch_center(iepoch) = days + seconds/86400.0_digits12

write(msgstring,'(''epoch '',i4,'' center '')')iepoch
call print_time(bincenter(iepoch),trim(adjustl(msgstring)),logfileunit)
call print_date(bincenter(iepoch),trim(adjustl(msgstring)),logfileunit)

write(logfileunit,*)''
BinLoop : do iepoch = 2,Nepochs
      bincenter(iepoch) = bincenter(iepoch-1) + binsep
      call get_time(bincenter(iepoch),seconds,days)
      epoch_center(iepoch) = days + seconds/86400.0_digits12

      write(msgstring,'(''epoch '',i4,'' center '')')iepoch
      call print_time(bincenter(iepoch),trim(adjustl(msgstring)),logfileunit)
      call print_date(bincenter(iepoch),trim(adjustl(msgstring)),logfileunit)
      write(logfileunit,*)''
enddo BinLoop

TimeMin = bincenter(   1   ) - halfbinwidth   ! minimum time of interest
TimeMax = bincenter(Nepochs) + halfbinwidth   ! maximum time of interest

if (verbose) call print_time(TimeMin,'minimum time of interest',logfileunit)
if (verbose) call print_time(TimeMax,'maximum time of interest',logfileunit)

allocate(rms_ges_mean(  Nepochs, Nregions, max_obs_kinds), &
         rms_ges_spread(Nepochs, Nregions, max_obs_kinds), &
         rms_anl_mean(  Nepochs, Nregions, max_obs_kinds), &
         rms_anl_spread(Nepochs, Nregions, max_obs_kinds), &
         num_in_level(  Nepochs, Nregions, max_obs_kinds) )

rms_ges_mean   = 0.0_r8
rms_anl_mean   = 0.0_r8
rms_ges_spread = 0.0_r8
rms_anl_spread = 0.0_r8
num_in_level   = 0

!-----------------------------------------------------------------------
! We must assume the observation sequence files span an unknown amount
! of time. We must make some sort of assumption about the naming structure
! of these files. Each file name is the same, but they live in sequentially-
! numbered directories. At one point, the first node in the directory name
! referred to 'month', so we will continue to interpret it that way.
! The last part of the directory name will be incremented ad infinitum.
!
! Directory/file names are similar to    01_03/obs_seq.final
!
!-----------------------------------------------------------------------
! The strategy at this point is to open WAY too many files and 
! check the observation sequences against ALL of the temporal bins.
! If the sequence is completely before the time period of interest, we skip.
! If the sequence is completely past the time period of interest, we stop.

ObsFileLoop : do ifile=1, Nepochs*4
!-----------------------------------------------------------------------

   write(day_num, '(i2.2,''_'',i2.2,''/'')') first_bin_center(2), ifile 
   write(obs_seq_in_file_name,*)trim(adjustl(day_num))//trim(adjustl(obs_sequence_name))

   if ( file_exist(trim(adjustl(obs_seq_in_file_name))) ) then
      write(msgstring,*)'opening ', trim(adjustl(obs_seq_in_file_name))
      call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate)
   else
      write(msgstring,*)trim(adjustl(obs_seq_in_file_name)),&
                        ' does not exist. Finishing up.'
      call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate)
      exit ObsFileLoop
   endif

   ! Read in information about observation sequence so we can allocate
   ! observations. We need info about how many copies, qc values, etc.

   obs_seq_in_file_name = trim(adjustl(obs_seq_in_file_name)) ! Lahey requirement

   call read_obs_seq_header(obs_seq_in_file_name, &
             num_copies, num_qc, num_obs, max_num_obs, &
             obs_seq_file_id, obs_seq_read_format, pre_I_format, &
             close_the_file = .true.)

   if ( verbose ) then
      write(logfileunit,*)'num_copies          is ',num_copies
      write(logfileunit,*)'num_qc              is ',num_qc
      write(logfileunit,*)'num_obs             is ',num_obs
      write(logfileunit,*)'max_num_obs         is ',max_num_obs
      write(logfileunit,*)'obs_seq_read_format is ',trim(adjustl(obs_seq_read_format))
      write(logfileunit,*)'pre_I_format        is ',pre_I_format
      write(    *      ,*)'num_copies          is ',num_copies
      write(    *      ,*)'num_qc              is ',num_qc
      write(    *      ,*)'num_obs             is ',num_obs
      write(    *      ,*)'max_num_obs         is ',max_num_obs
      write(    *      ,*)'obs_seq_read_format is ',trim(adjustl(obs_seq_read_format))
      write(    *      ,*)'pre_I_format        is ',pre_I_format
   endif

   ! Initialize some (individual) observation variables

   call init_obs(       obs1, num_copies, num_qc)   ! First obs in sequence
   call init_obs(       obsN, num_copies, num_qc)   ! Last  obs in sequence
   call init_obs(observation, num_copies, num_qc)   ! current obs
   call init_obs(   next_obs, num_copies, num_qc)   ! duh ...

   ! Read in the entire observation sequence

   call read_obs_seq(obs_seq_in_file_name, 0, 0, 0, seq)

   !--------------------------------------------------------------------
   ! Determine the time encompassed in the observation sequence.
   !--------------------------------------------------------------------

   is_there_one = get_first_obs(seq, obs1)
   if ( .not. is_there_one ) then
      call error_handler(E_ERR,'obs_diag','No first observation  in sequence.', &
      source,revision,revdate)
   endif
   call get_obs_def(obs1,   obs_def)
   seqT1 = get_obs_def_time(obs_def)

   is_there_one = get_last_obs(seq, obsN)
   if ( .not. is_there_one ) then
      call error_handler(E_ERR,'obs_diag','No last observation in sequence.', &
      source,revision,revdate)
   endif
   call get_obs_def(obsN,   obs_def)
   seqTN = get_obs_def_time(obs_def)

   call print_time(seqT1,'First observation time',logfileunit)
   call print_time(seqTN,'Last  observation time',logfileunit)

   !--------------------------------------------------------------------
   ! If the last observation is before the period of interest, move on.
   !--------------------------------------------------------------------

   if ( seqTN < TimeMin ) then
      if (verbose) write(*,*)'seqTN < TimeMin ... trying next file.'
      call destroy_obs(obs1)
      call destroy_obs(obsN)
      call destroy_obs(observation)
      call destroy_obs(next_obs)
      call destroy_obs_sequence(seq)
      cycle ObsFileLoop
   else
      if (verbose) write(*,*)'seqTN > TimeMin ... using ',trim(adjustl(obs_seq_in_file_name))
   endif

   !--------------------------------------------------------------------
   ! If the first observation is after the period of interest, finish.
   !--------------------------------------------------------------------

   if ( seqT1 > TimeMax ) then
      if (verbose) write(*,*)'seqT1 > TimeMax ... stopping.'
      call destroy_obs(obs1)
      call destroy_obs(obsN)
      call destroy_obs(observation)
      call destroy_obs(next_obs)
      call destroy_obs_sequence(seq)
      exit ObsFileLoop
   else
      if (verbose) write(*,*)'seqT1 < TimeMax ... using ',trim(adjustl(obs_seq_in_file_name))
   endif

   !--------------------------------------------------------------------
   ! Find the index of obs, ensemble mean, spread ... etc.
   !--------------------------------------------------------------------

   obs_index              = -1
   prior_mean_index       = -1
   posterior_mean_index   = -1
   prior_spread_index     = -1
   posterior_spread_index = -1

   MetaDataLoop : do i=1, get_num_copies(seq)
      if(index(get_copy_meta_data(seq,i), 'observation'              ) > 0) &
                          obs_index = i
      if(index(get_copy_meta_data(seq,i), 'prior ensemble mean'      ) > 0) &
                   prior_mean_index = i
      if(index(get_copy_meta_data(seq,i), 'posterior ensemble mean'  ) > 0) &
               posterior_mean_index = i
      if(index(get_copy_meta_data(seq,i), 'prior ensemble spread'    ) > 0) &
                 prior_spread_index = i
      if(index(get_copy_meta_data(seq,i), 'posterior ensemble spread') > 0) &
             posterior_spread_index = i
   enddo MetaDataLoop

   !--------------------------------------------------------------------
   ! Make sure we find an index for each of them.
   !--------------------------------------------------------------------

   if ( obs_index              < 0 ) then
      write(msgstring,*)'metadata:observation not found'
      call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate)
   endif
   if ( prior_mean_index       < 0 ) then
      write(msgstring,*)'metadata:prior ensemble mean not found'
      call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate)
   endif
   if ( posterior_mean_index   < 0 ) then 
      write(msgstring,*)'metadata:posterior ensemble mean not found' 
      call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate) 
   endif
   if ( prior_spread_index     < 0 ) then 
      write(msgstring,*)'metadata:prior ensemble spread not found'
      call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate) 
   endif
   if ( posterior_spread_index < 0 ) then 
      write(msgstring,*)'metadata:posterior ensemble spread not found' 
      call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate) 
   endif
   if ( any( (/obs_index, prior_mean_index, posterior_mean_index, & 
               prior_spread_index, posterior_spread_index /) < 0) ) then
      write(msgstring,*)'metadata incomplete'
      call error_handler(E_ERR,'obs_diag',msgstring,source,revision,revdate)
   endif

   !--------------------------------------------------------------------
   ! Echo what we found.
   !--------------------------------------------------------------------

   write(msgstring,'(''observation      index '',i2,'' metadata '',a)') &
        obs_index, trim(adjustl(get_copy_meta_data(seq,obs_index)))
   call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate)

   write(msgstring,'(''prior mean       index '',i2,'' metadata '',a)') &
        prior_mean_index, trim(adjustl(get_copy_meta_data(seq,prior_mean_index)))
   call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate)

   write(msgstring,'(''posterior mean   index '',i2,'' metadata '',a)') &
        posterior_mean_index, trim(adjustl(get_copy_meta_data(seq,posterior_mean_index)))
   call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate) 

   write(msgstring,'(''prior spread     index '',i2,'' metadata '',a)') &
        prior_spread_index, trim(adjustl(get_copy_meta_data(seq,prior_spread_index)))
   call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate)

   write(msgstring,'(''posterior spread index '',i2,'' metadata '',a)') &
        posterior_spread_index, trim(adjustl(get_copy_meta_data(seq,posterior_spread_index)))
   call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate)

   !====================================================================
   EpochLoop : do iepoch = 1, Nepochs
   !====================================================================

      beg_time = bincenter(iepoch) - halfbinwidth + set_time(1, 0)
      end_time = bincenter(iepoch) + halfbinwidth

      if ( verbose ) then
         write(str1,'(''epoch '',i6,''  start'')')iepoch
         write(str2,'(''epoch '',i6,'' center'')')iepoch
         write(str3,'(''epoch '',i6,''    end'')')iepoch
         call print_time(         beg_time,str1,logfileunit)
         call print_time(bincenter(iepoch),str2,logfileunit)
         call print_time(         end_time,str3,logfileunit)
         call print_time(         beg_time,str1)
         call print_time(bincenter(iepoch),str2)
         call print_time(         end_time,str3)
      endif

      call get_obs_time_range(seq, beg_time, end_time, key_bounds, &
                  num_obs_in_epoch, out_of_range)

      if( num_obs_in_epoch == 0 ) then
         if ( verbose ) then
            write(logfileunit,*)' No observations in epoch ',iepoch,' cycling ...'
            write(     *     ,*)' No observations in epoch ',iepoch,' cycling ...'
         endif
         cycle EpochLoop
      endif

      write(logfileunit, *) 'num_obs_in_epoch (', iepoch, ') = ', num_obs_in_epoch
      write(     *     , *) 'num_obs_in_epoch (', iepoch, ') = ', num_obs_in_epoch

      allocate(keys(num_obs_in_epoch))

      call get_time_range_keys(seq, key_bounds, num_obs_in_epoch, keys)

      !-----------------------------------------------------------------
      ObservationLoop : do obsindex = 1, num_obs_in_epoch
      !-----------------------------------------------------------------

         call get_obs_from_key(seq, keys(obsindex), observation)
         call get_obs_def(observation, obs_def)
         obs_time    = get_obs_def_time(obs_def)
         flavor      = get_obs_kind(obs_def)
         obs_err_var = get_obs_def_error_variance(obs_def) * &
                          scale_factor(get_obs_kind_var_type(flavor)) * &
                          scale_factor(get_obs_kind_var_type(flavor))

         obs_loc = get_obs_def_location(obs_def)
         obsloc3 = get_location(obs_loc)
         lon0    = obsloc3(1) ! [  0, 360]
         lat0    = obsloc3(2) ! [-90,  90]

         if(vert_is_surface(obs_loc)) then    ! use closest height equivalent 
            level_index        = 1            ! use 'surface' level
            ivert              = 1
            which_vert(flavor) = 1
            obslevel           = 1
         elseif(vert_is_pressure(obs_loc)) then
            level_index        = plevel_index    ! compare to desired pressure level
            ivert              = nint(0.01_r8 * obsloc3(3))  ! cvrt to hPa
            which_vert(flavor) = 2               ! use pressure column of 'levels'
            obslevel           = GetClosestLevel(ivert, which_vert(flavor))
         elseif(vert_is_height(obs_loc)) then
            level_index        = hlevel_index    ! compare to desired height level
            ivert              = nint(obsloc3(3)) 
            which_vert(flavor) = 3               ! use height column of 'levels'
            obslevel           = GetClosestLevel(ivert, which_vert(flavor))
         else
            call error_handler(E_ERR,'obs_diag','Vertical coordinate not recognized', &
                 source,revision,revdate)
         endif

         call get_qc(observation, qc, 1)
         call get_obs_values(observation, obs, obs_index)
         obs(1) = obs(1)*scale_factor(get_obs_kind_var_type(flavor))

         ! get interpolated values of prior and posterior ensemble mean

         call get_obs_values(observation,       prior_mean,       prior_mean_index)
         call get_obs_values(observation,   posterior_mean,   posterior_mean_index)
         call get_obs_values(observation,     prior_spread,     prior_spread_index)
         call get_obs_values(observation, posterior_spread, posterior_spread_index)

         pr_mean = prior_mean(1)      *scale_factor(get_obs_kind_var_type(flavor))
         po_mean = posterior_mean(1)  *scale_factor(get_obs_kind_var_type(flavor))
         pr_sprd = prior_spread(1)    *scale_factor(get_obs_kind_var_type(flavor))
         po_sprd = posterior_spread(1)*scale_factor(get_obs_kind_var_type(flavor))

         !--------------------------------------------------------------
         ! (DEBUG) Summary of observation knowledge at this point
         !--------------------------------------------------------------

         ! write(*,*)'observation # ',obsindex
         ! write(*,*)'obs_flavor ',flavor
         ! write(*,*)'obs_err_var ',obs_err_var
         ! write(*,*)'lon0/lat0 ',lon0,lat0
         ! write(*,*)'ivert,which_vert,closestlevel ',ivert,which_vert(flavor),obslevel
         ! write(*,*)'qc ',qc
         ! write(*,*)'obs(1) ',obs(1)
         ! write(*,*)'pr_mean,po_mean ',pr_mean,po_mean
         ! write(*,*)'pr_sprd,po_sprd ',pr_sprd,po_sprd

         !--------------------------------------------------------------
         ! A Whole bunch of reasons to be rejected
         !--------------------------------------------------------------

         keeper = CheckObsType(obs_select, flavor)
         if ( .not. keeper ) then
            write(*,*)'obs ',obsindex,' rejected by CheckObsType ',flavor
            NwrongType = NwrongType + 1
            cycle ObservationLoop
         endif

         if( qc(1) >= qc_threshold ) then
         !  write(*,*)'obs ',obsindex,' rejected by qc ',qc(1)
            NbadQC = NbadQC + 1
            cycle ObservationLoop
         endif

         if ( obslevel < 1 .or. obslevel > nlev )   then
         !  write(*,*)'obs ',obsindex,' rejected. Uninteresting level ',obslevel
         !  write(*,*)'obs ',obsindex,' rejected. ivert was ',ivert,&
         !                            ' for which_vert ',which_vert(flavor)
            NbadLevel = NbadLevel + 1
            cycle ObservationLoop
         endif

         ! update the histogram of the magnitude of the innovation,
         ! where each bin is a single standard deviation. This is 
         ! a one-sided histogram.

         ratio = GetRatio(obs(1), pr_mean, pr_sprd, obs_err_var)
         indx         = min(int(ratio), MaxSigmaBins)
         nsigma(indx) = nsigma(indx) + 1

         ! Individual observations that are very far away get individually
         ! logged to a separate file.

         if(ratio > 10.0_r8) then
            call get_time(obs_time,seconds,days)
            write(nsigmaUnit,FMT='(i7,1x,i5,1x,2f7.2,i6,2f8.2,f7.1,2i7)') &
                 days, seconds, lon0, lat0, ivert, &
                 obs(1), pr_mean, ratio, keys(obsindex), flavor
         endif

         obs_used_in_epoch(iepoch) = obs_used_in_epoch(iepoch) + 1

         !--------------------------------------------------------------
         ! If it is a U wind component, all we need to do is save it.
         ! It will be matched up with the subsequent V component.
         ! At some point we have to remove the dependency that the 
         ! U component MUST preceed the V component.
         !--------------------------------------------------------------

         if ( get_obs_kind_var_type(flavor) == KIND_U_WIND_COMPONENT ) then

           !if (verbose) then
           !   write(logfileunit,*)'obs ',obsindex,' is a U wind'
           !   write(     *     ,*)'obs ',obsindex,' is a U wind'
           !endif

            U_obs         = obs(1)
            U_obs_err_var = obs_err_var
            U_obs_loc     = obs_loc
            U_type        = KIND_U_WIND_COMPONENT
            U_pr_mean     = pr_mean
            U_pr_sprd     = pr_sprd
            U_po_mean     = po_mean
            U_po_sprd     = po_sprd

            cycle ObservationLoop

         endif

         !--------------------------------------------------------------
         ! We have Nregions of interest
         !--------------------------------------------------------------

         Areas : do iregion =1, Nregions

            keeper = InRegion( lon0, lat0, lonlim1(iregion), lonlim2(iregion), &
                                           latlim1(iregion), latlim2(iregion))
            if ( .not. keeper ) then
            !  if (verbose) then
            !     write(logfileunit,*)'lon/lat ',lon0,lat0,' not in region ',iregion
            !     write(     *     ,*)'lon/lat ',lon0,lat0,' not in region ',iregion
            !  endif
               cycle Areas
            endif

            !-----------------------------------------------------------
            ! Time series statistics of the selected layer and surface observations.
            !-----------------------------------------------------------
            ! If the observation is within our layer, great -- if
            ! not ... we still need to do vertical stats.

            DesiredLevel: if ( obslevel == level_index ) then

               if ( get_obs_kind_var_type(flavor) == KIND_V_WIND_COMPONENT ) then
                  ! The big assumption is that the U wind component has
                  ! immediately preceeded the V component and has been saved.
                  ! We check for compatibility and proceed.  

                  ierr = CheckMate(KIND_V_WIND_COMPONENT, U_type, obs_loc, U_obs_loc) 
                  if ( ierr /= 0 ) then
                     !  write(*,*)'time series ... V with no matching U ...'
                     NbadW(iregion) = NbadW(iregion) + 1
                     cycle ObservationLoop
                  endif

                  ! since we don't have the necessary covariance between U,V
                  ! we will reject if either univariate z score is bad 

                  ratioU = GetRatio(U_obs, U_pr_mean, U_pr_sprd, U_obs_err_var)

                  if( (ratio <= rat_cri) .and. (ratioU <= rat_cri) )  then
                     num_in_level(iepoch,iregion,flavor) = &
                     num_in_level(iepoch,iregion,flavor) + 1

                     rms_ges_mean(iepoch,iregion,flavor) = &
                     rms_ges_mean(iepoch,iregion,flavor) + &
                     (pr_mean - obs(1))**2 + (U_pr_mean - U_obs)**2

                     rms_anl_mean(iepoch,iregion,flavor) = &
                     rms_anl_mean(iepoch,iregion,flavor) + &
                     (po_mean - obs(1))**2 + (U_po_mean - U_obs)**2

                     ! these are wrong, but we don't have the off-diagonal
                     ! terms of the covariance matrix ... 
                     rms_ges_spread(iepoch,iregion,flavor) = &
                     rms_ges_spread(iepoch,iregion,flavor) + pr_sprd**2 + U_pr_sprd**2

                     rms_anl_spread(iepoch,iregion,flavor) = &
                     rms_anl_spread(iepoch,iregion,flavor) + po_sprd**2 + U_po_sprd**2
                  else
                     Nrejected(iregion,flavor) = Nrejected(iregion,flavor) + 1
                  endif

               else

                  if(ratio <= rat_cri ) then
                     num_in_level(iepoch,iregion,flavor) = &
                     num_in_level(iepoch,iregion,flavor) + 1

                     rms_ges_mean(iepoch,iregion,flavor) = &
                     rms_ges_mean(iepoch,iregion,flavor) + (pr_mean-obs(1))**2

                     rms_anl_mean(iepoch,iregion,flavor) = &
                     rms_anl_mean(iepoch,iregion,flavor) + (po_mean-obs(1))**2

                     rms_ges_spread(iepoch,iregion,flavor) = &
                     rms_ges_spread(iepoch,iregion,flavor) + pr_sprd**2

                     rms_anl_spread(iepoch,iregion,flavor) = &
                     rms_anl_spread(iepoch,iregion,flavor) + po_sprd**2
                  else
                     Nrejected(iregion,flavor) = Nrejected(iregion,flavor) + 1
                  endif

               endif

            endif DesiredLevel

            if (vert_is_surface(obs_loc)) cycle Areas

            !-----------------------------------------------------------
            ! end of time series statistics
            !-----------------------------------------------------------
            ! vertical statistical part
            !-----------------------------------------------------------

            if ( obs_time <= skip_time) cycle Areas

            if ( get_obs_kind_var_type(flavor) == KIND_V_WIND_COMPONENT ) then

               ierr = CheckMate(KIND_V_WIND_COMPONENT, U_type, obs_loc, U_obs_loc)

               if ( ierr /= 0 ) then

                  !  write(*,*)'vertical ... V with no matching U ...'

                  NbadWvert(iregion) = NbadWvert(iregion) + 1
                  cycle ObservationLoop
               endif

               ! Since we are treating wind as a vector quantity, the ratio
               ! calculation is a bit different.

               ratioU = GetRatio(U_obs, U_pr_mean, U_pr_sprd, U_obs_err_var)

               if( (ratio <= rat_cri) .and. (ratioU <= rat_cri) )  then
                  speed_ges2 = sqrt( U_pr_mean**2 + pr_mean**2 )
                  speed_anl2 = sqrt( U_po_mean**2 + po_mean**2 )
                  speed_obs2 = sqrt( U_obs**2 + obs(1)**2 )

                  num_ver(obslevel,iregion,flavor) =      num_ver(obslevel,iregion,flavor) + 1

                  rms_ges_ver(obslevel,iregion,flavor) =  rms_ges_ver(obslevel,iregion,flavor) + &
                       (pr_mean-obs(1))**2 + (U_pr_mean- U_obs)**2

                  rms_anl_ver(obslevel,iregion,flavor) =  rms_anl_ver(obslevel,iregion,flavor) + &
                       (po_mean-obs(1))**2 + (U_po_mean- U_obs)**2

                  bias_ges_ver(obslevel,iregion,flavor) = bias_ges_ver(obslevel,iregion,flavor) + &
                       speed_ges2 - speed_obs2

                  bias_anl_ver(obslevel,iregion,flavor) = bias_anl_ver(obslevel,iregion,flavor) + &
                       speed_anl2 - speed_obs2
               endif

            else

               if(ratio <= rat_cri )  then
                  num_ver(obslevel,iregion,flavor) =      num_ver(obslevel,iregion,flavor) + 1
                  rms_ges_ver(obslevel,iregion,flavor) =  rms_ges_ver(obslevel,iregion,flavor) + &
                       (pr_mean - obs(1))**2
                  rms_anl_ver(obslevel,iregion,flavor) =  rms_anl_ver(obslevel,iregion,flavor) + &
                       (po_mean - obs(1))**2
                  bias_ges_ver(obslevel,iregion,flavor) = bias_ges_ver(obslevel,iregion,flavor) + &
                       pr_mean - obs(1)
                  bias_anl_ver(obslevel,iregion,flavor) = bias_anl_ver(obslevel,iregion,flavor) + &
                       po_mean - obs(1)
               endif

            endif

            !-----------------------------------------------------------
            !  end of vertical statistics
            !-----------------------------------------------------------

         enddo Areas

      !-----------------------------------------------------------------
      enddo ObservationLoop
      !-----------------------------------------------------------------

      deallocate(keys)

   enddo EpochLoop

   if (verbose) then
      write(logfileunit,*)'End of EpochLoop for ',trim(adjustl(obs_seq_in_file_name))
      write(     *     ,*)'End of EpochLoop for ',trim(adjustl(obs_seq_in_file_name))
   endif

   call destroy_obs(obs1)
   call destroy_obs(obsN)
   call destroy_obs(observation)
   call destroy_obs(next_obs)
   call destroy_obs_sequence(seq)

enddo ObsFileLoop

!-----------------------------------------------------------------------
! We have read all possible files, and stuffed the observations into the
! appropriate bins. Time to normalize and finish up. Almost.
!-----------------------------------------------------------------------
! First, echo attributes to a file to facilitate plotting.
! This file is also a matlab function ... the variables are
! loaded by just typing the name at the matlab prompt.
! The output file names are included in this master file, 
! but they are created on-the-fly, so we must leave this open till then.
!-----------------------------------------------------------------------

iunit = open_file('ObsDiagAtts.m',form='formatted',action='rewind')
write(iunit,'(''first_bin_center = ['',6(1x,i5),''];'')')first_bin_center
write(iunit,'(''bin_separation   = ['',6(1x,i5),''];'')')bin_separation
write(iunit,'(''bin_width        = ['',6(1x,i5),''];'')')bin_width
write(iunit,'(''time_to_skip     = ['',6(1x,i5),''];'')')time_to_skip
write(iunit,'(''t1             = '',f20.6,'';'')')epoch_center(1)
write(iunit,'(''tN             = '',f20.6,'';'')')epoch_center(Nepochs)
write(iunit,'(''Nepochs        = '',i6,'';'')')Nepochs
write(iunit,'(''plevel         = '',i6,'';'')')plevel
write(iunit,'(''hlevel         = '',i6,'';'')')hlevel
write(iunit,'(''psurface       = '',i6,'';'')')levels_int(1,2)
write(iunit,'(''ptop           = '',i6,'';'')')levels_int(nlev+1,2)
write(iunit,'(''hlevel         = '',i6,'';'')')hlevel
write(iunit,'(''obs_select     = '',i6,'';'')')obs_select
write(iunit,'(''rat_cri        = '',f9.2,'';'')')rat_cri
write(iunit,'(''qc_threshold   = '',f9.2,'';'')')qc_threshold
write(iunit,'(''plev     = ['',11(1x,i5),''];'')')levels(:,2)
write(iunit,'(''plev_int = ['',12(1x,i5),''];'')')levels_int(:,2)
write(iunit,'(''hlev     = ['',11(1x,i5),''];'')')levels(:,3)
write(iunit,'(''hlev_int = ['',12(1x,i5),''];'')')levels_int(:,3)
write(iunit,'(''lonlim1 = ['',4(1x,f9.2),''];'')')lonlim1
write(iunit,'(''lonlim2 = ['',4(1x,f9.2),''];'')')lonlim2
write(iunit,'(''latlim1 = ['',4(1x,f9.2),''];'')')latlim1
write(iunit,'(''latlim2 = ['',4(1x,f9.2),''];'')')latlim2
do iregion=1,Nregions
   write(iunit,47)iregion,trim(adjustl(reg_names(iregion)))
enddo
47 format('Regions(',i3,') = {''',a,'''};')

do iepoch = 1, Nepochs
   write(msgstring,'(''num obs used in epoch '',i3,'' = '',i8)') iepoch, obs_used_in_epoch(iepoch)
   call error_handler(E_MSG,'obs_diag',msgstring,source,revision,revdate)
enddo

if (verbose) then
   write(logfileunit,*)'Normalizing time-region-variable quantities for desired level.'
   write(     *     ,*)'Normalizing time-region-variable quantities for desired level.'
endif

ivarcount = 0

OneLevel : do ivar=1,max_obs_kinds

   do iregion=1, Nregions
      do iepoch = 1, Nepochs
         if ( num_in_level(iepoch, iregion, ivar) == 0) then
              rms_ges_mean(iepoch, iregion, ivar) = -99.0_r8
              rms_anl_mean(iepoch, iregion, ivar) = -99.0_r8
            rms_ges_spread(iepoch, iregion, ivar) = -99.0_r8
            rms_anl_spread(iepoch, iregion, ivar) = -99.0_r8
         else

         !  write(logfileunit,*)'e,r,v #',iepoch,iregion,ivar,num_in_level(iepoch,iregion,ivar)
         !  write(     *     ,*)'e,r,v #',iepoch,iregion,ivar,num_in_level(iepoch,iregion,ivar)

              rms_ges_mean(iepoch, iregion, ivar) =   sqrt(rms_ges_mean(iepoch, iregion, ivar) / &
                                                           num_in_level(iepoch, iregion, ivar) )
              rms_anl_mean(iepoch, iregion, ivar) =   sqrt(rms_anl_mean(iepoch, iregion, ivar) / &
                                                           num_in_level(iepoch, iregion, ivar) )
            rms_ges_spread(iepoch, iregion, ivar) = sqrt(rms_ges_spread(iepoch, iregion, ivar) / &
                                                           num_in_level(iepoch, iregion, ivar) )
            rms_anl_spread(iepoch, iregion, ivar) = sqrt(rms_anl_spread(iepoch, iregion, ivar) / &
                                                           num_in_level(iepoch, iregion, ivar) )
         endif
      enddo
   enddo

   !--------------------------------------------------------------------
   ! Create data files for all observation kinds we have used
   !--------------------------------------------------------------------

   if( all (num_in_level(:, :, ivar) == 0) ) cycle OneLevel

   ivarcount = ivarcount + 1

   generic_obs_name = ProcessName(get_obs_name(ivar))

   write(gesName,'(a,''_ges_times.dat'')') trim(adjustl(generic_obs_name))
   write(anlName,'(a,''_anl_times.dat'')') trim(adjustl(generic_obs_name))
   gesUnit = open_file(trim(adjustl(gesName)),form='formatted',action='rewind')
   anlUnit = open_file(trim(adjustl(anlName)),form='formatted',action='rewind')

   if (verbose) then
      write(logfileunit,*)'Creating '//trim(adjustl(anlName))
      write(     *     ,*)'Creating '//trim(adjustl(gesName))
   endif

   do i=1, Nepochs
      if( any (num_in_level(i, :, ivar) /= 0) ) then
         call get_time(bincenter(i),seconds,days)
         write(gesUnit,91) days, seconds, &
              (rms_ges_mean(i,j,ivar),rms_ges_spread(i,j,ivar),num_in_level(i,j,ivar),j=1,Nregions)
         write(anlUnit,91) days, seconds, &
              (rms_anl_mean(i,j,ivar),rms_anl_spread(i,j,ivar),num_in_level(i,j,ivar),j=1,Nregions)
      endif
   enddo
   close(gesUnit)
   close(anlUnit)

   write(iunit,95) ivarcount, trim(adjustl(generic_obs_name))


enddo OneLevel

91 format(i7,1x,i5,4(1x,2f7.2,1x,i8))
95 format('One_Level_Varnames(',i3,') = {''',a,'''};')
96 format('All_Level_Varnames(',i3,') = {''',a,'''};')

! Actually print the histogram of innovations as a function of standard deviation. 
close(nsigmaUnit)
do i=0,MaxSigmaBins
   if(nsigma(i) /= 0) write(*,*)'innovations within ',i+1,' stdev = ',nsigma(i)
enddo

deallocate(rms_ges_mean, rms_ges_spread, &
           rms_anl_mean, rms_anl_spread, &
           num_in_level)

!-----------------------------------------------------------------------
! temporal average of the vertical statistics
!-----------------------------------------------------------------------
if (verbose) then
   write(logfileunit,*)'Normalize quantities for all levels.'
   write(     *     ,*)'Normalize quantities for all levels.'
endif

ivarcount = 0

AllLevels : do ivar=1,max_obs_kinds

   do iregion=1, Nregions
      do ilev=1, nlev
         if(     num_ver(ilev,iregion,ivar) == 0) then
             rms_ges_ver(ilev,iregion,ivar) = -99.0_r8
             rms_anl_ver(ilev,iregion,ivar) = -99.0_r8
            bias_ges_ver(ilev,iregion,ivar) = -99.0_r8
            bias_anl_ver(ilev,iregion,ivar) = -99.0_r8
         else

         !  write(logfileunit,*)'l,r,v #',ilev,iregion,ivar,num_ver(ilev,iregion,ivar)
         !  write(     *     ,*)'l,r,v #',ilev,iregion,ivar,num_ver(ilev,iregion,ivar)

             rms_ges_ver(ilev,iregion,ivar) = sqrt(  rms_ges_ver(ilev,iregion,ivar) / &
                                                         num_ver(ilev,iregion,ivar))
             rms_anl_ver(ilev,iregion,ivar) = sqrt(  rms_anl_ver(ilev,iregion,ivar) / &
                                                         num_ver(ilev,iregion,ivar))
            bias_ges_ver(ilev,iregion,ivar) =       bias_ges_ver(ilev,iregion,ivar) / &
                                                         num_ver(ilev,iregion,ivar)
            bias_anl_ver(ilev,iregion,ivar) =       bias_anl_ver(ilev,iregion,ivar) / &
                                                         num_ver(ilev,iregion,ivar)
         endif
      enddo
   enddo

   !--------------------------------------------------------------------
   ! Create data files for all observation kinds we have used
   !--------------------------------------------------------------------

   if( all (num_ver(:,:,ivar) == 0) ) cycle AllLevels

   ivarcount = ivarcount + 1

   generic_obs_name = ProcessName(get_obs_name(ivar))

   write(gesName,'(a,''_ges_ver_ave.dat'')') trim(adjustl(generic_obs_name))
   write(anlName,'(a,''_anl_ver_ave.dat'')') trim(adjustl(generic_obs_name))
   gesUnit = open_file(trim(adjustl(gesName)),form='formatted',action='rewind')
   anlUnit = open_file(trim(adjustl(anlName)),form='formatted',action='rewind')

   if (verbose) then
      write(logfileunit,*)'Creating '//trim(adjustl(anlName))
      write(     *     ,*)'Creating '//trim(adjustl(gesName))
   endif

   do ilev = nlev, 1, -1
      write(gesUnit, 610) levels(ilev,which_vert(ivar)), &
           (rms_ges_ver(ilev,iregion,ivar), num_ver(ilev,iregion,ivar), iregion=1, Nregions)
      write(anlUnit, 610) levels(ilev,which_vert(ivar)), &
           (rms_anl_ver(ilev,iregion,ivar), num_ver(ilev,iregion,ivar), iregion=1, Nregions) 
   enddo
   close(gesUnit)
   close(anlUnit)

   write(gesName,'(a,''_ges_ver_ave_bias.dat'')') trim(adjustl(generic_obs_name))
   write(anlName,'(a,''_anl_ver_ave_bias.dat'')') trim(adjustl(generic_obs_name))
   gesUnit = open_file(trim(adjustl(gesName)),form='formatted',action='rewind')
   anlUnit = open_file(trim(adjustl(anlName)),form='formatted',action='rewind')

   if (verbose) then
      write(logfileunit,*)'Creating '//trim(adjustl(anlName))
      write(     *     ,*)'Creating '//trim(adjustl(gesName))
   endif

   do ilev = nlev, 1, -1
      write(gesUnit, 610) levels(ilev,which_vert(ivar)), &
           (bias_ges_ver(ilev,iregion,ivar), num_ver(ilev,iregion,ivar), iregion=1, Nregions)
      write(anlUnit, 610) levels(ilev,which_vert(ivar)), &
           (bias_anl_ver(ilev,iregion,ivar), num_ver(ilev,iregion,ivar), iregion=1, Nregions) 
   enddo
   close(gesUnit)
   close(anlUnit)

   write(iunit,96) ivarcount, trim(adjustl(generic_obs_name))

enddo AllLevels

610 format(i5, 4(f8.3, i8) )

!-----------------------------------------------------------------------
close(iunit)   ! Finally close the 'master' matlab diagnostic file.
!-----------------------------------------------------------------------
! Print final rejection summary.
!-----------------------------------------------------------------------

write(*,*) ''
write(*,*) '# observations used  : ',sum(obs_used_in_epoch)
write(*,*) 'Rejected Observations summary.'
write(*,*) '# NwrongType         : ',NwrongType
write(*,*) '# NbadQC             : ',NbadQC
write(*,*) '# NbadLevel          : ',NbadLevel
write(*,'(a)')'Table of observations rejected by region for specified level'
write(*,'(5a)')'                                       ',reg_names(1:Nregions)
do ivar=1,max_obs_kinds
   generic_obs_name = ProcessName(get_obs_name(ivar))
   write(*,'(3a,4i8)') ' # ',generic_obs_name,'         : ',Nrejected(:,ivar)
enddo
write(*,'(a,4i8)') ' # bad winds per region for specified level         : ',NbadW
write(*,'(a,4i8)') ' # bad winds per region for all levels              : ',NbadWvert
write(*,*)''

write(logfileunit,*) ''
write(logfileunit,*) '# observations used  : ',sum(obs_used_in_epoch)
write(logfileunit,*) 'Rejected Observations summary.'
write(logfileunit,*) '# NwrongType         : ',NwrongType
write(logfileunit,*) '# NbadQC             : ',NbadQC
write(logfileunit,*) '# NbadLevel          : ',NbadLevel
write(logfileunit,'(a)')'Table of observations rejected by region for specified level'
write(logfileunit,'(5a)')'                                       ',reg_names(1:Nregions)
do ivar=1,max_obs_kinds
   generic_obs_name = ProcessName(get_obs_name(ivar))
   write(logfileunit,'(3a,4i8)') ' # ',generic_obs_name,'         : ',Nrejected(:,ivar)
enddo
write(logfileunit,'(a,4i8)') ' # bad winds per region for specified level         : ',NbadW
write(logfileunit,'(a,4i8)') ' # bad winds per region for all levels              : ',NbadWvert

!-----------------------------------------------------------------------
! Really, really, done.
!-----------------------------------------------------------------------

deallocate(rms_ges_ver, rms_anl_ver, bias_ges_ver, bias_anl_ver, &
           num_ver, NbadW, NbadWvert, Nrejected, & 
           epoch_center, bincenter, obs_used_in_epoch)

call timestamp(source,revision,revdate,'end') ! That closes the log file, too.

contains

   Function GetRatio(obsval, prmean, prspred, errcov) result (ratio)
   real(r8), intent(in) :: obsval, prmean, prspred, errcov
   real(r8)             :: ratio

   real(r8) :: numer, denom

   numer = abs(prmean- obsval)
   denom = sqrt( prspred**2 + errcov )
   ratio = numer / denom

   end Function GetRatio



   Function CheckMate(flavor1, flavor2, obsloc1, obsloc2) result (ierr)
   integer,             intent(in) :: flavor1, flavor2
   type(location_type), intent(in) :: obsloc1, obsloc2
   integer                         :: ierr

   ierr = -1 ! Assume no match ... till proven otherwise

   ! flavor 1 has to be either U or V, flavor 2 has to be the complement
   if ( .not.((flavor1 == KIND_U_WIND_COMPONENT .and. flavor2 == KIND_V_WIND_COMPONENT) .or. &
              (flavor2 == KIND_U_WIND_COMPONENT .and. flavor1 == KIND_V_WIND_COMPONENT)) ) then
      write(*,*) 'flavors not complementary ...',flavor1, flavor2
      return
   endif 

   if ( obsloc1 /= obsloc2 ) then
      if ( print_mismatched_locs ) then
         write(*,*) 'locations do not match ...'
         call write_location(6,obsloc1,'FORMATTED')
         call write_location(6,obsloc2,'FORMATTED')
      endif
      return
   endif

   ierr = 0

   end Function CheckMate



   Function GetClosestLevel(level_in, levind) result (level_index_out)
   ! The levels, intervals are ordered  surface == 1
   !
   ! nlev, levels and levels_int are scoped in this unit.
   !
   integer, intent(in) :: level_in         ! target level
   integer, intent(in) :: levind
   integer             :: level_index_out, a(1)

   integer, dimension(nlev) :: dx

   if (levind == 3) then   ! we have heights levels

      if (level_in < levels_int(1,levind) ) then             ! below surface
         level_index_out = -1
      else if ( level_in > levels_int(nlev+1,levind) ) then  ! outer space
         level_index_out = 100 + nlev
      else
         dx = abs(level_in - levels(:,levind))               ! whole array
         a  = minloc(dx)
         level_index_out = a(1)
      endif

      write(*,*)'level_in/column ',level_in,levind,' results in ',level_index_out

   else  ! we have pressure levels (or surface obs ... also in pressure units)

      if (level_in > levels_int(1,levind) )             then ! greater than surface
         level_index_out = -1
      else if ( level_in <= levels_int(nlev+1,levind) ) then ! outer space
         level_index_out = 100 + nlev
      else
         dx = abs(level_in - levels(:,levind))               ! whole array
         a  = minloc(dx)
         level_index_out = a(1)
      endif

   endif


   end Function GetClosestLevel



   Function InRegion( lon, lat, lon1, lon2, lat1, lat2 ) result( keeper )
   real(r8), intent(in) :: lon, lat, lon1, lon2, lat1, lat2
   logical :: keeper

   keeper = .false.

   if( (lon .ge. lon1) .and. (lon .le. lon2) .and. &
       (lat .ge. lat1) .and. (lat .le. lat2) ) keeper = .true.

   end Function InRegion


   Function CheckObsType(obs_select, flavor) result(keeper)

   integer,  intent(in) :: obs_select 
   integer,  intent(in) :: flavor
   logical              :: keeper

   character(len = 10) :: platform

   keeper = .true. ! Innocent till proven guilty ...

   platform = get_obs_kind_name(flavor)
   if( (obs_select == 2) .and. (platform /= 'RADIOSONDE') ) keeper = .false.
   if( (obs_select == 3) .and. (platform == 'RADIOSONDE') ) keeper = .false.

   end Function CheckObsType


   Function ProcessName(obs_name) result(generic_obs_name)
   ! Just an effort to replace "_V_WIND_COMPONENT" with
   ! _HORIZONTAL_WIND_VELOCITY
   !
   ! Since the second string is 8 characters longer than the first,
   ! the output string must be longer than the input.
   ! The intput string length is determined by the get_obs_name routine.

   character(len=*), intent(in) :: obs_name
   character(len=40)            :: generic_obs_name

   integer :: indx1,indxN

   indx1 = index(obs_name,'_V_WIND_COMPONENT') - 1
   indxN = len_trim(obs_name)

   if (indx1 > 0) then
      generic_obs_name = obs_name(1:indx1)//'_HORIZONTAL_WIND_VELOCITY'//obs_name(indx1+18:indxN)
   else
      generic_obs_name = obs_name
   endif

   end Function ProcessName


   Subroutine Convert2Time(beg_time, end_time, skip_time, binsep, &
                           binwidth, halfbinwidth)
   ! We are using bin_separation and bin_width as offsets relative to the
   ! first time. to ensure this, the year and month must be zero.

   type(time_type), intent(out) :: beg_time     ! first_bin_center
   type(time_type), intent(out) :: end_time     ! last_bin_center
   type(time_type), intent(out) :: skip_time    ! time AFTER first_bin_center
   type(time_type), intent(out) :: binsep       ! time between bin centers
   type(time_type), intent(out) :: binwidth     ! period of interest around center
   type(time_type), intent(out) :: halfbinwidth ! half that period

   character(len=129) :: msgstring
   logical :: error_out = .false.
   integer :: seconds

   ! do some error-checking first

   if ( (bin_separation(1) /= 0) .or. (bin_separation(2) /= 0) ) then
      write(msgstring,*)'bin_separation:year,month must both be zero, they are ', &
      bin_separation(1),bin_separation(2)
      call error_handler(E_MSG,'obs_diag:Convert2Time',msgstring,source,revision,revdate)
      error_out = .true.
   endif

   if ( (bin_width(1) /= 0) .or. (bin_width(2) /= 0) ) then
      write(msgstring,*)'bin_width:year,month must both be zero, they are ', &
      bin_width(1),bin_width(2)
      call error_handler(E_MSG,'obs_diag:Convert2Time',msgstring,source,revision,revdate)
      error_out = .true.
   endif
   
   if ( (time_to_skip(1) /= 0) .or. (time_to_skip(2) /= 0) ) then
      write(msgstring,*)'time_to_skip:year,month must both be zero, they are ', &
      time_to_skip(1),time_to_skip(2)
      call error_handler(E_MSG,'obs_diag:Convert2Time',msgstring,source,revision,revdate)
      error_out = .true.
   endif

   if ( error_out ) call error_handler(E_ERR,'obs_diag:Convert2Time', &
       'namelist parameter out-of-bounds. Fix and try again.',source,revision,revdate)

   ! Set time of first bin center

   beg_time   = set_date(first_bin_center(1), first_bin_center(2), &
                         first_bin_center(3), first_bin_center(4), &
                         first_bin_center(5), first_bin_center(6) )

   ! Set time of _intended_ last bin center
   end_time   = set_date( last_bin_center(1),  last_bin_center(2), &
                          last_bin_center(3),  last_bin_center(4), &
                          last_bin_center(5),  last_bin_center(6) )

   seconds  = bin_separation(4)*3600 + bin_separation(5)*60 + bin_separation(6)
   binsep   = set_time(seconds, bin_separation(3))

   seconds  = bin_width(4)*3600 + bin_width(5)*60 + bin_width(6)
   binwidth = set_time(seconds, bin_width(3))

   halfbinwidth = binwidth / 2

   seconds   = time_to_skip(4)*3600 + time_to_skip(5)*60 + time_to_skip(6)
   skip_time = beg_time + set_time(seconds, time_to_skip(3))

   if ( verbose ) then
      call print_date(    beg_time,'requested beginning date',logfileunit)
      call print_date(   skip_time,'requested skip      date',logfileunit)
      call print_date(    end_time,'requested end       date',logfileunit)
      call print_time(    beg_time,'requested beginning time',logfileunit)
      call print_time(   skip_time,'requested skip      time',logfileunit)
      call print_time(    end_time,'requested end       time',logfileunit)
      call print_time(      binsep,'requested bin separation',logfileunit)
      call print_time(    binwidth,'requested bin      width',logfileunit)
      call print_time(halfbinwidth,'implied     halfbinwidth',logfileunit)

      call print_date(    beg_time,'requested beginning date')
      call print_date(   skip_time,'requested skip      date')
      call print_date(    end_time,'requested end       date')
      call print_time(    beg_time,'requested beginning time')
      call print_time(   skip_time,'requested skip      time')
      call print_time(    end_time,'requested end       time')
      call print_time(      binsep,'requested bin separation')
      call print_time(    binwidth,'requested bin      width')
      call print_time(halfbinwidth,'implied     halfbinwidth')
   endif

   end Subroutine Convert2Time


end program obs_diag

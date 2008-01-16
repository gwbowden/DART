! Data Assimilation Research Testbed -- DART
! Copyright 2004-2007, Data Assimilation Research Section
! University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html

module model_mod

! <next few lines under version control, do not edit>
! $URL$
! $Id$
! $Revision$
! $Date$

! Assimilation interface for WRF model

!-----------------------------------------------------------------------
!
!     interface for WRF
!
!-----------------------------------------------------------------------
!---------------- m o d u l e   i n f o r m a t i o n ------------------
!-----------------------------------------------------------------------

use         types_mod, only : r8, deg2rad, missing_r8, ps0, earth_radius, &
                              gas_constant, gas_constant_v, gravity

use  time_manager_mod, only : time_type, set_time, set_calendar_type, GREGORIAN

use      location_mod, only : location_type, get_location, set_location, &
                              horiz_dist_only, &
                              LocationDims, LocationName, LocationLName, &
                              query_location, vert_is_undef, vert_is_surface, &
                              vert_is_level, vert_is_pressure, vert_is_height, &
                              VERTISUNDEF, VERTISSURFACE, VERTISLEVEL, VERTISPRESSURE, &
                              VERTISHEIGHT,&
                              get_close_type, get_dist, get_close_maxdist_init, &
                              get_close_obs_init, loc_get_close_obs => get_close_obs

use     utilities_mod, only : file_exist, open_file, close_file, &
                              register_module, error_handler, E_ERR, E_WARN, &
                              E_MSG, logfileunit, find_namelist_in_file, check_namelist_read

use      obs_kind_mod, only : KIND_U_WIND_COMPONENT, KIND_V_WIND_COMPONENT, &
                              KIND_SURFACE_PRESSURE, KIND_TEMPERATURE, &
                              KIND_SPECIFIC_HUMIDITY, KIND_SURFACE_ELEVATION, &
                              KIND_PRESSURE, KIND_VERTICAL_VELOCITY, &
                              KIND_RAINWATER_MIXING_RATIO, KIND_DENSITY, &
                              KIND_GRAUPEL_MIXING_RATIO, KIND_SNOW_MIXING_RATIO, &
                              KIND_CLOUD_LIQUID_WATER, KIND_CLOUD_ICE, &
                              KIND_CONDENSATIONAL_HEATING, KIND_VAPOR_MIXING_RATIO, &
                              KIND_ICE_NUMBER_CONCENTRATION, KIND_GEOPOTENTIAL_HEIGHT, &
                              KIND_POTENTIAL_TEMPERATURE, KIND_SOIL_MOISTURE, &
                              KIND_VORTEX_LAT, KIND_VORTEX_LON, &
                              KIND_VORTEX_PMIN, KIND_VORTEX_WMAX


!nc -- module_map_utils split the declarations of PROJ_* into a separate module called
!nc --   misc_definitions_module 
use         map_utils, only : proj_info, map_init, map_set, latlon_to_ij, &
                              ij_to_latlon, gridwind_to_truewind

use misc_definitions_module, only : PROJ_LATLON, PROJ_MERC, PROJ_LC, PROJ_PS, PROJ_CASSINI, &
                                    PROJ_CYL

use netcdf
use typesizes

implicit none
private


!-----
! DART requires 16 specific public interfaces from model_mod.f90 -- Note
!   that the last four are simply "stubs" since WRF currently requires use
!   of system called shell scripts to advance the model.

public ::  get_model_size,                    &
           get_state_meta_data,               &
           model_interpolate,                 &
           get_model_time_step,               &
           static_init_model,                 &
           pert_model_state,                  &
           nc_write_model_atts,               &
           nc_write_model_vars,               &
           get_close_obs,                     &
           ens_mean_for_model,                &
           get_close_maxdist_init,            &
           get_close_obs_init

!  public stubs 
public ::  adv_1step,       &
           end_model,       &
           init_time,       &
           init_conditions

!-----
! Here is the appropriate place for other users to make additional routines
!   contained within model_mod available for public use:
public ::  get_domain_info,      &
           get_number_domains,   &
           get_state_size,       &
           get_state_components



!-----------------------------------------------------------------------
! version controlled file description for error handling, do not edit
character(len=128), parameter :: &
   source   = "$URL$", &
   revision = "$Revision$", &
   revdate  = "$Date$"

!-----------------------------------------------------------------------
! Model namelist parameters with default values.
!
! center_search_half_length:  half length (in meter) of the searching box to locate 
!                             minimum pressure at a grid point
! center_spline_scale: coarse grid to spline interp. fine grid ratio
!-----------------------------------------------------------------------

logical :: output_state_vector  = .false.     ! output prognostic variables
integer :: num_moist_vars       = 3
integer :: num_domains          = 1
integer :: calendar_type        = GREGORIAN
integer :: assimilation_period_seconds = 21600
logical :: surf_obs             = .true.
logical :: soil_data            = .true.
logical :: h_diab               = .false.
character(len = 72) :: adv_mod_command = './wrf.exe'
real (kind=r8) :: center_search_half_length = 500000.0_r8
integer :: center_search_half_size
integer :: center_spline_grid_scale = 10
integer :: vert_localization_coord = VERTISHEIGHT
!nc -- we are adding these to the model.nml until they appear in the NetCDF files
logical :: polar = .false.
logical :: periodic_x = .false.

real(r8), allocatable :: ens_mean(:)

namelist /model_nml/ output_state_vector, num_moist_vars, &
                     num_domains, calendar_type, surf_obs, soil_data, h_diab, &
                     adv_mod_command, assimilation_period_seconds, &
                     vert_localization_coord, &
                     center_search_half_length, center_spline_grid_scale, &
                     polar, periodic_x

!-----------------------------------------------------------------------

! Private definition of domain map projection use by WRF

!nc -- added in CASSINI and CYL according to module_map_utils convention
integer, parameter :: map_sphere = 0, map_lambert = 1, map_polar_stereo = 2, map_mercator = 3
integer, parameter :: map_cassini = 6, map_cyl = 5

! Private definition of model variable types

integer, parameter :: TYPE_U     = 1,   TYPE_V     = 2,   TYPE_W     = 3,  &
                      TYPE_GZ    = 4,   TYPE_T     = 5,   TYPE_MU    = 6,  &
                      TYPE_TSK   = 7,   TYPE_QV    = 8,   TYPE_QC    = 9,  &
                      TYPE_QR    = 10,  TYPE_QI    = 11,  TYPE_QS    = 12, &
                      TYPE_QG    = 13,  TYPE_QNICE = 14,  TYPE_U10   = 15, &
                      TYPE_V10   = 16,  TYPE_T2    = 17,  TYPE_TH2   = 18, &
                      TYPE_Q2    = 19,  TYPE_PS    = 20,  TYPE_TSLB  = 21, &
                      TYPE_SMOIS = 22,  TYPE_SH2O  = 23,  TYPE_HDIAB = 24
integer, parameter :: num_model_var_types = 24

real (kind=r8), PARAMETER    :: kappa = 2.0_r8/7.0_r8 ! gas_constant / cp
real (kind=r8), PARAMETER    :: ts0 = 300.0_r8        ! Base potential temperature for all levels.

! Private logical parameter controlling behavior within subroutine model_interpolate
logical, parameter  :: allow_obs_below_surf = .false.

!---- private data ----

! Got rid of surf_var as global private variable for model_mod and just defined it locally
!   within model_interpolate

TYPE wrf_static_data_for_dart

   integer  :: bt, bts, sn, sns, we, wes, sls
   real(r8) :: dx, dy, dt, p_top
   integer  :: map_proj
   real(r8) :: cen_lat,cen_lon
   type(proj_info) :: proj

   ! Boundary conditions -- hopefully one day these will be in the global attributes of the
   !   input NetCDF file ("periodic_x" and "polar" are namelist items in the &bdy_control
   !   section of a standard WRF "namelist.input" file), but for now we have included them
   !   in the "model_nml" group of DART's own "input.nml".  Above, their default values are
   !   both set to .true. (indicating a global domain). 
   logical  :: periodic_x
   logical  :: polar

   integer  :: n_moist
   logical  :: surf_obs
   logical  :: soil_data
   integer  :: vert_coord
   real(r8), dimension(:),     pointer :: znu, dn, dnw, zs
   real(r8), dimension(:,:),   pointer :: mub, latitude, longitude, hgt
!   real(r8), dimension(:,:),   pointer :: mapfac_m, mapfac_u, mapfac_v
   real(r8), dimension(:,:,:), pointer :: phb

   integer :: number_of_wrf_variables
   integer, dimension(:,:), pointer :: var_index
   integer, dimension(:,:), pointer :: var_size
   integer, dimension(:),   pointer :: var_type
   integer, dimension(:),   pointer :: dart_kind
   integer, dimension(:,:), pointer :: land

   integer, dimension(:,:,:,:), pointer :: dart_ind

end type wrf_static_data_for_dart

type wrf_dom
   type(wrf_static_data_for_dart), pointer :: dom(:)
   integer :: model_size
end type wrf_dom

type(wrf_dom) :: wrf


contains

!#######################################################################

subroutine static_init_model()

! INitializes class data for WRF???

integer :: ncid
integer :: io, iunit

character (len=80)    :: name
character (len=1)     :: idom
logical, parameter    :: debug = .false.
integer               :: var_id, ind, i, j, k, id, dart_index, model_type

integer  :: proj_code
real(r8) :: stdlon,truelat1,truelat2,dt,latinc,loninc
character(len=129) :: errstring

!----------------------------------------------------------------------

! Register the module
call register_module(source, revision, revdate)

! Begin by reading the namelist input
call find_namelist_in_file("input.nml", "model_nml", iunit)
read(iunit, nml = model_nml, iostat = io)
call check_namelist_read(iunit, io, "model_nml")

! Record the namelist values used for the run ...
call error_handler(E_MSG,'static_init_model','model_nml values are',' ',' ',' ')
write(logfileunit, nml=model_nml)
write(     *     , nml=model_nml)

allocate(wrf%dom(num_domains))

wrf%dom(:)%n_moist = num_moist_vars

if( num_moist_vars > 7) then
   write(*,'(''num_moist_vars = '',i3)')num_moist_vars
   call error_handler(E_ERR,'static_init_model', &
        'num_moist_vars is too large.', source, revision,revdate)
endif

wrf%dom(:)%surf_obs = surf_obs
wrf%dom(:)%soil_data = soil_data

if ( debug ) then
   if ( output_state_vector ) then
      write(*,*)'netcdf file in state vector format'
   else
      write(*,*)'netcdf file in prognostic vector format'
   endif
endif

call set_calendar_type(calendar_type)

! Store vertical localization coordinate
! Only 3 are allowed: level(1), pressure(2), or height(3)
! Everything else is assumed height
if (vert_localization_coord == VERTISLEVEL) then
   wrf%dom(:)%vert_coord = VERTISLEVEL
elseif (vert_localization_coord == VERTISPRESSURE) then
   wrf%dom(:)%vert_coord = VERTISPRESSURE
elseif (vert_localization_coord == VERTISHEIGHT) then
   wrf%dom(:)%vert_coord = VERTISHEIGHT
else
   write(errstring,*)'vert_localization_coord must be one of ', &
                     VERTISLEVEL, VERTISPRESSURE, VERTISHEIGHT
   call error_handler(E_MSG,'static_init_model', errstring, source, revision,revdate)
   write(errstring,*)'vert_localization_coord is ', vert_localization_coord
   call error_handler(E_ERR,'static_init_model', errstring, source, revision,revdate)
endif

dart_index = 1

call read_dt_from_wrf_nml()

do id=1,num_domains

   write( idom , '(I1)') id

   write(*,*) '******************'
   write(*,*) '**  DOMAIN # ',idom,'  **'
   write(*,*) '******************'

   if(file_exist('wrfinput_d0'//idom)) then

      call check( nf90_open('wrfinput_d0'//idom, NF90_NOWRITE, ncid) )

   else

      call error_handler(E_ERR,'static_init_model', &
           'Please put wrfinput_d0'//idom//' in the work directory.', source, revision,revdate)

   endif

   if(debug) write(*,*) ' ncid is ',ncid

! get wrf grid dimensions

   call check( nf90_inq_dimid(ncid, "bottom_top", var_id) )
   call check( nf90_inquire_dimension(ncid, var_id, name, wrf%dom(id)%bt) )

   call check( nf90_inq_dimid(ncid, "bottom_top_stag", var_id) ) ! reuse var_id, no harm
   call check( nf90_inquire_dimension(ncid, var_id, name, wrf%dom(id)%bts) )

   call check( nf90_inq_dimid(ncid, "south_north", var_id) )
   call check( nf90_inquire_dimension(ncid, var_id, name, wrf%dom(id)%sn) )

   call check( nf90_inq_dimid(ncid, "south_north_stag", var_id)) ! reuse var_id, no harm
   call check( nf90_inquire_dimension(ncid, var_id, name, wrf%dom(id)%sns) )

   call check( nf90_inq_dimid(ncid, "west_east", var_id) )
   call check( nf90_inquire_dimension(ncid, var_id, name, wrf%dom(id)%we) )

   call check( nf90_inq_dimid(ncid, "west_east_stag", var_id) )  ! reuse var_id, no harm
   call check( nf90_inquire_dimension(ncid, var_id, name, wrf%dom(id)%wes) )

   call check( nf90_inq_dimid(ncid, "soil_layers_stag", var_id) )  ! reuse var_id, no harm
   call check( nf90_inquire_dimension(ncid, var_id, name, wrf%dom(id)%sls) )

   if(debug) then
      write(*,*) ' dimensions bt, sn, we are ',wrf%dom(id)%bt, &
           wrf%dom(id)%sn, wrf%dom(id)%we
      write(*,*) ' staggered  bt, sn, we are ',wrf%dom(id)%bts, &
           wrf%dom(id)%sns,wrf%dom(id)%wes
   endif

! get meta data and static data we need

   call check( nf90_get_att(ncid, nf90_global, 'DX', wrf%dom(id)%dx) )
   call check( nf90_get_att(ncid, nf90_global, 'DY', wrf%dom(id)%dy) )
   call check( nf90_get_att(ncid, nf90_global, 'DT', dt) )
   print*,'dt from wrfinput is: ',dt
   print*,'Using dt from namelist.input: ',wrf%dom(id)%dt
   if(debug) write(*,*) ' dx, dy, dt are ',wrf%dom(id)%dx, &
        wrf%dom(id)%dy, wrf%dom(id)%dt

   call check( nf90_get_att(ncid, nf90_global, 'MAP_PROJ', wrf%dom(id)%map_proj) )
   if(debug) write(*,*) ' map_proj is ',wrf%dom(id)%map_proj

   call check( nf90_get_att(ncid, nf90_global, 'CEN_LAT', wrf%dom(id)%cen_lat) )
   if(debug) write(*,*) ' cen_lat is ',wrf%dom(id)%cen_lat

   call check( nf90_get_att(ncid, nf90_global, 'CEN_LON', wrf%dom(id)%cen_lon) )
   if(debug) write(*,*) ' cen_lon is ',wrf%dom(id)%cen_lon

   call check( nf90_get_att(ncid, nf90_global, 'TRUELAT1', truelat1) )
   if(debug) write(*,*) ' truelat1 is ',truelat1

   call check( nf90_get_att(ncid, nf90_global, 'TRUELAT2', truelat2) )
   if(debug) write(*,*) ' truelat2 is ',truelat2

   call check( nf90_get_att(ncid, nf90_global, 'STAND_LON', stdlon) )
   if(debug) write(*,*) ' stdlon is ',stdlon


!nc -- fill in the boundary conditions (periodic_x and polar) here.  This will
!        need to be changed once these are taken from the NetCDF input instead
!        of the model namelist
!      NOTE :: because NetCDF cannot handle logicals, these boundary conditions
!        are likely to be read in as integers.  The agreed upon strategy is to 
!        test whether the integers are equal to 0 (for .false.) or 1 (for .true.)
!        and set the wrf%dom(id)% values to logicals to be used internally within
!        model_mod.f90.
!
!      Jeff Anderson points out that not everyone will convert to wrf3.0 and this
!        global attribute convention may not be backward-compatible.  So we should
!        test for existence of attributes and have defaults (from model_mod 
!        namelist) ready if they do not exist.  Note that defaults are currently 
!        true (as of 24 Oct 2007), but once the attributes arrive, the defaults
!        should be false.
   if ( id == 1 ) then
      wrf%dom(id)%periodic_x = periodic_x
      wrf%dom(id)%polar = polar
   else
      wrf%dom(id)%periodic_x = .false.
      wrf%dom(id)%polar = .false.      
   end if
   if(debug) write(*,*) ' periodic_x ',wrf%dom(id)%periodic_x
   if(debug) write(*,*) ' polar ',wrf%dom(id)%polar


   call check( nf90_inq_varid(ncid, "P_TOP", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%p_top) )

!  get 1D (z) static data defining grid levels

   allocate(wrf%dom(id)%dn(1:wrf%dom(id)%bt))
   call check( nf90_inq_varid(ncid, "DN", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%dn) )
   if(debug) write(*,*) ' dn ',wrf%dom(id)%dn

   allocate(wrf%dom(id)%znu(1:wrf%dom(id)%bt))
   call check( nf90_inq_varid(ncid, "ZNU", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%znu) )
   if(debug) write(*,*) ' znu is ',wrf%dom(id)%znu

   allocate(wrf%dom(id)%dnw(1:wrf%dom(id)%bt))
   call check( nf90_inq_varid(ncid, "DNW", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%dnw) )
   if(debug) write(*,*) ' dnw is ',wrf%dom(id)%dnw

   allocate(wrf%dom(id)%zs(1:wrf%dom(id)%sls))
   call check( nf90_inq_varid(ncid, "ZS", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%zs) )

!  get 2D (x,y) base state for mu, latitude, longitude

   allocate(wrf%dom(id)%mub(1:wrf%dom(id)%we,1:wrf%dom(id)%sn))
   call check( nf90_inq_varid(ncid, "MUB", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%mub) )
   if(debug) then
      write(*,*) ' corners of mub '
      write(*,*) wrf%dom(id)%mub(1,1),wrf%dom(id)%mub(wrf%dom(id)%we,1),  &
           wrf%dom(id)%mub(1,wrf%dom(id)%sn),wrf%dom(id)%mub(wrf%dom(id)%we, &
           wrf%dom(id)%sn)
   end if

   allocate(wrf%dom(id)%longitude(1:wrf%dom(id)%we,1:wrf%dom(id)%sn))
   call check( nf90_inq_varid(ncid, "XLONG", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%longitude) )

   allocate(wrf%dom(id)%latitude(1:wrf%dom(id)%we,1:wrf%dom(id)%sn))
   call check( nf90_inq_varid(ncid, "XLAT", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%latitude) )

   allocate(wrf%dom(id)%land(1:wrf%dom(id)%we,1:wrf%dom(id)%sn))
   call check( nf90_inq_varid(ncid, "XLAND", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%land) )
   if(debug) then
      write(*,*) ' corners of land '
      write(*,*) wrf%dom(id)%land(1,1),wrf%dom(id)%land(wrf%dom(id)%we,1),  &
           wrf%dom(id)%land(1,wrf%dom(id)%sn),wrf%dom(id)%land(wrf%dom(id)%we, &
           wrf%dom(id)%sn)
   end if

   if(debug) then
      write(*,*) ' corners of lat '
      write(*,*) wrf%dom(id)%latitude(1,1),wrf%dom(id)%latitude(wrf%dom(id)%we,1),  &
           wrf%dom(id)%latitude(1,wrf%dom(id)%sn), &
           wrf%dom(id)%latitude(wrf%dom(id)%we,wrf%dom(id)%sn)
      write(*,*) ' corners of long '
      write(*,*) wrf%dom(id)%longitude(1,1),wrf%dom(id)%longitude(wrf%dom(id)%we,1),  &
           wrf%dom(id)%longitude(1,wrf%dom(id)%sn), &
           wrf%dom(id)%longitude(wrf%dom(id)%we,wrf%dom(id)%sn)
   end if

!nc -- eliminated the reading in of MAPFACs since global WRF will have different 
!nc --   MAPFACs in the x and y directions

!   allocate(wrf%dom(id)%mapfac_m(1:wrf%dom(id)%we,1:wrf%dom(id)%sn))
!   call check( nf90_inq_varid(ncid, "MAPFAC_M", var_id) )
!   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%mapfac_m) )

   allocate(wrf%dom(id)%hgt(1:wrf%dom(id)%we,1:wrf%dom(id)%sn))
   call check( nf90_inq_varid(ncid, "HGT", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%hgt) )

!   allocate(wrf%dom(id)%mapfac_u(1:wrf%dom(id)%wes,1:wrf%dom(id)%sn))
!   call check( nf90_inq_varid(ncid, "MAPFAC_U", var_id) )
!   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%mapfac_u) )

!   allocate(wrf%dom(id)%mapfac_v(1:wrf%dom(id)%we,1:wrf%dom(id)%sns))
!   call check( nf90_inq_varid(ncid, "MAPFAC_V", var_id) )
!   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%mapfac_v) )

! get 3D base state geopotential

   allocate(wrf%dom(id)%phb(1:wrf%dom(id)%we,1:wrf%dom(id)%sn,1:wrf%dom(id)%bts))
   call check( nf90_inq_varid(ncid, "PHB", var_id) )
   call check( nf90_get_var(ncid, var_id, wrf%dom(id)%phb) )
   if(debug) then
      write(*,*) ' corners of phb '
      write(*,*) wrf%dom(id)%phb(1,1,1),wrf%dom(id)%phb(wrf%dom(id)%we,1,1),  &
           wrf%dom(id)%phb(1,wrf%dom(id)%sn,1),wrf%dom(id)%phb(wrf%dom(id)%we, &
           wrf%dom(id)%sn,1)
      write(*,*) wrf%dom(id)%phb(1,1,wrf%dom(id)%bts), &
           wrf%dom(id)%phb(wrf%dom(id)%we,1,wrf%dom(id)%bts),  &
           wrf%dom(id)%phb(1,wrf%dom(id)%sn,wrf%dom(id)%bts), &
           wrf%dom(id)%phb(wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bts)
   end if

! close data file, we have all we need

   call check( nf90_close(ncid) )

! Initializes the map projection structure to missing values

   call map_init(wrf%dom(id)%proj)

! Populate the map projection structure

!nc -- added in case structures for CASSINI and CYL
!nc -- global wrfinput_d01 has truelat1 = 1.e20, so we need to change it where needed
!nc -- for PROJ_LATLON stdlon and truelat1 have different meanings -- 
!nc --   stdlon --> loninc  and  truelat1 --> latinc
   latinc = 180.0_r8/wrf%dom(id)%sn
   loninc = 360.0_r8/wrf%dom(id)%we

   if(wrf%dom(id)%map_proj == map_sphere) then
      truelat1 = latinc
      stdlon = loninc
      proj_code = PROJ_LATLON
   elseif(wrf%dom(id)%map_proj == map_lambert) then
      proj_code = PROJ_LC
   elseif(wrf%dom(id)%map_proj == map_polar_stereo) then
      proj_code = PROJ_PS
   elseif(wrf%dom(id)%map_proj == map_mercator) then
      proj_code = PROJ_MERC
   elseif(wrf%dom(id)%map_proj == map_cyl) then
      proj_code = PROJ_CYL
   elseif(wrf%dom(id)%map_proj == map_cassini) then
      proj_code = PROJ_CASSINI
   else
      call error_handler(E_ERR,'static_init_model', &
        'Map projection no supported.', source, revision, revdate)
   endif

!nc -- new version of module_map_utils has optional arguments.  PROJ_CASSINI is the
!        map projection we are dealing with.  According to map_set, the required 
!        inputs are:
!          latinc, loninc, lat1, lon1, knowni, knownj, lat0, lon0, stdlon
!      Hence, we will need a dummy dx (or so it seems)
!
! OLD version -- all arguments required
!  SUBROUTINE map_set(proj_code,lat1,lon1,knowni,knownj,dx,stdlon,truelat1,truelat2,proj)
!
! NEW version -- all arguments optional after "proj"
!  SUBROUTINE map_set(proj_code, proj, lat1, lon1, lat0, lon0, knowni, knownj, dx, latinc, &
!                      loninc, stdlon, truelat1, truelat2, nlat, nlon, ixdim, jydim, &
!                      stagger, phi, lambda, r_earth)
!
!   call map_set(proj_code,wrf%dom(id)%latitude(1,1),wrf%dom(id)%longitude(1,1), &
!        1.0_r8,1.0_r8,wrf%dom(id)%dx,stdlon,truelat1,truelat2,wrf%dom(id)%proj)

!nc -- sufficiently specified inputs for PROJ_CASSINI, however, insufficient for other
!        map projections (see below for more general)
!   call map_set( proj_code=proj_code, &
!                 proj=wrf%dom(id)%proj, &
!                 lat1=wrf%dom(id)%latitude(1,1), &
!                 lon1=wrf%dom(id)%longitude(1,1), &
!                 lat0=90.0_r8, &
!                 lon0=0.0_r8, &
!                 knowni=1.0_r8, &
!                 knownj=1.0_r8, &
!                 latinc=latinc, &
!                 loninc=loninc, &
!                 stdlon=stdlon )

!nc -- specified inputs to hopefully handle ALL map projections -- hopefully map_set will
!        just ignore the inputs it doesn't need for its map projection of interest (?)
!     
!   NOTE:: We are NOT yet supporting the Gaussian grid or the Rotated Lat/Lon, so we
!            are going to skip the entries:  nlon, nlat, ixdim, jydim, stagger, phi, lambda
!
!      + Gaussian grid uses nlat & nlon
!      + Rotated Lat/Lon uses ixdim, jydim, stagger, phi, & lambda
!
   call map_set( proj_code=proj_code, &
                 proj=wrf%dom(id)%proj, &
                 lat1=wrf%dom(id)%latitude(1,1), &
                 lon1=wrf%dom(id)%longitude(1,1), &
                 lat0=90.0_r8, &
                 lon0=0.0_r8, &
                 knowni=1.0_r8, &
                 knownj=1.0_r8, &
                 dx=wrf%dom(id)%dx, &
                 latinc=latinc, &
                 loninc=loninc, &
                 stdlon=stdlon, &
                 truelat1=truelat1, &
                 truelat2=truelat2  )


!  build the map into the 1D DART vector for WRF data

   wrf%dom(id)%number_of_wrf_variables = 7 + wrf%dom(id)%n_moist
   if( wrf%dom(id)%surf_obs ) then
      wrf%dom(id)%number_of_wrf_variables = wrf%dom(id)%number_of_wrf_variables + 6
   endif
   if( wrf%dom(id)%soil_data ) then
      wrf%dom(id)%number_of_wrf_variables = wrf%dom(id)%number_of_wrf_variables + 3
   endif
   if( h_diab ) then
      wrf%dom(id)%number_of_wrf_variables = wrf%dom(id)%number_of_wrf_variables + 1
   endif
   allocate(wrf%dom(id)%var_type(wrf%dom(id)%number_of_wrf_variables))

   allocate(wrf%dom(id)%dart_kind(wrf%dom(id)%number_of_wrf_variables))
   wrf%dom(id)%var_type(1)  = TYPE_U
   wrf%dom(id)%dart_kind(1) = KIND_U_WIND_COMPONENT
   wrf%dom(id)%var_type(2)  = TYPE_V
   wrf%dom(id)%dart_kind(2) = KIND_V_WIND_COMPONENT
   wrf%dom(id)%var_type(3)  = TYPE_W
   wrf%dom(id)%dart_kind(3) = KIND_VERTICAL_VELOCITY
   wrf%dom(id)%var_type(4)  = TYPE_GZ
   wrf%dom(id)%dart_kind(4) = KIND_GEOPOTENTIAL_HEIGHT
   wrf%dom(id)%var_type(5)  = TYPE_T
   wrf%dom(id)%dart_kind(5) = KIND_TEMPERATURE
   wrf%dom(id)%var_type(6)  = TYPE_MU
   wrf%dom(id)%dart_kind(6) = KIND_PRESSURE
   wrf%dom(id)%var_type(7)  = TYPE_TSK
   wrf%dom(id)%dart_kind(7) = KIND_TEMPERATURE

   ind = 7
   if( wrf%dom(id)%n_moist >= 1) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind)  = TYPE_QV
      wrf%dom(id)%dart_kind(ind) = KIND_VAPOR_MIXING_RATIO
   end if
   if( wrf%dom(id)%n_moist >= 2) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind)  = TYPE_QC
      wrf%dom(id)%dart_kind(ind) = KIND_CLOUD_LIQUID_WATER
   end if
   if( wrf%dom(id)%n_moist >= 3) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_QR
      wrf%dom(id)%dart_kind(ind) = KIND_RAINWATER_MIXING_RATIO
   end if
   if( wrf%dom(id)%n_moist >= 4) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_QI
      wrf%dom(id)%dart_kind(ind) = KIND_CLOUD_ICE
   end if
   if( wrf%dom(id)%n_moist >= 5) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_QS
      wrf%dom(id)%dart_kind(ind) = KIND_SNOW_MIXING_RATIO
   end if
   if( wrf%dom(id)%n_moist >= 6) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_QG
      wrf%dom(id)%dart_kind(ind) = KIND_GRAUPEL_MIXING_RATIO
   end if
   if( wrf%dom(id)%n_moist == 7) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_QNICE
      wrf%dom(id)%dart_kind(ind) = KIND_ICE_NUMBER_CONCENTRATION
   end if
   if( wrf%dom(id)%surf_obs ) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_U10
      wrf%dom(id)%dart_kind(ind) = KIND_U_WIND_COMPONENT
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_V10
      wrf%dom(id)%dart_kind(ind) = KIND_V_WIND_COMPONENT
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_T2
      wrf%dom(id)%dart_kind(ind) = KIND_TEMPERATURE
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_TH2
      wrf%dom(id)%dart_kind(ind) = KIND_POTENTIAL_TEMPERATURE
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_Q2
      wrf%dom(id)%dart_kind(ind) = KIND_SPECIFIC_HUMIDITY
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_PS
      wrf%dom(id)%dart_kind(ind) = KIND_PRESSURE
   end if
   if( wrf%dom(id)%soil_data ) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind)  = TYPE_TSLB
      wrf%dom(id)%dart_kind(ind) = KIND_TEMPERATURE
      ind = ind + 1
      wrf%dom(id)%var_type(ind)  = TYPE_SMOIS
      wrf%dom(id)%dart_kind(ind) = KIND_SOIL_MOISTURE
      ind = ind + 1
      wrf%dom(id)%var_type(ind)  = TYPE_SH2O
      wrf%dom(id)%dart_kind(ind) = KIND_SOIL_MOISTURE
   end if
   if( h_diab ) then
      ind = ind + 1
      wrf%dom(id)%var_type(ind) = TYPE_HDIAB
      wrf%dom(id)%dart_kind(ind) = KIND_CONDENSATIONAL_HEATING
   end if

! indices into 1D array
   allocate(wrf%dom(id)%dart_ind(wrf%dom(id)%wes,wrf%dom(id)%sns,wrf%dom(id)%bts,num_model_var_types))
   allocate(wrf%dom(id)%var_index(2,wrf%dom(id)%number_of_wrf_variables))
! dimension of variables
   allocate(wrf%dom(id)%var_size(3,wrf%dom(id)%number_of_wrf_variables))

   wrf%dom(id)%dart_ind = 0

   ind = 1                         ! *** u field ***
   wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%wes
   wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
   wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%bt
   wrf%dom(id)%var_index(1,ind) = dart_index
   do k=1,wrf%dom(id)%var_size(3,ind)
      do j=1,wrf%dom(id)%var_size(2,ind)
         do i=1,wrf%dom(id)%var_size(1,ind)
            wrf%dom(id)%dart_ind(i,j,k,TYPE_U) = dart_index
            dart_index = dart_index + 1
         enddo
      enddo
   enddo
   wrf%dom(id)%var_index(2,ind) = dart_index - 1

   ind = ind + 1                   ! *** v field ***
   wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
   wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sns
   wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%bt
   wrf%dom(id)%var_index(1,ind) = dart_index
   do k=1,wrf%dom(id)%var_size(3,ind)
      do j=1,wrf%dom(id)%var_size(2,ind)
         do i=1,wrf%dom(id)%var_size(1,ind)
            wrf%dom(id)%dart_ind(i,j,k,TYPE_V) = dart_index
            dart_index = dart_index + 1
         enddo
      enddo
   enddo
   wrf%dom(id)%var_index(2,ind) = dart_index - 1

   ind = ind + 1                   ! *** w field ***
   wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
   wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
   wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%bts
   wrf%dom(id)%var_index(1,ind) = dart_index
   do k=1,wrf%dom(id)%var_size(3,ind)
      do j=1,wrf%dom(id)%var_size(2,ind)
         do i=1,wrf%dom(id)%var_size(1,ind)
            wrf%dom(id)%dart_ind(i,j,k,TYPE_W) = dart_index
            dart_index = dart_index + 1
         enddo
      enddo
   enddo
   wrf%dom(id)%var_index(2,ind) = dart_index - 1

   ind = ind + 1                   ! *** geopotential field ***
   wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
   wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
   wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%bts
   wrf%dom(id)%var_index(1,ind) = dart_index
   do k=1,wrf%dom(id)%var_size(3,ind)
      do j=1,wrf%dom(id)%var_size(2,ind)
         do i=1,wrf%dom(id)%var_size(1,ind)
            wrf%dom(id)%dart_ind(i,j,k,TYPE_GZ) = dart_index
            dart_index = dart_index + 1
         enddo
      enddo
   enddo
   wrf%dom(id)%var_index(2,ind) = dart_index - 1

   ind = ind + 1                   ! *** theta field ***
   wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
   wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
   wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%bt
   wrf%dom(id)%var_index(1,ind) = dart_index
   do k=1,wrf%dom(id)%var_size(3,ind)
      do j=1,wrf%dom(id)%var_size(2,ind)
         do i=1,wrf%dom(id)%var_size(1,ind)
            wrf%dom(id)%dart_ind(i,j,k,TYPE_T) = dart_index
            dart_index = dart_index + 1
         enddo
      enddo
   enddo
   wrf%dom(id)%var_index(2,ind) = dart_index - 1

   ind = ind + 1                   ! *** mu field ***
   wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
   wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
   wrf%dom(id)%var_size(3,ind) = 1
   wrf%dom(id)%var_index(1,ind) = dart_index
   do k=1,wrf%dom(id)%var_size(3,ind)
      do j=1,wrf%dom(id)%var_size(2,ind)
         do i=1,wrf%dom(id)%var_size(1,ind)
            wrf%dom(id)%dart_ind(i,j,k,TYPE_MU) = dart_index
            dart_index = dart_index + 1
         enddo
      enddo
   enddo
   wrf%dom(id)%var_index(2,ind) = dart_index - 1

   ind = ind + 1                   ! *** tsk field ***
   wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
   wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
   wrf%dom(id)%var_size(3,ind) = 1
   wrf%dom(id)%var_index(1,ind) = dart_index
   do k=1,wrf%dom(id)%var_size(3,ind)
      do j=1,wrf%dom(id)%var_size(2,ind)
         do i=1,wrf%dom(id)%var_size(1,ind)
            wrf%dom(id)%dart_ind(i,j,k,TYPE_TSK) = dart_index
            dart_index = dart_index + 1
         enddo
      enddo
   enddo
   wrf%dom(id)%var_index(2,ind) = dart_index - 1

   do model_type = TYPE_QV, TYPE_QV + wrf%dom(id)%n_moist - 1
      ind = ind + 1                   ! *** moisture field ***
      wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
      wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
      wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%bt
      wrf%dom(id)%var_index(1,ind) = dart_index
      do k=1,wrf%dom(id)%var_size(3,ind)
         do j=1,wrf%dom(id)%var_size(2,ind)
            do i=1,wrf%dom(id)%var_size(1,ind)
               wrf%dom(id)%dart_ind(i,j,k,model_type) = dart_index
               dart_index = dart_index + 1
            enddo
         enddo
      enddo
      wrf%dom(id)%var_index(2,ind) = dart_index - 1
   enddo

   if(wrf%dom(id)%surf_obs ) then
      do model_type = TYPE_U10, TYPE_PS
         ind = ind + 1                   ! *** Surface variable ***
         wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
         wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
         wrf%dom(id)%var_size(3,ind) = 1
         wrf%dom(id)%var_index(1,ind) = dart_index
         do k=1,wrf%dom(id)%var_size(3,ind)
            do j=1,wrf%dom(id)%var_size(2,ind)
               do i=1,wrf%dom(id)%var_size(1,ind)
                  wrf%dom(id)%dart_ind(i,j,k,model_type) = dart_index
                  dart_index = dart_index + 1
               enddo
            enddo
         enddo
         wrf%dom(id)%var_index(2,ind) = dart_index - 1
      enddo
   end if

   if(wrf%dom(id)%soil_data ) then
      ind = ind + 1                   ! *** tslb field ***
      wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
      wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
      wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%sls
      wrf%dom(id)%var_index(1,ind) = dart_index
      do k=1,wrf%dom(id)%var_size(3,ind)
         do j=1,wrf%dom(id)%var_size(2,ind)
            do i=1,wrf%dom(id)%var_size(1,ind)
               wrf%dom(id)%dart_ind(i,j,k,TYPE_TSLB) = dart_index
               dart_index = dart_index + 1
            enddo
         enddo
      enddo
      wrf%dom(id)%var_index(2,ind) = dart_index - 1

      ind = ind + 1                   ! *** smois field ***
      wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
      wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
      wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%sls
      wrf%dom(id)%var_index(1,ind) = dart_index
      do k=1,wrf%dom(id)%var_size(3,ind)
         do j=1,wrf%dom(id)%var_size(2,ind)
            do i=1,wrf%dom(id)%var_size(1,ind)
               wrf%dom(id)%dart_ind(i,j,k,TYPE_SMOIS) = dart_index
               dart_index = dart_index + 1
            enddo
         enddo
      enddo
      wrf%dom(id)%var_index(2,ind) = dart_index - 1  
      
      ind = ind + 1                   ! *** sh2o field ***
      wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
      wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
      wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%sls
      wrf%dom(id)%var_index(1,ind) = dart_index
      do k=1,wrf%dom(id)%var_size(3,ind)
         do j=1,wrf%dom(id)%var_size(2,ind)
            do i=1,wrf%dom(id)%var_size(1,ind)
               wrf%dom(id)%dart_ind(i,j,k,TYPE_SH2O) = dart_index
               dart_index = dart_index + 1
            enddo
         enddo
      enddo
      wrf%dom(id)%var_index(2,ind) = dart_index - 1  
   end if

   if(h_diab ) then
      ind = ind + 1                   ! *** h_diabatic variable ***
      wrf%dom(id)%var_size(1,ind) = wrf%dom(id)%we
      wrf%dom(id)%var_size(2,ind) = wrf%dom(id)%sn
      wrf%dom(id)%var_size(3,ind) = wrf%dom(id)%bt
      wrf%dom(id)%var_index(1,ind) = dart_index
      do k=1,wrf%dom(id)%var_size(3,ind)
         do j=1,wrf%dom(id)%var_size(2,ind)
            do i=1,wrf%dom(id)%var_size(1,ind)
               wrf%dom(id)%dart_ind(i,j,k,TYPE_HDIAB) = dart_index
               dart_index = dart_index + 1
            enddo
         enddo
      enddo
      wrf%dom(id)%var_index(2,ind) = dart_index - 1
   end if

enddo

write(*,*)

wrf%model_size = dart_index - 1
allocate (ens_mean(wrf%model_size))
if(debug) write(*,*) ' wrf model size is ',wrf%model_size

contains

  ! Internal subroutine - checks error status after each netcdf, prints
  !                       text message each time an error code is returned.
  subroutine check(istatus)
    integer, intent (in) :: istatus

    if(istatus /= nf90_noerr) call error_handler(E_ERR, 'static_init_model', &
       trim(nf90_strerror(istatus)), source, revision, revdate)

  end subroutine check

end subroutine static_init_model


!#######################################################################

function get_model_size()

integer :: get_model_size

get_model_size = wrf%model_size

end function get_model_size

!#######################################################################

function get_number_domains()

integer :: get_number_domains

get_number_domains = num_domains

end function get_number_domains

!#######################################################################

subroutine get_state_size(id, we, sn, bt, sls)

integer, intent(in)  :: id
integer, intent(out) :: we, sn, bt, sls

we  = wrf%dom(id)%we
sn  = wrf%dom(id)%sn
bt  = wrf%dom(id)%bt
sls = wrf%dom(id)%sls

return
end subroutine get_state_size

!#######################################################################

subroutine get_state_components(id, n_moist, surf_obs, soil_data, h_db)

integer, intent(in)  :: id
integer, intent(out) :: n_moist
logical, intent(out) :: surf_obs, soil_data, h_db

n_moist   = wrf%dom(id)%n_moist
surf_obs  = wrf%dom(id)%surf_obs
soil_data = wrf%dom(id)%soil_data
h_db      = h_diab

return
end subroutine get_state_components

!#######################################################################

function get_model_time_step()
!------------------------------------------------------------------------
! function get_model_time_step()
!
! Returns the time step of the model. In the long run should be replaced
! by a more general routine that returns details of a general time-stepping
! capability.
!
! toward that end ... we are now reading a namelist variable for the
! width of the assimilation time window.

type(time_type) :: get_model_time_step
integer :: model_dt, assim_dt

! We need to coordinate the desired assimilation window to be a 
! multiple of the model time step (which has no precision past integer seconds).

model_dt = nint(wrf%dom(1)%dt)

! The integer arithmetic does its magic.
assim_dt = (assimilation_period_seconds / model_dt) * model_dt

get_model_time_step = set_time(assim_dt)

end function get_model_time_step


!#######################################################################


subroutine get_state_meta_data(index_in, location, var_type_out, id_out)

! Given an integer index into the DART state vector structure, returns the
! associated location. This is not a function because the more general
! form of the call has a second intent(out) optional argument kind.
! Maybe a functional form should be added?

integer,             intent(in)  :: index_in
type(location_type), intent(out) :: location
integer, optional,   intent(out) :: var_type_out, id_out

integer  :: var_type, dart_type
integer  :: index, ip, jp, kp
integer  :: nz, ny, nx
logical  :: var_found
real(r8) :: lon, lat, lev

integer :: i, id
logical, parameter :: debug = .false.
character(len=129) :: errstring

if(debug) then
   write(errstring,*)' index_in = ',index_in
   call error_handler(E_MSG,'get_state_meta_data',errstring,' ',' ',' ')
endif

! index_in can be negative if ob is identity ob...
index = abs(index_in)

var_found = .false.

!  first find var_type

if(debug) then
   do id=1,num_domains
      do i=1, wrf%dom(id)%number_of_wrf_variables
         write(errstring,*)' domain, var, var_type(i) = ',id,i,wrf%dom(id)%var_type(i)
         call error_handler(E_MSG,'get_state_meta_data',errstring,' ',' ',' ')
      enddo
   enddo
endif

! first find var_type and domain id
i = 0
id = 1
do while (.not. var_found)
   i = i + 1
   if(i .gt. wrf%dom(id)%number_of_wrf_variables) then
      i = 1
      if (id < num_domains) then
         id = id + 1
      else
         write(errstring,*)' size of vector ',wrf%model_size
         call error_handler(E_MSG,'get_state_meta_data', errstring, ' ', ' ', ' ')
         write(errstring,*)' dart_index ',index_in
         call error_handler(E_ERR,'get_state_meta_data', 'index out of range', &
              source, revision, revdate)
      end if
   end if
   if( (index .ge. wrf%dom(id)%var_index(1,i) ) .and.  &
       (index .le. wrf%dom(id)%var_index(2,i) )       )  then
      var_found = .true.
      var_type  = wrf%dom(id)%var_type(i)
      dart_type = wrf%dom(id)%dart_kind(i)
      index = index - wrf%dom(id)%var_index(1,i) + 1
   end if
end do

!  now find i,j,k location.
!  index has been normalized such that it is relative to
!  array starting at (1,1,1)

nx = wrf%dom(id)%var_size(1,i)
ny = wrf%dom(id)%var_size(2,i)
nz = wrf%dom(id)%var_size(3,i)

kp = 1 + (index-1)/(nx*ny)
jp = 1 + (index - (kp-1)*nx*ny - 1)/nx
ip = index - (kp-1)*nx*ny - (jp-1)*nx

! at this point, (ip,jp,kp) refer to indices in the variable's own grid

if(debug) write(*,*) ' ip, jp, kp for index ',ip,jp,kp,index
if(debug) write(*,*) ' Var type: ',var_type

! first obtain lat/lon from (ip,jp)
call get_wrf_horizontal_location( ip, jp, var_type, id, lon, lat )

! now convert to desired vertical coordinate (defined in the namelist)
if (wrf%dom(id)%vert_coord == VERTISLEVEL) then
   ! here we need level index of mass grid
   if( (var_type == type_w ) .or. (var_type == type_gz) ) then
      lev = real(kp) - 0.5_r8
   else
      lev = real(kp)
   endif
elseif (wrf%dom(id)%vert_coord == VERTISPRESSURE) then
   ! directly convert to pressure
   lev = model_pressure(ip,jp,kp,id,var_type,ens_mean)
elseif (wrf%dom(id)%vert_coord == VERTISHEIGHT) then
   lev = model_height(ip,jp,kp,id,var_type,ens_mean)
endif

if(debug) write(*,*) 'lon, lat, lev: ',lon, lat, lev

! convert to DART location type
location = set_location(lon, lat, lev, wrf%dom(id)%vert_coord)

! return DART variable kind if requested
if(present(var_type_out)) var_type_out = dart_type

! return domain id if requested
if(present(id_out)) id_out = id

end subroutine get_state_meta_data


!#######################################################################

subroutine model_interpolate(x, location, obs_kind, obs_val, istatus)

! This is the main forward operator subroutine for WRF.
! Given an ob (its DART location and kind), the corresponding model
! value is computed at nearest i,j,k. Thus, first i,j,k is obtained
! from ob lon,lat,z and then the state value that corresponds to
! the ob kind is interpolated.

! No location conversions are carried out in this subroutine. See
! get_close_obs, where ob vertical location information is converted
! to the requested vertical coordinate type.

! x:       Full DART state vector relevant to what's being updated
!          in the filter (mean or individual members).
! istatus: Returned 0 if everything is OK, 1 if error occured.
!                  -1 if the station height is lower than the lowest model level 
!                     while the station is located inside the horizontal model domain.

! modified 26 June 2006 to accomodate vortex attributes
! modified 13 December 2006 to accomodate changes for the mpi version
! modified 22 October 2007 to accomodate global WRF (3.0)

! arguments
real(r8),            intent(in) :: x(:)
type(location_type), intent(in) :: location
integer,             intent(in) :: obs_kind
real(r8),           intent(out) :: obs_val
integer,            intent(out) :: istatus

! local
logical, parameter  :: debug = .false.
logical, parameter  :: restrict_polar = .false.
!logical, parameter  :: restrict_polar = .true.
real(r8)            :: xloc, yloc, zloc, xloc_u, yloc_v, xyz_loc(3)
integer             :: i, i_u, j, j_v, k, k2
real(r8)            :: dx,dy,dz,dxm,dym,dzm,dx_u,dxm_u,dy_v,dym_v
real(r8)            :: a1,utrue,vtrue,ugrid,vgrid
integer             :: id
logical             :: surf_var


! from getCorners
integer, dimension(2) :: ll, lr, ul, ur, ll_v, lr_v, ul_v, ur_v
integer            :: rc, ill, ilr, iul, iur, i1, i2

character(len=129) :: errstring

real(r8), dimension(2) :: fld
real(r8), allocatable, dimension(:) :: v_h, v_p

! local vars, used in finding sea-level pressure and vortex center
real(r8), allocatable, dimension(:)   :: t1d, p1d, qv1d, z1d
real(r8), allocatable, dimension(:,:) :: psea, pp, pd
real(r8), allocatable, dimension(:)   :: x1d,y1d,xx1d,yy1d
integer  :: xlen, ylen, xxlen, yylen, ii1, ii2
real(r8) :: clat, clon, cxmin, cymin

! center_track_*** used to define center search area
integer :: center_track_xmin, center_track_ymin, &
           center_track_xmax, center_track_ymax

! local vars, used in calculating density, pressure, height
real(r8)            :: rho1 , rho2 , rho3, rho4
real(r8)            :: pres1, pres2, pres3, pres4, pres


! Initialize stuff
istatus = 0
fld(:) = missing_r8
obs_val = missing_r8


! If identity observation (obs_kind < 0), then no need to interpolate
if ( obs_kind < 0 ) then

   ! identity observation -> -(obs_kind)=DART state vector index
   ! obtain state value directly from index
   obs_val = x(-1*obs_kind)
 
! Otherwise, we need to do interpolation
else

   ! Unravel location_type information
   xyz_loc = get_location(location)

   !----------------------------------
   ! 0. Prelude to Interpolation
   !----------------------------------
   
   ! 0.a Horizontal stuff

   ! first obtain domain id, and mass points (i,j)
   call get_domain_info(xyz_loc(1),xyz_loc(2),id,xloc,yloc)
    
   ! check that we obtained a valid domain id number
   if (id==0) then
      istatus = 1
      return
   endif
   
   !*****************************************************************************
   ! Check polar-b.c. constraints -- if restrict_polar = .true., then we are not 
   !   processing observations poleward of the 1st or last mass grid points.
   ! If we have tried to pass a polar observation, then exit with istatus = 10
   if ( wrf%dom(id)%polar .and. restrict_polar ) then
      if ( yloc < 1.0_r8 .or. yloc >= real(wrf%dom(id)%sn,r8) ) then

         ! Perhaps write to dart_log.out?
         write(errstring,*)'Obs cannot be polar with restrict_polar on: yloc = ',yloc
         call error_handler(E_WARN,'model_interpolate', errstring, &
              source, revision, revdate)

         istatus = 10  ! istatus 10, if it's not used, will mean the observation is too polar
         print*, 'model_mod.f90 :: model_interpolate :: No polar observations!  istatus = ', istatus
         return
      end if
   end if
   !*****************************************************************************
   
   ! print info if debugging
   if(debug) then
      i = xloc
      j = yloc
      print*,xyz_loc(2), xyz_loc(1), xloc,yloc
      write(*,*) ' corners of lat '
      write(*,*) wrf%dom(id)%latitude(i,j),wrf%dom(id)%latitude(i+1,j),  &
           wrf%dom(id)%latitude(i,j+1), &
           wrf%dom(id)%latitude(i+1,j+1)
      write(*,*) ' corners of long '
      write(*,*) wrf%dom(id)%longitude(i,j),wrf%dom(id)%longitude(i+1,j),  &
           wrf%dom(id)%longitude(i,j+1), &
           wrf%dom(id)%longitude(i+1,j+1)
   endif
   
   ! get integer (west/south) grid point and distances to neighboring grid points
   ! distances are used as weights to carry out horizontal interpolations
   call toGrid(xloc,i,dx,dxm)
   call toGrid(yloc,j,dy,dym)
   

   ! 0.b Vertical stuff

   ! Allocate both a vertical height and vertical pressure coordinate -- 0:bt
   allocate(v_h(0:wrf%dom(id)%bt), v_p(0:wrf%dom(id)%bt))

   ! Set surf_var to .false. and then change in vert_is_surface section if necessary
   surf_var = .false.

   ! Determine corresponding model level for obs location
   ! This depends on the obs vertical coordinate
   !   From this we get a meaningful z-direction real-valued index number
   if(vert_is_level(location)) then
      ! Ob is by model level
      zloc = xyz_loc(3)

   elseif(vert_is_pressure(location)) then
      ! Ob is by pressure: get corresponding mass level zloc from
      ! computed column pressure profile
      call get_model_pressure_profile(i,j,dx,dy,dxm,dym,wrf%dom(id)%bt,x,id,v_p)
      ! get pressure vertical co-ordinate
      call pres_to_zk(xyz_loc(3), v_p, wrf%dom(id)%bt,zloc)
      if(debug .and. obs_kind /= KIND_SURFACE_PRESSURE) &
                print*,' obs is by pressure and zloc =',zloc
      if(debug) print*,'model pressure profile'
      if(debug) print*,v_p
      
      !nc -- If location is below model terrain (and therefore has a missing_r8 value), 
      !        then push its location back to the level of model terrain.  This is only
      !        permitted if the user has set the logical parameter allow_obs_below_surf to
      !        be .true. (its default is .false.).
      if ( allow_obs_below_surf ) then
         if ( zloc == missing_r8 .and. xyz_loc(3) > v_p(0) ) then
            zloc = 1.0_r8         ! Higher pressure than p_surf (lower than model terrain)
            surf_var = .true.     ! Estimate U,V,T,and Q from the model sfc states.
         end if
      end if
         
   elseif(vert_is_height(location)) then
      ! Ob is by height: get corresponding mass level zloc from
      ! computed column height profile
      call get_model_height_profile(i,j,dx,dy,dxm,dym,wrf%dom(id)%bt,x,id,v_h)
      ! get height vertical co-ordinate
      call height_to_zk(xyz_loc(3), v_h, wrf%dom(id)%bt,zloc)
      if(debug) print*,' obs is by height and zloc =',zloc
      if(debug) print*,'model height profile'
      if(debug) print*,v_h

      !nc -- If location is below model terrain (and therefore has a missing_r8 value), 
      !        then push its location back to the level of model terrain.  This is only
      !        permitted if the user has set the logical parameter allow_obs_below_surf to
      !        be .true. (its default is .false.).
      if ( allow_obs_below_surf ) then
         if ( zloc == missing_r8 .and. xyz_loc(3) < v_h(0) ) then
            zloc = 1.0_r8         ! Lower than the model terrain.
            surf_var = .true.     ! Estimate U,V,T,and Q from the model sfc states.
         end if
      end if
   
   elseif(vert_is_surface(location)) then
      zloc = 1.0_r8
      surf_var = .true.
      if(debug) print*,' obs is at the surface = ', xyz_loc(3)

   elseif(vert_is_undef(location)) then
      zloc  = missing_r8
      if(debug) print*,' obs height is undefined -- ignoring observation is imminent'

   else
      write(errstring,*) 'wrong option for which_vert ', &
                         nint(query_location(location,'which_vert'))
      call error_handler(E_ERR,'model_interpolate', errstring, &
           source, revision, revdate)

   endif


   ! Deal with undefined / missing vertical coordinates -- return with istatus .ne. 0
   !   NOTE: observations with vert_is_undef == .true. will be ignored!
   if(zloc == missing_r8) then
      obs_val = missing_r8
      istatus = 1
      deallocate(v_h, v_p)
      return
   endif

   ! Set a working integer k value -- if (int(zloc) < 1), then k = 1
   k = max(1,int(zloc))


   !----------------------------------
   ! 1. Horizontal Interpolation 
   !----------------------------------

   ! This part is the forward operator -- compute desired model state value for given point.

   ! Strategy is to do the horizontal interpolation on two different levels in the
   !   vertical, and then to do the vertical interpolation afterwards, since it depends on
   !   what the vertical coordinate is

   ! Large if-structure to select on obs_kind of desired field....
   ! Table of Contents:
   ! a. U, V, U10, V10 -- Horizontal Winds
   ! b. T, T2 -- Sensible Temperature
   ! c. TH, TH2 -- Potential Temperature
   ! d. Rho -- Density
   ! e. W -- Vertical Wind
   ! f. SH, SH2 -- Specific Humidity
   ! g. QV, Q2 -- Vapor Mixing Ratio
   ! h. QR -- Rainwater Mixing Ratio
   ! i. QG -- Graupel Mixing Ratio
   ! j. QS -- Snow Mixing Ratio
   ! k. P -- Pressure
   ! l. PS -- Surface Pressure
   ! m. Vortex Center Stuff (Yongsheng)
   ! n. GZ -- Geopotential Height (Ryan Torn)
   ! o. HGT -- Surface Elevation (Ryan Torn)

   ! NOTE: the previous version of this code checked for surface observations with the syntax:
   !          "if(.not. vert_is_surface(location) .or. .not. surf_var) then"
   !   We identified this as redundant because surf_var is changed from .false. only by
   !     the above code (section 0.b), which must be traced through before one can arrive
   !     at the following forward operator code.  Hence, we can remove the call to 
   !     vert_is_surface.

   !-----------------------------------------------------
   ! 1.a Horizontal Winds (U, V, U10, V10)

   ! We need one case structure for both U & V because they comprise a vector which could need
   !   transformation depending on the map projection (hence, the call to gridwind_to_truewind)
   if( obs_kind == KIND_U_WIND_COMPONENT .or. obs_kind == KIND_V_WIND_COMPONENT) then   ! U, V

      ! This is for 3D wind fields -- surface winds later
      if(.not. surf_var) then

         ! xloc and yloc are indices on mass-grid.  If we are on a periodic longitude domain,
         !   then xloc can range from [1 wes).  This means that simply adding 0.5 to xloc has
         !   the potential to render xloc_u out of the valid mass-grid index bounds (>wes).
         !   To remedy this, we can either do periodicity check on xloc_u value, or we can
         !   leave it to a subroutine or function to alter xloc to xloc_u if the observation
         !   type requires it.
         xloc_u = xloc + 0.5_r8
         yloc_v = yloc + 0.5_r8

         ! Check periodicity if necessary -- but only subtract 'we' because the U-grid
         !   cannot have an index < 1 (i.e., U(wes) = U(1) ).
         if ( wrf%dom(id)%periodic_x .and. xloc_u > real(wrf%dom(id)%wes,r8) ) &
              xloc_u = xloc_u - real(wrf%dom(id)%we,r8)

         ! Get South West gridpoint indices for xloc_u and yloc_v
         call toGrid(xloc_u,i_u,dx_u,dxm_u)
         call toGrid(yloc_v,j_v,dy_v,dym_v)

         ! Check to make sure retrieved integer gridpoints are in valid range
         if ( boundsCheck( i_u, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_U ) .and. &
              boundsCheck( i,   wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_V ) .and. &
              boundsCheck( j,   wrf%dom(id)%polar,      id, dim=2, type=TYPE_U ) .and. &
              boundsCheck( j_v, wrf%dom(id)%polar,      id, dim=2, type=TYPE_V ) .and. &
              boundsCheck( k,   .false.,                id, dim=3, type=TYPE_U ) ) then

            ! Need to get grid cell corners surrounding observation location -- with
            !   periodicity, this could be non-consecutive (i.e., NOT necessarily i and i+1);
            !   Furthermore, it could be different for the U-grid and V-grid.  Remember, for 
            !   now, we are disallowing observations to be located poleward of the 1st and 
            !   last mass points.
            
            call getCorners(i_u, j, id, TYPE_U, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners U rc = ', rc
            
            call getCorners(i, j_v, id, TYPE_V, ll_v, ul_v, lr_v, ur_v, rc ) 
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners V rc = ', rc
            
            ! Now we want to get the corresponding DART state vector indices, and then
            !   interpolate horizontally on TWO different vertical levels (so that we can
            !   do the vertical interpolation properly later)
            do k2 = 1, 2

               ! Interpolation for the U field
               ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+k2-1, TYPE_U)
               iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+k2-1, TYPE_U)
               ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+k2-1, TYPE_U)
               iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+k2-1, TYPE_U)

               ugrid = dym*( dxm_u*x(ill) + dx_u*x(ilr) ) + dy*( dxm_u*x(iul) + dx_u*x(iur) )

               ! Interpolation for the V field
               ill = wrf%dom(id)%dart_ind(ll_v(1), ll_v(2), k+k2-1, TYPE_V)
               iul = wrf%dom(id)%dart_ind(ul_v(1), ul_v(2), k+k2-1, TYPE_V)
               ilr = wrf%dom(id)%dart_ind(lr_v(1), lr_v(2), k+k2-1, TYPE_V)
               iur = wrf%dom(id)%dart_ind(ur_v(1), ur_v(2), k+k2-1, TYPE_V)
               
               vgrid = dym_v*( dxm*x(ill) + dx*x(ilr) ) + dy_v*( dxm*x(iul) + dx*x(iur) )

               ! Certain map projections have wind on grid different than true wind (on map)
               !   subroutine gridwind_to_truewind is in module_map_utils.f90
               call gridwind_to_truewind(xyz_loc(1), wrf%dom(id)%proj, ugrid, vgrid, &
                    utrue, vtrue)
               
               ! Figure out which field was the actual desired observation and store that
               !   field as one of the two elements of "fld" (the other element is the other
               !   k-level)
               if( obs_kind == KIND_U_WIND_COMPONENT) then                  
                  fld(k2) = utrue                  
               else   ! must want v                  
                  fld(k2) = vtrue                  
               end if
               
            end do

         ! If the boundsCheck functions return an unsatisfactory integer index, then set
         !   fld as missing data
         else

            fld(:) = missing_r8

         end if

      ! This is for surface wind fields -- NOTE: surface winds are on Mass grid (therefore,
      !   TYPE_T), not U-grid & V-grid.  Also, there doesn't seem to be a need to call
      !   gridwind_to_truewind for surface winds (is that right?)
      ! Also, because surface winds are at a given single vertical level, only fld(1) will
      !   be filled.
      ! (U10 & V10, which are added to dart_ind if surf_obs = .true.)
      else

         ! Check to make sure retrieved integer gridpoints are in valid range
         if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
              boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
              wrf%dom(id)%surf_obs ) then

            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners U10, V10 rc = ', rc

            ! Interpolation for the U10 field
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), 1, TYPE_U10)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), 1, TYPE_U10)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), 1, TYPE_U10)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), 1, TYPE_U10)
            ugrid = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) ) 

            ! Interpolation for the V10 field
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), 1, TYPE_V10)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), 1, TYPE_V10)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), 1, TYPE_V10)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), 1, TYPE_V10)
            vgrid = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

            call gridwind_to_truewind(xyz_loc(1), wrf%dom(id)%proj, ugrid, vgrid, &
                 utrue, vtrue)

            ! U10 (U at 10 meters)
            if( obs_kind == KIND_U_WIND_COMPONENT) then
               fld(1) = utrue
            ! V10 (V at 10 meters)
            else
               fld(1) = vtrue
            end if

         ! If the boundsCheck functions return an unsatisfactory integer index, then set
         !   fld as missing data
         else

            fld(1) = missing_r8

         end if
      end if


   !-----------------------------------------------------
   ! 1.b Sensible Temperature (T, T2)

   elseif ( obs_kind == KIND_TEMPERATURE ) then

      ! This is for 3D temperature field -- surface temps later
      if(.not. surf_var) then

         ! Check to make sure retrieved integer gridpoints are in valid range
         if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
              boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
              boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then

            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners T rc = ', rc
            
            ! Interpolation for T field at level k
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_T)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_T)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_T)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_T)

            ! In terms of perturbation potential temperature
            a1 = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

            pres1 = model_pressure_t(ll(1), ll(2), k, id, x)
            pres2 = model_pressure_t(lr(1), lr(2), k, id, x)
            pres3 = model_pressure_t(ul(1), ul(2), k, id, x)
            pres4 = model_pressure_t(ur(1), ur(2), k, id, x)
            
            ! Pressure at location
            pres = dym*( dxm*pres1 + dx*pres2 ) + dy*( dxm*pres3 + dx*pres4 )

            ! Full sensible temperature field
            fld(1) = (ts0 + a1)*(pres/ps0)**kappa


            ! Interpolation for T field at level k+1
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+1, TYPE_T)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+1, TYPE_T)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+1, TYPE_T)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+1, TYPE_T)

            ! In terms of perturbation potential temperature
            a1 = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

            pres1 = model_pressure_t(ll(1), ll(2), k+1, id, x)
            pres2 = model_pressure_t(lr(1), lr(2), k+1, id, x)
            pres3 = model_pressure_t(ul(1), ul(2), k+1, id, x)
            pres4 = model_pressure_t(ur(1), ur(2), k+1, id, x)
            
            ! Pressure at location
            pres = dym*( dxm*pres1 + dx*pres2 ) + dy*( dxm*pres3 + dx*pres4 )

            ! Full sensible temperature field
            fld(2) = (ts0 + a1)*(pres/ps0)**kappa

         ! If the boundsCheck functions return an unsatisfactory integer index, then set
         !   fld as missing data
         else

            fld(:) = missing_r8

         end if

      ! This is for surface temperature (T2, which is added to dart_ind if surf_obs = .true.)
      else
         
         ! Check to make sure retrieved integer gridpoints are in valid range
         if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
              boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
              wrf%dom(id)%surf_obs ) then

            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners T2 rc = ', rc

            ! Interpolation for the T2 field
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), 1, TYPE_T2)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), 1, TYPE_T2)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), 1, TYPE_T2)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), 1, TYPE_T2)
            
            fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

         ! If the boundsCheck functions return an unsatisfactory integer index, then set
         !   fld as missing data
         else

            fld(1) = missing_r8

         end if
      end if


   !-----------------------------------------------------
   ! 1.c Potential Temperature (Theta, TH2)

   ! Note:  T is perturbation potential temperature (potential temperature - ts0)
   !   TH2 is potential temperature at 2 m
   elseif ( obs_kind == KIND_POTENTIAL_TEMPERATURE ) then

      ! This is for 3D potential temperature field -- surface pot temps later
      if(.not. surf_var) then

         ! Check to make sure retrieved integer gridpoints are in valid range
         if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
              boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
              boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then
      
            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners Theta rc = ', rc
            
            ! Interpolation for Theta field at level k
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_T)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_T)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_T)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_T)

            fld(1) = ts0 + dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

            ! Interpolation for Theta field at level k+1
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+1, TYPE_T)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+1, TYPE_T)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+1, TYPE_T)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+1, TYPE_T)

            fld(2) = ts0 + dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

         ! If the boundsCheck functions return an unsatisfactory integer index, then set
         !   fld as missing data
         else

            fld(:) = missing_r8

         end if

      ! This is for surface potential temperature (TH2, which is added to dart_ind 
      !   if surf_obs = .true.)
      else
         
         ! Check to make sure retrieved integer gridpoints are in valid range
         if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
              boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
              wrf%dom(id)%surf_obs ) then

            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners TH2 rc = ', rc

            ! Interpolation for the TH2 field
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), 1, TYPE_TH2)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), 1, TYPE_TH2)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), 1, TYPE_TH2)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), 1, TYPE_TH2)
            
            fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

         ! If the boundsCheck functions return an unsatisfactory integer index, then set
         !   fld as missing data
         else

            fld(1) = missing_r8

         end if
      end if


   !-----------------------------------------------------
   ! 1.d Density (Rho)

   ! Rho calculated at mass points, and so is like "TYPE_T" -- KIND_DENSITY apparently only
   !   refers to full 3D density field (i.e., no surface fields!)
   elseif ( obs_kind == KIND_DENSITY ) then
      
      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then
         
         call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
         if ( rc .ne. 0 ) &
              print*, 'model_mod.f90 :: model_interpolate :: getCorners Rho rc = ', rc
      
         ! calculate full rho at corners of interp box
         ! and interpolate to desired horizontal location

         ! Hmmm, it does not appear that Rho is part of the DART state vector, so there
         !   is not a reference to wrf%dom(id)%dart_ind -- we'll have to go right from
         !   the corner indices

         ! Interpolation for the Rho field at level k
         rho1 = model_rho_t(ll(1), ll(2), k, id, x)
         rho2 = model_rho_t(lr(1), lr(2), k, id, x)
         rho3 = model_rho_t(ul(1), ul(2), k, id, x)
         rho4 = model_rho_t(ur(1), ur(2), k, id, x)

         fld(1) = dym*( dxm*rho1 + dx*rho2 ) + dy*( dxm*rho3 + dx*rho4 )

         ! Interpolation for the Rho field at level k+1
         rho1 = model_rho_t(ll(1), ll(2), k+1, id, x)
         rho2 = model_rho_t(lr(1), lr(2), k+1, id, x)
         rho3 = model_rho_t(ul(1), ul(2), k+1, id, x)
         rho4 = model_rho_t(ur(1), ur(2), k+1, id, x)

         fld(2) = dym*( dxm*rho1 + dx*rho2 ) + dy*( dxm*rho3 + dx*rho4 )

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else

         fld(:) = missing_r8

      end if


   !-----------------------------------------------------
   ! 1.e Vertical Wind (W)

   elseif ( obs_kind == KIND_VERTICAL_VELOCITY ) then

      ! Adjust zloc for staggered ZNW grid (or W-grid, as compared to ZNU or M-grid)
      zloc = zloc + 0.5_r8
      k = max(1,int(zloc))
      
      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_W ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_W ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_W ) ) then

         call getCorners(i, j, id, TYPE_W, ll, ul, lr, ur, rc )
         if ( rc .ne. 0 ) &
              print*, 'model_mod.f90 :: model_interpolate :: getCorners W rc = ', rc
         
         ! Interpolation for W field at level k
         ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_W)
         iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_W)
         ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_W)
         iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_W)
         
         fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
         
         ! Interpolation for W field at level k+1
         ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+1, TYPE_W)
         iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+1, TYPE_W)
         ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+1, TYPE_W)
         iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+1, TYPE_W)
         
         fld(2) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
      
      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else

         fld(:) = missing_r8

      end if


   !-----------------------------------------------------
   ! 1.f Specific Humidity (SH, SH2)

   ! Convert water vapor mixing ratio to specific humidity:
   else if( obs_kind == KIND_SPECIFIC_HUMIDITY ) then

      ! First confirm that vapor mixing ratio is in the DART state vector
      if ( wrf%dom(id)%n_moist >= 1 ) then
      
         ! This is for 3D specific humidity -- surface spec humidity later
         if(.not. surf_var) then

            ! Check to make sure retrieved integer gridpoints are in valid range
            if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
                 boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
                 boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then
      
               call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
               if ( rc .ne. 0 ) &
                    print*, 'model_mod.f90 :: model_interpolate :: getCorners SH rc = ', rc
               
               ! Interpolation for SH field at level k
               ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_QV)
               iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_QV)
               ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_QV)
               iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_QV)
               
               a1 = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
               fld(1) = a1 /(1.0_r8 + a1)
               
               ! Interpolation for SH field at level k+1
               ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+1, TYPE_QV)
               iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+1, TYPE_QV)
               ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+1, TYPE_QV)
               iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+1, TYPE_QV)
               
               a1 = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
               fld(2) = a1 /(1.0_r8 + a1)

            ! If the boundsCheck functions return an unsatisfactory integer index, then set
            !   fld as missing data
            else
            
               fld(:) = missing_r8
            
            end if

         ! This is for surface specific humidity (calculated from Q2, which is added to 
         !   dart_ind if surf_obs = .true.)
         else
         
            ! Check to make sure retrieved integer gridpoints are in valid range
            if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
                 boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
                 wrf%dom(id)%surf_obs ) then
               
               call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
               if ( rc .ne. 0 ) &
                    print*, 'model_mod.f90 :: model_interpolate :: getCorners SH2 rc = ', rc

               ! Interpolation for the SH2 field
               ill = wrf%dom(id)%dart_ind(ll(1), ll(2), 1, TYPE_Q2)
               iul = wrf%dom(id)%dart_ind(ul(1), ul(2), 1, TYPE_Q2)
               ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), 1, TYPE_Q2)
               iur = wrf%dom(id)%dart_ind(ur(1), ur(2), 1, TYPE_Q2)
               
               a1 = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
               fld(1) = a1 /(1.0_r8 + a1)

            ! If the boundsCheck functions return an unsatisfactory integer index, then set
            !   fld as missing data
            else
            
               fld(1) = missing_r8
            
            end if
         end if
         
      ! If not in the state vector, then set to 0 (?)
      else

         fld(:) = 0.0_r8

      end if


   !-----------------------------------------------------
   ! 1.g Vapor Mixing Ratio (QV, Q2)
   else if( obs_kind == KIND_VAPOR_MIXING_RATIO ) then

      ! First confirm that vapor mixing ratio is in the DART state vector
      if ( wrf%dom(id)%n_moist >= 1 ) then
      
         ! This is for 3D vapor mixing ratio -- surface QV later
         if(.not. surf_var) then

            ! Check to make sure retrieved integer gridpoints are in valid range
            if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
                 boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
                 boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then
      
               call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
               if ( rc .ne. 0 ) &
                    print*, 'model_mod.f90 :: model_interpolate :: getCorners QV rc = ', rc
               
               ! Interpolation for QV field at level k
               ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_QV)
               iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_QV)
               ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_QV)
               iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_QV)
               
               fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
               
               ! Interpolation for QV field at level k+1
               ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+1, TYPE_QV)
               iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+1, TYPE_QV)
               ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+1, TYPE_QV)
               iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+1, TYPE_QV)
               
               fld(2) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

            ! If the boundsCheck functions return an unsatisfactory integer index, then set
            !   fld as missing data
            else
            
               fld(:) = missing_r8
            
            end if

         ! This is for surface QV (Q2, which is added to dart_ind if surf_obs = .true.)
         else
         
            ! Check to make sure retrieved integer gridpoints are in valid range
            if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
                 boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
                 wrf%dom(id)%surf_obs ) then
               
               call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
               if ( rc .ne. 0 ) &
                    print*, 'model_mod.f90 :: model_interpolate :: getCorners QV2 rc = ', rc

               ! Interpolation for the SH2 field
               ill = wrf%dom(id)%dart_ind(ll(1), ll(2), 1, TYPE_Q2)
               iul = wrf%dom(id)%dart_ind(ul(1), ul(2), 1, TYPE_Q2)
               ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), 1, TYPE_Q2)
               iur = wrf%dom(id)%dart_ind(ur(1), ur(2), 1, TYPE_Q2)
               
               fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

            ! If the boundsCheck functions return an unsatisfactory integer index, then set
            !   fld as missing data
            else
            
               fld(1) = missing_r8
            
            end if
         end if
         
      ! If not in the state vector, then set to 0 (?)
      else

         fld(:) = 0.0_r8

      end if


   !-----------------------------------------------------
   ! 1.h Rainwater Mixing Ratio (QR)
   else if( obs_kind == KIND_RAINWATER_MIXING_RATIO ) then

      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then
      
         ! Confirm that QR is in the DART state vector
         if ( wrf%dom(id)%n_moist >= 3 ) then

            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners QR rc = ', rc
               
            ! Interpolation for QR field at level k
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_QR)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_QR)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_QR)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_QR)
            
            fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
               
            ! Interpolation for QR field at level k+1
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+1, TYPE_QR)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+1, TYPE_QR)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+1, TYPE_QR)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+1, TYPE_QR)
               
            fld(2) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
            
            ! Don't accept negative rain amounts (?)
            fld = max(0.0_r8, fld)

         ! If QR is not in state vector, then zero-out the retrieved field -- is this 
         !   right?  should we instead keep it as missing?
         else

            fld(:) = 0.0_r8

         end if

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else
            
         fld(:) = missing_r8
            
      end if
   

   !-----------------------------------------------------
   ! 1.i Graupel Mixing Ratio (QG)
   else if( obs_kind == KIND_GRAUPEL_MIXING_RATIO ) then

      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then
         
         ! Confirm that QG is in the DART state vector
         if ( wrf%dom(id)%n_moist >= 6 ) then

            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners QG rc = ', rc
               
            ! Interpolation for QG field at level k
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_QG)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_QG)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_QG)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_QG)
            
            fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
               
            ! Interpolation for QG field at level k+1
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+1, TYPE_QG)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+1, TYPE_QG)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+1, TYPE_QG)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+1, TYPE_QG)
               
            fld(2) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

            ! Don't accept negative rain amounts (?)
            fld = max(0.0_r8, fld)
            
         ! If QG is not in state vector, then zero-out the retrieved field -- is this 
         !   right?  should we instead keep it as missing?
         else

            fld(:) = 0.0_r8

         end if

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else
            
            fld(:) = missing_r8
            
      end if
   

  !-----------------------------------------------------
  ! 1.j Snow Mixing Ratio (QS)
   else if( obs_kind == KIND_SNOW_MIXING_RATIO ) then

      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then
         
         ! Confirm that QS is in the DART state vector
         if ( wrf%dom(id)%n_moist >= 5 ) then

            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: model_interpolate :: getCorners QS rc = ', rc
               
            ! Interpolation for QS field at level k
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_QS)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_QS)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_QS)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_QS)
            
            fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
               
            ! Interpolation for QS field at level k+1
            ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+1, TYPE_QS)
            iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+1, TYPE_QS)
            ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+1, TYPE_QS)
            iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+1, TYPE_QS)
               
            fld(2) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

            ! Don't accept negative rain amounts (?)
            fld = max(0.0_r8, fld)
            
         ! If QS is not in state vector, then zero-out the retrieved field -- is this 
         !   right?  should we instead keep it as missing?
         else

            fld(:) = 0.0_r8

         end if

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else
            
            fld(:) = missing_r8
            
      end if
   

   !-----------------------------------------------------
   ! 1.k Pressure (P)
   else if( obs_kind == KIND_PRESSURE ) then

      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then

         call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
         if ( rc .ne. 0 ) &
              print*, 'model_mod.f90 :: model_interpolate :: getCorners P rc = ', rc
      
         ! Hmmm, it does not appear that P is part of the DART state vector, so there
         !   is not a reference to wrf%dom(id)%dart_ind -- we'll have to go right from
         !   the corner indices

         ! Interpolation for the P field at level k
         pres1 = model_pressure_t(ll(1), ll(2), k, id, x)
         pres2 = model_pressure_t(lr(1), lr(2), k, id, x)
         pres3 = model_pressure_t(ul(1), ul(2), k, id, x)
         pres4 = model_pressure_t(ur(1), ur(2), k, id, x)

         fld(1) = dym*( dxm*pres1 + dx*pres2 ) + dy*( dxm*pres3 + dx*pres4 )

         ! Interpolation for the P field at level k+1
         pres1 = model_pressure_t(ll(1), ll(2), k+1, id, x)
         pres2 = model_pressure_t(lr(1), lr(2), k+1, id, x)
         pres3 = model_pressure_t(ul(1), ul(2), k+1, id, x)
         pres4 = model_pressure_t(ur(1), ur(2), k+1, id, x)

         fld(2) = dym*( dxm*pres1 + dx*pres2 ) + dy*( dxm*pres3 + dx*pres4 )

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else

         fld(:) = missing_r8

      end if


   !-----------------------------------------------------
   ! 1.l Surface Pressure (PS, add to dart_ind if surf_obs = .true.)
   else if( obs_kind == KIND_SURFACE_PRESSURE ) then

      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           wrf%dom(id)%surf_obs ) then

         call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
         if ( rc .ne. 0 ) &
              print*, 'model_mod.f90 :: model_interpolate :: getCorners PS rc = ', rc

         ! Interpolation for the PS field
         ill = wrf%dom(id)%dart_ind(ll(1), ll(2), 1, TYPE_PS)
         iul = wrf%dom(id)%dart_ind(ul(1), ul(2), 1, TYPE_PS)
         ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), 1, TYPE_PS)
         iur = wrf%dom(id)%dart_ind(ur(1), ur(2), 1, TYPE_PS)
            
         ! I'm not quite sure where this comes from, but I will trust them on it....
         if ( x(ill) /= 0.0_r8 .and. x(ilr) /= 0.0_r8 .and. x(iul) /= 0.0_r8 .and. &
              x(iur) /= 0.0_r8 ) then

            fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

         else

            fld(1) = missing_r8

         end if

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else

         fld(1) = missing_r8

      end if


   !-----------------------------------------------------
   ! 1.m Vortex Center Stuff from Yongsheng

   else if ( obs_kind == KIND_VORTEX_LAT .or. &
             obs_kind == KIND_VORTEX_LON .or. &
             obs_kind == KIND_VORTEX_PMIN .or. &
             obs_kind == KIND_VORTEX_WMAX ) then

      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then

!*****************************************************************************         
! NOTE :: with the exception of changing the original if-structure to calls of the 
!   function boundsCheck, the below is Yongsheng's original verbatim ---
!   *** THERE IS NO GUARANTEE THAT THIS WILL CONTINUE TO WORK WITH GLOBAL WRF ***
!*****************************************************************************         

!!   define a search box bounded by center_track_***
     center_search_half_size = nint(center_search_half_length/wrf%dom(id)%dx)
     center_track_xmin = max(1,i-center_search_half_size)
     center_track_xmax = min(wrf%dom(id)%var_size(1,TYPE_MU),i+center_search_half_size)
     center_track_ymin = max(1,j-center_search_half_size)
     center_track_ymax = min(wrf%dom(id)%var_size(2,TYPE_MU),j+center_search_half_size)
     if(center_track_xmin<1 .or. center_track_xmax>wrf%dom(id)%var_size(1,TYPE_MU) .or. &
        center_track_ymin<1 .or. center_track_ymax>wrf%dom(id)%var_size(2,TYPE_MU) .or. &
        center_track_xmin >= center_track_xmax .or. &
        center_track_ymin >= center_track_ymax) then
          print*,'i,j,center_search_half_length,center_track_xmin(max),center_track_ymin(max)'
          print*,i,j,center_search_half_length,center_track_xmin,center_track_xmax,center_track_ymin,center_track_ymax
         write(errstring,*)'Wrong setup in center_track_nml'
         call error_handler(E_ERR,'model_interpolate', errstring, source, revision, revdate)
     endif 

!!   define spline interpolation box dimensions
     xlen = center_track_xmax - center_track_xmin + 1
     ylen = center_track_ymax - center_track_ymin + 1
     xxlen = (center_track_xmax - center_track_xmin)*center_spline_grid_scale + 1
     yylen = (center_track_ymax - center_track_ymin)*center_spline_grid_scale + 1
     allocate(p1d(wrf%dom(id)%bt), t1d(wrf%dom(id)%bt))
     allocate(qv1d(wrf%dom(id)%bt), z1d(wrf%dom(id)%bt))
     allocate(psea(xlen,ylen))
     allocate(pd(xlen,ylen))
     allocate(pp(xxlen,yylen))
     allocate(x1d(xlen))
     allocate(y1d(ylen))
     allocate(xx1d(xxlen))
     allocate(yy1d(yylen))

!!   compute sea-level pressure
     do i1 = center_track_xmin, center_track_xmax
     do i2 = center_track_ymin, center_track_ymax
        do k2 = 1,wrf%dom(id)%var_size(3,TYPE_T)
           p1d(k2) = model_pressure_t(i1,i2,k2,id,x)
           t1d(k2) = ts0 + x(wrf%dom(id)%dart_ind(i1,i2,k2,TYPE_T))
           qv1d(k2)= x(wrf%dom(id)%dart_ind(i1,i2,k2,TYPE_QV))
           z1d(k2) = ( x(wrf%dom(id)%dart_ind(i1,i2,k2,TYPE_GZ))+wrf%dom(id)%phb(i1,i2,k2) + &
                      x(wrf%dom(id)%dart_ind(i1,i2,k2+1,TYPE_GZ))+wrf%dom(id)%phb(i1,i2,k2+1) &
                    )*0.5_r8/gravity
        enddo
        call compute_seaprs(wrf%dom(id)%bt, z1d, t1d, p1d, qv1d, &
                          psea(i1-center_track_xmin+1,i2-center_track_ymin+1),debug)
     enddo
     enddo

!!   spline-interpolation
     do i1 = 1,xlen
        x1d(i1) = (i1-1)+center_track_xmin
     enddo
     do i2 = 1,ylen
        y1d(i2) = (i2-1)+center_track_ymin
     enddo
     do ii1 = 1,xxlen
        xx1d(ii1) = center_track_xmin+real(ii1-1,r8)*1_r8/real(center_spline_grid_scale,r8)
     enddo
     do ii2 = 1,yylen
        yy1d(ii2) = center_track_ymin+real(ii2-1,r8)*1_r8/real(center_spline_grid_scale,r8)
     enddo

     call splie2(x1d,y1d,psea,xlen,ylen,pd)

     pres1 = 1.e20
     cxmin = -1
     cymin = -1
     do ii1=1,xxlen
     do ii2=1,yylen
        call splin2(x1d,y1d,psea,pd,xlen,ylen,xx1d(ii1),yy1d(ii2),pp(ii1,ii2))
        if (pres1 .gt. pp(ii1,ii2)) then
           pres1=pp(ii1,ii2)
           cxmin=xx1d(ii1)
           cymin=yy1d(ii2)
        endif
     enddo
     enddo

!!   if too close to the edge of the box, reset to observed center
     if( cxmin-xx1d(1) < 1_r8 .or. xx1d(xxlen)-cxmin < 1_r8 .or.  &
         cymin-yy1d(1) < 1_r8 .or. yy1d(yylen)-cymin < 1_r8 ) then
       cxmin = xloc
       cymin = yloc
       call splin2(x1d,y1d,psea,pd,xlen,ylen,cxmin,cymin,pres1)
     endif

     call ij_to_latlon(wrf%dom(id)%proj, cxmin, cymin, clat, clon)

     if( obs_kind == KIND_VORTEX_LAT ) then
        fld(1) = clat
     else if( obs_kind == KIND_VORTEX_LON ) then
        fld(1) = clon
     else if( obs_kind == KIND_VORTEX_PMIN ) then
        fld(1) = pres1
     else if( obs_kind == KIND_VORTEX_WMAX ) then
        fld(1) = missing_r8
        ! not implemented yet
     endif

     deallocate(p1d, t1d, qv1d, z1d)
     deallocate(psea,pd,pp,x1d,y1d,xx1d,yy1d)


   else

      fld(1) = missing_r8

   endif
!*****************************************************************************         
! END OF VERBATIM BIT
!*****************************************************************************         


   !-----------------------------------------------------
   ! 1.n Geopotential Height (GZ)

   ! Geopotential Height has been added by Ryan Torn to accommodate altimeter observations.
   !   GZ is on the ZNW grid (bottom_top_stagger), so its bottom-most level is defined to
   !   be at eta = 1 (the surface).  Thus, we have a 3D variable that contains a surface
   !   variable; the same is true for W as well.  If one wants to observe the surface value
   !   of either of these variables, then one can simply operate on the full 3D field 
   !   (toGrid below should return dz ~ 0 and dzm ~ 1) 
   else if( obs_kind == KIND_GEOPOTENTIAL_HEIGHT ) then

      ! Adjust zloc for staggered ZNW grid (or W-grid, as compared to ZNU or M-grid)
      zloc = zloc + 0.5_r8
      k = max(1,int(zloc))

      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_GZ ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_GZ ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_GZ ) ) then
         
         call getCorners(i, j, id, TYPE_GZ, ll, ul, lr, ur, rc )
         if ( rc .ne. 0 ) &
              print*, 'model_mod.f90 :: model_interpolate :: getCorners GZ rc = ', rc
         
         ! Interpolation for GZ field at level k
         ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_GZ) / gravity
         iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_GZ) / gravity
         ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_GZ) / gravity
         iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_GZ) / gravity
         
         fld(1) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )
         
         ! Interpolation for GZ field at level k+1
         ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k+1, TYPE_GZ) / gravity
         iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k+1, TYPE_GZ) / gravity
         ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k+1, TYPE_GZ) / gravity
         iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k+1, TYPE_GZ) / gravity
         
         fld(2) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else

         fld(:) = missing_r8
         
      end if


   !-----------------------------------------------------
   ! 1.o Surface Elevation (HGT)

   ! Surface Elevation has been added by Ryan Torn to accommodate altimeter observations.
   !   HGT is not in the dart_ind vector, so get it from wrf%dom(id)%hgt.
   else if( obs_kind == KIND_SURFACE_ELEVATION ) then

      ! Check to make sure retrieved integer gridpoints are in valid range -- since the 
      !   altimeter obs_def code has calls to surface pressure is it, then surf_obs must
      !   equal to .true. in order to use altimeter obs.
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           wrf%dom(id)%surf_obs ) then
      
         call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
         if ( rc .ne. 0 ) &
              print*, 'model_mod.f90 :: model_interpolate :: getCorners HGT rc = ', rc
         
         ! Interpolation for the HGT field -- HGT is NOT part of state vector x, but rather
         !   in the associated domain meta data
         fld(1) = dym*( dxm*wrf%dom(id)%hgt(ll(1), ll(2)) + &
                         dx*wrf%dom(id)%hgt(lr(1), lr(2)) ) + &
                   dy*( dxm*wrf%dom(id)%hgt(ul(1), ul(2)) + &
                         dx*wrf%dom(id)%hgt(ur(1), ur(2)) )

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else

         fld(1) = missing_r8

      end if


   !-----------------------------------------------------
   ! If obs_kind is not negative (for identity obs), or if it is not one of the above 15
   !   explicitly checked-for kinds, then return error message.
   else

      write(errstring,*)'Obs kind not recognized for following kind: ',obs_kind
      call error_handler(E_ERR,'model_interpolate', errstring, &
           source, revision, revdate)

   end if


   !----------------------------------
   ! 2. Vertical Interpolation 
   !----------------------------------

   ! Do vertical interpolation -- only for non-surface, non-indetity obs.  

   ! The previous section (1. Horizontal Interpolation) has produced a variable called
   !   "fld", which nominally has two entries in it.  3D fields have hopefully produced
   !   2 non-zero entries, whereas surface fields only have filled the first entry.
   ! If a full 3D field, then do vertical interpolation between sandwiched model levels
   !   (k and k+1).

   ! Check to make sure that we did something sensible in the Horizontal Interpolation 
   !   section above.  All valid obs_kinds will have changed fld(1).
   if ( fld(1) == missing_r8 ) then

      obs_val = missing_r8

   ! We purposefully changed fld(1), so continue onward
   else

      ! If a surface variable, then no need to do any vertical interpolation
      if ( surf_var ) then 

         obs_val = fld(1)

      ! If an interior variable, then we DO need to do vertical interpolation
      else

         ! First make sure fld(2) is no longer a missing value
         if ( fld(2) == missing_r8 ) then

            obs_val = missing_r8

         ! Do vertical interpolation -- I believe this assumes zloc is well-defined and
         !   >= 1.0_r8.
         else

            ! Get fractional distances between grid points
            call toGrid(zloc, k, dz, dzm)

            ! Linearly interpolate between grid points
            obs_val = dzm*fld(1) + dz*fld(2)
            
         end if
      end if
   end if

end if  ! end of "if ( obs_kind < 0 )"


! Now that we are done, check to see if a missing value somehow made it through
if ( obs_val == missing_r8 ) istatus = 1

! Pring the observed value if in debug mode
if(debug) print*,' interpolated value= ',obs_val

! Deallocate variables before exiting
deallocate(v_h, v_p)

end subroutine model_interpolate


!#######################################################################


subroutine vert_interpolate(x, location, obs_kind, istatus)

! This subroutine converts a given ob/state vertical coordinate to
! the vertical coordinate type requested through the model_mod namelist.

! Notes: (1) obs_kind is only necessary to check whether the ob
!            is an identity ob.
!        (2) This subroutine can convert both obs' and state points'
!            vertical coordinates. Remember that state points get
!            their DART location information from get_state_meta_data
!            which is called by filter_assim during the assimilation
!            process.
!        (3) x is the relevant DART state vector for carrying out
!            interpolations necessary for the vertical coordinate
!            transformations. As the vertical coordinate is only used
!            in distance computations, this is actually the "expected"
!            vertical coordinate, so that computed distance is the
!            "expected" distance. Thus, under normal circumstances,
!            x that is supplied to vert_interpolate should be the
!            ensemble mean. Nevertheless, the subroutine has the
!            functionality to operate on any DART state vector that
!            is supplied to it.

real(r8),            intent(in)    :: x(:)
integer,             intent(in)    :: obs_kind
type(location_type), intent(inout) :: location
integer,             intent(out)   :: istatus

real(r8)            :: xloc, yloc, zloc, xyz_loc(3), zvert
integer             :: id, i, j, k, rc
real(r8)            :: dx,dy,dz,dxm,dym,dzm
integer, dimension(2) :: ll, lr, ul, ur

character(len=129) :: errstring

real(r8), allocatable, dimension(:) :: v_h, v_p

! local vars, used in calculating pressure and height
real(r8)            :: pres1, pres2, pres3, pres4
real(r8)            :: presa, presb
real(r8)            :: hgt1, hgt2, hgt3, hgt4, hgta, hgtb


istatus = 0

! first off, check if ob is identity ob
if (obs_kind < 0) then
   call get_state_meta_data(obs_kind,location)
   return
endif

xyz_loc = get_location(location)

! first obtain domain id, and mass points (i,j)
call get_domain_info(xyz_loc(1),xyz_loc(2),id,xloc,yloc)

if (id==0) then
   ! Note: need to reset location using the namelist variable directly because
   ! wrf%dom(id)%vert_coord is not defined for id=0
   location = set_location(xyz_loc(1),xyz_loc(2),missing_r8,vert_localization_coord)
   istatus = 1
   return
endif

allocate(v_h(0:wrf%dom(id)%bt), v_p(0:wrf%dom(id)%bt))

! get integer (west/south) grid point and distances to neighboring grid points
! distances are used as weights to carry out horizontal interpolations
call toGrid(xloc,i,dx,dxm)
call toGrid(yloc,j,dy,dym)

! Determine corresponding model level for obs location
! This depends on the obs vertical coordinate
! Obs vertical coordinate will also be converted to the desired
! vertical coordinate as specified by the namelist variable
! "vert_localization_coord" (stored in wrf structure pointer "vert_coord")
if(vert_is_level(location)) then
   ! If obs is by model level: get neighboring mass level indices
   ! and compute weights to zloc
   zloc = xyz_loc(3)
   ! convert obs vert coordinate to desired coordinate type
   if (wrf%dom(id)%vert_coord == VERTISPRESSURE) then
      call toGrid(zloc,k,dz,dzm)

      ! Check that integer indices of Mass grid are in valid ranges for the given
      !   boundary conditions (i.e., periodicity)
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then

         ! Get indices of corners (i,i+1,j,j+1), which depend on periodicities
         call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
         if ( rc .ne. 0 ) &
              print*, 'model_mod.f90 :: vert_interpolate :: getCorners rc = ', rc

         ! need to compute pressure at all neighboring mass points
         ! and interpolate
         presa = model_pressure_t(ll(1), ll(2), k  ,id,x)
         presb = model_pressure_t(ll(1), ll(2), k+1,id,x)
         pres1 = dzm*presa + dz*presb
         presa = model_pressure_t(lr(1), lr(2), k  ,id,x)
         presb = model_pressure_t(lr(1), lr(2), k+1,id,x)
         pres2 = dzm*presa + dz*presb
         presa = model_pressure_t(ul(1), ul(2), k  ,id,x)
         presb = model_pressure_t(ul(1), ul(2), k+1,id,x)
         pres3 = dzm*presa + dz*presb
         presa = model_pressure_t(ur(1), ur(2), k  ,id,x)
         presb = model_pressure_t(ur(1), ur(2), k+1,id,x)
         pres4 = dzm*presa + dz*presb
         zvert = dym*( dxm*pres1 + dx*pres2 ) + dy*( dxm*pres3 + dx*pres4 )

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else
         zloc  = missing_r8
         zvert = missing_r8
      end if

   elseif (wrf%dom(id)%vert_coord == VERTISHEIGHT) then
      ! need to add half a grid to get to staggered vertical coordinate
      call toGrid(zloc+0.5,k,dz,dzm)

      ! Check to make sure retrieved integer gridpoints are in valid range
      if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
           boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
           boundsCheck( k, .false.,                id, dim=3, type=TYPE_GZ ) ) then

         ! Get indices of corners (i,i+1,j,j+1), which depend on periodicities
         call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
         if ( rc .ne. 0 ) &
              print*, 'model_mod.f90 :: vert_interpolate :: getCorners rc = ', rc

         ! need to compute pressure at all neighboring mass points
         ! and interpolate
         hgta = model_height_w(ll(1), ll(2), k  ,id,x)
         hgtb = model_height_w(ll(1), ll(2), k+1,id,x)
         hgt1 = dzm*hgta + dz*hgtb
         hgta = model_height_w(lr(1), lr(2), k  ,id,x)
         hgtb = model_height_w(lr(1), lr(2), k+1,id,x)
         hgt2 = dzm*hgta + dz*hgtb
         hgta = model_height_w(ul(1), ul(2), k  ,id,x)
         hgtb = model_height_w(ul(1), ul(2), k+1,id,x)
         hgt3 = dzm*hgta + dz*hgtb
         hgta = model_height_w(ur(1), ur(2), k  ,id,x)
         hgtb = model_height_w(ur(1), ur(2), k+1,id,x)
         hgt4 = dzm*hgta + dz*hgtb
         zvert = dym*( dxm*hgt1 + dx*hgt2 ) + dy*( dxm*hgt3 + dx*hgt4 )

      ! If the boundsCheck functions return an unsatisfactory integer index, then set
      !   fld as missing data
      else
         zloc  = missing_r8
         zvert = missing_r8
      end if

   ! If not VERTISPRESSURE or VERTISHEIGHT, then either return missing value or set
   !   set zvert equal to zloc if zloc is legally defined (is this right?)
   else
      if ( boundsCheck( k, .false., id, dim=3, type=TYPE_T ) ) then
         zvert = zloc
      else
         zloc  = missing_r8
         zvert = missing_r8
      end if
   end if

elseif(vert_is_pressure(location)) then
   ! If obs is by pressure: get corresponding mass level zk,
   ! then get neighboring mass level indices
   ! and compute weights to zloc
   ! get model pressure profile
   call get_model_pressure_profile(i,j,dx,dy,dxm,dym,wrf%dom(id)%bt,x,id,v_p)
   ! get pressure vertical co-ordinate
   call pres_to_zk(xyz_loc(3), v_p, wrf%dom(id)%bt,zloc)
   ! convert obs vert coordinate to desired coordinate type
   if (zloc==missing_r8) then
      zvert = missing_r8
   else
      if (wrf%dom(id)%vert_coord == VERTISLEVEL) then
         zvert = zloc
      elseif (wrf%dom(id)%vert_coord == VERTISHEIGHT) then
         ! adding 0.5 to get to the staggered vertical grid
         ! because height is on staggered vertical grid
         call toGrid(zloc+0.5,k,dz,dzm)

         ! Check to make sure retrieved integer gridpoints are in valid range
         if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
              boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
              boundsCheck( k, .false.,                id, dim=3, type=TYPE_GZ ) ) then

            ! Get indices of corners (i,i+1,j,j+1), which depend on periodicities
            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: vert_interpolate :: getCorners rc = ', rc

            ! need to compute pressure at all neighboring mass points
            ! and interpolate
            hgta = model_height_w(ll(1), ll(2), k  ,id,x)
            hgtb = model_height_w(ll(1), ll(2), k+1,id,x)
            hgt1 = dzm*hgta + dz*hgtb
            hgta = model_height_w(lr(1), lr(2), k  ,id,x)
            hgtb = model_height_w(lr(1), lr(2), k+1,id,x)
            hgt2 = dzm*hgta + dz*hgtb
            hgta = model_height_w(ul(1), ul(2), k  ,id,x)
            hgtb = model_height_w(ul(1), ul(2), k+1,id,x)
            hgt3 = dzm*hgta + dz*hgtb
            hgta = model_height_w(ur(1), ur(2), k  ,id,x)
            hgtb = model_height_w(ur(1), ur(2), k+1,id,x)
            hgt4 = dzm*hgta + dz*hgtb
            zvert = dym*( dxm*hgt1 + dx*hgt2 ) + dy*( dxm*hgt3 + dx*hgt4 )
            
         ! If the boundsCheck functions return an unsatisfactory integer index, then set
         !   fld as missing data
         else
            zloc  = missing_r8
            zvert = missing_r8
         end if

      else
         ! take pressure directly
         zvert  = xyz_loc(3)
      end if
   end if

elseif(vert_is_height(location)) then
   ! If obs is by height: get corresponding mass level zk,
   ! then get neighboring mass level indices
   ! and compute weights to zloc
   ! get model height profile
   call get_model_height_profile(i,j,dx,dy,dxm,dym,wrf%dom(id)%bt,x,id,v_h)
   ! get height vertical co-ordinate
   call height_to_zk(xyz_loc(3), v_h, wrf%dom(id)%bt,zloc)
   ! convert obs vert coordinate to desired coordinate type
   if (zloc==missing_r8) then
      zvert = missing_r8
   else
      if (wrf%dom(id)%vert_coord == VERTISLEVEL) then
         zvert = zloc
      elseif (wrf%dom(id)%vert_coord == VERTISPRESSURE) then
         call toGrid(zloc,k,dz,dzm)

         ! Check that integer indices of Mass grid are in valid ranges for the given
         !   boundary conditions (i.e., periodicity)
         if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
              boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) .and. &
              boundsCheck( k, .false.,                id, dim=3, type=TYPE_T ) ) then

            ! Get indices of corners (i,i+1,j,j+1), which depend on periodicities
            call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
            if ( rc .ne. 0 ) &
                 print*, 'model_mod.f90 :: vert_interpolate :: getCorners rc = ', rc

            ! need to compute pressure at all neighboring mass points
            ! and interpolate
            presa = model_pressure_t(ll(1), ll(2), k  ,id,x)
            presb = model_pressure_t(ll(1), ll(2), k+1,id,x)
            pres1 = dzm*presa + dz*presb
            presa = model_pressure_t(lr(1), lr(2), k  ,id,x)
            presb = model_pressure_t(lr(1), lr(2), k+1,id,x)
            pres2 = dzm*presa + dz*presb
            presa = model_pressure_t(ul(1), ul(2), k  ,id,x)
            presb = model_pressure_t(ul(1), ul(2), k+1,id,x)
            pres3 = dzm*presa + dz*presb
            presa = model_pressure_t(ur(1), ur(2), k  ,id,x)
            presb = model_pressure_t(ur(1), ur(2), k+1,id,x)
            pres4 = dzm*presa + dz*presb
            zvert = dym*( dxm*pres1 + dx*pres2 ) + dy*( dxm*pres3 + dx*pres4 )

         ! If the boundsCheck functions return an unsatisfactory integer index, then set
         !   fld as missing data
         else
            zloc  = missing_r8
            zvert = missing_r8
         end if

      else
         ! take height directly
         zvert  = xyz_loc(3)
      end if
   end if

!nc -- got rid of ".or. surf_var" from elseif statement here because it can potentially be outdated
!        in its value.  assim_tools_mod calls get_close_obs, which in turn calls vert_interpolate.
!        This calling order can potentially cut model_interpolate out of the loop, and it is only
!        within model_interpolate where surf_var can change its value.
elseif(vert_is_surface(location)) then
   zloc = 1.0_r8
   ! convert obs vert coordinate to desired coordinate type
   if (wrf%dom(id)%vert_coord == VERTISLEVEL) then
      zvert = zloc
   elseif (wrf%dom(id)%vert_coord == VERTISPRESSURE) then
      ! need to compute surface pressure at all neighboring mass points
      ! and interpolate
      call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
      if ( rc .ne. 0 ) &
           print*, 'model_mod.f90 :: vert_interpolate :: getCorners rc = ', rc

      pres1 = model_pressure_s(ll(1), ll(2), id,x)
      pres2 = model_pressure_s(lr(1), lr(2), id,x)
      pres3 = model_pressure_s(ul(1), ul(2), id,x)
      pres4 = model_pressure_s(ur(1), ur(2), id,x)
      zvert = dym*( dxm*pres1 + dx*pres2 ) + dy*( dxm*pres3 + dx*pres4 )
   else
      ! a surface ob is assumed to have height as vertical coordinate...
      ! this may need to be revised if this is not always true (in which
      ! case, just need to uncomment below lines to get terrain height
      ! from model)
      zvert = xyz_loc(3)
      !! directly interpolate terrain height at neighboring mass points
      !zvert = dym*( dxm*wrf%dom(id)%hgt(i,j) + &
      !             dx*wrf%dom(id)%hgt(i+1,j) ) + &
      !        dy*( dxm*wrf%dom(id)%hgt(i,j+1) + &
      !             dx*wrf%dom(id)%hgt(i+1,j+1) )
   endif

elseif(vert_is_undef(location)) then
   zloc  = missing_r8
   zvert = missing_r8

else
   write(errstring,*) 'Vertical coordinate not recognized: ',nint(query_location(location,'which_vert'))
   call error_handler(E_ERR,'vert_interpolate', errstring, &
        source, revision, revdate)

endif

deallocate(v_h, v_p)

if(zvert == missing_r8) istatus = 1

! Reset location   
location = set_location(xyz_loc(1),xyz_loc(2),zvert,wrf%dom(id)%vert_coord)

end subroutine vert_interpolate


!#######################################################################


function get_wrf_index( i,j,k,var_type,id )

integer, intent(in) :: i,j,k,var_type,id

integer :: get_wrf_index
integer :: in

character(len=129) :: errstring

write(errstring,*)'function get_wrf_index should not be called -- still needs updating!'
call error_handler(E_ERR,'get_wrf_index', errstring, &
     source, revision, revdate)

do in = 1, wrf%dom(id)%number_of_wrf_variables
   if(var_type == wrf%dom(id)%var_type(in) ) then
      exit
   endif
enddo

! If one decides to use get_wrf_index, then the following test should be updated
!   to take periodicity into account at the boundaries -- or should it?
if(i >= 1 .and. i <= wrf%dom(id)%var_size(1,in) .and. &
   j >= 1 .and. j <= wrf%dom(id)%var_size(2,in) .and. &
   k >= 1 .and. k <= wrf%dom(id)%var_size(3,in)) then

   get_wrf_index = wrf%dom(id)%dart_ind(i,j,k,var_type)

!!$   get_wrf_index = wrf%dom(id)%var_index(1,in)-1 +   &
!!$        i + wrf%dom(id)%var_size(1,in)*((j-1) + &
!!$        wrf%dom(id)%var_size(2,in)*(k-1))

else

  write(errstring,*)'Indices ',i,j,k,' exceed grid dimensions: ', &
       wrf%dom(id)%var_size(1,in), &
       wrf%dom(id)%var_size(2,in),wrf%dom(id)%var_size(3,in)
  call error_handler(E_ERR,'get_wrf_index', errstring, &
       source, revision, revdate)

endif

end function get_wrf_index


!***********************************************************************


subroutine get_wrf_horizontal_location( i, j, var_type, id, long, lat )

integer,  intent(in)  :: i,j,var_type, id
real(r8), intent(out) :: long, lat

! find lat and long, must
! correct for possible u or v staggering in x, y

if (var_type == type_u) then

   if (i == 1) then
      long = wrf%dom(id)%longitude(1,j) - &
           0.5_r8*(wrf%dom(id)%longitude(2,j)-wrf%dom(id)%longitude(1,j))
      if ( abs(wrf%dom(id)%longitude(2,j) - wrf%dom(id)%longitude(1,j)) > 180.0_r8 ) then
         long = long - 180.0_r8
      endif
      lat = wrf%dom(id)%latitude(1,j) - &
           0.5_r8*(wrf%dom(id)%latitude(2,j)-wrf%dom(id)%latitude(1,j))
   else if (i == wrf%dom(id)%wes) then
      long = wrf%dom(id)%longitude(i-1,j) + &
           0.5_r8*(wrf%dom(id)%longitude(i-1,j)-wrf%dom(id)%longitude(i-2,j))
      if ( abs(wrf%dom(id)%longitude(i-1,j) - wrf%dom(id)%longitude(i-2,j)) > 180.0_r8 ) then
         long = long - 180.0_r8
      endif
      lat = wrf%dom(id)%latitude(i-1,j) + &
           0.5_r8*(wrf%dom(id)%latitude(i-1,j)-wrf%dom(id)%latitude(i-2,j))
   else
      long = 0.5_r8*(wrf%dom(id)%longitude(i,j)+wrf%dom(id)%longitude(i-1,j))
      if ( abs(wrf%dom(id)%longitude(i,j) - wrf%dom(id)%longitude(i-1,j)) > 180.0_r8 ) then
         long = long - 180.0_r8
      endif
      lat = 0.5_r8*(wrf%dom(id)%latitude(i,j) +wrf%dom(id)%latitude(i-1,j))
   end if

elseif (var_type == type_v) then

   if (j == 1) then
      long = wrf%dom(id)%longitude(i,1) - &
           0.5_r8*(wrf%dom(id)%longitude(i,2)-wrf%dom(id)%longitude(i,1))
      if ( abs(wrf%dom(id)%longitude(i,2) - wrf%dom(id)%longitude(i,1)) > 180.0_r8 ) then
         long = long - 180.0_r8
      endif
      lat = wrf%dom(id)%latitude(i,1) - &
           0.5_r8*(wrf%dom(id)%latitude(i,2)-wrf%dom(id)%latitude(i,1))
   else if (j == wrf%dom(id)%sns) then
      long = wrf%dom(id)%longitude(i,j-1) + &
           0.5_r8*(wrf%dom(id)%longitude(i,j-1)-wrf%dom(id)%longitude(i,j-2))
      if ( abs(wrf%dom(id)%longitude(i,j-1) - wrf%dom(id)%longitude(i,j-2)) > 180.0_r8 ) then
         long = long - 180.0_r8
      endif
      lat = wrf%dom(id)%latitude(i,j-1) + &
           0.5_r8*(wrf%dom(id)%latitude(i,j-1)-wrf%dom(id)%latitude(i,j-2))
   else
      long = 0.5_r8*(wrf%dom(id)%longitude(i,j)+wrf%dom(id)%longitude(i,j-1))
      if ( abs(wrf%dom(id)%longitude(i,j) - wrf%dom(id)%longitude(i,j-1)) > 180.0_r8 ) then
         long = long - 180.0_r8
      endif
      lat  = 0.5_r8*(wrf%dom(id)%latitude(i,j) +wrf%dom(id)%latitude(i,j-1))

   end if

else

   long = wrf%dom(id)%longitude(i,j)
   lat  = wrf%dom(id)%latitude(i,j)

end if

do while (long <   0.0_r8)
   long = long + 360.0_r8
end do
do while (long > 360.0_r8)
   long = long - 360.0_r8
end do

end subroutine get_wrf_horizontal_location



!***********************************************************************


function nc_write_model_atts( ncFileID ) result (ierr)
!-----------------------------------------------------------------
! Writes the model-specific attributes to a netCDF file
! A. Caya May 7 2003
! T. Hoar Mar 8 2004 writes prognostic flavor

integer, intent(in)  :: ncFileID      ! netCDF file identifier
integer              :: ierr          ! return value of function

!-----------------------------------------------------------------

integer :: nDimensions, nVariables, nAttributes, unlimitedDimID
integer :: StateVarDimID, StateVarVarID, StateVarID, TimeDimID

integer, dimension(num_domains) :: weDimID, weStagDimID, snDimID, snStagDimID, &
     btDimID, btStagDimID, slSDimID, tmp

integer :: MemberDimID, DomDimID
integer :: DXVarID, DYVarID, TRUELAT1VarID, TRUELAT2VarID
integer :: CEN_LATVarID, CEN_LONVarID, MAP_PROJVarID
integer :: PERIODIC_XVarID, POLARVarID

integer, dimension(num_domains) :: DNVarID, ZNUVarID, DNWVarID, phbVarID, &
     MubVarID, LonVarID, LatVarID, ilevVarID, XlandVarID, hgtVarID 

! currently unused, but if needed could be added back in.  these fields
! only appear to be supported in certain projections, so the code should
! test to be sure they exist before trying to read them from the netcdf file.
!integer, dimension(num_domains) :: MapFacMVarID, MapFacUVarID, MapFacVVarID

integer :: var_id
integer :: i, id

character(len=129) :: errstring

character(len=8)      :: crdate      ! needed by F90 DATE_AND_TIME intrinsic
character(len=10)     :: crtime      ! needed by F90 DATE_AND_TIME intrinsic
character(len=5)      :: crzone      ! needed by F90 DATE_AND_TIME intrinsic
integer, dimension(8) :: values      ! needed by F90 DATE_AND_TIME intrinsic
character(len=NF90_MAX_NAME) :: str1

character (len=1)     :: idom

!-----------------------------------------------------------------

ierr = 0     ! assume normal termination

!-----------------------------------------------------------------
! make sure ncFileID refers to an open netCDF file, 
! and then put into define mode.
!-----------------------------------------------------------------

call check(nf90_Inquire(ncFileID, nDimensions, nVariables, nAttributes, unlimitedDimID))
call check(nf90_Redef(ncFileID))

!-----------------------------------------------------------------
! We need the dimension ID for the number of copies 
!-----------------------------------------------------------------

call check(nf90_inq_dimid(ncid=ncFileID, name="copy", dimid=MemberDimID))
call check(nf90_inq_dimid(ncid=ncFileID, name="time", dimid=  TimeDimID))

if ( TimeDimID /= unlimitedDimId ) then
   write(errstring,*)'Time Dimension ID ',TimeDimID, &
        ' must match Unlimited Dimension ID ',unlimitedDimID
   call error_handler(E_ERR,'nc_write_model_atts', errstring, source, revision, revdate)
endif

!-----------------------------------------------------------------
! Define the model size, state variable dimension ... whatever ...
!-----------------------------------------------------------------
call check(nf90_def_dim(ncid=ncFileID, name="StateVariable", &
                        len=wrf%model_size, dimid = StateVarDimID))

!-----------------------------------------------------------------
! Write Global Attributes 
!-----------------------------------------------------------------
call DATE_AND_TIME(crdate,crtime,crzone,values)
write(str1,'(''YYYY MM DD HH MM SS = '',i4,5(1x,i2.2))') &
                  values(1), values(2), values(3), values(5), values(6), values(7)

call check(nf90_put_att(ncFileID, NF90_GLOBAL, "creation_date",str1))
call check(nf90_put_att(ncFileID, NF90_GLOBAL, "model","WRF"))
call check(nf90_put_att(ncFileID, NF90_GLOBAL, "model_source",source))
call check(nf90_put_att(ncFileID, NF90_GLOBAL, "model_revision",revision))
call check(nf90_put_att(ncFileID, NF90_GLOBAL, "model_revdate",revdate))

! how about namelist input? might be nice to save ...

!-----------------------------------------------------------------
! Define the dimensions IDs
!-----------------------------------------------------------------

call check(nf90_def_dim(ncid=ncFileID, name="domain",           &
          len = num_domains,  dimid = DomDimID))

do id=1,num_domains
   write( idom , '(I1)') id
   call check(nf90_def_dim(ncid=ncFileID, name="west_east_d0"//idom,        &
        len = wrf%dom(id)%we,  dimid = weDimID(id)))
   call check(nf90_def_dim(ncid=ncFileID, name="west_east_stag_d0"//idom,   &
        len = wrf%dom(id)%wes, dimid = weStagDimID(id)))
   call check(nf90_def_dim(ncid=ncFileID, name="south_north_d0"//idom,      &
        len = wrf%dom(id)%sn,  dimid = snDimID(id)))
   call check(nf90_def_dim(ncid=ncFileID, name="south_north_stag_d0"//idom, &
        len = wrf%dom(id)%sns, dimid = snStagDimID(id)))
   call check(nf90_def_dim(ncid=ncFileID, name="bottom_top_d0"//idom,       &
        len = wrf%dom(id)%bt,  dimid = btDimID(id)))
   call check(nf90_def_dim(ncid=ncFileID, name="bottom_top_stag_d0"//idom,  &
        len = wrf%dom(id)%bts, dimid = btStagDimID(id)))
   call check(nf90_def_dim(ncid=ncFileID, name="soil_layers_stag_d0"//idom,  &
        len = wrf%dom(id)%sls, dimid = slSDimID(id)))
enddo

!-----------------------------------------------------------------
! Create the (empty) Variables and the Attributes
!-----------------------------------------------------------------

!-----------------------------------------------------------------
! Create the (empty) static variables and their attributes
! Commented block is from wrfinput
!-----------------------------------------------------------------

call check(nf90_def_var(ncFileID, name="DX", xtype=nf90_real, &
     dimids= DomDimID, varid=DXVarID) )
call check(nf90_put_att(ncFileID, DXVarID, "long_name", &
     "X HORIZONTAL RESOLUTION"))
call check(nf90_put_att(ncFileID, DXVarID, "units", "m"))

call check(nf90_def_var(ncFileID, name="DY", xtype=nf90_real, &
     dimids= DomDimID, varid=DYVarID) )
call check(nf90_put_att(ncFileID, DYVarID, "long_name", &
     "Y HORIZONTAL RESOLUTION"))
call check(nf90_put_att(ncFileID, DYVarID, "units", "m"))

call check(nf90_def_var(ncFileID, name="TRUELAT1", xtype=nf90_real, &
     dimids= DomDimID, varid=TRUELAT1VarID) )
call check(nf90_put_att(ncFileID, TRUELAT1VarID, "long_name", &
     "first standard parallel"))
call check(nf90_put_att(ncFileID, TRUELAT1VarID, "units", &
     "degrees, negative is south"))

call check(nf90_def_var(ncFileID, name="TRUELAT2", xtype=nf90_real, &
     dimids= DomDimID, varid=TRUELAT2VarID) )
call check(nf90_put_att(ncFileID, TRUELAT2VarID, "long_name", &
     "second standard parallel"))
call check(nf90_put_att(ncFileID, TRUELAT2VarID, "units", &
     "degrees, negative is south"))

call check(nf90_def_var(ncFileID, name="CEN_LAT", xtype=nf90_real, &
     dimids= DomDimID, varid=CEN_LATVarID) )
call check(nf90_put_att(ncFileID, CEN_LATVarID, "long_name", &
     "center latitude"))
call check(nf90_put_att(ncFileID, CEN_LATVarID, "units", &
     "degrees, negative is south"))

call check(nf90_def_var(ncFileID, name="CEN_LON", xtype=nf90_real, &
     dimids= DomDimID, varid=CEN_LONVarID) )
call check(nf90_put_att(ncFileID, CEN_LONVarID, "long_name", &
     "central longitude"))
call check(nf90_put_att(ncFileID, CEN_LONVarID, "units", &
     "degrees, negative is west"))

call check(nf90_def_var(ncFileID, name="MAP_PROJ", xtype=nf90_real, &
     dimids= DomDimID, varid=MAP_PROJVarID) )
call check(nf90_put_att(ncFileID, MAP_PROJVarID, "long_name", &
     "domain map projection"))
call check(nf90_put_att(ncFileID, MAP_PROJVarID, "units", &
     "0=none, 1=Lambert, 2=polar, 3=Mercator, 5=Cylindrical, 6=Cassini"))

!nc -- we need to add in code here to report the domain values for the 
!        boundary condition flags periodic_x and polar.  Since these are
!        carried internally as logicals, they will first need to be 
!        converted back to integers.
call check(nf90_def_var(ncFileID, name="PERIODIC_X", xtype=nf90_int, &
     dimids= DomDimID, varid=PERIODIC_XVarID) )
call check(nf90_put_att(ncFileID, PERIODIC_XVarID, "long_name", &
     "Longitudinal periodic b.c. flag"))
call check(nf90_put_att(ncFileID, PERIODIC_XVarID, "units", &
     "logical: 1 = .true., 0 = .false."))

call check(nf90_def_var(ncFileID, name="POLAR", xtype=nf90_int, &
     dimids= DomDimID, varid=POLARVarID) )
call check(nf90_put_att(ncFileID, POLARVarID, "long_name", &
     "Polar periodic b.c. flag"))
call check(nf90_put_att(ncFileID, POLARVarID, "units", &
     "logical: 1 = .true., 0 = .false."))



do id=1,num_domains
   write( idom , '(I1)') id

   call check(nf90_def_var(ncFileID, name="DN_d0"//idom, xtype=nf90_real, &
        dimids= btDimID(id), varid=DNVarID(id)) )
   call check(nf90_put_att(ncFileID, DNVarID(id), "long_name", &
        "dn values on half (mass) levels"))
   call check(nf90_put_att(ncFileID, DNVarID(id), "units", "dimensionless"))

   call check(nf90_def_var(ncFileID, name="ZNU_d0"//idom, xtype=nf90_real, &
        dimids= btDimID(id), varid=ZNUVarID(id)) )
   call check(nf90_put_att(ncFileID, ZNUVarID(id), "long_name", &
        "eta values on half (mass) levels"))
   call check(nf90_put_att(ncFileID, ZNUVarID(id), "units", "dimensionless"))

   call check(nf90_def_var(ncFileID, name="DNW_d0"//idom, xtype=nf90_real, &
        dimids= btDimID(id), varid=DNWVarID(id)) )
   call check(nf90_put_att(ncFileID, DNWVarID(id), "long_name", &
        "dn values on full (w) levels"))
   call check(nf90_put_att(ncFileID, DNWVarID(id), "units", "dimensionless"))

!
!    float MUB(Time, south_north, west_east) ;
!            MUB:FieldType = 104 ;
!            MUB:MemoryOrder = "XY " ;
!            MUB:stagger = "" ;
   call check(nf90_def_var(ncFileID, name="MUB_d0"//idom, xtype=nf90_real, &
        dimids= (/ weDimID(id), snDimID(id) /), varid=MubVarID(id)) )
   call check(nf90_put_att(ncFileID, MubVarID(id), "long_name", &
        "base state dry air mass in column"))
   call check(nf90_put_att(ncFileID, MubVarID(id), "units", "Pa"))

! Longitudes
!      float XLONG(Time, south_north, west_east) ;
!         XLONG:FieldType = 104 ;
!         XLONG:MemoryOrder = "XY " ;
!         XLONG:stagger = "" ;
   call check(nf90_def_var(ncFileID, name="XLON_d0"//idom, xtype=nf90_real, &
        dimids= (/ weDimID(id), snDimID(id) /), varid=LonVarID(id)) )
   call check(nf90_put_att(ncFileID, LonVarID(id), "long_name", "longitude"))
   call check(nf90_put_att(ncFileID, LonVarID(id), "units", "degrees_east"))
   call check(nf90_put_att(ncFileID, LonVarID(id), "valid_range", &
        (/ -180.0_r8, 180.0_r8 /)))
   call check(nf90_put_att(ncFileID, LonVarID(id), "description", &
        "LONGITUDE, WEST IS NEGATIVE"))

! Latitudes
!      float XLAT(Time, south_north, west_east) ;
!         XLAT:FieldType = 104 ;
!         XLAT:MemoryOrder = "XY " ;
!         XLAT:stagger = "" ;
   call check(nf90_def_var(ncFileID, name="XLAT_d0"//idom, xtype=nf90_real, &
        dimids=(/ weDimID(id), snDimID(id) /), varid=LatVarID(id)) ) 
   call check(nf90_put_att(ncFileID, LatVarID(id), "long_name", "latitude"))
   call check(nf90_put_att(ncFileID, LatVarID(id), "units", "degrees_north"))
   call check(nf90_put_att(ncFileID, LatVarID(id), "valid_range", &
        (/ -90.0_r8, 90.0_r8 /)))
   call check(nf90_put_att(ncFileID, LatVarID(id), "description", &
        "LATITUDE, SOUTH IS NEGATIVE"))

! grid levels
   call check(nf90_def_var(ncFileID, name="level_d0"//idom, xtype=nf90_short, &
        dimids=btDimID(id), varid=ilevVarID(id)) )
   call check(nf90_put_att(ncFileID, ilevVarID(id), "long_name", &
        "placeholder for level"))
   call check(nf90_put_att(ncFileID, ilevVarID(id), "units", &
        "at this point, indexical"))

! Land Mask
!    float XLAND(Time, south_north, west_east) ;
!            XLAND:FieldType = 104 ;
!            XLAND:MemoryOrder = "XY " ;
!            XLAND:units = "NA" ;
!            XLAND:stagger = "" ;
   call check(nf90_def_var(ncFileID, name="XLAND_d0"//idom, xtype=nf90_short, &
        dimids= (/ weDimID(id), snDimID(id) /), varid=XlandVarID(id)) )
   call check(nf90_put_att(ncFileID, XlandVarID(id), "long_name", "land mask"))
   call check(nf90_put_att(ncFileID, XlandVarID(id), "units", "NA"))
   call check(nf90_put_att(ncFileID, XlandVarID(id), "valid_range", (/ 1, 2 /)))
   call check(nf90_put_att(ncFileID, XlandVarID(id), "description", &
        "1 = LAND, 2 = WATER"))

!nc -- eliminated the reading in of MAPFACs since global WRF will have different 
!nc --   MAPFACs in the x and y directions

! Map Scale Factor on m-grid
!    float MAPFAC_M(Time, south_north, west_east) ;
!            MAPFAC_M:FieldType = 104 ;
!            MAPFAC_M:MemoryOrder = "XY " ;
!            MAPFAC_M:stagger = "" ;
!   call check(nf90_def_var(ncFileID, name="MAPFAC_M_d0"//idom, xtype=nf90_real, &
!        dimids= (/ weDimID(id), snDimID(id) /), varid=MapFacMVarID(id)) )
!   call check(nf90_put_att(ncFileID, MapFacMVarID(id), "long_name", &
!       "Map scale factor on mass grid"))
!   call check(nf90_put_att(ncFileID, MapFacMVarID(id), "units", "dimensionless"))

! Map Scale Factor on u-grid
!    float MAPFAC_U(Time, south_north, west_east_stag) ;
!            MAPFAC_U:FieldType = 104 ;
!            MAPFAC_U:MemoryOrder = "XY " ;
!            MAPFAC_U:stagger = "X" ;
!   call check(nf90_def_var(ncFileID, name="MAPFAC_U_d0"//idom, xtype=nf90_real, &
!        dimids= (/ weStagDimID(id), snDimID(id) /), varid=MapFacUVarID(id)) )
!   call check(nf90_put_att(ncFileID, MapFacUVarID(id), "long_name", &
!        "Map scale factor on u-grid"))
!   call check(nf90_put_att(ncFileID, MapFacUVarID(id), "units", "dimensionless"))

! Map Scale Factor on v-grid
!    float MAPFAC_V(Time, south_north_stag, west_east) ;
!            MAPFAC_V:FieldType = 104 ;
!            MAPFAC_V:MemoryOrder = "XY " ;
!            MAPFAC_V:stagger = "Y" ;
!   call check(nf90_def_var(ncFileID, name="MAPFAC_V_d0"//idom, xtype=nf90_real, &
!        dimids= (/ weDimID(id), snStagDimID(id) /), varid=MapFacVVarID(id)) )
!   call check(nf90_put_att(ncFileID, MapFacVVarID(id), "long_name", &
!        "Map scale factor on v-grid"))
!   call check(nf90_put_att(ncFileID, MapFacVVarID(id), "units", "dimensionless"))

! PHB
!    float PHB(Time, bottom_top_stag, south_north, west_east) ;
!            PHB:FieldType = 104 ;
!            PHB:MemoryOrder = "XYZ" ;
!            PHB:stagger = "Z" ;
   call check(nf90_def_var(ncFileID, name="PHB_d0"//idom, xtype=nf90_real, &
        dimids= (/ weDimID(id), snDimID(id), btStagDimID(id) /), varid=phbVarId(id)) )
   call check(nf90_put_att(ncFileID, phbVarId(id), "long_name", &
        "base-state geopotential"))
   call check(nf90_put_att(ncFileID, phbVarId(id), "units", "m2/s2"))
   call check(nf90_put_att(ncFileID, phbVarId(id), "units_long_name", "m{2} s{-2}"))

   call check(nf90_def_var(ncFileID, name="HGT_d0"//idom, xtype=nf90_real, &
        dimids= (/ weDimID(id), snDimID(id) /), varid=hgtVarId(id)) )
   call check(nf90_put_att(ncFileID, hgtVarId(id), "long_name", "Terrain Height"))
   call check(nf90_put_att(ncFileID, hgtVarId(id), "units", "m"))
   call check(nf90_put_att(ncFileID, hgtVarId(id), "units_long_name", "meters"))

enddo

if ( output_state_vector ) then

   !-----------------------------------------------------------------
   ! Create attributes for the state vector 
   !-----------------------------------------------------------------

   ! Define the state vector coordinate variable

   call check(nf90_def_var(ncid=ncFileID,name="StateVariable", xtype=nf90_int, &
              dimids=StateVarDimID, varid=StateVarVarID))

   call check(nf90_put_att(ncFileID, StateVarVarID, "long_name", &
        "State Variable ID"))
   call check(nf90_put_att(ncFileID, StateVarVarID, "units", &
        "indexical") )
   call check(nf90_put_att(ncFileID, StateVarVarID, "valid_range", &
        (/ 1, wrf%model_size /)))

   ! Define the actual state vector

   call check(nf90_def_var(ncid=ncFileID, name="state", xtype=nf90_real, &
              dimids = (/ StateVarDimID, MemberDimID, unlimitedDimID /), &
              varid=StateVarID))
   call check(nf90_put_att(ncFileID, StateVarID, "long_name", &
        "model state or fcopy"))
   call check(nf90_put_att(ncFileID, StateVarId, "U_units","m/s"))
   call check(nf90_put_att(ncFileID, StateVarId, "V_units","m/s"))
   call check(nf90_put_att(ncFileID, StateVarId, "W_units","m/s"))
   call check(nf90_put_att(ncFileID, StateVarId, "GZ_units","m2/s2"))
   call check(nf90_put_att(ncFileID, StateVarId, "T_units","K"))
   call check(nf90_put_att(ncFileID, StateVarId, "MU_units","Pa"))
   call check(nf90_put_att(ncFileID, StateVarId, "TSK_units","K"))
   if( wrf%dom(num_domains)%n_moist >= 1) then
      call check(nf90_put_att(ncFileID, StateVarId, "QV_units","kg/kg"))
   endif
   if( wrf%dom(num_domains)%n_moist >= 2) then
      call check(nf90_put_att(ncFileID, StateVarId, "QC_units","kg/kg"))
   endif
   if( wrf%dom(num_domains)%n_moist >= 3) then
      call check(nf90_put_att(ncFileID, StateVarId, "QR_units","kg/kg"))
   endif
   if( wrf%dom(num_domains)%n_moist >= 4) then
      call check(nf90_put_att(ncFileID, StateVarId, "QI_units","kg/kg"))
   endif
   if( wrf%dom(num_domains)%n_moist >= 5) then
      call check(nf90_put_att(ncFileID, StateVarId, "QS_units","kg/kg"))
   endif
   if( wrf%dom(num_domains)%n_moist >= 6) then
      call check(nf90_put_att(ncFileID, StateVarId, "QG_units","kg/kg"))
   endif
   if( wrf%dom(num_domains)%n_moist == 7) then
      call check(nf90_put_att(ncFileID, StateVarId, "QNICE_units","kg-1"))
   endif
   if(wrf%dom(num_domains)%surf_obs ) then
      call check(nf90_put_att(ncFileID, StateVarId, "U10_units","m/s"))
      call check(nf90_put_att(ncFileID, StateVarId, "V10_units","m/s"))
      call check(nf90_put_att(ncFileID, StateVarId, "T2_units","K"))
      call check(nf90_put_att(ncFileID, StateVarId, "TH2_units","K"))
      call check(nf90_put_att(ncFileID, StateVarId, "Q2_units","kg/kg"))
      call check(nf90_put_att(ncFileID, StateVarId, "PS_units","Pa"))
   endif
   if(wrf%dom(num_domains)%soil_data ) then
      call check(nf90_put_att(ncFileID, StateVarId, "TSLB_units","K"))
      call check(nf90_put_att(ncFileID, StateVarId, "SMOIS_units","m3/m3"))
      call check(nf90_put_att(ncFileID, StateVarId, "SH2O_units","m3/m3"))
   endif
   if(h_diab ) then
      call check(nf90_put_att(ncFileID, StateVarId, "H_DIAB_units",""))
   endif

   ! Leave define mode so we can actually fill the variables.

   call check(nf90_enddef(ncfileID))

   call check(nf90_put_var(ncFileID, StateVarVarID, &
        (/ (i,i=1,wrf%model_size) /) ))

else

do id=1,num_domains
   write( idom , '(I1)') id

   !----------------------------------------------------------------------------
   ! Create the (empty) Prognostic Variables and their attributes
   !----------------------------------------------------------------------------

   !      float U(Time, bottom_top, south_north, west_east_stag) ;
   !         U:FieldType = 104 ;
   !         U:MemoryOrder = "XYZ" ;
   !         U:stagger = "X" ;
   call check(nf90_def_var(ncid=ncFileID, name="U_d0"//idom, xtype=nf90_real, &
         dimids = (/ weStagDimID(id), snDimId(id), btDimID(id), MemberDimID, &
         unlimitedDimID /), varid  = var_id))
   call check(nf90_put_att(ncFileID, var_id, "long_name", "x-wind component"))
   call check(nf90_put_att(ncFileID, var_id, "units", "m/s"))
   call check(nf90_put_att(ncFileID, var_id, "units_long_name", "m s{-1}"))


   !      float V(Time, bottom_top, south_north_stag, west_east) ;
   !         V:FieldType = 104 ;
   !         V:MemoryOrder = "XYZ" ;
   !         V:stagger = "Y" ;
   call check(nf90_def_var(ncid=ncFileID, name="V_d0"//idom, xtype=nf90_real, &
         dimids = (/ weDimID(id), snStagDimID(id), btDimID(id), MemberDimID, &
         unlimitedDimID /), varid  = var_id))
   call check(nf90_put_att(ncFileID, var_id, "long_name", "y-wind component"))
   call check(nf90_put_att(ncFileID, var_id, "units", "m/s"))
   call check(nf90_put_att(ncFileID, var_id, "units_long_name", "m s{-1}"))


   !      float W(Time, bottom_top_stag, south_north, west_east) ;
   !         W:FieldType = 104 ;
   !         W:MemoryOrder = "XYZ" ;
   !         W:stagger = "Z" ;
   call check(nf90_def_var(ncid=ncFileID, name="W_d0"//idom, xtype=nf90_real, &
         dimids = (/ weDimID(id), snDimID(id), btStagDimID(id), MemberDimID, &
         unlimitedDimID /), varid  = var_id))
   call check(nf90_put_att(ncFileID, var_id, "long_name", "z-wind component"))
   call check(nf90_put_att(ncFileID, var_id, "units", "m/s"))
   call check(nf90_put_att(ncFileID, var_id, "units_long_name", "m s{-1}"))


   !      float PH(Time, bottom_top_stag, south_north, west_east) ;
   !         PH:FieldType = 104 ;
   !         PH:MemoryOrder = "XYZ" ;
   !         PH:stagger = "Z" ;
   call check(nf90_def_var(ncid=ncFileID, name="PH_d0"//idom, xtype=nf90_real, &
         dimids = (/ weDimID(id), snDimID(id), btStagDimID(id), MemberDimID, &
         unlimitedDimID /), varid  = var_id))
   call check(nf90_put_att(ncFileID, var_id, "long_name", &
        "perturbation geopotential"))
   call check(nf90_put_att(ncFileID, var_id, "units", "m2/s2"))
   call check(nf90_put_att(ncFileID, var_id, "units_long_name", "m{2} s{-2}"))


   !      float T(Time, bottom_top, south_north, west_east) ;
   !         T:FieldType = 104 ;
   !         T:MemoryOrder = "XYZ" ;
   !         T:units = "K" ;
   !         T:stagger = "" ;
   call check(nf90_def_var(ncid=ncFileID, name="T_d0"//idom, xtype=nf90_real, &
         dimids = (/ weDimID(id), snDimID(id), btDimID(id), MemberDimID, &
         unlimitedDimID /), varid  = var_id))
   call check(nf90_put_att(ncFileID, var_id, "long_name", "temperature"))
   call check(nf90_put_att(ncFileID, var_id, "units", "K"))
   call check(nf90_put_att(ncFileId, var_id, "description", &
        "perturbation potential temperature (theta-t0)"))


   !      float MU(Time, south_north, west_east) ;
   !         MU:FieldType = 104 ;
   !         MU:MemoryOrder = "XY " ;
   !         MU:description = "perturbation dry air mass in column" ;
   !         MU:units = "pascals" ;
   !         MU:stagger = "" ;
   call check(nf90_def_var(ncid=ncFileID, name="MU_d0"//idom, xtype=nf90_real, &
         dimids = (/ weDimID(id), snDimID(id), MemberDimID, &
         unlimitedDimID /), varid  = var_id))
   call check(nf90_put_att(ncFileID, var_id, "long_name", "mu field"))
   call check(nf90_put_att(ncFileID, var_id, "units", "pascals"))
   call check(nf90_put_att(ncFileId, var_id, "description", &
        "perturbation dry air mass in column"))


   !      float TSK(Time, south_north, west_east) ;
   !         TSK:FieldType = 104 ;
   !         TSK:MemoryOrder = "XY " ;
   !         TSK:description = "SURFACE SKIN TEMPERATURE" ;
   !         TSK:units = "K" ;
   !         TSK:stagger = "" ;
   call check(nf90_def_var(ncid=ncFileID, name="TSK_d0"//idom, xtype=nf90_real, &
         dimids = (/ weDimID(id), snDimID(id), MemberDimID, &
         unlimitedDimID /), varid  = var_id))
   call check(nf90_put_att(ncFileID, var_id, "long_name", "tsk field"))
   call check(nf90_put_att(ncFileID, var_id, "units", "K"))
   call check(nf90_put_att(ncFileId, var_id, "description", &
        "SURFACE SKIN TEMPERATURE"))


   !      float QVAPOR(Time, bottom_top, south_north, west_east) ;
   !         QVAPOR:FieldType = 104 ;
   !         QVAPOR:MemoryOrder = "XYZ" ;
   !         QVAPOR:stagger = "" ;
   if( wrf%dom(id)%n_moist >= 1) then
      call check(nf90_def_var(ncid=ncFileID, name="QVAPOR_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), btDimID(id), MemberDimID, &
           unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "kg/kg"))
      call check(nf90_put_att(ncFileId, var_id, "description", &
           "Water vapor mixing ratio"))
   endif


   !      float QCLOUD(Time, bottom_top, south_north, west_east) ;
   !         QCLOUD:FieldType = 104 ;
   !         QCLOUD:MemoryOrder = "XYZ" ;
   !         QCLOUD:stagger = "" ;
   if( wrf%dom(id)%n_moist >= 2) then
      call check(nf90_def_var(ncid=ncFileID, name="QCLOUD_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), btDimID(id), MemberDimID, &
           unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "kg/kg"))
      call check(nf90_put_att(ncFileID, var_id, "description", &
           "Cloud water mixing ratio"))
   endif


   !      float QRAIN(Time, bottom_top, south_north, west_east) ;
   !         QRAIN:FieldType = 104 ;
   !         QRAIN:MemoryOrder = "XYZ" ;
   !         QRAIN:stagger = "" ;
   if( wrf%dom(id)%n_moist >= 3) then
      call check(nf90_def_var(ncid=ncFileID, name="QRAIN_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), btDimID(id), MemberDimID, &
           unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "kg/kg"))
      call check(nf90_put_att(ncFileID, var_id, "description", &
           "Rain water mixing ratio"))
   endif

   if( wrf%dom(id)%n_moist >= 4) then
      call check(nf90_def_var(ncid=ncFileID, name="QICE_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), btDimID(id), MemberDimID, &
           unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "kg/kg"))
      call check(nf90_put_att(ncFileID, var_id, "description", &
           "Ice mixing ratio"))
   endif

   if( wrf%dom(id)%n_moist >= 5) then
      call check(nf90_def_var(ncid=ncFileID, name="QSNOW_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), btDimID(id), MemberDimID, &
           unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "kg/kg"))
      call check(nf90_put_att(ncFileID, var_id, &
           "description", "Snow mixing ratio"))
   endif

   if( wrf%dom(id)%n_moist >= 6) then
      call check(nf90_def_var(ncid=ncFileID, name="QGRAUP_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), btDimID(id), MemberDimID, &
           unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "kg/kg"))
      call check(nf90_put_att(ncFileID, var_id, "description", &
           "Graupel mixing ratio"))
   endif

   if( wrf%dom(id)%n_moist == 7) then
      call check(nf90_def_var(ncid=ncFileID, name="QNICE_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), btDimID(id), MemberDimID, &
           unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "kg-1"))
      call check(nf90_put_att(ncFileID, var_id, "description", &
           "Ice Number concentration"))
   endif

   if(wrf%dom(id)%surf_obs ) then

      call check(nf90_def_var(ncid=ncFileID, name="U10_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), MemberDimID, unlimitedDimID /), &
           varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "m/s"))
      call check(nf90_put_att(ncFileID, var_id, "description", "U at 10 m"))

      call check(nf90_def_var(ncid=ncFileID, name="V10_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), MemberDimID, unlimitedDimID /), &
           varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "m/s"))
      call check(nf90_put_att(ncFileID, var_id, "description", "V at 10 m"))

      call check(nf90_def_var(ncid=ncFileID, name="T2_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), MemberDimID, unlimitedDimID /), &
           varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "K"))
      call check(nf90_put_att(ncFileID, var_id, "description", "TEMP at 2 m"))

      call check(nf90_def_var(ncid=ncFileID, name="TH2_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), MemberDimID, unlimitedDimID /), &
           varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "K"))
      call check(nf90_put_att(ncFileID, var_id, "description", "POT TEMP at 2 m"))

      call check(nf90_def_var(ncid=ncFileID, name="Q2_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), MemberDimID, unlimitedDimID /), &
           varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "kg/kg"))
      call check(nf90_put_att(ncFileID, var_id, "description", "QV at 2 m"))

      call check(nf90_def_var(ncid=ncFileID, name="PS_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), MemberDimID, unlimitedDimID /), &
           varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "units", "Pa"))
      call check(nf90_put_att(ncFileID, var_id, "description", "Total surface pressure"))

   end if

   if(wrf%dom(id)%soil_data) then   
      !      float TSLB(Time, soil_layers_stag, south_north, west_east) ;
      !         TSLB:FieldType = 104 ;
      !         TSLB:MemoryOrder = "XYZ" ;
      !         TSLB:description = "SOIL TEMPERATURE" ;
      !         TSLB:units = "K" ;
      !         TSLB:stagger = "Z" ;
      call check(nf90_def_var(ncid=ncFileID, name="TSLB_d0"//idom, xtype=nf90_real, &
           dimids = (/ weDimID(id), snDimID(id), slSDimID(id), MemberDimID, &
           unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "long_name", "soil temperature"))
      call check(nf90_put_att(ncFileID, var_id, "units", "K"))
      call check(nf90_put_att(ncFileId, var_id, "description", &
           "SOIL TEMPERATURE"))
           
      call check(nf90_def_var(ncid=ncFileID, name="SMOIS_d0"//idom, xtype=nf90_real, &
            dimids = (/ weDimID(id), snDimID(id), slSDimID(id), MemberDimID, &
            unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "long_name", "soil moisture"))
      call check(nf90_put_att(ncFileID, var_id, "units", "m3/m3"))
      call check(nf90_put_att(ncFileId, var_id, "description", &
           "SOIL MOISTURE"))

      call check(nf90_def_var(ncid=ncFileID, name="SH2O_d0"//idom, xtype=nf90_real, &
            dimids = (/ weDimID(id), snDimID(id), slSDimID(id), MemberDimID, &
            unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "long_name", "soil liquid water"))
      call check(nf90_put_att(ncFileID, var_id, "units", "m3/m3"))
      call check(nf90_put_att(ncFileId, var_id, "description", &
           "SOIL LIQUID WATER"))

   endif

   if(h_diab ) then
      !    float H_DIABATIC(Time, bottom_top, south_north, west_east) ;
      !            H_DIABATIC:FieldType = 104 ;
      !            H_DIABATIC:MemoryOrder = "XYZ" ;
      !            H_DIABATIC:description = "PREVIOUS TIMESTEP CONDENSATIONAL HEATING" ;
      !            H_DIABATIC:units = "" ;
      !            H_DIABATIC:stagger = "" ;
      call check(nf90_def_var(ncid=ncFileID, name="H_DIAB_d0"//idom, xtype=nf90_real, &
            dimids = (/ weDimID(id), snDimID(id), btDimID(id), MemberDimID, &
            unlimitedDimID /), varid  = var_id))
      call check(nf90_put_att(ncFileID, var_id, "long_name", "diabatic heating"))
      call check(nf90_put_att(ncFileID, var_id, "units", ""))
      call check(nf90_put_att(ncFileID, var_id, "FieldType", 104))
      call check(nf90_put_att(ncFileID, var_id, "MemoryOrder", "XYZ"))
      call check(nf90_put_att(ncFileID, var_id, "stagger", ""))
      call check(nf90_put_att(ncFileId, var_id, "description", &
           "previous timestep condensational heating"))
   endif

enddo

endif

!-----------------------------------------------------------------
! Fill the variables we can
!-----------------------------------------------------------------
call check(nf90_enddef(ncfileID))

call check(nf90_put_var(ncFileID,       DXVarID, wrf%dom(1:num_domains)%dx        ))
call check(nf90_put_var(ncFileID,       DYVarID, wrf%dom(1:num_domains)%dy        ))
call check(nf90_put_var(ncFileID, TRUELAT1VarID, wrf%dom(1:num_domains)%proj%truelat1  ))
call check(nf90_put_var(ncFileID, TRUELAT2VarID, wrf%dom(1:num_domains)%proj%truelat2  ))
call check(nf90_put_var(ncFileID,  CEN_LATVarID, wrf%dom(1:num_domains)%cen_lat   ))
call check(nf90_put_var(ncFileID,  CEN_LONVarID, wrf%dom(1:num_domains)%cen_lon   ))
call check(nf90_put_var(ncFileID, MAP_PROJVarID, wrf%dom(1:num_domains)%map_proj  ))

!nc -- convert internally logical boundary condition variables into integers before filling
do id=1,num_domains
   if ( wrf%dom(id)%periodic_x ) then
      tmp(id) = 1
   else
      tmp(id) = 0
   end if
end do
call check(nf90_put_var(ncFileID, PERIODIC_XVarID, tmp(1:num_domains) ))

do id=1,num_domains
   if ( wrf%dom(id)%polar ) then
      tmp(id) = 1
   else
      tmp(id) = 0
   end if
end do
call check(nf90_put_var(ncFileID, POLARVarID, tmp(1:num_domains) ))


do id=1,num_domains

! defining grid levels
   call check(nf90_put_var(ncFileID,       DNVarID(id), wrf%dom(id)%dn        ))
   call check(nf90_put_var(ncFileID,      ZNUVarID(id), wrf%dom(id)%znu       ))
   call check(nf90_put_var(ncFileID,      DNWVarID(id), wrf%dom(id)%dnw       ))

! defining horizontal
   call check(nf90_put_var(ncFileID,      mubVarID(id), wrf%dom(id)%mub       ))
   call check(nf90_put_var(ncFileID,      LonVarID(id), wrf%dom(id)%longitude ))
   call check(nf90_put_var(ncFileID,      LatVarID(id), wrf%dom(id)%latitude  ))
   call check(nf90_put_var(ncFileID,     ilevVarID(id), (/ (i,i=1,wrf%dom(id)%bt) /) ))
   call check(nf90_put_var(ncFileID,    XlandVarID(id), wrf%dom(id)%land      ))
!   call check(nf90_put_var(ncFileID,  MapFacMVarID(id), wrf%dom(id)%mapfac_m  ))
!   call check(nf90_put_var(ncFileID,  MapFacUVarID(id), wrf%dom(id)%mapfac_u  ))
!   call check(nf90_put_var(ncFileID,  MapFacVVarID(id), wrf%dom(id)%mapfac_v  ))
   call check(nf90_put_var(ncFileID,      phbVarID(id), wrf%dom(id)%phb       ))
   call check(nf90_put_var(ncFileID,      hgtVarID(id), wrf%dom(id)%hgt       ))

enddo

!-----------------------------------------------------------------
! Flush the buffer and leave netCDF file open
!-----------------------------------------------------------------

call check(nf90_sync(ncFileID))

write (*,*)'nc_write_model_atts: netCDF file ',ncFileID,' is synched ...'

contains

  ! Internal subroutine - checks error status after each netcdf, prints
  !                       text message each time an error code is returned.
  subroutine check(istatus)
    integer, intent ( in) :: istatus

    if(istatus /= nf90_noerr) call error_handler(E_ERR, 'nc_write_model_atts', &
       trim(nf90_strerror(istatus)), source, revision, revdate)

  end subroutine check

end function nc_write_model_atts



function nc_write_model_vars( ncFileID, statevec, copyindex, timeindex ) result (ierr)
!-----------------------------------------------------------------
! Writes the model-specific variables to a netCDF file
! TJH 25 June 2003
!
! TJH 29 July 2003 -- for the moment, all errors are fatal, so the
! return code is always '0 == normal', since the fatal errors stop execution.


integer,                intent(in) :: ncFileID      ! netCDF file identifier
real(r8), dimension(:), intent(in) :: statevec
integer,                intent(in) :: copyindex
integer,                intent(in) :: timeindex
integer                            :: ierr          ! return value of function

!-----------------------------------------------------------------

logical, parameter :: debug = .false.  
integer :: nDimensions, nVariables, nAttributes, unlimitedDimID
integer :: StateVarID, VarID, id
integer :: i,j
real(r8), allocatable, dimension(:,:)   :: temp2d
real(r8), allocatable, dimension(:,:,:) :: temp3d
character(len=10) :: varname
character(len=1) :: idom

ierr = 0     ! assume normal termination

!-----------------------------------------------------------------
! make sure ncFileID refers to an open netCDF file, 
! then get all the Variable ID's we need.
!-----------------------------------------------------------------

call check(nf90_Inquire(ncFileID, nDimensions, nVariables, nAttributes, unlimitedDimID))

if ( output_state_vector ) then

   call check(NF90_inq_varid(ncFileID, "state", StateVarID) )
   call check(NF90_put_var(ncFileID, StateVarID, statevec,  &
                start=(/ 1, copyindex, timeindex /)))

else

j = 0

do id=1,num_domains

   write( idom , '(I1)') id

   !----------------------------------------------------------------------------
   ! Fill the variables, the order is CRITICAL  ...   U,V,W,GZ,T,MU,TSK,QV,QC,QR,...
   !----------------------------------------------------------------------------

   !----------------------------------------------------------------------------
   varname = 'U_d0'//idom
   !----------------------------------------------------------------------------
   call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
   i       = j + 1
   j       = i + wrf%dom(id)%wes * wrf%dom(id)%sn * wrf%dom(id)%bt - 1 
   if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
              trim(adjustl(varname)),i,j,wrf%dom(id)%wes,wrf%dom(id)%sn,wrf%dom(id)%bt 
   allocate ( temp3d(wrf%dom(id)%wes, wrf%dom(id)%sn, wrf%dom(id)%bt) )
   temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%wes, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
   call check(nf90_put_var( ncFileID, VarID, temp3d, &
                            start=(/ 1, 1, 1, copyindex, timeindex /) ))
   deallocate(temp3d)


   !----------------------------------------------------------------------------
   varname = 'V_d0'//idom
   !----------------------------------------------------------------------------
   call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
   i       = j + 1
   j       = i + wrf%dom(id)%we * wrf%dom(id)%sns * wrf%dom(id)%bt - 1
   if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
              trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sns,wrf%dom(id)%bt
   allocate ( temp3d(wrf%dom(id)%we, wrf%dom(id)%sns, wrf%dom(id)%bt) )
   temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sns, wrf%dom(id)%bt /) ) 
   call check(nf90_put_var( ncFileID, VarID, temp3d, &
                            start=(/ 1, 1, 1, copyindex, timeindex /) ))
   deallocate(temp3d)


   !----------------------------------------------------------------------------
   varname = 'W_d0'//idom
   !----------------------------------------------------------------------------
   call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
   i       = j + 1
   j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bts - 1
   if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
              trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bts
   allocate ( temp3d(wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bts) )
   temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bts /) ) 
   call check(nf90_put_var( ncFileID, VarID, temp3d, &
                            start=(/ 1, 1, 1, copyindex, timeindex /) ))


   !----------------------------------------------------------------------------
   varname = 'PH_d0'//idom       ! AKA "GZ"
   !----------------------------------------------------------------------------
   call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
   i       = j + 1
   j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bts - 1
   if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
              trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bts
   temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bts /) ) 
   call check(nf90_put_var( ncFileID, VarID, temp3d, &
                            start=(/ 1, 1, 1, copyindex, timeindex /) ))
   deallocate(temp3d)


   !----------------------------------------------------------------------------
   varname = 'T_d0'//idom
   !----------------------------------------------------------------------------
   call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
   i       = j + 1
   j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bt - 1
   if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
              trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bt
   allocate ( temp3d(wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt) )
   temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
   call check(nf90_put_var( ncFileID, VarID, temp3d, &
                            start=(/ 1, 1, 1, copyindex, timeindex /) ))
   deallocate(temp3d)


   !----------------------------------------------------------------------------
   varname = 'MU_d0'//idom
   !----------------------------------------------------------------------------
   call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
   i       = j + 1
   j       = i + wrf%dom(id)%we * wrf%dom(id)%sn - 1
   if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
              trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn
   allocate ( temp2d(wrf%dom(id)%we, wrf%dom(id)%sn) )
   temp2d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn /) ) 
   call check(nf90_put_var( ncFileID, VarID, temp2d, &
                            start=(/ 1, 1, copyindex, timeindex /) ))


   !----------------------------------------------------------------------------
   varname = 'TSK_d0'//idom
   !----------------------------------------------------------------------------
   call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
   i       = j + 1
   j       = i + wrf%dom(id)%we * wrf%dom(id)%sn - 1
   if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
              trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn
   temp2d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn /) ) 
   call check(nf90_put_var( ncFileID, VarID, temp2d, &
                            start=(/ 1, 1, copyindex, timeindex /) ))


   if( wrf%dom(id)%n_moist >= 1) then
      !----------------------------------------------------------------------------
      varname = 'QVAPOR_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bt - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bt
      allocate ( temp3d(wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt) )
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
           start=(/ 1, 1, 1, copyindex, timeindex /) ))
   endif


   if( wrf%dom(id)%n_moist >= 2) then
      !----------------------------------------------------------------------------
      varname = 'QCLOUD_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bt - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bt
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
           start=(/ 1, 1, 1, copyindex, timeindex /) ))
   endif


   if( wrf%dom(id)%n_moist >= 3) then
      !----------------------------------------------------------------------------
      varname = 'QRAIN_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bt - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bt
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
           start=(/ 1, 1, 1, copyindex, timeindex /) ))
   endif


   if( wrf%dom(id)%n_moist >= 4) then
      !----------------------------------------------------------------------------
      varname = 'QICE_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bt - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bt
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
           start=(/ 1, 1, 1, copyindex, timeindex /) ))
   endif
   if( wrf%dom(id)%n_moist >= 5) then
      !----------------------------------------------------------------------------
      varname = 'QSNOW_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bt - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bt
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
           start=(/ 1, 1, 1, copyindex, timeindex /) ))
   endif
   if( wrf%dom(id)%n_moist >= 6) then
      !----------------------------------------------------------------------------
      varname = 'QGRAUP_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bt - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bt
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
           start=(/ 1, 1, 1, copyindex, timeindex /) ))
   endif
   if( wrf%dom(id)%n_moist == 7) then
      !----------------------------------------------------------------------------
      varname = 'QNICE_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bt - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bt
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
           start=(/ 1, 1, 1, copyindex, timeindex /) ))
   endif

   deallocate(temp3d)

   if ( wrf%dom(id)%n_moist > 7 ) then
      write(*,'(''wrf%dom(id)%n_moist = '',i3)')wrf%dom(id)%n_moist
      call error_handler(E_ERR,'nc_write_model_vars', &
               'num_moist_vars is too large.', source, revision, revdate)
   endif

   if(wrf%dom(id)%surf_obs ) then

      !----------------------------------------------------------------------------
      varname = 'U10_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn
      temp2d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp2d, &
           start=(/ 1, 1, copyindex, timeindex /) ))

      !----------------------------------------------------------------------------
      varname = 'V10_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn
      temp2d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp2d, &
           start=(/ 1, 1, copyindex, timeindex /) ))

      !----------------------------------------------------------------------------
      varname = 'T2_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn
      temp2d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp2d, &
           start=(/ 1, 1, copyindex, timeindex /) ))

      !----------------------------------------------------------------------------
      varname = 'TH2_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn
      temp2d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp2d, &
           start=(/ 1, 1, copyindex, timeindex /) ))

      !----------------------------------------------------------------------------
      varname = 'Q2_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn
      temp2d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp2d, &
           start=(/ 1, 1, copyindex, timeindex /) ))

      !----------------------------------------------------------------------------
      varname = 'PS_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
           trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn
      temp2d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp2d, &
           start=(/ 1, 1, copyindex, timeindex /) ))

   endif

   if(wrf%dom(id)%soil_data ) then   

      !----------------------------------------------------------------------------
      varname = 'TSLB_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%sls - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
                 trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%sls
      allocate ( temp3d(wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%sls) )
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%sls /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
                               start=(/ 1, 1, 1, copyindex, timeindex /) ))

      !----------------------------------------------------------------------------
      varname = 'SMOIS_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%sls - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
                 trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%sls
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%sls /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
                               start=(/ 1, 1, 1, copyindex, timeindex /) ))

      !----------------------------------------------------------------------------
      varname = 'SH2O_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%sls - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
                 trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%sls
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%sls /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
                               start=(/ 1, 1, 1, copyindex, timeindex /) ))

      deallocate(temp3d)

   endif

   deallocate(temp2d)

   if( h_diab) then

      !----------------------------------------------------------------------------
      varname = 'H_DIAB_d0'//idom
      !----------------------------------------------------------------------------
      call check(NF90_inq_varid(ncFileID, trim(adjustl(varname)), VarID))
      i       = j + 1
      j       = i + wrf%dom(id)%we * wrf%dom(id)%sn * wrf%dom(id)%bt - 1
      if (debug) write(*,'(a10,'' = statevec('',i7,'':'',i7,'') with dims '',3(1x,i3))') &
                 trim(adjustl(varname)),i,j,wrf%dom(id)%we,wrf%dom(id)%sn,wrf%dom(id)%bt
      allocate ( temp3d(wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt) )
      temp3d  = reshape(statevec(i:j), (/ wrf%dom(id)%we, wrf%dom(id)%sn, wrf%dom(id)%bt /) ) 
      call check(nf90_put_var( ncFileID, VarID, temp3d, &
                               start=(/ 1, 1, 1, copyindex, timeindex /) ))
      deallocate(temp3d)

   end if

enddo

endif

!-----------------------------------------------------------------
! Flush the buffer and leave netCDF file open
!-----------------------------------------------------------------

write (*,*)'Finished filling variables ...'
call check(nf90_sync(ncFileID))
write (*,*)'netCDF file is synched ...'

contains

  ! Internal subroutine - checks error status after each netcdf, prints
  !                       text message each time an error code is returned.
  subroutine check(istatus)
    integer, intent ( in) :: istatus

    if(istatus /= nf90_noerr) call error_handler(E_ERR, 'nc_write_model_vars', &
         trim(nf90_strerror(istatus)), source, revision, revdate)

  end subroutine check

end function nc_write_model_vars

!-------------------------------

!  public stubs

!**********************************************

subroutine adv_1step(x, Time)

! Does single time-step advance with vector state as
! input and output.

  real(r8), intent(inout) :: x(:)

! Time is needed for more general models like this; need to add in to 
! low-order models
  type(time_type), intent(in) :: Time

end subroutine adv_1step

!**********************************************

subroutine end_model()
end subroutine end_model

!**********************************************

subroutine init_time(i_time)
! For now returns value of Time_init which is set in initialization routines.

  type(time_type), intent(out) :: i_time

!Where should initial time come from here?
! WARNING: CURRENTLY SET TO 0
  i_time = set_time(0, 0)

end subroutine init_time

!**********************************************

subroutine init_conditions(x)
! Reads in restart initial conditions and converts to vector

! Following changed to intent(inout) for ifc compiler;should be like this
  real(r8), intent(inout) :: x(:)

end subroutine init_conditions



!#######################################################################

subroutine toGrid (x, j, dx, dxm)

!  Transfer obs. x to grid j and calculate its
!  distance to grid j and j+1

  real(r8), intent(in)  :: x
  real(r8), intent(out) :: dx, dxm
  integer,  intent(out) :: j

  j = int (x)

  dx = x - real (j)

  dxm= 1.0_r8 - dx

end subroutine toGrid

!#######################################################################

subroutine pres_to_zk(pres, mdl_v, n3, zk)

! Calculate the model level "zk" on half (mass) levels,
! corresponding to pressure "pres".

  integer,  intent(in)  :: n3
  real(r8), intent(in)  :: pres
  real(r8), intent(in)  :: mdl_v(0:n3)
  real(r8), intent(out) :: zk

  integer  :: k

  zk = missing_r8

  if (pres > mdl_v(0) .or. pres < mdl_v(n3)) return

  do k = 0,n3-1
     if(pres <= mdl_v(k) .and. pres >= mdl_v(k+1)) then
        zk = real(k) + (mdl_v(k) - pres)/(mdl_v(k) - mdl_v(k+1))
        exit
     endif
  enddo

end subroutine pres_to_zk

!#######################################################################

subroutine height_to_zk(obs_v, mdl_v, n3, zk)

! Calculate the model level "zk" on half (mass) levels,
! corresponding to height "obs_v".

  real(r8), intent(in)  :: obs_v
  integer,  intent(in)  :: n3
  real(r8), intent(in)  :: mdl_v(0:n3)
  real(r8), intent(out) :: zk

  integer   :: k

  zk = missing_r8

  if (obs_v < mdl_v(0) .or. obs_v > mdl_v(n3)) return

  do k = 0,n3-1
     if(obs_v >= mdl_v(k) .and. obs_v <= mdl_v(k+1)) then
        zk = real(k) + (mdl_v(k) - obs_v)/(mdl_v(k) - mdl_v(k+1))
        exit
     endif
  enddo

end subroutine height_to_zk

!#######################################################

subroutine get_model_pressure_profile(i,j,dx,dy,dxm,dym,n,x,id,v_p)

! Calculate the full model pressure profile on half (mass) levels,
! horizontally interpolated at the observation location.

integer,  intent(in)  :: i,j,n,id
real(r8), intent(in)  :: dx,dy,dxm,dym
real(r8), intent(in)  :: x(:)
real(r8), intent(out) :: v_p(0:n)

integer, dimension(2) :: ll, lr, ul, ur
integer  :: ill,ilr,iul,iur,k, rc
real(r8) :: pres1, pres2, pres3, pres4

if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_T ) .and. &
     boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_T ) ) then

   call getCorners(i, j, id, TYPE_T, ll, ul, lr, ur, rc )
   if ( rc .ne. 0 ) &
        print*, 'model_mod.f90 :: get_model_pressure_profile :: getCorners rc = ', rc

   do k=1,n
      pres1 = model_pressure_t(ll(1), ll(2), k,id,x)
      pres2 = model_pressure_t(lr(1), lr(2), k,id,x)
      pres3 = model_pressure_t(ul(1), ul(2), k,id,x)
      pres4 = model_pressure_t(ur(1), ur(2), k,id,x)
      v_p(k) = dym*( dxm*pres1 + dx*pres2 ) + dy*( dxm*pres3 + dx*pres4 )
   enddo

   if( wrf%dom(id)%surf_obs ) then

      ill = wrf%dom(id)%dart_ind(ll(1), ll(2), 1, TYPE_PS)
      iul = wrf%dom(id)%dart_ind(ul(1), ul(2), 1, TYPE_PS)
      ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), 1, TYPE_PS)
      iur = wrf%dom(id)%dart_ind(ur(1), ur(2), 1, TYPE_PS)

      ! I'm not quite sure where this comes from, but I will trust them on it....
      if ( x(ill) /= 0.0_r8 .and. x(ilr) /= 0.0_r8 .and. x(iul) /= 0.0_r8 .and. &
           x(iur) /= 0.0_r8 ) then

         v_p(0) = dym*( dxm*x(ill) + dx*x(ilr) ) + dy*( dxm*x(iul) + dx*x(iur) )

      else

         pres1 = model_pressure_t(ll(1), ll(2), 2,id,x)
         pres2 = model_pressure_t(lr(1), lr(2), 2,id,x)
         pres3 = model_pressure_t(ul(1), ul(2), 2,id,x)
         pres4 = model_pressure_t(ur(1), ur(2), 2,id,x)

         v_p(0) = (3.0_r8*v_p(1) - &
              dym*( dxm*pres1 + dx*pres2 ) - dy*( dxm*pres3 + dx*pres4 ))/2.0_r8

      endif

   else

      pres1 = model_pressure_t(ll(1), ll(2), 2,id,x)
      pres2 = model_pressure_t(lr(1), lr(2), 2,id,x)
      pres3 = model_pressure_t(ul(1), ul(2), 2,id,x)
      pres4 = model_pressure_t(ur(1), ur(2), 2,id,x)

      v_p(0) = (3.0_r8*v_p(1) - &
           dym*( dxm*pres1 + dx*pres2 ) - dy*( dxm*pres3 + dx*pres4 ))/2.0_r8

   endif

else

   v_p(:) = missing_r8

endif

end subroutine get_model_pressure_profile

!#######################################################

function model_pressure(i,j,k,id,var_type,x)

! Calculate the pressure at grid point (i,j,k), domain id.
! The grid is defined according to var_type.

integer,  intent(in)  :: i,j,k,id,var_type
real(r8), intent(in)  :: x(:)
real(r8)              :: model_pressure

integer  :: off
real(r8) :: pres1, pres2

model_pressure = missing_r8

! If W-grid (on ZNW levels), then we need to average in vertical, unless
!   we are at the upper or lower boundary in which case we will extrapolate.
if( (var_type == type_w) .or. (var_type == type_gz) ) then

   if( k == 1 ) then

      pres1 = model_pressure_t(i,j,k,id,x)
      pres2 = model_pressure_t(i,j,k+1,id,x)
      model_pressure = (3.0_r8*pres1 - pres2)/2.0_r8

   elseif( k == wrf%dom(id)%var_size(3,TYPE_W) ) then

      pres1 = model_pressure_t(i,j,k-1,id,x)
      pres2 = model_pressure_t(i,j,k-2,id,x)
      model_pressure = (3.0_r8*pres1 - pres2)/2.0_r8

   else

      pres1 = model_pressure_t(i,j,k,id,x)
      pres2 = model_pressure_t(i,j,k-1,id,x)
      model_pressure = (pres1 + pres2)/2.0_r8

   endif

! If U-grid, then pressure is defined between U points, so average --
!   averaging depends on longitude periodicity
elseif( var_type == type_u ) then

   if( i == wrf%dom(id)%var_size(1,TYPE_U) ) then

      ! Check to see if periodic in longitude
      if ( wrf%dom(id)%periodic_x ) then

         ! We are at seam in longitude, take first and last M-grid points
         pres1 = model_pressure_t(i-1,j,k,id,x)
         pres2 = model_pressure_t(1,j,k,id,x)
         model_pressure = (pres1 + pres2)/2.0_r8
         
      else

         ! If not periodic, then try extrapolating
         pres1 = model_pressure_t(i-1,j,k,id,x)
         pres2 = model_pressure_t(i-2,j,k,id,x)
         model_pressure = (3.0_r8*pres1 - pres2)/2.0_r8

      end if

   elseif( i == 1 ) then

      ! Check to see if periodic in longitude
      if ( wrf%dom(id)%periodic_x ) then

         ! We are at seam in longitude, take first and last M-grid points
         pres1 = model_pressure_t(i,j,k,id,x)
         pres2 = model_pressure_t(wrf%dom(id)%we,j,k,id,x)
         model_pressure = (pres1 + pres2)/2.0_r8
         
      else

         ! If not periodic, then try extrapolating
         pres1 = model_pressure_t(i,j,k,id,x)
         pres2 = model_pressure_t(i+1,j,k,id,x)
         model_pressure = (3.0_r8*pres1 - pres2)/2.0_r8

      end if

   else

      pres1 = model_pressure_t(i,j,k,id,x)
      pres2 = model_pressure_t(i-1,j,k,id,x)
      model_pressure = (pres1 + pres2)/2.0_r8

   endif

! If V-grid, then pressure is defined between V points, so average --
!   averaging depends on polar periodicity
elseif( var_type == type_v ) then

   if( j == wrf%dom(id)%var_size(2,TYPE_V) ) then

      ! Check to see if periodic in latitude (polar)
      if ( wrf%dom(id)%polar ) then

         ! The upper corner is 180 degrees of longitude away
         off = i + wrf%dom(id)%we/2
         if ( off > wrf%dom(id)%we ) off = off - wrf%dom(id)%we

         pres1 = model_pressure_t(off,j-1,k,id,x)
         pres2 = model_pressure_t(i  ,j-1,k,id,x)
         model_pressure = (pres1 + pres2)/2.0_r8

      ! If not periodic, then try extrapolating
      else

         pres1 = model_pressure_t(i,j-1,k,id,x)
         pres2 = model_pressure_t(i,j-2,k,id,x)
         model_pressure = (3.0_r8*pres1 - pres2)/2.0_r8

      end if

   elseif( j == 1 ) then

      ! Check to see if periodic in latitude (polar)
      if ( wrf%dom(id)%polar ) then

         ! The lower corner is 180 degrees of longitude away
         off = i + wrf%dom(id)%we/2
         if ( off > wrf%dom(id)%we ) off = off - wrf%dom(id)%we

         pres1 = model_pressure_t(off,j,k,id,x)
         pres2 = model_pressure_t(i,j,k,id,x)
         model_pressure = (pres1 + pres2)/2.0_r8

      ! If not periodic, then try extrapolating
      else

         pres1 = model_pressure_t(i,j,k,id,x)
         pres2 = model_pressure_t(i,j+1,k,id,x)
         model_pressure = (3.0_r8*pres1 - pres2)/2.0_r8

      end if

   else

      pres1 = model_pressure_t(i,j,k,id,x)
      pres2 = model_pressure_t(i,j-1,k,id,x)
      model_pressure = (pres1 + pres2)/2.0_r8

   endif

elseif( var_type == type_mu    .or. var_type == type_tslb .or. &
        var_type == type_ps    .or. var_type == type_u10  .or. &
        var_type == type_v10   .or. var_type == type_t2   .or. &
        var_type == type_th2   .or.                            &
        var_type == type_q2    .or. var_type == type_tsk  .or. &
        var_type == type_smois .or. var_type == type_sh2o) then

   model_pressure = model_pressure_s(i,j,id,x)

else

   model_pressure = model_pressure_t(i,j,k,id,x)

endif

end function model_pressure

!#######################################################

function model_pressure_t(i,j,k,id,x)

! Calculate total pressure on mass point (half (mass) levels, T-point).

integer,  intent(in)  :: i,j,k,id
real(r8), intent(in)  :: x(:)
real(r8)              :: model_pressure_t

real (kind=r8), PARAMETER    :: rd_over_rv = gas_constant / gas_constant_v
real (kind=r8), PARAMETER    :: cpovcv = 1.4_r8        ! cp / (cp - gas_constant)

integer  :: iqv,it
real(r8) :: qvf1,rho

model_pressure_t = missing_r8

! Adapted the code from WRF module_big_step_utilities_em.F ----
!         subroutine calc_p_rho_phi      Y.-R. Guo (10/20/2004)

! Simplification: alb*mub = (phb(i,j,k+1) - phb(i,j,k))/dnw(k)

!!$iqv = get_wrf_index(i,j,k,TYPE_QV,id)
!!$it  = get_wrf_index(i,j,k,TYPE_T,id)
iqv = wrf%dom(id)%dart_ind(i,j,k,TYPE_QV)
it  = wrf%dom(id)%dart_ind(i,j,k,TYPE_T)

qvf1 = 1.0_r8 + x(iqv) / rd_over_rv

rho = model_rho_t(i,j,k,id,x)

! .. total pressure:
model_pressure_t = ps0 * ( (gas_constant*(ts0+x(it))*qvf1) / &
     (ps0/rho) )**cpovcv

end function model_pressure_t

!#######################################################

function model_pressure_s(i,j,id,x)

! compute pressure at surface at mass point

integer,  intent(in)  :: i,j,id
real(r8), intent(in)  :: x(:)
real(r8)              :: model_pressure_s

integer  :: ips, imu

if(wrf%dom(id)%surf_obs ) then
   ips = wrf%dom(id)%dart_ind(i,j,1,TYPE_PS)
   model_pressure_s = x(ips)

else
   imu = wrf%dom(id)%dart_ind(i,j,1,TYPE_MU)
   model_pressure_s = wrf%dom(id)%p_top + wrf%dom(id)%mub(i,j) + x(imu)

endif


end function model_pressure_s

!#######################################################

function model_rho_t(i,j,k,id,x)

! Calculate the total density on mass point (half (mass) levels, T-point).

integer,  intent(in)  :: i,j,k,id
real(r8), intent(in)  :: x(:)
real(r8)              :: model_rho_t

integer  :: imu,iph,iphp1
real(r8) :: ph_e

model_rho_t = missing_r8

! Adapted the code from WRF module_big_step_utilities_em.F ----
!         subroutine calc_p_rho_phi      Y.-R. Guo (10/20/2004)

! Simplification: alb*mub = (phb(i,j,k+1) - phb(i,j,k))/dnw(k)

!!$imu = get_wrf_index(i,j,1,TYPE_MU,id)
!!$iph = get_wrf_index(i,j,k,TYPE_GZ,id)
!!$iphp1 = get_wrf_index(i,j,k+1,TYPE_GZ,id)
imu = wrf%dom(id)%dart_ind(i,j,1,TYPE_MU)
iph = wrf%dom(id)%dart_ind(i,j,k,TYPE_GZ)
iphp1 = wrf%dom(id)%dart_ind(i,j,k+1,TYPE_GZ)

ph_e = ( (x(iphp1) + wrf%dom(id)%phb(i,j,k+1)) - (x(iph) + wrf%dom(id)%phb(i,j,k)) ) &
     /wrf%dom(id)%dnw(k)

! now calculate rho = - mu / dphi/deta

model_rho_t = - (wrf%dom(id)%mub(i,j)+x(imu)) / ph_e

end function model_rho_t

!#######################################################

subroutine get_model_height_profile(i,j,dx,dy,dxm,dym,n,x,id,v_h)

! Calculate the model height profile on half (mass) levels,
! horizontally interpolated at the observation location.

integer,  intent(in)  :: i,j,n,id
real(r8), intent(in)  :: dx,dy,dxm,dym
real(r8), intent(in)  :: x(:)
real(r8), intent(out) :: v_h(0:n)

real(r8)  :: fll(n+1)
integer   :: ill,iul,ilr,iur,k, rc
integer, dimension(2) :: ll, lr, ul, ur

if ( boundsCheck( i, wrf%dom(id)%periodic_x, id, dim=1, type=TYPE_GZ ) .and. &
     boundsCheck( j, wrf%dom(id)%polar,      id, dim=2, type=TYPE_GZ ) ) then

   call getCorners(i, j, id, TYPE_GZ, ll, ul, lr, ur, rc )
   if ( rc .ne. 0 ) &
        print*, 'model_mod.f90 :: get_model_height_profile :: getCorners rc = ', rc

   do k = 1, wrf%dom(id)%var_size(3,TYPE_GZ)

      ill = wrf%dom(id)%dart_ind(ll(1), ll(2), k, TYPE_GZ)
      iul = wrf%dom(id)%dart_ind(ul(1), ul(2), k, TYPE_GZ)
      ilr = wrf%dom(id)%dart_ind(lr(1), lr(2), k, TYPE_GZ)
      iur = wrf%dom(id)%dart_ind(ur(1), ur(2), k, TYPE_GZ)

      fll(k) = ( dym*( dxm*( wrf%dom(id)%phb(ll(1),ll(2),k) + x(ill) ) + &
                        dx*( wrf%dom(id)%phb(lr(1),lr(2),k) + x(ilr) ) ) + &
                  dy*( dxm*( wrf%dom(id)%phb(ul(1),ul(2),k) + x(iul) ) + &
                        dx*( wrf%dom(id)%phb(ur(1),ur(2),k) + x(iur) ) ) )/gravity

   end do

   do k=1,n
      v_h(k) = 0.5_r8*(fll(k) + fll(k+1) )
   end do

   v_h(0) = dym*( dxm*wrf%dom(id)%hgt(ll(1), ll(2)) + &
                   dx*wrf%dom(id)%hgt(lr(1), lr(2)) ) + &
             dy*( dxm*wrf%dom(id)%hgt(ul(1), ul(2)) + &
                   dx*wrf%dom(id)%hgt(ur(1), ur(2)) )

! If the boundsCheck functions return an unsatisfactory integer index, then set
!   fld as missing data
else

   print*,'Not able the get height_profile'
   print*,i,j,dx,dy,dxm,dym,n,id,wrf%dom(id)%var_size(1,TYPE_GZ), &
        wrf%dom(id)%var_size(2,TYPE_GZ)

   v_h(:) =  missing_r8

endif

end subroutine get_model_height_profile

!#######################################################

function model_height(i,j,k,id,var_type,x)

integer,  intent(in)  :: i,j,k,id,var_type
real(r8), intent(in)  :: x(:)
real(r8)              :: model_height

integer   :: i1, i2, i3, i4, off

model_height = missing_r8

! If W-grid (on ZNW levels), then we are fine because it is native to GZ
if( (var_type == type_w) .or. (var_type == type_gz) ) then

!!$   i1 = get_wrf_index(i,j,k,TYPE_GZ,id)
   i1 = wrf%dom(id)%dart_ind(i,j,k,TYPE_GZ)
   model_height = (wrf%dom(id)%phb(i,j,k)+x(i1))/gravity

! If U-grid, then height is defined between U points, both in horizontal 
!   and in vertical, so average -- averaging depends on longitude periodicity
elseif( var_type == type_u ) then

   if( i == wrf%dom(id)%var_size(1,TYPE_U) ) then

      ! Check to see if periodic in longitude
      if ( wrf%dom(id)%periodic_x ) then

         ! We are at the seam in longitude, so take first and last mass points
         i1 = wrf%dom(id)%dart_ind(i-1,j,k  ,TYPE_GZ)
         i2 = wrf%dom(id)%dart_ind(i-1,j,k+1,TYPE_GZ)
         i3 = wrf%dom(id)%dart_ind(1,j,k  ,TYPE_GZ)
         i4 = wrf%dom(id)%dart_ind(1,j,k+1,TYPE_GZ)

         model_height = ( ( wrf%dom(id)%phb(i-1,j,k  ) + x(i1) ) &
                         +( wrf%dom(id)%phb(i-1,j,k+1) + x(i2) ) &
                         +( wrf%dom(id)%phb(1  ,j,k  ) + x(i3) ) &
                         +( wrf%dom(id)%phb(1  ,j,k+1) + x(i4) ) )/(4.0_r8*gravity)
         
      else

!!$      i1 = get_wrf_index(i-1,j,k  ,TYPE_GZ,id)
!!$      i2 = get_wrf_index(i-1,j,k+1,TYPE_GZ,id)

         ! If not periodic, then try extrapolating
         i1 = wrf%dom(id)%dart_ind(i-1,j,k  ,TYPE_GZ)
         i2 = wrf%dom(id)%dart_ind(i-1,j,k+1,TYPE_GZ)

         model_height = ( 3.0_r8*(wrf%dom(id)%phb(i-1,j,k  )+x(i1)) &
                         +3.0_r8*(wrf%dom(id)%phb(i-1,j,k+1)+x(i2)) &
                                -(wrf%dom(id)%phb(i-2,j,k  )+x(i1-1)) &
                                -(wrf%dom(id)%phb(i-2,j,k+1)+x(i2-1)) )/(4.0_r8*gravity)
      end if

   elseif( i == 1 ) then

      ! Check to see if periodic in longitude
      if ( wrf%dom(id)%periodic_x ) then

         ! We are at the seam in longitude, so take first and last mass points
         off = wrf%dom(id)%we
         i1 = wrf%dom(id)%dart_ind(i  ,j,k  ,TYPE_GZ)
         i2 = wrf%dom(id)%dart_ind(i  ,j,k+1,TYPE_GZ)
         i3 = wrf%dom(id)%dart_ind(off,j,k  ,TYPE_GZ)
         i4 = wrf%dom(id)%dart_ind(off,j,k+1,TYPE_GZ)

         model_height = ( ( wrf%dom(id)%phb(i  ,j,k  ) + x(i1) ) &
                         +( wrf%dom(id)%phb(i  ,j,k+1) + x(i2) ) &
                         +( wrf%dom(id)%phb(off,j,k  ) + x(i3) ) &
                         +( wrf%dom(id)%phb(off,j,k+1) + x(i4) ) )/(4.0_r8*gravity)
         
      else

!!$      i1 = get_wrf_index(i,j,k  ,TYPE_GZ,id)
!!$      i2 = get_wrf_index(i,j,k+1,TYPE_GZ,id)

         ! If not periodic, then try extrapolating
         i1 = wrf%dom(id)%dart_ind(i,j,k  ,TYPE_GZ)
         i2 = wrf%dom(id)%dart_ind(i,j,k+1,TYPE_GZ)
         
         model_height = ( 3.0_r8*(wrf%dom(id)%phb(i  ,j,k  )+x(i1)) &
                         +3.0_r8*(wrf%dom(id)%phb(i  ,j,k+1)+x(i2)) &
                                -(wrf%dom(id)%phb(i+1,j,k  )+x(i1+1)) &
                                -(wrf%dom(id)%phb(i+1,j,k+1)+x(i2+1)) )/(4.0_r8*gravity)

      end if

   else

!!$      i1 = get_wrf_index(i,j,k  ,TYPE_GZ,id)
!!$      i2 = get_wrf_index(i,j,k+1,TYPE_GZ,id)
      i1 = wrf%dom(id)%dart_ind(i,j,k  ,TYPE_GZ)
      i2 = wrf%dom(id)%dart_ind(i,j,k+1,TYPE_GZ)

      model_height = ( (wrf%dom(id)%phb(i  ,j,k  )+x(i1)) &
                      +(wrf%dom(id)%phb(i  ,j,k+1)+x(i2)) &
                      +(wrf%dom(id)%phb(i-1,j,k  )+x(i1-1)) &
                      +(wrf%dom(id)%phb(i-1,j,k+1)+x(i2-1)) )/(4.0_r8*gravity)

   endif

! If V-grid, then pressure is defined between V points, both in horizontal 
!   and in vertical, so average -- averaging depends on polar periodicity
elseif( var_type == type_v ) then

   if( j == wrf%dom(id)%var_size(2,TYPE_V) ) then

      ! Check to see if periodic in latitude (polar)
      if ( wrf%dom(id)%polar ) then

         ! The upper corner is 180 degrees of longitude away
         off = i + wrf%dom(id)%we/2
         if ( off > wrf%dom(id)%we ) off = off - wrf%dom(id)%we

         i1 = wrf%dom(id)%dart_ind(off,j-1,k  ,TYPE_GZ)
         i2 = wrf%dom(id)%dart_ind(off,j-1,k+1,TYPE_GZ)
         i3 = wrf%dom(id)%dart_ind(i  ,j-1,k  ,TYPE_GZ)
         i4 = wrf%dom(id)%dart_ind(i  ,j-1,k+1,TYPE_GZ)

         model_height = ( (wrf%dom(id)%phb(off,j-1,k  )+x(i1)) &
                         +(wrf%dom(id)%phb(off,j-1,k+1)+x(i2)) &
                         +(wrf%dom(id)%phb(i  ,j-1,k  )+x(i3)) &
                         +(wrf%dom(id)%phb(i  ,j-1,k+1)+x(i4)) )/(4.0_r8*gravity)
         
      else

!!$      i1 = get_wrf_index(i,j-1,k  ,TYPE_GZ,id)
!!$      i2 = get_wrf_index(i,j-1,k+1,TYPE_GZ,id)
!!$      i3 = get_wrf_index(i,j-2,k  ,TYPE_GZ,id)
!!$      i4 = get_wrf_index(i,j-2,k+1,TYPE_GZ,id)

         ! If not periodic, then try extrapolating
         i1 = wrf%dom(id)%dart_ind(i,j-1,k  ,TYPE_GZ)
         i2 = wrf%dom(id)%dart_ind(i,j-1,k+1,TYPE_GZ)
         i3 = wrf%dom(id)%dart_ind(i,j-2,k  ,TYPE_GZ)
         i4 = wrf%dom(id)%dart_ind(i,j-2,k+1,TYPE_GZ)

         model_height = ( 3.0_r8*(wrf%dom(id)%phb(i,j-1,k  )+x(i1)) &
                         +3.0_r8*(wrf%dom(id)%phb(i,j-1,k+1)+x(i2)) &
                                -(wrf%dom(id)%phb(i,j-2,k  )+x(i3)) &
                                -(wrf%dom(id)%phb(i,j-2,k+1)+x(i4)) )/(4.0_r8*gravity)

      end if

   elseif( j == 1 ) then

      ! Check to see if periodic in latitude (polar)
      if ( wrf%dom(id)%polar ) then

         ! The lower corner is 180 degrees of longitude away
         off = i + wrf%dom(id)%we/2
         if ( off > wrf%dom(id)%we ) off = off - wrf%dom(id)%we

         i1 = wrf%dom(id)%dart_ind(off,j,k  ,TYPE_GZ)
         i2 = wrf%dom(id)%dart_ind(off,j,k+1,TYPE_GZ)
         i3 = wrf%dom(id)%dart_ind(i  ,j,k  ,TYPE_GZ)
         i4 = wrf%dom(id)%dart_ind(i  ,j,k+1,TYPE_GZ)

         model_height = ( (wrf%dom(id)%phb(off,j,k  )+x(i1)) &
                         +(wrf%dom(id)%phb(off,j,k+1)+x(i2)) &
                         +(wrf%dom(id)%phb(i  ,j,k  )+x(i3)) &
                         +(wrf%dom(id)%phb(i  ,j,k+1)+x(i4)) )/(4.0_r8*gravity)
         
      else

!!$      i1 = get_wrf_index(i,j  ,k  ,TYPE_GZ,id)
!!$      i2 = get_wrf_index(i,j  ,k+1,TYPE_GZ,id)
!!$      i3 = get_wrf_index(i,j+1,k  ,TYPE_GZ,id)
!!$      i4 = get_wrf_index(i,j+1,k+1,TYPE_GZ,id)

         ! If not periodic, then try extrapolating
         i1 = wrf%dom(id)%dart_ind(i,j  ,k  ,TYPE_GZ)
         i2 = wrf%dom(id)%dart_ind(i,j  ,k+1,TYPE_GZ)
         i3 = wrf%dom(id)%dart_ind(i,j+1,k  ,TYPE_GZ)
         i4 = wrf%dom(id)%dart_ind(i,j+1,k+1,TYPE_GZ)

         model_height = ( 3.0_r8*(wrf%dom(id)%phb(i,j  ,k  )+x(i1)) &
                         +3.0_r8*(wrf%dom(id)%phb(i,j  ,k+1)+x(i2)) &
                                 -(wrf%dom(id)%phb(i,j+1,k  )+x(i3)) &
                                 -(wrf%dom(id)%phb(i,j+1,k+1)+x(i4)) )/(4.0_r8*gravity)

      end if

   else

!!$      i1 = get_wrf_index(i,j  ,k  ,TYPE_GZ,id)
!!$      i2 = get_wrf_index(i,j  ,k+1,TYPE_GZ,id)
!!$      i3 = get_wrf_index(i,j-1,k  ,TYPE_GZ,id)
!!$      i4 = get_wrf_index(i,j-1,k+1,TYPE_GZ,id)
      i1 = wrf%dom(id)%dart_ind(i,j  ,k  ,TYPE_GZ)
      i2 = wrf%dom(id)%dart_ind(i,j  ,k+1,TYPE_GZ)
      i3 = wrf%dom(id)%dart_ind(i,j-1,k  ,TYPE_GZ)
      i4 = wrf%dom(id)%dart_ind(i,j-1,k+1,TYPE_GZ)

      model_height = ( (wrf%dom(id)%phb(i,j  ,k  )+x(i1)) &
                      +(wrf%dom(id)%phb(i,j  ,k+1)+x(i2)) &
                      +(wrf%dom(id)%phb(i,j-1,k  )+x(i3)) &
                      +(wrf%dom(id)%phb(i,j-1,k+1)+x(i4)) )/(4.0_r8*gravity)

   endif

elseif( var_type == type_mu .or. var_type == type_ps .or. &
        var_type == type_tsk) then

   model_height = wrf%dom(id)%hgt(i,j)

elseif( var_type == type_tslb .or. var_type == type_smois .or. &
        var_type == type_sh2o ) then

   model_height = wrf%dom(id)%hgt(i,j) - wrf%dom(id)%zs(k)

elseif( var_type == type_u10 .or. var_type == type_v10 ) then

   model_height = wrf%dom(id)%hgt(i,j) + 10.0_r8

elseif( var_type == type_t2 .or. var_type == type_th2 .or. var_type == type_q2 ) then

   model_height = wrf%dom(id)%hgt(i,j) + 2.0_r8

else

!!$   i1 = get_wrf_index(i,j,k  ,TYPE_GZ,id)
!!$   i2 = get_wrf_index(i,j,k+1,TYPE_GZ,id)
   i1 = wrf%dom(id)%dart_ind(i,j,k  ,TYPE_GZ)
   i2 = wrf%dom(id)%dart_ind(i,j,k+1,TYPE_GZ)

   model_height = ( (wrf%dom(id)%phb(i,j,k  )+x(i1)) &
                   +(wrf%dom(id)%phb(i,j,k+1)+x(i2)) )/(2.0_r8*gravity)

endif

end function model_height

!#######################################################

function model_height_w(i,j,k,id,x)

! return total height at staggered vertical coordinate
! and horizontal mass coordinates

integer,  intent(in)  :: i,j,k,id
real(r8), intent(in)  :: x(:)
real(r8)              :: model_height_w

integer   :: i1

i1 = wrf%dom(id)%dart_ind(i,j,k,TYPE_GZ)

model_height_w = (wrf%dom(id)%phb(i,j,k) + x(i1))/gravity

end function model_height_w

!#######################################################


subroutine pert_model_state(state, pert_state, interf_provided)

! Perturbs a model state for generating initial ensembles
! Returning interf_provided means go ahead and do this with uniform
! small independent perturbations.

real(r8), intent(in)  :: state(:)
real(r8), intent(out) :: pert_state(:)
logical,  intent(out) :: interf_provided

interf_provided = .false.
pert_state = state

end subroutine pert_model_state

!#######################################################

subroutine read_dt_from_wrf_nml()

real(r8) :: dt

integer :: time_step, time_step_fract_num, time_step_fract_den
integer :: max_dom, feedback, smooth_option
integer, dimension(3) :: s_we, e_we, s_sn, e_sn, s_vert, e_vert
integer, dimension(3) :: dx, dy, ztop, grid_id, parent_id
integer, dimension(3) :: i_parent_start, j_parent_start, parent_grid_ratio
integer, dimension(3) :: parent_time_step_ratio
integer :: io, iunit, id
integer :: num_metgrid_levels, p_top_requested, nproc_x, nproc_y

!nc -- we added "num_metgrid_levels" to the domains nml to make all well with the
!        namelist.input file belonging to global WRF,
!        also "p_top_requested" in domains nml
!        also "nproc_x" & "nproc_y"
!nc -- we notice that "ztop" is unused in code -- perhaps get rid of later?
namelist /domains/ time_step, time_step_fract_num, time_step_fract_den
namelist /domains/ max_dom
namelist /domains/ s_we, e_we, s_sn, e_sn, s_vert, e_vert
namelist /domains/ dx, dy, ztop, grid_id, parent_id
namelist /domains/ i_parent_start, j_parent_start, parent_grid_ratio
namelist /domains/ parent_time_step_ratio
namelist /domains/ feedback, smooth_option
namelist /domains/ num_metgrid_levels, p_top_requested, nproc_x, nproc_y

! Begin by reading the namelist input
call find_namelist_in_file("namelist.input", "domains", iunit)
read(iunit, nml = domains, iostat = io)
call check_namelist_read(iunit, io, "domains")

! Record the namelist values used for the run ...
call error_handler(E_MSG,'read_dt_from_wrf_nml','domains namelist values are',' ',' ',' ')
write(logfileunit, nml=domains)
write(     *     , nml=domains)

if (max_dom /= num_domains) then

   write(*,*) 'max_dom in namelist.input = ',max_dom
   write(*,*) 'num_domains in input.nml  = ',num_domains
   call error_handler(E_ERR,'read_dt_from_wrf_nml', &
        'Make them consistent.', source, revision,revdate)

endif

if (time_step_fract_den /= 0) then
   dt = real(time_step) + real(time_step_fract_num) / real(time_step_fract_den)
else
   dt = real(time_step)
endif

do id=1,num_domains
   wrf%dom(id)%dt = dt / real(parent_time_step_ratio(id))
enddo

end subroutine read_dt_from_wrf_nml



subroutine compute_seaprs ( nz, z, t, p , q ,          &
                            sea_level_pressure, debug)
!-------------------------------------------------------------------------
! compute_seaprs    Estimate sea level pressure.
!
! This routines has been taken "as is" from wrf_user_fortran_util_0.f
!
! This routine assumes
!    index order is (i,j,k)
!    wrf staggering
!    units: pressure (Pa), temperature(K), height (m), mixing ratio (kg kg{-1})
!    availability of 3d p, t, and qv; 2d terrain; 1d half-level zeta string
!    output units of SLP are Pa, but you should divide that by 100 for the
!          weather weenies.
!    virtual effects are included
!
! Dave
!
! cys: change to 1d
! TJH: verified intent() qualifiers, declaration syntax, uses error_handler

      IMPLICIT NONE
      INTEGER,  intent(in)    :: nz
      REAL(r8), intent(in)    :: z(nz), p(nz), q(nz)
      REAL(r8), intent(inout) :: t(nz)
      REAL(r8), intent(out)   :: sea_level_pressure
      LOGICAL,  intent(in)    :: debug

      INTEGER  :: level
      REAL(r8) :: t_surf, t_sea_level

!     Some required physical constants:

      REAL(r8) :: R, G, GAMMA
      PARAMETER (R=287.04_r8, G=9.81_r8, GAMMA=0.0065_r8)

!     Specific constants for assumptions made in this routine:

      REAL(r8) :: TC, PCONST
      PARAMETER (TC=273.16_r8 + 17.5_r8, PCONST = 10000.0_r8)

      LOGICAL  :: ridiculous_mm5_test
      PARAMETER  (ridiculous_mm5_test = .TRUE.)
!     PARAMETER  (ridiculous_mm5_test = .false.)

!     Local variables:

      character(len=129) :: errstring
      INTEGER :: k
      INTEGER :: klo, khi

      REAL(r8) :: plo, phi, tlo, thi, zlo, zhi
      REAL(r8) :: p_at_pconst, t_at_pconst, z_at_pconst
      REAL(r8) :: z_half_lowest

      REAL(r8), PARAMETER :: cp           = 7.0_r8*R/2.0_r8
      REAL(r8), PARAMETER :: rcp          = R/cp
      REAL(r8), PARAMETER :: p1000mb      = 100000.0_r8

      LOGICAL ::  l1 , l2 , l3, found

!     Find least zeta level that is PCONST Pa above the surface.  We later use this
!     level to extrapolate a surface pressure and temperature, which is supposed
!     to reduce the effect of the diurnal heating cycle in the pressure field.

      t = t*(p/p1000mb)**rcp

      level = -1

      k = 1
      found = .false.
      do while( (.not. found) .and. (k.le.nz))
         IF ( p(k) .LT. p(1)-PCONST ) THEN
            level = k
            found = .true.
         END IF
         k = k+1
      END DO

      IF ( level .EQ. -1 ) THEN
         PRINT '(A,I4,A)','Troubles finding level ',   &
               NINT(PCONST)/100,' above ground.'
         print*, 'p=',p
         print*, 't=',t
         print*, 'z=',z
         print*, 'q=',q
         write(errstring,*)'Error_in_finding_100_hPa_up'
         call error_handler(E_ERR,'compute_seaprs',errstring,' ',' ',' ')
      END IF


!     Get temperature PCONST Pa above surface.  Use this to extrapolate
!     the temperature at the surface and down to sea level.

      klo = MAX ( level - 1 , 1      )
      khi = MIN ( klo + 1        , nz - 1 )

      IF ( klo .EQ. khi ) THEN
         PRINT '(A)','Trapping levels are weird.'
         PRINT '(A,I3,A,I3,A)','klo = ',klo,', khi = ',khi, &
               ': and they should not be equal.'
         write(errstring,*)'Error_trapping_levels'
         call error_handler(E_ERR,'compute_seaprs',errstring,' ',' ',' ')
      END IF

      plo = p(klo)
      phi = p(khi)
      tlo = t(klo)*(1. + 0.608 * q(klo) )
      thi = t(khi)*(1. + 0.608 * q(khi) )
!     zlo = zetahalf(klo)/ztop*(ztop-terrain(i,j))+terrain(i,j)
!     zhi = zetahalf(khi)/ztop*(ztop-terrain(i,j))+terrain(i,j)
      zlo = z(klo)
      zhi = z(khi)

      p_at_pconst = p(1) - pconst
      t_at_pconst = thi-(thi-tlo)*LOG(p_at_pconst/phi)*LOG(plo/phi)
      z_at_pconst = zhi-(zhi-zlo)*LOG(p_at_pconst/phi)*LOG(plo/phi)

      t_surf = t_at_pconst*(p(1)/p_at_pconst)**(gamma*R/g)
      t_sea_level = t_at_pconst+gamma*z_at_pconst


!     If we follow a traditional computation, there is a correction to the sea level
!     temperature if both the surface and sea level temnperatures are *too* hot.

      IF ( ridiculous_mm5_test ) THEN
         l1 = t_sea_level .LT. TC
         l2 = t_surf      .LE. TC
         l3 = .NOT. l1
         IF ( l2 .AND. l3 ) THEN
            t_sea_level = TC
         ELSE
            t_sea_level = TC - 0.005*(t_surf-TC)**2
         END IF
      END IF

!     The grand finale: ta da!

!     z_half_lowest=zetahalf(1)/ztop*(ztop-terrain(i,j))+terrain(i,j)
      z_half_lowest=z(1)
      sea_level_pressure = p(1) *              &
                           EXP((2.*g*z_half_lowest)/   &
                           (R*(t_sea_level+t_surf)))

!        sea_level_pressure(i,j) = sea_level_pressure(i,j)*0.01

    if (debug) then
      print *,'slp=',sea_level_pressure
    endif
!      print *,'t=',t(10:15,10:15,1),t(10:15,2,1),t(10:15,3,1)
!      print *,'z=',z(10:15,1,1),z(10:15,2,1),z(10:15,3,1)
!      print *,'p=',p(10:15,1,1),p(10:15,2,1),p(10:15,3,1)
!      print *,'slp=',sea_level_pressure(10:15,10:15),     &
!         sea_level_pressure(10:15,10:15),sea_level_pressure(20,10:15)

end subroutine compute_seaprs


      
SUBROUTINE splin2(x1a,x2a,ya,y2a,m,n,x1,x2,y)
      INTEGER m,n,NN
      REAL(r8), intent(in) :: x1,x2,x1a(m),x2a(n),y2a(m,n),ya(m,n)
      real(r8), intent(out) :: y
      PARAMETER (NN=100)
!     USES spline,splint
      INTEGER j,k
      REAL(r8) y2tmp(NN),ytmp(NN),yytmp(NN)
      do 12 j=1,m
        do 11 k=1,n
          ytmp(k)=ya(j,k)
          y2tmp(k)=y2a(j,k)
11      continue
        call splint(x2a,ytmp,y2tmp,n,x2,yytmp(j))
12    continue
      call spline(x1a,yytmp,m,1.e30_r8,1.e30_r8,y2tmp)
      call splint(x1a,yytmp,y2tmp,m,x1,y)
      return
END subroutine splin2

SUBROUTINE splie2(x1a,x2a,ya,m,n,y2a)
      INTEGER m,n,NN
      REAL(r8), intent(in) :: x1a(m),x2a(n),ya(m,n)
      REAL(r8), intent(out) :: y2a(m,n)
      PARAMETER (NN=100)
!     USES spline
      INTEGER j,k
      REAL(r8) y2tmp(NN),ytmp(NN)
      do 13 j=1,m
        do 11 k=1,n
          ytmp(k)=ya(j,k)
11      continue
        call spline(x2a,ytmp,n,1.e30_r8,1.e30_r8,y2tmp)
        do 12 k=1,n
          y2a(j,k)=y2tmp(k)
12      continue
13    continue
      return
END subroutine splie2

SUBROUTINE spline(x,y,n,yp1,ypn,y2)
      INTEGER n,NMAX
      REAL(r8), intent(in) :: yp1,ypn,x(n),y(n)
      REAL(r8), intent(out) :: y2(n)
      PARAMETER (NMAX=500)
      INTEGER i,k
      REAL(r8) p,qn,sig,un,u(NMAX)
      if (yp1.gt..99e30) then
        y2(1)=0.
        u(1)=0.
      else
        y2(1)=-0.5
        u(1)=(3./(x(2)-x(1)))*((y(2)-y(1))/(x(2)-x(1))-yp1)
      endif
      do 11 i=2,n-1
        sig=(x(i)-x(i-1))/(x(i+1)-x(i-1))
        p=sig*y2(i-1)+2.
        y2(i)=(sig-1.)/p
        u(i)=(6.*((y(i+1)-y(i))/(x(i+ &
      1)-x(i))-(y(i)-y(i-1))/(x(i)-x(i-1)))/(x(i+1)-x(i-1))-sig* &
      u(i-1))/p
11    continue
      if (ypn.gt..99e30) then
        qn=0.
        un=0.
      else
        qn=0.5
        un=(3./(x(n)-x(n-1)))*(ypn-(y(n)-y(n-1))/(x(n)-x(n-1)))
      endif
      y2(n)=(un-qn*u(n-1))/(qn*y2(n-1)+1.)
      do 12 k=n-1,1,-1
        y2(k)=y2(k)*y2(k+1)+u(k)
12    continue
      return
END subroutine spline


SUBROUTINE splint(xa,ya,y2a,n,x,y)
      INTEGER n
      REAL(r8),intent(in) :: x,xa(n),y2a(n),ya(n)
      REAL(r8),intent(out) :: y
      INTEGER k,khi,klo
      REAL(r8) a,b,h
      klo=1
      khi=n
1     if (khi-klo.gt.1) then
        k=(khi+klo)/2
        if(xa(k).gt.x)then
          khi=k
        else
          klo=k
        endif
      goto 1
      endif
      h=xa(khi)-xa(klo)
      if (h.eq.0.) pause 'bad xa input in splint'
      a=(xa(khi)-x)/h
      b=(x-xa(klo))/h
      y=a*ya(klo)+b*ya(khi)+((a**3-a)*y2a(klo)+(b**3-b)*y2a(khi))*(h**2)/6.
      return
END subroutine splint


!#######################################################################


subroutine ens_mean_for_model(filter_ens_mean)

! Not used in low-order models
! Stores provided ensemble mean within the module for later use

real(r8), intent(in) :: filter_ens_mean(:)

ens_mean = filter_ens_mean

end subroutine ens_mean_for_model


!#######################################################################

subroutine get_domain_info(obslon,obslat,id,iloc,jloc)

real(r8), intent(in)  :: obslon, obslat
integer, intent(out)  :: id
real(r8), intent(out) :: iloc, jloc

logical               :: dom_found

! given arbitrary lat and lon values, returns closest domain id and
! horizontal mass point grid points (xloc,yloc)

dom_found = .false.

id = num_domains
do while (.not. dom_found)

   ! Checking for exact equality on real variable types is generally a bad idea.

   if( (wrf%dom(id)%proj%hemi ==  1.0_r8 .and. obslat == -90.0_r8) .or. &
       (wrf%dom(id)%proj%hemi == -1.0_r8 .and. obslat ==  90.0_r8) .or. &
       (wrf%dom(id)%proj%code == PROJ_MERC .and. abs(obslat) >= 90.0_r8) ) then

!nc -- strange that there is nothing in this if-case structure
print*, 'model_mod.f90 :: subroutine get_domain_info :: in empty if-case'

   else
      call latlon_to_ij(wrf%dom(id)%proj,obslat,obslon,iloc,jloc)

      ! Array bound checking depends on whether periodic or not -- these are
      !   real-valued indices here, so we cannot use boundsCheck  :( 

      if ( wrf%dom(id)%periodic_x  ) then
         if ( wrf%dom(id)%polar ) then        
            !   Periodic     X & M_grid ==> [1 we+1)    
            !   Periodic     Y & M_grid ==> [0.5 sn+0.5]
            if ( iloc >= 1.0_r8 .and. iloc <  real(wrf%dom(id)%we,r8)+1.0_r8 .and. &
                 jloc >= 0.5_r8 .and. jloc <= real(wrf%dom(id)%sn,r8)+0.5_r8 ) &
                 dom_found = .true.     
         else
            !   Periodic     X & M_grid ==> [1 we+1)    
            !   NOT Periodic Y & M_grid ==> [1 sn]
            if ( iloc >= 1.0_r8 .and. iloc <  real(wrf%dom(id)%we,r8)+1.0_r8 .and. &
                 jloc >= 1.0_r8 .and. jloc <= real(wrf%dom(id)%sn,r8) ) &
                 dom_found = .true.
         end if
      else
         if ( wrf%dom(id)%polar ) then        
            !   NOT Periodic X & M_grid ==> [1 we]    
            !   Periodic     Y & M_grid ==> [0.5 sn+0.5]
            if ( iloc >= 1.0_r8 .and. iloc <= real(wrf%dom(id)%we,r8) .and. &
                 jloc >= 0.5_r8 .and. jloc <= real(wrf%dom(id)%sn,r8)+0.5_r8 ) &
                 dom_found = .true.     
         else
            !   NOT Periodic X & M_grid ==> [1 we]    
            !   NOT Periodic Y & M_grid ==> [1 sn]
            if ( iloc >= 1.0_r8 .and. iloc <= real(wrf%dom(id)%we,r8) .and. &
                 jloc >= 1.0_r8 .and. jloc <= real(wrf%dom(id)%sn,r8) ) &
                 dom_found = .true.
         end if 
      end if

   end if

   if (.not. dom_found) then
      id = id - 1
      if (id == 0) return
   endif

end do

end subroutine get_domain_info

!#######################################################################

subroutine get_close_obs(gc, base_obs_loc, base_obs_kind, obs_loc, obs_kind, &
                            num_close, close_ind, dist)

! Given a DART ob (referred to as "base") and a set of obs priors or state variables
! (obs_loc, obs_kind), returns the subset of close ones to the "base" ob, their
! indices, and their distances to the "base" ob...

! For vertical distance computations, general philosophy is to convert all vertical
! coordinates to a common coordinate. This coordinate type is defined in the namelist
! with the variable "vert_localization_coord".

! Vertical conversion is carried out by the subroutine vert_interpolate.

! Note that both base_obs_loc and obs_loc are intent(inout), meaning that these
! locations are possibly modified here and returned as such to the calling routine.
! The calling routine is always filter_assim and these arrays are local arrays
! within filter_assim. In other words, these modifications will only matter within
! filter_assim, but will not propagate backwards to filter.
      
implicit none

type(get_close_type), intent(in)     :: gc
type(location_type),  intent(inout)  :: base_obs_loc, obs_loc(:)
integer,              intent(in)     :: base_obs_kind, obs_kind(:)
integer,              intent(out)    :: num_close, close_ind(:)
real(r8),             intent(out)    :: dist(:)

integer                :: t_ind, istatus1, istatus2, k
integer                :: base_which, local_obs_which
real(r8), dimension(3) :: base_array, local_obs_array
type(location_type)    :: local_obs_loc


! Initialize variables to missing status
num_close = 0
close_ind = -99
dist      = 1.0e9

istatus1 = 0
istatus2 = 0

! Convert base_obs vertical coordinate to requested vertical coordinate if necessary

base_array = get_location(base_obs_loc) 
base_which = nint(query_location(base_obs_loc))

if (.not. horiz_dist_only) then
   if (base_which /= wrf%dom(1)%vert_coord) then
      call vert_interpolate(ens_mean, base_obs_loc, base_obs_kind, istatus1)
   elseif (base_array(3) == missing_r8) then
      istatus1 = 1
   end if
endif

if (istatus1 == 0) then

   ! Get all the potentially close obs but no dist (optional argument dist(:) is not present)
   ! This way, we are decreasing the number of distance computations that will follow.
   ! This is a horizontal-distance operation and we don't need to have the relevant vertical
   ! coordinate information yet (for obs_loc).
   call loc_get_close_obs(gc, base_obs_loc, base_obs_kind, obs_loc, obs_kind, &
                          num_close, close_ind)

   ! Loop over potentially close subset of obs priors or state variables
   do k = 1, num_close

      t_ind = close_ind(k)
      local_obs_loc   = obs_loc(t_ind)
      local_obs_which = nint(query_location(local_obs_loc))

      ! Convert local_obs vertical coordinate to requested vertical coordinate if necessary.
      ! This should only be necessary for obs priors, as state location information already
      ! contains the correct vertical coordinate (filter_assim's call to get_state_meta_data).
      if (.not. horiz_dist_only) then
         if (local_obs_which /= wrf%dom(1)%vert_coord) then
            call vert_interpolate(ens_mean, local_obs_loc, obs_kind(t_ind), istatus2)
            ! Store the "new" location into the original full local array
            obs_loc(t_ind) = local_obs_loc
         endif
      endif

      ! Compute distance - set distance to a very large value if vert coordinate is missing
      ! or vert_interpolate returned error (istatus2=1)
      local_obs_array = get_location(local_obs_loc)
      if (((.not. horiz_dist_only).and.(local_obs_array(3) == missing_r8)).or.(istatus2 == 1)) then
         dist(k) = 1.0e9        
      else
         dist(k) = get_dist(base_obs_loc, local_obs_loc, base_obs_kind, obs_kind(t_ind))
      end if

   end do
endif

end subroutine get_close_obs

!#######################################################################
!nc -- additional function from Greg Lawson & Nancy Collins
!
!  logical function boundsCheck determines whether real-valued location indices are
!    within a sensible range based on the assumed (un)staggered grid and based on 
!    whether the domain is assumed to be periodic in a given direction.

function boundsCheck ( ind, periodic, id, dim, type )

  integer,  intent(in)  :: ind, id, dim, type
  logical,  intent(in)  :: periodic

  logical :: boundsCheck  
!  logical, parameter :: restrict_polar = .true.
  logical, parameter :: restrict_polar = .false.

  ! Consider cases in REAL-VALUED indexing:
  !
  ! I. Longitude -- x-direction
  !    A. PERIODIC (period_x = .true.)
  !
  !       Consider Mass-grid (& V-grid) longitude grid with 4 west-east gridpoints
  !         Values  ::  [ -135 -45  45 135 ] .. {225}
  !         Indices ::  [   1   2   3   4  ] .. {1,5}
  !       Complementary U-grid
  !         Values  ::  [ -180 -90  0  90  180 ]
  !         Indices ::  [   1   2   3   4   5  ]
  !
  !       What are the allowable values for a real-valued index on each of these grids?
  !       1. M-grid  --->  [1 5)       ---> [1 we+1)
  !                  --->  [-135 225)  
  !       2. U-grid  --->  [1 5)       ---> [1 wes)
  !                  --->  [-180 180)
  !       [Note that above "allowable values" reflect that one should be able to have
  !        an observation anywhere on a given longitude circle -- the information 
  !        exists in order to successfully interpolate to anywhere over [0 360).]
  !
  !       It is up to the routine calling "boundsCheck" to have handled the 0.5 offset
  !         in indices between the M-grid & U-grid.  Hence, two examples: 
  !          a. If there is an observation location at -165 longitude, then:
  !             * An observation of TYPE_T (on the M-grid) would have ind = 4.667
  !             * An observation of TYPE_U (on the U-grid) would have ind = 1.167
  !          b. If there is an observation location at 0 longitude, then:
  !             * An observation of TYPE_T (on the M-grid) would have ind = 2.5
  !             * An observation of TYPE_U (on the U-grid) would have ind = 3.0
  !
  !    B. NOT periodic (period_x = .false.)
  !
  !       Consider Mass-grid (& V-grid) longitude grid with 4 west-east gridpoints
  !         Values  ::  [  95  105 115 125 ] 
  !         Indices ::  [   1   2   3   4  ] 
  !       Complementary U-grid
  !         Values  ::  [  90  100 110 120 130 ]
  !         Indices ::  [   1   2   3   4   5  ]
  !
  !       What are the allowable values for a real-valued index on each of these grids?
  !       1. M-grid  --->  [1 4]       ---> [1 we]
  !                  --->  [95 125]  
  !       2. U-grid  --->  [1.5 4.5]       ---> [1.5 we+0.5]
  !                  --->  [95 125]
  !       [Note that above "allowable values" reflect that one should only be able to
  !        have an observation within the M-grid, since that is the only way to  
  !        guarantee that the necessary information exists in order to successfully 
  !        interpolate to a specified location.]
  !
  !       It is up to the routine calling "boundsCheck" to have handled the 0.5 offset
  !         in indices between the M-grid & U-grid.  Hence, two examples: 
  !          a. If there is an observation location at 96 longitude, then:
  !             * An observation of TYPE_T (on the M-grid) would have ind = 1.1
  !             * An observation of TYPE_U (on the U-grid) would have ind = 1.6
  !          b. If there is an observation location at 124 longitude, then:
  !             * An observation of TYPE_T (on the M-grid) would have ind = 3.9
  !             * An observation of TYPE_U (on the U-grid) would have ind = 4.4
  !
  ! II. Latitude -- y-direction
  !    A. PERIODIC (polar = .true.)
  !
  !       Consider Mass-grid (& U-Grid) latitude grid with 4 south-north gridpoints
  !         Values  :: [ -67.5 -22.5  22.5  67.5 ] 
  !         Indices :: [   1     2     3     4   ] 
  !       Complementary V-grid 
  !         Values  :: [ -90   -45     0    45    90 ] 
  !         Indices :: [   1     2     3     4     5 ] 
  !
  !       What are the allowable values for a real-valued index on each of these grids?
  !       1. M-grid  --->  [0.5 4.5]   ---> [0.5 sn+0.5]
  !                  --->  [-90 90]  
  !       2. U-grid  --->  [1 5]       ---> [1 sns]
  !                  --->  [-90 90]
  !       [Note that above "allowable values" reflect that one should be able to have
  !        an observation anywhere along a give latitude circle -- the information 
  !        exists in order to successfully interpolate to anywhere over [-90 90]; 
  !        however, in latitude this poses a special challenge since the seams join
  !        two separate columns of data over the pole, as opposed to in longitude
  !        where the seam wraps back on a single row of data.]  
  !
  !       It is up to the routine calling "boundsCheck" to have handled the 0.5 offset
  !         in indices between the M-grid & V-grid.  Hence, two examples: 
  !          a. If there is an observation location at -75 latitude, then:
  !             * An observation of TYPE_T (on the M-grid) would have ind = 0.833
  !             * An observation of TYPE_V (on the V-grid) would have ind = 1.333
  !          b. If there is an observation location at 0 latitude, then:
  !             * An observation of TYPE_T (on the M-grid) would have ind = 2.5
  !             * An observation of TYPE_V (on the V-grid) would have ind = 3.0
  !
  !    B. NOT periodic (polar = .false.)
  !
  !       Consider Mass-grid (& U-Grid) latitude grid with 4 south-north gridpoints
  !         Values  :: [ 10  20  30  40 ] 
  !         Indices :: [  1   2   3   4 ] 
  !       Complementary V-grid 
  !         Values  :: [  5  15  25  35  45 ] 
  !         Indices :: [  1   2   3   4   5 ] 
  !
  !       What are the allowable values for a real-valued index on each of these grids?
  !       1. M-grid  --->  [1 4]   ---> [1 sn]
  !                  --->  [10 40]  
  !       2. U-grid  --->  [1.5 4.5]       ---> [1.5 sn+0.5]
  !                  --->  [10 40]
  !       [Note that above "allowable values" reflect that one should only be able to
  !        have an observation within the M-grid, since that is the only way to  
  !        guarantee that the necessary information exists in order to successfully 
  !        interpolate to a specified location.]
  !
  !       It is up to the routine calling "boundsCheck" to have handled the 0.5 offset
  !         in indices between the M-grid & V-grid.  Hence, two examples: 
  !          a. If there is an observation location at 11 latitude, then:
  !             * An observation of TYPE_T (on the M-grid) would have ind = 1.1
  !             * An observation of TYPE_V (on the V-grid) would have ind = 1.6
  !          b. If there is an observation location at 25 latitude, then:
  !             * An observation of TYPE_T (on the M-grid) would have ind = 2.5
  !             * An observation of TYPE_V (on the V-grid) would have ind = 3.0
  ! 
  ! III. Vertical -- z-direction (periodicity not an issue)
  !    
  !    Consider Mass vertical grid with 4 bottom-top gridpoints
  !      Values  :: [ 0.875 0.625 0.375 0.125 ]
  !      Indices :: [   1     2     3     4   ]
  !    Complementary W-grid
  !      Values  :: [   1   0.75  0.50  0.25    0   ]
  !      Indices :: [   1     2     3     4     5   ]
  !
  !    What are the allowable values for a real-valued index on each of these grids?
  !    1. M-grid  --->  [1 4]           ---> [1 bt]
  !               --->  [0.875 0.125]  
  !    2. W-grid  --->  [1.5 4.5]       ---> [1.5 bt+0.5]
  !               --->  [0.875 0.125]
  !
  !    [Note that above "allowable values" reflect that one should only be able to
  !     have an observation within the M-grid, since that is the only way to  
  !     guarantee that the necessary information exists in order to successfully 
  !     interpolate to a specified location.]
  !

  ! Summary of Allowable REAL-VALUED Index Values ==> INTEGER Index Values 
  !
  ! In longitude (x) direction
  !   Periodic     & M_grid ==> [1 we+1)       ==> [1 wes)
  !   Periodic     & U_grid ==> [1 wes)        ==> [1 wes)
  !   NOT Periodic & M_grid ==> [1 we]         ==> [1 we)
  !   NOT Periodic & U_grid ==> [1.5 we+0.5]   ==> [1 wes)
  ! In latitude (y) direction
  !   Periodic     & M_grid ==> [0.5 sn+0.5]   ==> [0 sns) *though in practice, [1 sn)*
  !   Periodic     & V_grid ==> [1 sns]        ==> [1 sns) *though allowable range, [1.5 sn+.5]*
  !   NOT Periodic & M_grid ==> [1 sn]         ==> [1 sn)
  !   NOT Periodic & V_grid ==> [1.5 sn+0.5]   ==> [1 sns)
  ! In vertical (z) direction
  !                  M_grid ==> [1 bt]         ==> [1 bt)
  !                  W_grid ==> [1.5 bt+0.5]   ==> [1 bts)
  

  ! Assume boundsCheck is false unless we can prove otherwise
  boundsCheck = .false.

  ! First check direction (dimension)
  !   Longitude (x-direction) has dim == 1
  if ( dim == 1 ) then

     ! Next check periodicity
     if ( periodic ) then
        
        ! If periodic in longitude, then no need to check staggering because both
        !   M and U grids allow integer indices from [1 wes)
        if ( ind >= 1 .and. ind < wrf%dom(id)%wes ) boundsCheck = .true.

     else

        ! If NOT periodic in longitude, then we need to check staggering because
        !   M and U grids allow different index ranges

        ! Check staggering by comparing var_size(dim,type) to the staggered dimension 
        !   for dim == 1 stored in wrf%dom(id)
        if ( wrf%dom(id)%var_size(dim,type) == wrf%dom(id)%wes ) then
           ! U-grid allows integer range of [1 wes)
           if ( ind >= 1 .and. ind < wrf%dom(id)%wes ) boundsCheck = .true.
        else  
           ! M & V-grid allow [1 we)
           if ( ind >= 1 .and. ind < wrf%dom(id)%we ) boundsCheck = .true.
        end if

     end if

   !   Latitude (y-direction) has dim == 2
   elseif ( dim == 2 ) then

     ! Next check periodicity
     if ( periodic ) then
        
        ! We need to check staggering because M and V grids allow different indices

!*** NOTE: For now are disallowing observation locations that occur poleward of the 
!            first and last M-grid gridpoints.  This means that this function will 
!            return false for polar observations.  This need not be the case because
!            the information should be available for proper interpolation across the
!            poles, but it will require more clever thinking.  Hopefully this can 
!            be added in later.  

        ! Check staggering by comparing var_size(dim,type) to the staggered dimension 
        !   for dim == 2 stored in wrf%dom(id)
        if ( wrf%dom(id)%var_size(dim,type) == wrf%dom(id)%sns ) then
           ! V-grid allows integer range [1 sns)
           if ( ind >= 1 .and. ind < wrf%dom(id)%sns ) boundsCheck = .true.
        else  
           ! For now we will set a logical flag to more restrictively check the array
           !   bounds under our no-polar-obs assumptions
           if ( restrict_polar ) then
              ! M & U-grid allow integer range [1 sn) in practice (though properly, [0 sns) )
              if ( ind >= 1 .and. ind < wrf%dom(id)%sn ) boundsCheck = .true.
           else
              ! M & U-grid allow integer range [0 sns) in unrestricted circumstances
              if ( ind >= 0 .and. ind < wrf%dom(id)%sns ) boundsCheck = .true.
           end if
        end if
        
     else

        ! We need to check staggering because M and V grids allow different indices
        if ( wrf%dom(id)%var_size(dim,type) == wrf%dom(id)%sns ) then
           ! V-grid allows [1 sns)
           if ( ind >= 1 .and. ind < wrf%dom(id)%sns ) boundsCheck = .true.
        else 
           ! M & U-grid allow [1 sn)
           if ( ind >= 1 .and. ind < wrf%dom(id)%sn ) boundsCheck = .true.
        end if

     end if

  elseif ( dim == 3 ) then

     ! No periodicity to worry about in the vertical!  However, we still need to check
     !   staggering because the ZNU and ZNW grids allow different index ranges
     if ( wrf%dom(id)%var_size(dim,type) == wrf%dom(id)%bts ) then
        ! W vertical grid allows [1 bts)
        if ( ind >= 1 .and. ind < wrf%dom(id)%bts ) boundsCheck = .true.
     else
        ! M vertical grid allows [1 bt)
        if ( ind >= 1 .and. ind < wrf%dom(id)%bt ) boundsCheck = .true.
     end if
  
  else

     print*, 'model_mod.f90 :: function boundsCheck :: dim must equal 1, 2, or 3!'

  end if


end function boundsCheck

!#######################################################################
! getCorners takes in an i and j index, information about domain and grid staggering, 
!   and then returns the four cornering gridpoints' 2-element integer indices. 
subroutine getCorners(i, j, id, type, ll, ul, lr, ur, rc)

  implicit none

  integer, intent(in)  :: i, j, id, type
  integer, dimension(2), intent(out) :: ll, ul, lr, ur
  integer, intent(out) :: rc

!  logical, parameter :: restrict_polar = .true.
  logical, parameter :: restrict_polar = .false.

  ! set return code to 0, and change this if necessary
  rc = 0

  !----------------
  ! LOWER LEFT
  !----------------

  ! i and j are the lower left (ll) corner already
  !
  ! NOTE :: once we allow for polar periodicity, the incoming j index could actually 
  !           be 0, which would imply a ll(2) value of 1, with a ll(1) value 180 degrees
  !           of longitude away from the incoming i index!  But we have not included 
  !           this possibility yet.  

  ! As of 22 Oct 2007, this option is not allowed!
  !   Note that j = 0 can only happen if we are on the M (or U) wrt to latitude
  if ( wrf%dom(id)%polar .and. j == 0 .and. .not. restrict_polar ) then

     ! j = 0 should be mapped to j = 1 (ll is on other side of globe)
     ll(2) = 1
     
     ! Need to map i index 180 degrees away
     ll(1) = i + wrf%dom(id)%we/2
     
     ! Check validity of bounds & adjust by periodicity if necessary
     if ( ll(1) > wrf%dom(id)%we ) ll(1) = ll(1) - wrf%dom(id)%we

     ! We shouldn't be able to get this return code if restrict_polar = .true.
!     rc = 1
!     print*, 'model_mod.f90 :: getCorners :: Tried to do polar bc -- rc = ', rc

  else
     
     ll(1) = i
     ll(2) = j

  end if


  !----------------
  ! LOWER RIGHT
  !----------------

  ! Most of the time, the lower right (lr) corner will simply be (i+1,j), but we need to check
  ! Summary of x-direction corners:
  !   Periodic     & M_grid has ind = [1 wes)
  !     ind = [1 we)    ==> ind_p_1 = ind + 1
  !     ind = [we wes)  ==> ind_p_1 = 1
  !   Periodic     & U_grid has ind = [1 wes)
  !     ind = [1 we)    ==> ind_p_1 = ind + 1
  !     ind = [we wes)  ==> ind_p_1 = wes       ( keep in mind that U(1) = U(wes) if periodic )
  !   NOT Periodic & M_grid has ind = [1 we)
  !     ind = [1 we-1)  ==> ind_p_1 = ind + 1
  !     ind = [we-1 we) ==> ind_p_1 = we
  !   NOT Periodic & U_grid has ind = [1 wes)
  !     ind = [1 we)    ==> ind_p_1 = ind + 1
  !     ind = [we wes)  ==> ind_p_1 = wes 

  if ( wrf%dom(id)%periodic_x ) then
    
     ! Check to see what grid we have, M vs. U
     if ( wrf%dom(id)%var_size(1,type) == wrf%dom(id)%wes ) then
        ! U-grid is always i+1 -- do this in reference to already adjusted ll points
        lr(1) = ll(1) + 1
        lr(2) = ll(2)
     else
        ! M-grid is i+1 except if we <= ind < wes, in which case it's 1
        if ( i < wrf%dom(id)%we ) then
           lr(1) = ll(1) + 1
        else
           lr(1) = 1
        end if
        lr(2) = ll(2)
     end if

  else

     ! Regardless of grid, NOT Periodic always has i+1
     lr(1) = ll(1) + 1
     lr(2) = ll(2)

  end if
        

  !----------------
  ! UPPER LEFT
  !----------------

!*** NOTE: For now are disallowing observation locations that occur poleward of the 
!            first and last M-grid gridpoints.  This need not be the case because
!            the information should be available for proper interpolation across the
!            poles, but it will require more clever thinking.  Hopefully this can 
!            be added in later.

  ! Most of the time, the upper left (ul) corner will simply be (i,j+1), but we need to check
  ! Summary of y-direction corners:
  !   Periodic     & M_grid has ind = [0 sns)  *though in practice, [1 sn)*
  !     ind = [1 sn-1)  ==> ind_p_1 = ind + 1
  !     ind = [sn-1 sn) ==> ind_p_1 = sn
  !   Periodic     & V_grid has ind = [1 sns) 
  !     ind = [1 sn)    ==> ind_p_1 = ind + 1
  !     ind = [sn sns)  ==> ind_p_1 = sns  
  !   NOT Periodic & M_grid has ind = [1 sn)
  !     ind = [1 sn-1)  ==> ind_p_1 = ind + 1
  !     ind = [sn-1 sn) ==> ind_p_1 = sn
  !   NOT Periodic & V_grid has ind = [1 sns)
  !     ind = [1 sn)    ==> ind_p_1 = ind + 1
  !     ind = [sn sns)  ==> ind_p_1 = sns 
  !
  ! Hence, with our current polar obs restrictions, all four possible cases DO map into
  !   ul = (i,j+1).  But this will not always be the case.
  
  if ( wrf%dom(id)%polar ) then

     ! Check to see what grid we have, M vs. V
     if ( wrf%dom(id)%var_size(2,type) == wrf%dom(id)%sns ) then
        ! V-grid is always j+1, even if we allow for full [1 sns) range
        ul(1) = ll(1)
        ul(2) = ll(2) + 1
     else
        ! M-grid changes depending on polar restriction
        if ( restrict_polar ) then 
           ! If restricted, then we can simply add 1
           ul(1) = ll(1)
           ul(2) = ll(2) + 1
        else
           ! If not restricted, then we can potentially wrap over the north pole, which 
           !   means that ul(2) is set to sn and ul(1) is shifted by 180 deg.

           if ( j == wrf%dom(id)%sn ) then
              ! j > sn should be mapped to j = sn (ul is on other side of globe)
              ul(2) = wrf%dom(id)%sn
     
              ! Need to map i index 180 degrees away
              ul(1) = ll(1) + wrf%dom(id)%we/2
     
              ! Check validity of bounds & adjust by periodicity if necessary
              if ( ul(1) > wrf%dom(id)%we ) ul(1) = ul(1) - wrf%dom(id)%we

              ! We shouldn't be able to get this return code if restrict_polar = .true.
!              rc = 1
!              print*, 'model_mod.f90 :: getCorners :: Tried to do polar bc -- rc = ', rc

           elseif ( j == 0 ) then
              ! In this case, we have place ll on the other side of the globe, so we 
              !   cannot reference ul to ll
              ul(1) = i
              ul(2) = 1

           else
              ! We can confidently set to j+1
              ul(1) = ll(1)
              ul(2) = ll(2) + 1
           end if

        end if
     end if

  else

     ! Regardless of grid, NOT Periodic always has j+1
     ul(1) = ll(1) 
     ul(2) = ll(2) + 1

  end if
     

  !----------------
  ! UPPER RIGHT
  !----------------

!*** NOTE: For now are disallowing observation locations that occur poleward of the 
!            first and last M-grid gridpoints.  This need not be the case because
!            the information should be available for proper interpolation across the
!            poles, but it will require more clever thinking.  Hopefully this can 
!            be added in later.

  ! Most of the time, the upper right (ur) corner will simply be (i+1,j+1), but we need to check
  !   In fact, we can largely get away with ur = (lr(1),ul(2)).  Where this will NOT work is
  !   where we have had to re-map the i index to the other side of the globe (180 deg) due to 
  !   the polar boundary condition.  There are no situations where ur(2) will not be equal to
  !   ul(2).  

  ur(2) = ul(2)

  ! Need to check if ur(1) .ne. lr(1)
  if ( wrf%dom(id)%polar .and. .not. restrict_polar ) then

     ! Only if j == 0 or j == sn
     if ( j == 0 .or. j ==  wrf%dom(id)%sn) then
        ! j == 0 means that ll(1) = i + 180 deg, so we cannot use lr(1) -- hence, we will
        !   add 1 to ul(1), unless doing so spans the longitude seam point.
        ! j == sn means that ul(1) = i + 180 deg.  Here we cannot use lr(1) either because
        !   it will be half a domain away from ul(1)+1.  Be careful of longitude seam point.

        !   Here we need to check longitude periodicity and the type of grid
        if ( wrf%dom(id)%periodic_x ) then
    
           ! Check to see what grid we have, M vs. U
           if ( wrf%dom(id)%var_size(1,type) == wrf%dom(id)%wes ) then
              ! U-grid is always i+1 -- do this in reference to already adjusted ll points
              ur(1) = ul(1) + 1
           else
              ! M-grid is i+1 except if we <= ind < wes, in which case it's 1
              if ( ul(1) < wrf%dom(id)%we ) then
                 ur(1) = ul(1) + 1
              else
                 ur(1) = 1
              end if
           end if

        else

           ! Regardless of grid, NOT Periodic always has i+1
           ur(1) = ul(1) + 1

        end if

     ! If not a special j value, then we are set for the ur(1) = lr(1)
     else

        ur(1) = lr(1)

     end if

  ! If not an unrestricted polar periodic domain, then we have nothing to worry about
  else

     ur(1) = lr(1)

  end if

end subroutine getCorners


end module model_mod

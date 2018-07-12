! DART software - Copyright UCAR. This open source software is provided
! by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download
!
! DART $Id$

module noah_hydro_mod

use            types_mod, only : r4, r8, i8, MISSING_R8, MISSING_I, MISSING_I8

use        utilities_mod, only : register_module, error_handler, to_upper, &
                                 E_ERR, E_MSG, file_exist, do_output, &
                                 nmlfileunit, do_nml_file, do_nml_term,  &
                                 find_namelist_in_file, check_namelist_read

use             map_utils, only : proj_info, map_init, map_set

use misc_definitions_module, only : PROJ_LATLON, PROJ_MERC, PROJ_LC, &
                                    PROJ_PS, PROJ_CASSINI, PROJ_CYL

use    mpi_utilities_mod, only : my_task_id 

use netcdf_utilities_mod, only : nc_check, nc_open_file_readonly, nc_close_file, &
                                 nc_get_global_attribute, nc_add_global_attribute

use netcdf

implicit none
private

!>@todo check to make sure all public routines initialize the module ...

public :: configure_lsm, &
          configure_hydro, &
          n_link, &
          linkLong, &
          linkLat, &
          linkAlt, &
          get_link_tree, &
          full_to_connection, &
          get_downstream_links, &
          get_noah_timestepping, &
          num_soil_layers, &
          soil_layer_thickness, &
          lsm_namelist_filename, &
          get_lsm_domain_info, &
          wrf_static_data, &
          get_lsm_domain_filename, &
          read_hydro_global_atts, write_hydro_global_atts , &
          read_noah_global_atts, write_noah_global_atts 

! version controlled file description for error handling, do not edit
character(len=*), parameter :: source   = "$URL$"
character(len=*), parameter :: revision = "$Revision$"
character(len=*), parameter :: revdate  = "$Date$"

logical, save :: module_initialized = .false.

character(len=512) :: string1, string2, string3

integer :: debug = 0

!------------------------------------------------------------------
! From the models' namelists we get everything needed to recreate
! specify these (for restarts after DART filters).
! For both noah and noahMP the namelist is called namelist.hrldas

character(len=*),parameter :: lsm_namelist_filename = 'namelist.hrldas'
character(len=*),parameter :: hydro_namelist_filename = 'hydro.namelist'
integer,         parameter :: NSOLDX = 100

!! &HYDRO_nlist
!! The noah and noahMP models have some same/repeated variables in their respective namelists.
!! I note repeated varaibles and any related issues here.
!! Note: These are default values in case a variable is not specified in the namelist.
integer             :: sys_cpl          = 1  !! this is hrldas, should be enforced
character(len=256)  :: geo_static_flnm = ''
character(len=256)  :: geo_finegrid_flnm = ''
character(len=256)  :: hydrotbl_f   = ''
character(len=1024) :: land_spatial_meta_flnm = ''
character(len=256)  :: restart_file  = ''
integer             :: igrid = 3
integer             :: rst_dt = 1440
integer             :: out_dt = 1440
integer             :: split_output_count = 1  !! repeated but equal
integer             :: rst_typ = 1
integer             :: rstrt_swc = 0
integer             :: order_to_write = 1
integer             :: teradj_solar = 0
integer             :: nsoil=4  !! repeated but equal
real(r8), dimension(NSOLDX) :: zsoil8  !! this is for the hydro component (bad name)
real(r8)            :: dxrt = -999.0_r8
integer             :: aggfactrt = -999
integer             :: dtrt_ter = 2
integer             :: dtrt_ch = 2
integer             :: subrtswcrt = 1
integer             :: ovrtswcrt = 1
integer             :: rt_option    = 1
integer             :: chanrtswcrt = 1
integer             :: channel_option = 3
character(len=256)  :: route_link_f = ''
character(len=256)  :: route_lake_f = ''
integer             :: gwbaseswcrt = 2
integer             :: gw_restart = 1
character(len=256)  :: gwbasmskfil = 'DOMAIN/basn_msk1k_frng_ohd.txt'
character(len=256)  :: gwbuckparm_file = ''
character(len=256)  :: udmap_file =''
integer             :: iocflag, nwmIo, t0OutputFlag, udmp_opt, output_channelBucket_influx
integer             :: chrtout_domain, chrtout_grid, lsmout_domain, rtout_domain, output_gw, outlake
integer             :: rst_bi_out
integer             :: rst_bi_in
integer             :: frxst_pts_out
integer             :: chanobs_domain
integer             :: io_config_outputs
integer             :: io_form_outputs


namelist /HYDRO_nlist/ sys_cpl, geo_static_flnm, geo_finegrid_flnm,  &
     hydrotbl_f, land_spatial_meta_flnm, restart_file, &
     igrid, rst_dt, rst_typ, rst_bi_in, rst_bi_out, rstrt_swc, &
     gw_restart, out_dt, split_output_count, order_to_write, nwmIo, iocflag, &
     t0OutputFlag, output_channelBucket_influx, &
     chrtout_domain, chrtout_grid, lsmout_domain, rtout_domain, output_gw, outlake, &
     teradj_solar, nsoil, zsoil8, dxrt, aggfactrt, dtrt_ter, dtrt_ch, subrtswcrt, &
     ovrtswcrt, rt_option, chanrtswcrt, channel_option, route_link_f, route_lake_f, &
     gwbaseswcrt, gwbuckparm_file, gwbasmskfil, udmp_opt, udmap_file, &
     frxst_pts_out, chanobs_domain, io_config_outputs, io_form_outputs


!-----------------------------------------------------------------------
!> variables accessed by public functions

integer :: num_soil_layers = -1
real(r8) :: soil_layer_thickness(NSOLDX)
character(len=256) :: lsm_domain_file(1)   ! 1 domain in this application

!-----------------------------------------------------------------------

real(r8), allocatable, dimension(:,:) :: xlong, xlat  ! LSM   grid
real(r8), allocatable, dimension(:,:) :: hlong, hlat  ! Hydro grid
real(r8), allocatable, dimension(:) :: linkLat
real(r8), allocatable, dimension(:) :: linkLong
real(r8), allocatable, dimension(:) :: linkAlt
real(r8), allocatable, dimension(:) :: roughness  ! Manning's roughness
real(r8), allocatable, dimension(:) :: channelIndsX, channelIndsY
real(r8), allocatable, dimension(:) :: basnMask, basnLon, basnLat
integer,  allocatable, dimension(:) :: linkID ! Link ID (NHDFlowline_network COMID)
real(r4), allocatable, dimension(:) :: length
integer,  allocatable, dimension(:) :: downstream
integer,  allocatable, dimension(:,:) :: upstream

integer, parameter :: IDSTRLEN = 15 ! must match declaration in netCDF file
character(len=IDSTRLEN), allocatable, dimension(:) :: gageID ! NHD Gage Event ID from SOURCE_FEA field in Gages feature class

integer :: south_north, west_east, n_hlong, n_hlat, n_link, n_basn, n_upstream

integer, dimension(2)               :: fine2dShape, coarse2dShape
integer, dimension(3)               :: fine3dShape, coarse3dShape

!! Following are global because they are used in multiple subroutines.
real(R8), dimension(:,:,:), allocatable :: smc, sice, sh2oMaxRt, sh2oWltRt
real(R8), dimension(:,:),   allocatable ::              smcMax1, smcWlt1

!! Used to hold the fine res variables to be adjusted. Not allocated if not used.
real(R8), dimension(:,:,:), allocatable :: sh2oDisag
real(R8), dimension(:,:),   allocatable :: sfcHeadDisag

real(r8) :: fineGridArea, coarseGridArea
logical :: hydroSmcPresent, hydroSfcHeadPresent

! user-defined type to enable a 'linked list' of stream links
type link_relations
   private
   character(len=IDSTRLEN) :: gageName           = ' '
   integer                 :: linkID             = MISSING_I
   real(r4)                :: linkLength         = 0.0_r8      ! stream length (meters)
   integer(i8)             :: domain_offset      = MISSING_I8  ! into DART state vector
   integer                 :: downstream_linkID  = MISSING_I
   integer                 :: upstream_linkID(2) = MISSING_I
   integer                 :: to_link_index      = MISSING_I   ! into link_type structure
   integer                 :: from_link_index(2) = MISSING_I   ! into link_type structure
end type link_relations
type(link_relations), allocatable :: connections(:)


type noah_dynamics
   integer :: day       = 0
   integer :: hour      = 0
   integer :: dynamical = 0
   integer :: output    = 0
   integer :: forcing   = 0
   integer :: restart   = 0
end type noah_dynamics

type(noah_dynamics) :: timestepping

! Each WRF domain has its own geometry/metadata
! This is used by NOAH

type wrf_static_data
   character(len=256) :: filename   = ''
   character(len=256) :: title      = ''
   character(len=256) :: start_date = ''
   type(proj_info) :: proj
   integer         :: map_proj    = -1
   integer         :: sn          = 0
   integer         :: we          = 0
   logical         :: scm         = .false.
   logical         :: periodic_x  = .false.
   logical         :: periodic_y  = .false.
   logical         :: polar       = .false.
   real(r8)        :: lat1        = MISSING_R8
   real(r8)        :: lon1        = MISSING_R8
   real(r8)        :: dx          = MISSING_R8
   real(r8)        :: dy          = MISSING_R8
   real(r8)        :: truelat1    = MISSING_R8
   real(r8)        :: truelat2    = MISSING_R8
   real(r8)        :: stand_lon   = MISSING_R8
   real(r8)        :: pole_lat    = 90.0_r8
   real(r8)        :: pole_lon    =  0.0_r8
end type wrf_static_data

type(wrf_static_data) :: noah_global_atts

type hydro_static_data
   character(len=256) :: filename     = ''
   character(len=256) :: Restart_Time = ''
   character(len=256) :: Since_Date   = ''
   real(r8)           :: DTCT
   integer            :: channel_only
   integer            :: channelBucket_only
end type hydro_static_data

type(hydro_static_data) :: hydro_global_atts

contains

!-----------------------------------------------------------------------
!>

subroutine configure_lsm(model_choice)

character(len=*), intent(in) :: model_choice

character(len=*), parameter :: routine = 'configure_lsm'
logical, save :: lsm_namelist_read = .false.

character(len=len_trim(model_choice)) :: version
character(len=256) :: hrldas_setup_file
 
if ( lsm_namelist_read ) return ! only need to read namelists once

version = model_choice
call to_upper(version)

select case (version)
   case ('NOAHMP_36')
      call read_36_namelist(hrldas_setup_file)
   case default
      call read_noah_namelist(hrldas_setup_file)
end select

lsm_namelist_read = .true.

! This gets the LSM geospatial information for the module:
!   south_north, west_east, xlong, xlat

lsm_domain_file(1) = hrldas_setup_file

call get_hrldas_constants(hrldas_setup_file)

end subroutine configure_lsm


!-----------------------------------------------------------------------
!>

subroutine configure_hydro()

character(len=*), parameter :: routine = 'configure_hydro'

integer :: iunit, io
logical, save :: hydro_namelist_read = .false.

if ( hydro_namelist_read ) return ! only need to read namelists once

hydro_namelist_read = .true.

! The hydro namelist file MUST be available.
if ( file_exist(hydro_namelist_filename) ) then
   call find_namelist_in_file(hydro_namelist_filename, 'HYDRO_nlist', iunit)
   read(iunit, nml = HYDRO_nlist, iostat = io)
   call check_namelist_read(iunit, io, 'HYDRO_nlist')
else
   write(string1,*) 'hydro namelist file "', trim(hydro_namelist_filename),'" does not exist.'
   call error_handler(E_ERR,routine,string1,source,revision,revdate)
endif

! Though all non-soil variables are "surface" it may be advisable to extract 
! elevation at this point?  for localization routines?
! **** NOTE that all variables from this file (Fulldom) must  ****
! ****      be FLIPPED in y to match the noah/wrf model.      ****
! Note: get_hydro_constants gets gridded-channel information if gridded channel is selected. 
call get_hydro_constants(geo_finegrid_flnm)

end subroutine configure_hydro


!-----------------------------------------------------------------------
!> Read the 'wrfinput' netCDF file for grid information, etc.
!> This is all time-invariant, so we can mostly ignore the Time coordinate.

subroutine get_hrldas_constants(filename)

! MODULE variables set by this routine:
!    south_north
!    west_east
!    xlong
!    xlat

character(len=*), intent(in) :: filename

character(len=*), parameter :: routine = 'get_hrldas_constants'

integer, dimension(NF90_MAX_VAR_DIMS) :: dimIDs, ncstart, nccount
character(len=NF90_MAX_NAME)          :: dimname

integer :: io, ncid
integer :: i, DimID, VarID, numdims, dimlen, xtype

ncid = nc_open_file_readonly(filename,'get_hrldas_constants') 

io = nf90_inq_dimid(ncid, 'south_north', DimID)
call nc_check(io, routine, 'inq_dimid south_north',ncid=ncid)

io = nf90_inquire_dimension(ncid, DimID, len=south_north)
call nc_check(io, routine, 'inquire_dimension south_north',ncid=ncid)

io = nf90_inq_dimid(ncid, 'west_east', DimID)
call nc_check(io, routine, 'inq_dimid west_east',ncid=ncid)

io = nf90_inquire_dimension(ncid, DimID, len=west_east)
call nc_check(io, routine, 'inquire_dimension west_east',ncid=ncid)

! Require that the xlong and xlat are the same shape.

allocate(xlong(west_east,south_north), &
          xlat(west_east,south_north))

io = nf90_inq_varid(ncid, 'XLONG', VarID)
call nc_check(io, routine, 'inq_varid XLONG',ncid=ncid)

io = nf90_inquire_variable(ncid, VarID, dimids=dimIDs, ndims=numdims, xtype=xtype)
call nc_check(io, routine, 'inquire_variable XLONG',ncid=ncid)

! Form the start/count such that we always get the 'latest' time.

ncstart(:) = 0
nccount(:) = 0

do i = 1,numdims

   write(string1,'(''inquire dimension'',i2)') i
   io = nf90_inquire_dimension(ncid, dimIDs(i), name=dimname, len=dimlen)
   call nc_check(io, routine, string1, ncid=ncid)

   ncstart(i) = 1
   nccount(i) = dimlen

   if ((trim(dimname) == 'Time') .or. (trim(dimname) == 'time')) then
      ncstart(i) = dimlen
      nccount(i) = 1
   endif

enddo

if (debug > 99) then
   write(*,*)'DEBUG get_hrldas_constants ncstart is',ncstart(1:numdims)
   write(*,*)'DEBUG get_hrldas_constants nccount is',nccount(1:numdims)
endif

! get the longitudes

io = nf90_get_var(ncid, VarID, xlong, start=ncstart(1:numdims), &
                                      count=nccount(1:numdims))
call nc_check(io, routine, 'get_var XLONG',ncid=ncid)

where(xlong <    0.0_r8) xlong = xlong + 360.0_r8
where(xlong == 360.0_r8) xlong = 0.0_r8

! get the latitudes

io = nf90_inq_varid(ncid, 'XLAT', VarID)
call nc_check(io, routine,'inq_varid XLAT',ncid=ncid)

io = nf90_get_var(ncid, VarID, xlat, start=ncstart(1:numdims), &
                                     count=nccount(1:numdims))
call nc_check(io, routine, 'get_var XLAT',ncid=ncid)

call nc_close_file(ncid, routine)

end subroutine get_hrldas_constants


!-----------------------------------------------------------------------
!> Read the 'geo_finegrid_flnm' netCDF file for grid information, etc.
!> This is all time-invariant, so we can mostly ignore the Time coordinate.

subroutine get_hydro_constants(filename)

! MODULE variables set by this routine:
!    n_hlat, n_hlong, n_link, n_basn, basnMask
!    hlong, hlat, linkLat, linkLong

! **** NOTE that all variables from this file (Fulldom) must  ****
! ****      be FLIPPED in y to match the noah/wrf model.      ****

character(len=*), intent(in) :: filename
character(len=*), parameter :: routine = 'get_hydro_constants'

integer, dimension(NF90_MAX_VAR_DIMS) :: dimIDs, ncstart, nccount
character(len=NF90_MAX_NAME)          :: dimname
integer,  allocatable, dimension(:,:) :: basnGrid
real(r8), allocatable, dimension(:,:) :: hlongFlip ! local dummies
real(r8), allocatable, dimension(:,:) :: hlatFlip  ! local dummies
real(r8), allocatable, dimension(:)   :: channelLon1D, channelLat1D
integer,  allocatable, dimension(:)   :: basnMaskTmp

integer :: i, ii, jj, io
integer :: iunit, DimID, VarID, numdims, dimlen, xtype
integer :: indx, indx1, indx2, indx3, indx4, dumSum
logical :: nBasnWasZero

io = nf90_open(filename, NF90_NOWRITE, iunit)
call nc_check(io, routine, 'open', filename)

! The number of latitudes is dimension 'y'
io = nf90_inq_dimid(iunit, 'y', DimID)
call nc_check(io, routine, 'inq_dimid y', filename)

io = nf90_inquire_dimension(iunit, DimID, len=n_hlat)
call nc_check(io, routine,'inquire_dimension y',filename)

! The number of longitudes is dimension 'x'
io = nf90_inq_dimid(iunit, 'x', DimID)
call nc_check(io, routine,'inq_dimid x',filename)

io = nf90_inquire_dimension(iunit, DimID, len=n_hlong)
call nc_check(io, routine,'inquire_dimension x',filename)

!>@todo could just check the dimension lengths for LONGITUDE
!> and use them for all ... removes the dependency on knowing
!> the dimension names are 'y' and 'x' ... and the order.

!! module allocation
allocate(hlong(n_hlong, n_hlat))
allocate( hlat(n_hlong, n_hlat)) 

!! local allocation
allocate( basnGrid(n_hlong, n_hlat))
allocate(hlongFlip(n_hlong, n_hlat))
allocate( hlatFlip(n_hlong, n_hlat))

! Require that the xlong and xlat are the same shape.??
io = nf90_inq_varid(iunit, 'LONGITUDE', VarID)
call nc_check(io, routine,'inq_varid LONGITUDE',filename)

io = nf90_inquire_variable(iunit, VarID, dimids=dimIDs, &
                            ndims=numdims, xtype=xtype)
call nc_check(io, routine, 'inquire_variable LONGITUDE',filename)

! numdims = 2, these are all 2D fields
! Form the start/count such that we always get the 'latest' time.
ncstart(:) = 0
nccount(:) = 0
do i = 1,numdims
   write(string1,'(''LONGITUDE inquire dimension '',i2,A)') i,trim(filename)
   io = nf90_inquire_dimension(iunit, dimIDs(i), name=dimname, len=dimlen)
   call nc_check(io, routine, string1)
   ncstart(i) = 1
   nccount(i) = dimlen
   if ((trim(dimname) == 'Time') .or. (trim(dimname) == 'time')) then
      ncstart(i) = dimlen
      nccount(i) = 1
   endif
enddo !i

!>@todo ncstart, nccount are not needed if there is no time dimension 

if (debug > 99) then
   write(*,*)'DEBUG get_hydro_constants ncstart is',ncstart(1:numdims)
   write(*,*)'DEBUG get_hydro_constants nccount is',nccount(1:numdims)
endif

!get the longitudes
io = nf90_get_var(iunit, VarID, hlong, &
                  start=ncstart(1:numdims), &
                  count=nccount(1:numdims))
call nc_check(io, routine, 'get_var LONGITUDE',filename)

where(hlong <    0.0_r8) hlong = hlong + 360.0_r8
where(hlong == 360.0_r8) hlong = 0.0_r8

!get the latitudes
io = nf90_inq_varid(iunit, 'LATITUDE', VarID)
call nc_check(io, routine,'inq_varid LATITUDE',filename)
io = nf90_get_var(iunit, VarID, hlat, &
                  start=ncstart(1:numdims), &
                  count=nccount(1:numdims))
call nc_check(io, routine, 'get_var LATITUDE',filename)

where (hlat < -90.0_r8) hlat = -90.0_r8
where (hlat >  90.0_r8) hlat =  90.0_r8

! Flip the longitues and latitudes
do ii=1,n_hlong
   do jj=1,n_hlat
      hlongFlip(ii,jj) = hlong(ii,n_hlat-jj+1)
       hlatFlip(ii,jj) =  hlat(ii,n_hlat-jj+1)
   end do
end do
hlong = hlongFlip
hlat  = hlatFlip
deallocate(hlongFlip, hlatFlip)

!get the channelgrid
! i'm doing this exactly to match how it's done in the wrfHydro code 
! (line 1044 of /home/jamesmcc/WRF_Hydro/ndhms_wrf_hydro/trunk/NDHMS/Routing/module_HYDRO_io.F)
! so that the output set of indices correspond to the grid in the Fulldom file 
! and therefore these can be used to grab other channel attributes in that file. 
! but the code is really long so I've put it in a module subroutine. 
! Dont need to flip lat and lon in this (already done) but will flip other vars from Fulldom file.
! Specify channel routing option: 1=Muskingam-reach, 2=Musk.-Cunge-reach, 3=Diff.Wave-gridded

if (chanrtswcrt == 1 .or. chanrtswcrt ==2 ) then 

   if ( channel_option == 2) then

       call get_routelink_constants(route_link_f)

   else if ( channel_option == 3) then

      call getChannelGridCoords(filename, iunit, numdims, ncstart, nccount)

   else
       write(string1,'("channel_option ",i1," is not supported.")')channel_option
       call error_handler(E_ERR,routine,string1,source,revision,revdate)

   endif
else
   write(string1,'("CHANRTSWCRT ",i1," is not supported.")')chanrtswcrt
   write(string2,*)'This is specified in hydro.namelist'
   call error_handler(E_ERR,routine,string1,source,revision,revdate)
endif

!>@todo the basn_msk variable looks hosed ... does not match its own missing_value
!> if the rest of this code is enabled

call error_handler(E_MSG,routine,'basn_msk variable is hosed, skipping')

!TJH basn_msk issue ! get the basin grid - this wont need to be flipped as unique values
!TJH basn_msk issue ! are packed in to a 1D array without geolocation information.
!TJH basn_msk issue io = nf90_inq_varid(iunit, 'basn_msk', VarID)
!TJH basn_msk issue call nc_check(io, routine,'inq_varid basn_msk',filename)
!TJH basn_msk issue io = nf90_get_var(iunit, VarID, basnGrid, &
!TJH basn_msk issue                   start=ncstart(1:numdims), &
!TJH basn_msk issue                   count=nccount(1:numdims))
!TJH basn_msk issue call nc_check(io, routine, 'get_var basn_msk',filename)
!TJH basn_msk issue 
!TJH basn_msk issue write(*,*)'TJH debug maxval(basnGrid) is',maxval(basnGrid)
!TJH basn_msk issue 
!TJH basn_msk issue ! make it a 1D array of single values
!TJH basn_msk issue ! question is how to localize this, since it has no coordinates.
!TJH basn_msk issue ! for now going to use the average lat and lon of each basin
!TJH basn_msk issue allocate(basnMaskTmp(maxval(basnGrid)))  !local
!TJH basn_msk issue 
!TJH basn_msk issue basnMaskTmp(:) = -9999
!TJH basn_msk issue indx2=0
!TJH basn_msk issue do indx = 1,maxval(basnGrid)
!TJH basn_msk issue    if(any(basnGrid == indx)) then
!TJH basn_msk issue       indx2=indx2+1
!TJH basn_msk issue       basnMaskTmp(indx2) = indx
!TJH basn_msk issue    end if
!TJH basn_msk issue enddo
!TJH basn_msk issue n_basn = indx2
!TJH basn_msk issue 
!TJH basn_msk issue nBasnWasZero = .FALSE.
!TJH basn_msk issue if(n_basn == 0) then
!TJH basn_msk issue    nBasnWasZero = .true.
!TJH basn_msk issue    n_basn=1
!TJH basn_msk issue end if
!TJH basn_msk issue 
!TJH basn_msk issue allocate(basnMask(n_basn),basnLon(n_basn),basnLat(n_basn))
!TJH basn_msk issue 
!TJH basn_msk issue where(basnMaskTmp /= -9999) basnMask(:) = basnMaskTmp(1:n_basn)
!TJH basn_msk issue 
!TJH basn_msk issue deallocate(basnMaskTmp)
!TJH basn_msk issue 
!TJH basn_msk issue ! geolocate the basins
!TJH basn_msk issue do indx = 1, n_basn
!TJH basn_msk issue    basnLon = sum(hlong, basnGrid == indx) / count(basnGrid == indx)
!TJH basn_msk issue    basnLat = sum( hlat, basnGrid == indx) / count(basnGrid == indx)
!TJH basn_msk issue enddo
!TJH basn_msk issue 
!TJH basn_msk issue if(nBasnWasZero) then
!TJH basn_msk issue    basnLon = 0 !sum(hlong) / size(hlong)
!TJH basn_msk issue    basnLat = 0 !sum( hlat) / size( hlat)
!TJH basn_msk issue end if
!TJH basn_msk issue 
!TJH basn_msk issue deallocate(basnGrid)

io = nf90_close(iunit)
call nc_check(io, routine, filename)

end subroutine get_hydro_constants


!===============================================================================
!> Painful amount of code for getting the channel lat/lon/ele which matches
!> the wrfHydro state variable

subroutine getChannelGridCoords(filename, iunit, numdims, ncstart, nccount)

character(len=*),      intent(in) :: filename
integer,               intent(in) :: iunit
integer,               intent(in) :: numdims
integer, dimension(:), intent(in) :: ncstart
integer, dimension(:), intent(in) :: nccount

integer                               :: IXRT,JXRT
real(r8), allocatable, dimension(:,:) :: ELRT, ELRT_in
integer,  allocatable, dimension(:,:) :: DIRECTION, LAKE_MSKRT, channelGrid
integer,  allocatable, dimension(:,:) :: DIRECTION_in, LAKE_MSKRT_in, channelGrid_in

integer :: VarID, tmp, cnt, i, j, jj
character(len=155) :: header

!integer                                  :: NLAKES
!real(r4), allocatable, dimension(NLAKES) :: HRZAREA, LAKEMAXH, WEIRC, WEIRL
!real(r4), allocatable, dimension(NLAKES) :: ORIFICEC, ORIFICEA, ORIFICEE
!real(r4), allocatable, dimension(NLAKES) :: LATLAKE,LONLAKE,ELEVLAKE

! allocate the local variables
! these grid ones have to be flipped on y.

allocate(channelGrid_in(n_hlong,n_hlat), LAKE_MSKRT_in(n_hlong,n_hlat), &
           DIRECTION_in(n_hlong,n_hlat),       ELRT_in(n_hlong,n_hlat) )
allocate(   channelGrid(n_hlong,n_hlat),    LAKE_MSKRT(n_hlong,n_hlat), &
              DIRECTION(n_hlong,n_hlat),          ELRT(n_hlong,n_hlat) )

call nc_check(nf90_inq_varid(iunit, 'CHANNELGRID', VarID), &
     'getChannelGridCoords','inq_varid CHANNELGRID '//trim(filename))
call nc_check(nf90_get_var(iunit, VarID, channelGrid_in, &
     start=ncstart(1:numdims), count=nccount(1:numdims)), &
     'getChannelGridCoords', 'get_var CHANNELGRID '//trim(filename))

call nc_check(nf90_inq_varid(iunit, 'LAKEGRID', VarID), &
     'getChannelGridCoords','inq_varid LAKEGRID '//trim(filename))
call nc_check(nf90_get_var(iunit, VarID, LAKE_MSKRT_in, &
        start=ncstart(1:numdims), count=nccount(1:numdims)), &
        'getChannelGridCoords', 'get_var LAKEGRID '//trim(filename))

call nc_check(nf90_inq_varid(iunit, 'FLOWDIRECTION', VarID), &
     'getChannelGridCoords','inq_varid FLOWDIRECTION '//trim(filename))
call nc_check(nf90_get_var(iunit, VarID, DIRECTION_in, &
     start=ncstart(1:numdims), count=nccount(1:numdims)), &
     'getChannelGridCoords', 'get_var FLOWDIRECTION '//trim(filename))

call nc_check(nf90_inq_varid(iunit, 'TOPOGRAPHY', VarID), &
     'getChannelGridCoords','inq_varid TOPOGRAPHY '//trim(filename))
call nc_check(nf90_get_var(iunit, VarID, ELRT_in, &
     start=ncstart(1:numdims), count=nccount(1:numdims)), &
     'getChannelGridCoords', 'get_var TOPOGRAPHY '//trim(filename))

ixrt = n_hlong
jxrt = n_hlat

! wrfHydro flips the y dimension of the variables from the Fulldom file
do i=1,ixrt  !>@TJH reverse order of operations here?
   do j=1,jxrt
      channelGrid(i,j) = channelGrid_in(i,jxrt-j+1)
      LAKE_MSKRT(i,j)  =  LAKE_MSKRT_in(i,jxrt-j+1)
      DIRECTION(i,j)   =   DIRECTION_in(i,jxrt-j+1)
      ELRT(i,j)        =        ELRT_in(i,jxrt-j+1)
   end do
end do
deallocate(channelGrid_in, LAKE_MSKRT_in, DIRECTION_in, ELRT_in)

! subset to the 1D channel network as presented in the hydro restart file.
n_link = sum(channelGrid_in*0+1, mask = channelGrid <= 0)

! allocate the necessary wrfHydro variables with module scope 
allocate(channelIndsX(n_link), channelIndsY(n_link))
allocate(    linkLong(n_link),      linkLat(n_link))

! temp fix for buggy Arc export...
do j=1,jxrt
   do i=1,ixrt
      if(DIRECTION(i,j).eq.-128) DIRECTION(i,j)=128
   end do
end do

cnt = 0

!! Looks like all of the if-else statements could be removed because they all result
!! in the same action. But because this code needs to match the WRF-Hydro topology
!! setup exactly, it seems convenient to keep the overall structure identical. 
!! This topology should really be calculated off line
do j = 1, JXRT  !rows
   do i = 1 ,IXRT   !colsumns
      if (CHANNELGRID(i, j) .ge. 0) then !get its direction and assign its elevation and order
         if ((DIRECTION(i, j) .eq. 64) .and. &
             (j + 1 .le. JXRT)         .and. &
             (CHANNELGRID(i,j+1).ge.0) ) then !North
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j  !! again have to match the flip
         else if ((DIRECTION(i, j) .eq. 128) .and. &
                            (i + 1 .le. IXRT) .and. &
                            (j + 1 .le. JXRT) .and. &
                  (CHANNELGRID(i+1,j+1).ge.0) ) then !North East
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
         else if ((DIRECTION(i, j) .eq. 1) .and. &
                            (i + 1 .le. IXRT) .and. &
                (CHANNELGRID(i+1,j).ge.0) ) then !East
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
         else if ((DIRECTION(i, j) .eq. 2) .and. &
                            (i + 1 .le. IXRT) .and. &
                            (j - 1 .ne. 0) .and. &
              (CHANNELGRID(i+1,j-1).ge.0) ) then !south east
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
         else if ((DIRECTION(i, j) .eq. 4) .and. (j - 1 .ne. 0).and.(CHANNELGRID(i,j-1).ge.0) ) then !due south
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
         else if ((DIRECTION(i, j) .eq. 8) .and. (i - 1 .gt. 0) &
              .and. (j - 1 .ne. 0) .and. (CHANNELGRID(i-1,j-1).ge.0)) then !south west
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
         else if ((DIRECTION(i, j) .eq. 16) .and. (i - 1 .gt. 0).and.(CHANNELGRID(i-1,j).ge.0) ) then !West
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
         else if ((DIRECTION(i, j) .eq. 32) .and. (i - 1 .gt. 0) &
              .and. (j + 1 .le. JXRT) .and. (CHANNELGRID(i-1,j+1).ge.0) ) then !North West
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
         else
            write(string1,*)"NO MATCH", i,j
            call error_handler(E_MSG,'getChannelGridCoords',string1)
         end if

      end if !CHANNELGRID check for this node

   end do
end do

!   print *, "after exiting the channel, this many nodes", cnt
!   write(*,*) " "

!Find out if the boundaries are on an edge
do j = 1,JXRT
   do i = 1 ,IXRT
      if (CHANNELGRID(i, j) .ge. 0) then !get its direction
         !-- 64's can only flow north
         if (((DIRECTION(i, j).eq. 64) .and. (j + 1 .gt. JXRT)) .or. &
              ((DIRECTION(i, j).eq. 64) .and. (j < jxrt) .and.  &
              (CHANNELGRID(i,j+1) .lt. 0))) then !North
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
            !               print *, "Pour Point N"
         else if ( ((DIRECTION(i, j) .eq. 128) .and. (i + 1 .gt. IXRT))  &
                                !-- 128's can flow out of the North or East edge
              .or.  ((DIRECTION(i, j) .eq. 128) .and. (j + 1 .gt. JXRT))  &
                                !   this is due north edge
              .or.  ((DIRECTION(i, j) .eq. 128) .and. (i<ixrt .and. j<jxrt) .and. &
              (CHANNELGRID(i + 1, j + 1).lt.0))) then !North East
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
            !               print *, "Pour Point NE"
         else if (((DIRECTION(i, j) .eq. 1) .and. (i + 1 .gt. IXRT)) .or. &    !-- 1's can only flow due east
              ((DIRECTION(i, j) .eq. 1) .and. (i<ixrt) .and. (CHANNELGRID(i + 1, j) .lt. 0))) then !East
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
            !               print *, "Pour Point E"
         else if ( ((DIRECTION(i, j) .eq. 2) .and. (i + 1 .gt. IXRT))    &      !-- 2's can flow out of east or south edge
              .or. ((DIRECTION(i, j) .eq. 2) .and. (j - 1 .eq. 0))       &      !-- this is the south edge
              .or. ((DIRECTION(i, j) .eq. 2) .and. (i<ixrt .and. j>1) .and.(CHANNELGRID(i + 1, j - 1) .lt.0))) then !south east
            cnt = cnt + 1
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
            !               print *, "Pour Point SE"
         else if (((DIRECTION(i, j) .eq. 4) .and. (j - 1 .eq. 0)) .or. &       !-- 4's can only flow due south
              ((DIRECTION(i, j) .eq. 4) .and. (j>1) .and.(CHANNELGRID(i, j - 1) .lt. 0))) then !due south
            cnt = cnt + 1
            !ZELEV(cnt) = ELRT(i,j)
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
            !               print *, "Pour Point S"
         else if ( ((DIRECTION(i, j) .eq. 8) .and. (i - 1 .le. 0))      &      !-- 8's can flow south or west
              .or.  ((DIRECTION(i, j) .eq. 8) .and. (j - 1 .eq. 0))      &      !-- this is the south edge
              .or.  ((DIRECTION(i, j).eq.8).and. (i>1 .and. j>1) .and.(CHANNELGRID(i - 1, j - 1).lt.0))) then !south west
            cnt = cnt + 1
            !ZELEV(cnt) = ELRT(i,j)
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
            !               print *, "Pour Point SW"
         else if (((DIRECTION(i, j) .eq. 16) .and. (i - 1 .le.0) ) &                  !16's can only flow due west
              .or.((DIRECTION(i, j).eq.16) .and. (i>1) .and.(CHANNELGRID(i - 1, j).lt.0))) then !West
            cnt = cnt + 1
            !ZELEV(cnt) = ELRT(i,j)
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
            !               print *, "Pour Point W"
         else if ( ((DIRECTION(i, j) .eq. 32) .and. (i - 1 .le. 0))      &      !-- 32's can flow either west or north
              .or.  ((DIRECTION(i, j) .eq. 32) .and. (j + 1 .gt. JXRT))   &      !-- this is the north edge
              .or.  ((DIRECTION(i, j).eq.32) .and. (i>1 .and. j<jxrt) .and.(CHANNELGRID(i - 1, j + 1).lt.0))) then !North West
            cnt = cnt + 1
            !ZELEV(cnt) = ELRT(i,j)
            linkLat(cnt) = hlat(i,j)
            linkLong(cnt) = hlong(i,j)
            channelIndsX(cnt) = i
            channelIndsY(cnt) = j
            !               print *, "Pour Point NW"
         endif
      endif !CHANNELGRID check for this node
   end do
end do

!close(79)

deallocate(channelGrid, LAKE_MSKRT, DIRECTION, ELRT)

if (cnt .ne. n_link) then
   write(string1,*) 'Error with number of links in the channel grid.'
   call error_handler(E_ERR,'getChannelGridCoords',string1,source,revision,revdate)
endif

end subroutine getChannelGridCoords


!-----------------------------------------------------------------------
!> read the necessary 'route_link_f' file variables. 

subroutine get_routelink_constants(filename)

! char  gages(linkDim, IDLength) ;
!       gages:long_name = "NHD Gage Event ID from SOURCE_FEA field in Gages feature class" ;
!       gages:coordinates = "lat lon" ;
! int   link(linkDim) ;
!       link:long_name = "Link ID (NHDFlowline_network COMID)" ;
!       link:cf_role = "timeseries_id" ;
!       link:coordinates = "lat lon" ;
! float lat(linkDim) ;
!       lat:long_name = "latitude of the start node" ;
!       lat:units = "degrees_north" ;
!       lat:standard_name = "latitude" ;
!       lat:coordinates = "lat lon" ;
! float lon(linkDim) ;
!       lon:long_name = "longitude of the start node" ;
!       lon:units = "degrees_east" ;
!       lon:standard_name = "longitude" ;
!       lon:coordinates = "lat lon" ;
!float alt(linkDim) ;
!	alt:long_name = "Elevation in meters from the North American Vertical Datum 1988 (NADV88) at start node (MaxElevSmo)" ;
!	alt:standard_name = "height" ;
!	alt:units = "m" ;
!	alt:positive = "up" ;
!	alt:axis = "Z" ;
!	alt:coordinates = "lat lon" ;
!float Length(linkDim) ;
!       Length:long_name = "Stream length (m)" ;
!       Length:coordinates = "lat lon" ;
!int to(linkDim) ;
!       to:long_name = "To Link ID (PlusFlow table TOCOMID for every FROMCOMID)" ;
!       to:coordinates = "lat lon" ;
!int upstreamLinks(linkDim, localDim) ;
!       localLinks:units = " " ;
!       localLinks:_FillValue = -9999 ;
!float n(linkDim) ;
!	n:long_name = "Manning\'s roughness" ;
!	n:coordinates = "lat lon" ;

! module variables set: n_link, linkLong, linkLat, linkAlt, roughness, linkID, gageID
! module variables set: channelIndsX, channelIndsY

character(len=*), intent(in) :: filename

character(len=*), parameter :: routine = 'get_routelink_constants'

integer :: io, iunit, DimID, i, VarID, strlen

!! open the file
io = nf90_open(filename, NF90_NOWRITE, iunit)
call nc_check(io, routine, 'open', filename)

!! get the linkDim ID and its length ... n_link
io = nf90_inq_dimid(iunit, 'linkDim', DimID)
call nc_check(io, routine,'inq_dimid','linkDim', filename)
io = nf90_inquire_dimension(iunit, DimID, len=n_link)
call nc_check(io, routine,'inquire_dimension','linkDim',filename)

!! Need to test the character string length for the linkID
io = nf90_inq_dimid(iunit, 'IDLength', DimID)
call nc_check(io, routine,'inq_dimid','IDLength', filename)
io = nf90_inquire_dimension(iunit, DimID, len=strlen)
call nc_check(io, routine,'inquire_dimension','IDLength',filename)

if (strlen /= IDSTRLEN) then 
   write(string1,*)'IDLength read as ',strlen,' expected ',IDSTRLEN
   write(string2,*)'Required to interpret "gages" variable in'
   call error_handler(E_ERR, routine, string1, source, revision, &
              revdate, text2=string2, text3=filename)
endif

! get the upstream links dimensionality
io = nf90_inq_dimid(iunit, 'localDim', DimID)
call nc_check(io, routine,'inq_dimid','localDim', filename)
io = nf90_inquire_dimension(iunit, DimID, len=n_upstream)
call nc_check(io, routine,'inquire_dimension','localDim',filename)

!! Allocate these module variables
allocate(linkLong(n_link), linkLat(n_link), linkAlt(n_link))
allocate(roughness(n_link))
allocate(linkID(n_link))
allocate(gageID(n_link))
allocate(channelIndsX(n_link), channelIndsY(n_link))
allocate(connections(n_link))
allocate(length(n_link))
allocate(downstream(n_link))
allocate(upstream(n_upstream,n_link))

! Longitude [DART uses longitudes [0,360)]
io = nf90_inq_varid(iunit, 'lon', VarID)
call nc_check(io, routine, 'inq_varid', 'lon', filename)
io = nf90_get_var(iunit, VarID, linkLong)
call nc_check(io, routine, 'get_var', 'lon', filename)

where(linkLong < 0.0_r8)    linkLong = linkLong + 360.0_r8
where(linkLong == 360.0_r8) linkLong = 0.0_r8

! Latitude
io = nf90_inq_varid(iunit, 'lat', VarID)
call nc_check(io, routine, 'inq_varid', 'lat', filename)
io = nf90_get_var(iunit, VarID, linkLat)
call nc_check(io, routine, 'get_var', 'lat', filename)

! Elevation from the North American Vertical Datum 1988 (NADV88)
io = nf90_inq_varid(iunit, 'alt', VarID)
call nc_check(io, routine, 'inq_varid', 'alt', filename)
io = nf90_get_var(iunit, VarID, linkAlt)
call nc_check(io, routine, 'get_var', 'alt', filename)

! Manning's roughness
io = nf90_inq_varid(iunit, 'n', VarID)
call nc_check(io, routine, 'inq_varid', 'n', filename)
io = nf90_get_var(iunit, VarID, roughness)
call nc_check(io, routine, 'get_var', 'n', filename)

! NHD Gage Event ID from SOURCE_FEA field in Gages feature class
io = nf90_inq_varid(iunit, 'gages', VarID)
call nc_check(io, routine, 'inq_varid', 'gages', filename)
io = nf90_get_var(iunit, VarID,  gageID)
call nc_check(io, routine, 'get_var', 'gages', filename)

! Link ID (NHDFlowline_network COMID)
io = nf90_inq_varid(iunit, 'link', VarID)
call nc_check(io, routine, 'inq_varid', 'link', filename)
io = nf90_get_var(iunit, VarID, linkID)
call nc_check(io, routine, 'get_var', 'link', filename)

! Length (Stream length (m))
io = nf90_inq_varid(iunit, 'Length', VarID)
call nc_check(io, routine, 'inq_varid', 'Length', filename)
io = nf90_get_var(iunit, VarID, length)
call nc_check(io, routine, 'get_var', 'Length', filename)

! "To Link ID (PlusFlow table TOCOMID for every FROMCOMID)"
io = nf90_inq_varid(iunit, 'to', VarID)
call nc_check(io, routine, 'inq_varid', 'to', filename)
io = nf90_get_var(iunit, VarID, downstream)
call nc_check(io, routine, 'get_var', 'to', filename)

! upstreamLinks  ... TBD
io = nf90_inq_varid(iunit, 'localLinks', VarID)
call nc_check(io, routine, 'inq_varid', 'localLinks', filename)
io = nf90_get_var(iunit, VarID, upstream)
call nc_check(io, routine, 'get_var', 'localLinks', filename)

io = nf90_close(iunit)
call nc_check(io, routine, filename)

! Not sure what these are for ...
channelIndsX = (/ (i, i=1,n_link) /)
channelIndsY = (/ (i, i=1,n_link) /)

call fill_connections()

if (debug > 99) then
   do i=1,n_link
      write(*,*)'link ',i,linkLong(i),linkLat(i),linkAlt(i),gageID(i),roughness(i),linkID(i)
   enddo

   write(*,*)'Longitude range is ',minval(linkLong),maxval(linkLong)
   write(*,*)'Latitude  range is ',minval(linkLat),maxval(linkLat)
   write(*,*)'Altitude  range is ',minval(linkAlt),maxval(linkAlt)
endif

deallocate(gageID)
deallocate(linkID)
deallocate(length)
deallocate(downstream)
deallocate(upstream)

end subroutine get_routelink_constants


!-----------------------------------------------------------------------
!> 

subroutine fill_connections()

integer :: i, j, k

! hydro_domain_offset = 0   !>@todo get the actual offset somehow

do i = 1,n_link
   connections(i)%gageName               = gageID(i)
   connections(i)%linkID                 = linkID(i)
   connections(i)%linkLength             = length(i)
   connections(i)%domain_offset          = i
   connections(i)%downstream_linkID      = downstream(i)
   connections(i)%upstream_linkID        = upstream(:,i)
   connections(i)%to_link_index          = MISSING_I
   connections(i)%from_link_index        = MISSING_I 
enddo

! Now try to figure out the linking structure

DOWN1 : do i = 1,n_link  ! loops over dimension to fill
DOWN2 : do j = 1,n_link  ! loops over dimension to query
   if (connections(i)%downstream_linkID == connections(j)%linkID) then
       connections(i)%to_link_index     = j
       exit DOWN2
   endif
enddo DOWN2
enddo DOWN1

UP1 : do i = 1,n_link  ! loops over dimension to fill
UP2 : do j = 1,n_link  ! loops over dimension to query
   do k=1,n_upstream
      if (connections(i)%upstream_linkID(k) == connections(j)%linkID) then
          connections(i)%from_link_index(k) = j 
      endif
   enddo
   !>@todo should be a way to exit UP2 early ... after two links are found, perhaps?
enddo UP2
enddo UP1

if (debug > 99) then
   write(string1,'("PE ",i7)') my_task_id()
   do i = 1,n_link
   write(*,*)''
   write(*,*)trim(string1),' connectivity for link : ',i
   write(*,*)trim(string1),' gageName              : ',connections(i)%gageName
   write(*,*)trim(string1),' linkID                : ',connections(i)%linkID
   write(*,*)trim(string1),' linkLength            : ',connections(i)%linkLength
   write(*,*)trim(string1),' domain_offset         : ',connections(i)%domain_offset
   
   write(*,*)trim(string1),' downstream_linkID     : ',connections(i)%downstream_linkID
   write(*,*)trim(string1),' to_link_index         : ',connections(i)%to_link_index
   
   write(*,*)trim(string1),' upstream_linkID       : ',connections(i)%upstream_linkID
   write(*,*)trim(string1),' from_link_index       : ',connections(i)%from_link_index
   enddo
endif

end subroutine fill_connections


!-----------------------------------------------------------------------
!> 

recursive subroutine get_link_tree(my_index, reach_cutoff, depth, &
                    reach_length, nclose, close_indices, distances)

integer,     intent(in)    :: my_index
real(r8),    intent(in)    :: reach_cutoff   ! meters
integer,     intent(in)    :: depth
real(r8),    intent(inout) :: reach_length
integer,     intent(inout) :: nclose
integer(i8), intent(inout) :: close_indices(:)
real(r8),    intent(inout) :: distances(:)

real(r8) :: direct_length
integer  :: iup

direct_length = reach_length

if (depth > 1) direct_length = direct_length + connections(my_index)%linkLength

if (debug > 99) then
   write(string1,'("PE ",i7)') my_task_id()
   write(*,*)trim(string1)
   write(*,*)trim(string1),' glt:my_index      ', my_index
   write(*,*)trim(string1),' glt:depth         ', depth
   write(*,*)trim(string1),' glt:reach_length  ', reach_length
   write(*,*)trim(string1),' glt:direct_length ', direct_length
endif

! reach_length may also need to include elevation change
if (direct_length >= reach_cutoff) return

nclose                = nclose + 1
close_indices(nclose) = my_index
distances(nclose)     = direct_length

if (debug > 99) then
   write(*,*)trim(string1),' glt:task, nclose        ', nclose
   write(*,*)trim(string1),' glt:task, close_indices ', close_indices(1:nclose)
   write(*,*)trim(string1),' glt:task, distances     ', distances(1:nclose)
endif

do iup = 1,n_upstream
   if ( connections(my_index)%from_link_index(iup) /= MISSING_I8 ) then
      call get_link_tree( connections(my_index)%from_link_index(iup), &
               reach_cutoff, depth+1, direct_length, nclose, close_indices, distances)
   endif
enddo

end subroutine get_link_tree


function full_to_connection(full_index) result (connectionID)
integer(i8), intent(in) :: full_index
integer                 :: connectionID

integer :: i

do i = 1,n_link
   if (connections(i)%domain_offset == full_index) then
      connectionID = i
      return
   endif
enddo

connectionID = -1

end function full_to_connection



!-----------------------------------------------------------------------
!> 

subroutine get_downstream_links(my_index, reach_cutoff, depth, &
                    nclose, close_indices, distances)

integer,     intent(in)    :: my_index
real(r8),    intent(in)    :: reach_cutoff   ! meters
integer,     intent(in)    :: depth
integer,     intent(inout) :: nclose
integer(i8), intent(inout) :: close_indices(:)
real(r8),    intent(inout) :: distances(:)

real(r8) :: direct_length
integer  :: idown


idown = my_index

direct_length = connections(idown)%linkLength

do while( direct_length < reach_cutoff .and. &
          connections(idown)%to_link_index > 0)

   idown     = connections(idown)%to_link_index

   nclose                = nclose + 1
   close_indices(nclose) = idown
   distances(nclose)     = direct_length

   if (debug > 99) then
   write(string1,'("PE ",I7)') my_task_id()
   write(*,*)trim(string1)
   write(*,*)trim(string1), ' gdl: my_index, nclose, direct_length ', &
                              idown, nclose, direct_length
   endif

   direct_length = direct_length + connections(idown)%linkLength

enddo

end subroutine get_downstream_links


!-----------------------------------------------------------------------
!> Routine 'specific' to what I think is being used in the wrfhydro full model run
!> would be nice to know a version or something

subroutine read_noah_namelist(setup_filename)

character(len=*), intent(out) :: setup_filename

character(len=*), parameter :: routine = 'read_noah_namelist'

! namelist variables specific to this version.
!>@todo now that we do not need to write a namelist, I am not sure
!> we need anything more than a few variables.

character(len=256) :: hrldas_setup_file = 'no_hrldas_setup_file'
character(len=256) :: spatial_filename  = 'no_spatial_filename'
character(len=256) :: indir             = ''
character(len=256) :: outdir            = ''
integer            :: start_year, start_month, start_day, start_hour, start_min
character(len=256) :: restart_filename_requested        = 'no_restart_filename'
integer            :: kday                              = 0
integer            :: dynamic_veg_option                = 4
integer            :: canopy_stomatal_resistance_option = 1
integer            :: btr_option                        = 4
integer            :: runoff_option                     = 3
integer            :: surface_drag_option               = 1
integer            :: frozen_soil_option                = 1
integer            :: supercooled_water_option          = 1
integer            :: radiative_transfer_option         = 3
integer            :: snow_albedo_option                = 2
integer            :: pcp_partition_option              = 1
integer            :: tbot_option                       = 1
integer            :: temp_time_scheme_option           = 1
integer            :: glacier_option
integer            :: surface_resistance_option
integer            :: forcing_timestep                  = -999
integer            :: noah_timestep                     = -999
integer            :: output_timestep                   = -999
integer            :: restart_frequency_hours           = -999
integer            :: split_output_count                = 1
integer            :: nsoil
real(r8)           :: soil_thick_input(NSOLDX)          = MISSING_R8
real(r8)           :: zlvl
integer            :: rst_bi_out
integer            :: rst_bi_in

namelist / NOAHLSM_OFFLINE / hrldas_setup_file, spatial_filename, &
   indir, outdir, start_year, start_month, start_day, start_hour, start_min, &
   restart_filename_requested, kday, dynamic_veg_option, &
   canopy_stomatal_resistance_option, btr_option, runoff_option, &
   surface_drag_option, frozen_soil_option, supercooled_water_option, &
   radiative_transfer_option, snow_albedo_option, pcp_partition_option, &
   tbot_option, temp_time_scheme_option, glacier_option, &
   surface_resistance_option, forcing_timestep, noah_timestep, output_timestep, &
   restart_frequency_hours, split_output_count, nsoil, soil_thick_input, &
   zlvl, rst_bi_out, rst_bi_in

logical, save :: lsm_namelist_read = .false.
integer :: iunit, io

if ( lsm_namelist_read ) return ! only need to read namelists once

lsm_namelist_read = .true.

if ( file_exist(lsm_namelist_filename) ) then
   call find_namelist_in_file(lsm_namelist_filename, 'NOAHLSM_OFFLINE', iunit)
   read(iunit, nml = NOAHLSM_OFFLINE, iostat = io)
   call check_namelist_read(iunit, io, 'NOAHLSM_OFFLINE')
else
   write(string1,*) 'LSM namelist file "', trim(lsm_namelist_filename),'" does not exist.'
   call error_handler(E_ERR,routine,string1,source,revision,revdate)
endif

! Check to make sure the hrldas setup file exists
if ( .not. file_exist(hrldas_setup_file) ) then
   write(string1,*) 'NOAH hrldas_setup_file "',trim(hrldas_setup_file), &
                    '" does not exist.'
   call error_handler(E_ERR,routine,string1,source,revision,revdate)
endif

setup_filename       = hrldas_setup_file
num_soil_layers      = nsoil
soil_layer_thickness = soil_thick_input

!>@todo I am not sure this has any relevance now that DART is not advancing NOAH
! Check to make sure the required NOAH namelist items are set:
if ( (kday             < 0    ) .or. &
     (forcing_timestep /= 3600) .or. &
     (noah_timestep    /= 3600) .or. &
     (output_timestep  /= 3600) .or. &
     (restart_frequency_hours /= 1) ) then
   write(string3,*)'the only configuration supported is for hourly timesteps &
        &(kday, forcing_timestep==3600, noah_timestep=3600, &
        &output_timestep=3600, restart_frequency_hours=1)'
   write(string2,*)'restart_frequency_hours must be equal to the noah_timestep'
   write(string1,*)'unsupported noah namelist settings'
   call error_handler(E_MSG,routine,string1,source,revision,revdate,&
        text2=string2,text3=string3)
endif

timestepping%day       = kday
timestepping%hour      = 0
timestepping%forcing   = forcing_timestep
timestepping%dynamical = noah_timestep
timestepping%output    = output_timestep
timestepping%restart   = restart_frequency_hours * 3600

end subroutine read_noah_namelist


!-----------------------------------------------------------------------
!>

subroutine read_36_namelist(setup_filename)

character(len=*), intent(out) :: setup_filename

character(len=*), parameter :: routine = 'read_36_namelist'

character(len=256) :: hrldas_constants_file = ' '
character(len=256) :: indir = ' '
character(len=256) :: outdir = ' '
integer            :: start_year, start_month, start_day, start_hour, start_min
character(len=256) :: restart_filename_requested = ' '
integer            :: kday  = 0
integer            :: dynamic_veg_option                = 4
integer            :: canopy_stomatal_resistance_option = 1
integer            :: btr_option                        = 4
integer            :: runoff_option                     = 3
integer            :: surface_drag_option               = 1
integer            :: frozen_soil_option                = 1
integer            :: supercooled_water_option          = 1
integer            :: radiative_transfer_option         = 3
integer            :: snow_albedo_option                = 2
integer            :: pcp_partition_option              = 1
integer            :: tbot_option                       = 1
integer            :: temp_time_scheme_option           = 1
integer            :: soil_hydraulic_parameter_option   = 1
integer            :: forcing_timestep                  = -999
integer            :: noah_timestep                     = -999
integer            :: output_timestep                   = -999
integer            :: split_output_count                = 1
integer            :: restart_frequency_hours           = -999
integer            :: nsoil ! number of soil layers in use.
real(r8)           :: soil_thick_input(NSOLDX)          = MISSING_R8
real(r8)           :: zlvl

namelist / NOAHLSM_OFFLINE / hrldas_constants_file, indir, outdir, &
           start_year, start_month, start_day, start_hour, start_min, &
           restart_filename_requested, kday, dynamic_veg_option, &
           canopy_stomatal_resistance_option, btr_option, runoff_option, &
           surface_drag_option, frozen_soil_option, supercooled_water_option, &
           radiative_transfer_option, snow_albedo_option, pcp_partition_option, &
           tbot_option, temp_time_scheme_option, soil_hydraulic_parameter_option, &
           forcing_timestep, noah_timestep, output_timestep, split_output_count, &
           restart_frequency_hours, nsoil, soil_thick_input, zlvl

integer :: iunit, io
logical, save :: lsm_namelist_read = .false.

if ( lsm_namelist_read ) return ! only need to read namelists once

lsm_namelist_read = .true.

if ( file_exist(lsm_namelist_filename) ) then
   call find_namelist_in_file(lsm_namelist_filename, 'NOAHLSM_OFFLINE', iunit)
   read(iunit, nml = NOAHLSM_OFFLINE, iostat = io)
   call check_namelist_read(iunit, io, 'NOAHLSM_OFFLINE')
else
   write(string1,*) 'LSM namelist file "', trim(lsm_namelist_filename), &
                    '" does not exist.'
   call error_handler(E_ERR,routine,string1,source,revision,revdate)
endif

! Check to make sure the hrldas constants file exists
if ( .not. file_exist(hrldas_constants_file) ) then
   write(string1,*) 'NOAH constants file "',trim(hrldas_constants_file), &
                    '" does not exist.'
   call error_handler(E_ERR,routine,string1,source,revision,revdate)
endif

setup_filename       = hrldas_constants_file
num_soil_layers      = nsoil
soil_layer_thickness = soil_thick_input

!>@todo not sure any of this is needed because DART does not advance model ...
!> Check to make sure the required NOAH namelist items are set:
if ( (kday             < 0    ) .or. &
     (forcing_timestep /= 3600) .or. &
     (noah_timestep    /= 3600) .or. &
     (output_timestep  /= 3600) .or. &
     (restart_frequency_hours /= 1) ) then
   write(string3,*)'the only configuration supported is for hourly timesteps &
        &(kday, forcing_timestep==3600, noah_timestep=3600, &
        &output_timestep=3600, restart_frequency_hours=1)'
   write(string2,*)'restart_frequency_hours must be equal to the noah_timestep'
   write(string1,*)'unsupported noah namelist settings'
   call error_handler(E_MSG,routine,string1,source,revision,revdate,&
        text2=string2,text3=string3)
endif

timestepping%day       = kday
timestepping%hour      = 0
timestepping%forcing   = forcing_timestep
timestepping%dynamical = noah_timestep
timestepping%output    = output_timestep
timestepping%restart   = restart_frequency_hours * 3600

end subroutine read_36_namelist


!-----------------------------------------------------------------------
!>@todo get_noah_timestepping might not be needed at all since DART does not advance


subroutine get_noah_timestepping(day,hour,dynamical,output,forcing,restart)

integer, intent(out) :: day
integer, intent(out) :: hour
integer, intent(out) :: dynamical
integer, intent(out) :: output
integer, intent(out) :: forcing
integer, intent(out) :: restart

character(len=*), parameter :: routine = 'get_noah_timestepping'

call error_handler(E_MSG,routine,'routine not tested',source,revision,revdate)

day       = timestepping%day
hour      = timestepping%hour
dynamical = timestepping%dynamical
output    = timestepping%output
forcing   = timestepping%forcing
restart   = timestepping%restart

end subroutine get_noah_timestepping


!-----------------------------------------------------------------------
!> get_lsm_domain_info  is definitely needed


subroutine get_lsm_domain_info(nlongitudes,nlatitudes,longitudes,latitudes)

integer,            intent(out) :: nlongitudes
integer,            intent(out) :: nlatitudes
real(r8), optional, intent(out) :: longitudes(:,:)
real(r8), optional, intent(out) :: latitudes(:,:)

character(len=*), parameter :: routine = 'get_lsm_domain_info'

nlongitudes = west_east
nlatitudes  = south_north
if (present(longitudes)) longitudes = xlong
if (present( latitudes))  latitudes = xlat

end subroutine get_lsm_domain_info


!-----------------------------------------------------------------------
!> return the filename used to determine variable shapes for the lsm domain

subroutine get_lsm_domain_filename(domain_id, filename)

integer,          intent(in)  :: domain_id
character(len=*), intent(out) :: filename
character(len=*), parameter :: routine = 'get_lsm_domain_filename'

if (domain_id /= 1) then
   write(string1,*)'only configured for 1 lsm domain at present'
   call error_handler(E_ERR, routine, string1, source, revision, revdate)
endif

filename = lsm_domain_file(1)

end subroutine get_lsm_domain_filename



!-----------------------------------------------------------------------
!> read the global attributes from a hydro restart file

subroutine read_hydro_global_atts(filename)
character(len=*), intent(in) :: filename

character(len=*), parameter :: routine = 'read_hydro_global_atts'

integer :: ncid

hydro_global_atts%filename = trim(filename)

ncid = nc_open_file_readonly(filename, routine)
call nc_get_global_attribute(ncid, 'Restart_Time', &
                  hydro_global_atts%Restart_Time , routine)

call nc_get_global_attribute(ncid, 'Since_Date', &
                  hydro_global_atts%Since_Date , routine)

call nc_get_global_attribute(ncid, 'DTCT', &
                  hydro_global_atts%DTCT , routine)

call nc_get_global_attribute(ncid, 'channel_only', &
                  hydro_global_atts%channel_only , routine)

call nc_get_global_attribute(ncid, 'channelBucket_only', &
                  hydro_global_atts%channelBucket_only , routine)

call nc_close_file(ncid, routine)

end subroutine read_hydro_global_atts


!-----------------------------------------------------------------------
!> write the hydro global attributes to a DART output file for hydro domains
!> this only applies when DART creates the file from scratch

subroutine write_hydro_global_atts(ncid)

integer,          intent(in)  :: ncid
character(len=*), parameter :: routine = 'write_hydro_global_atts'

call nc_add_global_attribute(ncid,'HYDRO_filename', &
            trim(hydro_global_atts%filename), routine )
call nc_add_global_attribute(ncid,'Restart_Time', &
            trim(hydro_global_atts%Restart_Time), routine )
call nc_add_global_attribute(ncid,'Since_Date', &
            trim(hydro_global_atts%Since_Date), routine )
call nc_add_global_attribute(ncid,'DTCT', &
                 hydro_global_atts%DTCT, routine )
call nc_add_global_attribute(ncid,'channel_only', &
                 hydro_global_atts%channel_only, routine )
call nc_add_global_attribute(ncid,'channelBucket_only', &
                 hydro_global_atts%channelBucket_only, routine )

end subroutine write_hydro_global_atts


!-----------------------------------------------------------------------
!> read the global attributes from a lsm restart file

subroutine read_noah_global_atts(filename)
character(len=*), intent(in) :: filename

character(len=*), parameter :: routine = 'read_noah_global_atts'

integer :: ncid

noah_global_atts%filename = trim(filename)

ncid = nc_open_file_readonly(filename, routine)
call nc_get_global_attribute(ncid, 'TITLE',     noah_global_atts%title,      routine)
call nc_get_global_attribute(ncid, 'START_DATE',noah_global_atts%start_date, routine)
call nc_get_global_attribute(ncid, 'MAP_PROJ',  noah_global_atts%map_proj,   routine)
call nc_get_global_attribute(ncid, 'LAT1',      noah_global_atts%lat1,       routine)
call nc_get_global_attribute(ncid, 'LON1',      noah_global_atts%lon1,       routine)
call nc_get_global_attribute(ncid, 'DX',        noah_global_atts%dx,         routine)
call nc_get_global_attribute(ncid, 'DY',        noah_global_atts%dy,         routine)
call nc_get_global_attribute(ncid, 'TRUELAT1',  noah_global_atts%truelat1,   routine) 
call nc_get_global_attribute(ncid, 'TRUELAT2',  noah_global_atts%truelat2,   routine) 
call nc_get_global_attribute(ncid, 'STAND_LON', noah_global_atts%stand_lon,  routine)
call nc_close_file(ncid, routine)

!>@todo there are a bunch of optional attributes that we may want ...
!>      there seems to be quite a lot of variation ...

end subroutine read_noah_global_atts


!-----------------------------------------------------------------------
!> write the noah global attributes to a DART output file for noah domains
!> this only applies when DART creates the file from scratch

subroutine write_noah_global_atts(ncid)

integer,          intent(in)  :: ncid
character(len=*), parameter :: routine = 'write_noah_global_atts'


call nc_add_global_attribute(ncid,'noah_filename', &
            trim(noah_global_atts%filename), routine )
call nc_add_global_attribute(ncid, 'TITLE', &
              trim(noah_global_atts%TITLE),      routine)
call nc_add_global_attribute(ncid, 'START_DATE',&
              trim(noah_global_atts%START_DATE), routine)

call nc_add_global_attribute(ncid, 'MAP_PROJ',  noah_global_atts%map_proj,   routine)
call nc_add_global_attribute(ncid, 'LAT1',      noah_global_atts%lat1,       routine)
call nc_add_global_attribute(ncid, 'LON1',      noah_global_atts%lon1,       routine)
call nc_add_global_attribute(ncid, 'DX',        noah_global_atts%dx,         routine)
call nc_add_global_attribute(ncid, 'DY',        noah_global_atts%dy,         routine)
call nc_add_global_attribute(ncid, 'TRUELAT1',  noah_global_atts%truelat1,   routine) 
call nc_add_global_attribute(ncid, 'TRUELAT2',  noah_global_atts%truelat2,   routine) 
call nc_add_global_attribute(ncid, 'STAND_LON', noah_global_atts%stand_lon,  routine)

end subroutine write_noah_global_atts


end module noah_hydro_mod

! <next few lines under version control, do not edit>
! $URL$
! $Id$
! $Revision$
! $Date$

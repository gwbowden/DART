! Data Assimilation Research Testbed -- DART
! Copyright 2004-2008, Data Assimilation Research Section
! University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   convert_cosmic_gps_cdf - program that reads a COSMIC GPS observation 
!                            profile and writes the data to a DART 
!                            observation sequence file. 
!
!     created June 2008 Ryan Torn, NCAR/MMM
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

program convert_cosmic_gps_cdf

use        types_mod, only : r8, metadatalength
use time_manager_mod, only : time_type, set_calendar_type, GREGORIAN, set_time,&
                             increment_time, get_time, set_date, operator(-),  &
                             print_date
use    utilities_mod, only : initialize_utilities, find_namelist_in_file,    &
                             check_namelist_read, nmlfileunit, do_output,    &
                             get_next_filename, error_handler, E_ERR, E_MSG, &
                             nc_check, find_textfile_dims
use     location_mod, only : VERTISHEIGHT, set_location
use obs_sequence_mod, only : obs_sequence_type, obs_type, read_obs_seq,       &
                             static_init_obs_sequence, init_obs, destroy_obs, &
                             write_obs_seq, init_obs_sequence, get_num_obs,   &
                             insert_obs_in_seq, destroy_obs_sequence,         &
                             set_copy_meta_data, set_qc_meta_data, set_qc,    & 
                             set_obs_values, set_obs_def, insert_obs_in_seq
use obs_def_mod,      only : obs_def_type, set_obs_def_time, set_obs_def_kind, &
                             set_obs_def_error_variance, set_obs_def_location, &
                             set_obs_def_key
use  obs_def_gps_mod, only : set_gpsro_ref
use     obs_kind_mod, only : GPSRO_REFRACTIVITY

use           netcdf

implicit none

! version controlled file description for error handling, do not edit
character(len=128), parameter :: &
   source   = "$URL$", &
   revision = "$Revision$", &
   revdate  = "$Date$"


integer, parameter ::   num_copies = 1,   &   ! number of copies in sequence
                        num_qc     = 1        ! number of QC entries

character (len=metadatalength) :: meta_data
character (len=129) :: msgstring, next_infile
character (len=80)  :: name
character (len=19)  :: datestr
character (len=6)   :: subset
integer :: rcode, ncid, varid, nlevels, k, nfiles, num_new_obs,  &
           aday, asec, dday, dsec, oday, osec,                   &
           iyear, imonth, iday, ihour, imin, isec,               &
           glat, glon, zloc, obs_num, io, iunit, nobs, filenum, dummy
logical :: file_exist, first_obs, did_obs, from_list = .false.
real(r8) :: hght_miss, refr_miss, azim_miss, oerr,               & 
            qc, lato, lono, hghto, refro, azimo, wght, nx, ny,   & 
            nz, ds, htop, rfict, obsval, phs, obs_val(1), qc_val(1)

real(r8), allocatable :: lat(:), lon(:), hght(:), refr(:), azim(:), & 
                         hghtp(:), refrp(:)

type(obs_def_type)      :: obs_def
type(obs_sequence_type) :: obs_seq
type(obs_type)          :: obs, prev_obs
type(time_type)         :: time_obs, time_anal

!------------------------------------------------------------------------
!  Declare namelist parameters
!------------------------------------------------------------------------

integer, parameter :: nmaxlevels = 200   !  max number of observation levels

logical  :: local_operator = .true.
logical  :: overwrite_time = .false.
real(r8) :: obs_levels(nmaxlevels) = -1.0_r8
real(r8) :: obs_window = 12.0     ! accept obs within +/- hours from anal time
real(r8) :: ray_ds = 5000.0_r8    ! delta stepsize (m) along ray, nonlocal op
real(r8) :: ray_htop = 15000.0_r8 ! max height (m) for nonlocal op
character(len=128) :: gpsro_netcdf_file     = 'cosmic_gps_input.nc'
character(len=128) :: gpsro_netcdf_filelist = 'cosmic_gps_input_list'
character(len=128) :: gpsro_out_file        = 'obs_seq.gpsro'

namelist /convert_cosmic_gps_nml/ obs_levels, local_operator, obs_window, &
                                  ray_ds, ray_htop, gpsro_netcdf_file,    &
                                  gpsro_netcdf_filelist, gpsro_out_file 

! could add overwrite_time to namelist

! initialize some values
obs_num = 1
qc = 0.0_r8

print*,'Enter the target assimilation time (yyyy-mm-dd_hh:mm:ss)'
read*,datestr

call set_calendar_type(GREGORIAN)
read(datestr(1:4),   fmt='(i4)') iyear
read(datestr(6:7),   fmt='(i2)') imonth
read(datestr(9:10),  fmt='(i2)') iday
read(datestr(12:13), fmt='(i2)') ihour
read(datestr(15:16), fmt='(i2)') imin
read(datestr(18:19), fmt='(i2)') isec
time_anal = set_date(iyear, imonth, iday, ihour, imin, isec)
call get_time(time_anal, asec, aday)

!  read the necessary parameters from input.nml
call initialize_utilities()
call find_namelist_in_file("input.nml", "convert_cosmic_gps_nml", iunit)
read(iunit, nml = convert_cosmic_gps_nml, iostat = io)

! Record the namelist values used for the run 
if (do_output()) write(nmlfileunit, nml=convert_cosmic_gps_nml)

! namelist checks for sanity

!  count observation levels, make sure observation levels increase from 0
nlevels = 0
do k = 1, nmaxlevels
  if ( obs_levels(k) == -1.0_r8 )  exit
  nlevels = k
end do
do k = 2, nlevels
  if ( obs_levels(k-1) >= obs_levels(k) ) then
    call error_handler(E_ERR, 'convert_cosmic_gps_cdf',       &
                       'Observation levels should increase',  &
                       source, revision, revdate)
  end if
end do

!  should error check the window some
if (obs_window <= 0.0_r8 .or. obs_window > 24.0_r8) then
    call error_handler(E_ERR, 'convert_cosmic_gps_cdf',       &
                       'Bad value for obs_window (hours)',    &
                       source, revision, revdate)
else
   obs_window = obs_window * 3600.0_r8
endif


! cannot have both a single filename and a list; the namelist must
! shut one off.
if (gpsro_netcdf_file /= '' .and. gpsro_netcdf_filelist /= '') then
  call error_handler(E_ERR, 'convert_cosmic_gps_cdf',                     &
                     'One of gpsro_netcdf_file or filelist must be NULL', &
                     source, revision, revdate)
endif
if (gpsro_netcdf_filelist /= '') from_list = .true.

! need to know a reasonable max number of obs that could be added here.
if (from_list) then
   call find_textfile_dims(gpsro_netcdf_filelist, nfiles, dummy)
   num_new_obs = nlevels * nfiles
else
   num_new_obs = nlevels
endif

!  either read existing obs_seq or create a new one
call static_init_obs_sequence()
call init_obs(obs, num_copies, num_qc)
call init_obs(prev_obs, num_copies, num_qc)
inquire(file=gpsro_out_file, exist=file_exist)
if ( file_exist ) then

print *, "found existing obs_seq file, appending to ", trim(gpsro_out_file)
   call read_obs_seq(gpsro_out_file, 0, 0, num_new_obs, obs_seq)

else

print *, "no existing obs_seq file, creating ", trim(gpsro_out_file)
print *, "max entries = ", num_new_obs
  call init_obs_sequence(obs_seq, num_copies, num_qc, num_new_obs)
  do k = 1, num_copies
    meta_data = 'COSMIC GPS observation'
    call set_copy_meta_data(obs_seq, k, meta_data)
  end do
  do k = 1, num_qc
    meta_data = 'COSMIC QC'
    call set_qc_meta_data(obs_seq, k, meta_data)
  end do

end if

allocate(hghtp(nlevels))  ;  allocate(refrp(nlevels))
did_obs = .false.

! main loop that does either a single file or a list of files

filenum = 1
fileloop: do      ! until out of files

   ! get the single name, or the next name from a list
   if (from_list) then 
      next_infile = get_next_filename(gpsro_netcdf_filelist, filenum)
   else
      next_infile = gpsro_netcdf_file
      if (filenum > 1) next_infile = ''
   endif
   if (next_infile == '') exit fileloop
  
   !  open the occultation profile, check if it is within the window
   call nc_check( nf90_open(next_infile, nf90_nowrite, ncid), 'file open', next_infile)
   call nc_check( nf90_get_att(ncid,nf90_global,'year',  iyear) ,'get_att year')
   call nc_check( nf90_get_att(ncid,nf90_global,'month', imonth),'get_att month')
   call nc_check( nf90_get_att(ncid,nf90_global,'day',   iday)  ,'get_att day')
   call nc_check( nf90_get_att(ncid,nf90_global,'hour',  ihour) ,'get_att hour')
   call nc_check( nf90_get_att(ncid,nf90_global,'minute',imin)  ,'get_att minute')
   call nc_check( nf90_get_att(ncid,nf90_global,'second',isec)  ,'get_att second')
   
   time_obs = set_date(iyear, imonth, iday, ihour, imin, isec)
   call get_time(time_obs,  osec, oday)
   
   ! time1-time2 is always positive no matter the relative magnitudes
   call get_time(time_anal-time_obs,dsec,dday)
   if ( real(dsec+dday*86400) > obs_window ) then
     call print_date(time_obs, 'observation: ')
     call print_date(time_anal, 'window center: ')
     write(msgstring, *) 'Window width (hours): ', obs_window / 3600.0_r8
     call error_handler(E_MSG, 'convert_cosmic_gps_cdf',       &
                        msgstring, source, revision, revdate)
     call error_handler(E_ERR, 'convert_cosmic_gps_cdf',       &
                        'Observation is outside window',       &
                        source, revision, revdate)
   end if
   
   call nc_check( nf90_inq_dimid(ncid, "MSL_alt", varid), 'inq dimid MSL_alt')
   call nc_check( nf90_inquire_dimension(ncid, varid, name, nobs), 'inq dim MSL_alt')
   
   call nc_check( nf90_get_att(ncid,nf90_global,'lon',  glon) ,'get_att lon'  )
   call nc_check( nf90_get_att(ncid,nf90_global,'lat',  glat) ,'get_att lat'  )
   call nc_check( nf90_get_att(ncid,nf90_global,'rfict',rfict),'get_att rfict')
   rfict = rfict * 1000.0_r8
   
   allocate( lat(nobs))  ;  allocate( lon(nobs))
   allocate(hght(nobs))  ;  allocate(refr(nobs))
   allocate(azim(nobs))
   
   ! read the latitude array
   call nc_check( nf90_inq_varid(ncid, "Lat", varid) ,'inq varid Lat')
   call nc_check( nf90_get_var(ncid, varid, lat)     ,'get var   Lat')
   
   ! read the latitude array
   call nc_check( nf90_inq_varid(ncid, "Lon", varid) ,'inq varid Lon')
   call nc_check( nf90_get_var(ncid, varid, lon)     ,'get var   Lon')
   
   ! read the altitude array
   call nc_check( nf90_inq_varid(ncid, "MSL_alt", varid) ,'inq varid MSL_alt')
   call nc_check( nf90_get_var(ncid, varid, hght)        ,'get_var   MSL_alt')
   call nc_check( nf90_get_att(ncid, varid, '_FillValue', hght_miss) ,'get_att _FillValue MSL_alt')
   
   ! read the refractivity
   call nc_check( nf90_inq_varid(ncid, "Ref", varid) ,'inq varid Ref')
   call nc_check( nf90_get_var(ncid, varid, refr)    ,'get var   Ref')
   call nc_check( nf90_get_att(ncid, varid, '_FillValue', refr_miss) ,'get_att _FillValue Ref')
   
   ! read the dew-point temperature array
   call nc_check( nf90_inq_varid(ncid, "Azim", varid) ,'inq varid Azim')
   call nc_check( nf90_get_var(ncid, varid, azim)     ,'get var   Azim')
   call nc_check( nf90_get_att(ncid, varid, '_FillValue', azim_miss) ,'get_att _FillValue Azim')
   
   call nc_check( nf90_close(ncid) , 'close file')
   
   obsloop: do k = 1, nlevels
   
     call interp_height_wght(hght, obs_levels(k), nobs, zloc, wght)
     if ( zloc < 1 )  cycle obsloop
     hghtp(nlevels-k+1) = obs_levels(k) * 1000.0_r8
     refrp(nlevels-k+1) = exp( wght * log(refr(zloc)) + & 
                       (1.0_r8 - wght) * log(refr(zloc+1)) ) * 1.0e-6_r8
   
   end do obsloop
   
   first_obs = .true.
   
   obsloop2: do k = 1, nlevels
   
     call interp_height_wght(hght, obs_levels(k), nobs, zloc, wght)
     if ( zloc < 1 )  cycle obsloop2
   
     lato  = wght * lat(zloc)  + (1.0_r8 - wght) * lat(zloc+1)
     lono  = wght * lon(zloc)  + (1.0_r8 - wght) * lon(zloc+1)
     if ( lono < 0.0_r8 )  lono = lono + 360.0_r8
     hghto = wght * hght(zloc) + (1.0_r8 - wght) * hght(zloc+1)
     hghto = hghto * 1000.0_r8
     refro = wght * refr(zloc) + (1.0_r8 - wght) * refr(zloc+1)
     azimo = wght * azim(zloc) + (1.0_r8 - wght) * azim(zloc+1)
   
     if ( local_operator ) then
   
        nx        = 0.0_r8
        ny        = 0.0_r8
        nz        = 0.0_r8
        ray_ds    = 0.0_r8
        ray_htop  = 0.0_r8
        rfict     = 0.0_r8
   
        obsval = refro
        oerr   = 0.01_r8 * ref_obserr_kuo_percent(hghto * 0.001_r8) * obsval
        subset = 'GPSREF'
   
     else
   
       !  compute tangent unit vector
       call tanvec01(lono, lato, azimo, nx, ny, nz)
   
       !  compute the excess phase
       call excess(refrp, hghtp, lono, lato, hghto, nx, & 
                   ny, nz, rfict, ray_ds, ray_htop, phs, nlevels)
   
       !  if too high, phs will return as 0.  cycle loop here.
       if (phs <= 0) cycle obsloop2
   
       obsval = phs
       oerr   = 0.01_r8 * excess_obserr_percent(hghto * 0.001_r8) * obsval
   !print *, 'hghto,obsval,perc,err=', hghto, obsval, &
   !          excess_obserr_percent(hghto * 0.001_r8), oerr
       subset = 'GPSEXC'
   
     end if
   
     call set_gpsro_ref(obs_num, nx, ny, nz, rfict, ray_ds, ray_htop, subset)
     call set_obs_def_location(obs_def,set_location(lono,lato,hghto,VERTISHEIGHT))
     call set_obs_def_kind(obs_def, GPSRO_REFRACTIVITY)
     if (overwrite_time) then   ! generally do not want to do this here.
        call set_obs_def_time(obs_def, set_time(asec, aday))
     else
        call set_obs_def_time(obs_def, set_time(osec, oday))
     endif
     call set_obs_def_error_variance(obs_def, oerr * oerr)
     call set_obs_def_key(obs_def, obs_num)
     call set_obs_def(obs, obs_def)
   
     obs_val(1) = obsval
     call set_obs_values(obs, obs_val)
     qc_val(1)  = qc
     call set_qc(obs, qc_val)
   
     ! first one, insert with no prev.  otherwise, since all times will be the
     ! same for this column, insert with the prev obs as the starting point.
     ! (this code used to call append, but calling insert makes it work even if
     ! the input files are processed out of strict time order, which one message
     ! i got seemed to indicate was happening...)
     if (first_obs) then
        call insert_obs_in_seq(obs_seq, obs)
        first_obs = .false.
   !print *, 'inserting first obs'
     else
        call insert_obs_in_seq(obs_seq, obs, prev_obs)
   !print *, 'inserting other obs'
     endif
     obs_num = obs_num+1
     prev_obs = obs

     if (.not. did_obs) did_obs = .true.
   
   end do obsloop2

  ! clean up and loop if there is another input file
  deallocate( lat, lon, hght, refr, azim )

  filenum = filenum + 1

end do fileloop

! done with main loop.  if we added any obs to the sequence, write it out.
if (did_obs) then
!print *, 'ready to write, nobs = ', get_num_obs(obs_seq)
   if (get_num_obs(obs_seq) > 0) &
      call write_obs_seq(obs_seq, gpsro_out_file)

   ! minor stab at cleanup, in the off chance this will someday get turned
   ! into a subroutine in a module.  probably not all that needs to be done,
   ! but a start.
!print *, 'calling destroy_obs'
   call destroy_obs(obs)
   call destroy_obs(prev_obs)
print *, 'skipping destroy_seq'
   ! get core dumps here, not sure why?
   !if (get_num_obs(obs_seq) > 0) call destroy_obs_sequence(obs_seq)
endif

! END OF MAIN ROUTINE

contains

! local subroutines/functions follow

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   excess - subroutine that computes the excess phase based on the 
!            method of Sergey et al. (2004), eq. 1 and 2
!
!    refp   - refractivity profile
!    hghtp  - height profile of refractivity observations
!    lon    - longitude of GPS perigee point
!    lat    - latitude of GPS perigee point
!    height - height of GPS perigee point
!    nx     - x component of tangent point of ray
!    ny     - y component of tangent point of ray
!    nz     - z component of tangent point of ray
!    rfict  - local curvature radius
!    ds     - increment of excess computation - intent(in) now
!    htop   - heighest level of computation - intent(in) now
!    phs    - excess phase
!    nobs   - number of points in profile
!
!     created June 2004, Hui Liu NCAR/MMM
!     modified Ryan Torn, NCAR/MMM  
!     updated Nancy Collins, NCAR/IMAGe
!       quit before computing segment when one endpoint is above top, not after
!       pass delta step and htop in as input args instead of out.
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine excess(refp, hghtp, lon, lat, height, nx, ny, nz, &
                                    rfict, ds, htop, phs, nobs)

use  types_mod, only : r8

implicit none

integer, intent(in)   :: nobs
real(r8), intent(in)  :: refp(nobs), hghtp(nobs), lon, lat, height, nx, & 
                         ny, nz, rfict, ds, htop
real(r8), intent(out) :: phs

integer :: iter
real(r8) :: xo, yo, zo, ref00, ref1, ref2, ss, xx, yy, zz, height1, &
            lat1, lon1, dphs1, dphs2

! make sure height is not already above requested top of integration
if( height >= htop ) then
   phs = 0.0_r8           ! excess phase
   return
endif

!  convert location of perigee from geodetic to Cartesian coordinate
call geo2car(height, lat, lon, xo, yo, zo, rfict)

!  get refractivity at perigee
call ref_int(height, refp, hghtp, ref00, nobs)

!  integrate refractivity along a straight line path in cartesian coordinate
!   (x-xo)/a = (y-yo)/b = (z-zo)/c,  (a,b,c) is the line direction
ref1 = ref00  ;  ref2 = ref00

!    initialization
phs = 0.0_r8           ! excess phase
ss  = 0.0_r8           ! distance to perigee from a ray point
iter = 0

do 

  iter = iter + 1
  ss   = ss + ds

  !  integrate to one direction of the line for one step
  xx = xo + ss * nx
  yy = yo + ss * ny
  zz = zo + ss * nz

  !  convert the location of the point to geodetic coordinates
  !   height(m), lat, lon(deg)
  call car2geo(xx, yy, zz, height1, lat1, lon1, rfict)
  if( height1 >= htop ) exit  ! break out of loop if above level

  call ref_int(height1, refp, hghtp, ref00, nobs)
  dphs1 = (ref1 + ref00) * ds / 2.0_r8

  ref1 = ref00

  !  integrate to the other direction of the line for one step
  xx = xo - ss * nx
  yy = yo - ss * ny
  zz = zo - ss * nz

  call car2geo(xx, yy, zz, height1, lat1, lon1, rfict)
  call ref_int(height1, refp, hghtp, ref00, nobs)
  dphs2 = (ref2 + ref00) * ds / 2.0_r8

  ref2 = ref00

  phs = phs + dphs1 + dphs2

end do

return
end subroutine excess

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   excess_obserr_percent - function that computes the observation 
!                           error percentage for a given height.
!
!    hght - height of excess observation (km)
!
!     created Hui Liu NCAR/MMM
!     updated June 2008, Ryan Torn NCAR/MMM
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
function excess_obserr_percent(hght)

use types_mod, only : r8

implicit none

integer, parameter :: nobs_level = 18

real(r8), intent(in) :: hght

integer  :: k, k0
real(r8) :: hght0, exc_err(nobs_level), obs_ht(nobs_level), excess_obserr_percent

!-------------------------------------------------------------------------------
! obs height in km
data obs_ht/17.0_r8, 16.0_r8, 15.0_r8, 14.0_r8, 13.0_r8, 12.0_r8, & 
            11.0_r8, 10.0_r8,  9.0_r8,  8.0_r8,  7.0_r8,  6.0_r8, &
             5.0_r8,  4.0_r8,  3.0_r8,  2.0_r8,  1.0_r8,  0.0_r8/

data exc_err/0.2_r8,  0.2_r8,  0.2_r8,  0.2_r8,  0.2_r8,  0.2_r8, & 
             0.2_r8,  0.3_r8,  0.4_r8,  0.5_r8,  0.6_r8,  0.7_r8, &
             0.8_r8,  0.9_r8,  1.0_r8,  1.1_r8,  1.2_r8,  1.3_r8/

!-------------------------------------------------------------------------------

hght0 = max(hght,0.0_r8)

do k = 1, nobs_level
  if ( hght >= obs_ht(k) ) then
    k0 = k
    exit
  end if
end do

excess_obserr_percent = exc_err(k0) + (exc_err(k0) - exc_err(k0-1)) / & 
                        (obs_ht(k0) - obs_ht(k0-1)) * (hght - obs_ht(k0))

return
end function excess_obserr_percent

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   car2geo - subroutine that converts cartesian coordinates to
!             geodetical.
!
!    x1    - x coordinate
!    x2    - y coordinate
!    x3    - z coordinate
!    s1    - geodetical height
!    s2    - geodetical latitude
!    s3    - geodetical longitude
!    rfict - local curvature radius
!
!     created Hui Liu NCAR/MMM
!     Modified June 2008, Ryan Torn NCAR/MMM 
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine car2geo (x1, x2, x3, s1, s2, s3, rfict)

use types_mod, only : r8, rad2deg, pi

implicit none

real(r8), intent(in)  :: x1, x2, x3, rfict
real(r8), intent(out) :: s1, s2, s3

real(r8) :: rho, azmth

rho   = sqrt (x1 * x1 + x2 * x2 + x3 * x3)
s1    = rho - rfict
s2    = asin(x3 / rho)
azmth = atan2(x2, x1)
s3    = mod((azmth + 4.0_r8 * pi), 2.0_r8 * pi)

s2 = s2 * rad2deg
s3 = s3 * rad2deg

return
end subroutine car2geo

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   geo2car - subroutine that converts geodetical coordinates to 
!             cartesian.
!
!    s1    - geodetical height
!    s2    - geodetical latitude
!    s3    - geodetical longitude
!    x1    - x coordinate
!    x2    - y coordinate
!    x3    - z coordinate
!    rfict - local curvature radius
!
!     created Hui Liu NCAR/MMM
!     modified June 2008, Ryan Torn NCAR/MMM 
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine geo2car(s1, s2, s3, x1, x2, x3, rfict)

use types_mod, only : r8, deg2rad

implicit none

real(r8), intent(in)  :: s1, s2, s3, rfict
real(r8), intent(out) :: x1, x2, x3

real(r8) :: g3, g4

g3  = s1 + rfict
g4  = g3 * cos(s2 * deg2rad)

x1  = g4 * cos(s3 * deg2rad)
x2  = g4 * sin(s3 * deg2rad)
x3  = g3 * sin(s2 * deg2rad)

return
end subroutine geo2car

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   interp_height_wght - subroutine that finds the vertical levels
!                        closest to the desired height level and the
!                        weights to give to these levels to perform
!                        vertical interpolation.
!
!    hght  - height levels in column
!    level - height level to interpolate to
!    zgrid - index of lowest level for interpolation
!    wght  - weight to give to the lower level in interpolation
!    iz    - number of vertical levels
!
!     created June 2008, Ryan Torn NCAR/MMM
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine interp_height_wght(hght, level, iz, zgrid, wght)

use        types_mod, only : r8

implicit none

integer,  intent(in)  :: iz
real(r8), intent(in)  :: hght(iz), level
integer,  intent(out) :: zgrid
real(r8), intent(out) :: wght

integer :: k, klev, kbot, ktop, kinc, kleva

if ( hght(1) > hght(iz) ) then
  kbot = iz  ;   ktop = 1   ;  kinc = -1   ;  kleva = 0
else
  kbot = 1   ;   ktop = iz  ;  kinc = 1    ;  kleva = 1
end if

if ( (hght(kbot) <= level) .AND. (hght(ktop) >= level) ) then

  do k = kbot, ktop, kinc  !  search for appropriate level
    if ( hght(k) > level ) then
      klev = k - kleva
      exit
    endif
  enddo

  ! compute the weights
  zgrid = klev
  wght  = (level-hght(klev+1)) / (hght(klev) - hght(klev+1))

else

  zgrid = -1
  wght  = 0.0_r8

endif

return
end subroutine interp_height_wght

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   ref_int - subroutine that calculates the refractivity at any 
!             particular point.
!
!    height - GPS observation height (m)
!    refp   - refractivity profile
!    hghtp  - height profile
!    lref   - local refractivity value
!    nobs   - number of observations in the profile
!
!     created Hui Liu NCAR/MMM
!     updated June 2008, Ryan TORN NCAR/MMM
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine ref_int(height, refp, hghtp, lref, nobs)

use   types_mod, only : r8

implicit none

integer, intent(in)   :: nobs
real(r8), intent(in)  :: height, refp(nobs), hghtp(nobs)
real(r8), intent(out) :: lref

integer  :: bot_lev, k
real(r8) :: fract

!  Search down through height levels
do k = 2, nobs
  if ( height >= hghtp(k) ) then
    bot_lev = k
    fract = (hghtp(k) - height) / (hghtp(k) - hghtp(k-1))
    exit
  endif
end do

lref = (1.0_r8 - fract) * refp(bot_lev) + fract * refp(bot_lev-1)

return
end subroutine ref_int

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   ref_obserr_kuo_percent - function that computes the observation 
!                            error for a refractivity observation.
!                            These numbers are taken from a Kuo paper.
!
!    hght - height of refractivity observation
!
!     created Hui Liu NCAR/MMM
!     modified June 2008, Ryan Torn NCAR/MMM
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
function ref_obserr_kuo_percent(hght)

use   types_mod, only : r8

implicit none

integer, parameter :: nobs_level = 22  !  maximum number of obs levels

real(r8), intent(in)  :: hght

integer  :: k, k0
real(r8) :: hght0, ref_err(nobs_level), obs_ht(nobs_level), ref_obserr_kuo_percent

!   observation error heights (km) and errors
data obs_ht/17.98_r8, 16.39_r8, 14.97_r8, 13.65_r8, 12.39_r8, 11.15_r8, &
             9.95_r8,  8.82_r8,  7.82_r8,  6.94_r8,  6.15_r8,  5.45_r8, & 
             4.83_r8,  4.27_r8,  3.78_r8,  3.34_r8,  2.94_r8,  2.59_r8, & 
             2.28_r8,  1.99_r8,  1.00_r8,  0.00_r8/

data ref_err/0.48_r8,  0.56_r8,  0.36_r8,  0.28_r8,  0.33_r8,  0.41_r8, & 
             0.57_r8,  0.73_r8,  0.90_r8,  1.11_r8,  1.18_r8,  1.26_r8, & 
             1.53_r8,  1.85_r8,  1.81_r8,  2.08_r8,  2.34_r8,  2.43_r8, & 
             2.43_r8,  2.43_r8,  2.43_r8,  2.43_r8/

hght0 = max(hght, 0.0_r8)

do k = 1, nobs_level
  
  k0 = k
  if ( hght0 >= obs_ht(k) )  exit

end do 

ref_obserr_kuo_percent = ref_err(k0) + (ref_err(k0) - ref_err(k0-1)) / &
                             (obs_ht(k0)-obs_ht(k0-1)) * (hght0-obs_ht(k0))

return
end function ref_obserr_kuo_percent

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   tanvec01 - subroutine that computes the unit vector tangent of the 
!              ray at the perigee.
!
!    lon0  - longitude of the tangent point
!    lat0  - latitude of the tangent point
!    azim0 - angle between occultation plane from north
!    uz    - x component of tangent vector at tangent point of array
!    uy    - y component of tangent vector at tangent point of array
!    uz    - z component of tangent vector at tangent point of array
!
!     created Hui Liu, NCAR/MMM
!     modified June 2008, Ryan Torn NCAR/MMM
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine tanvec01(lon0, lat0, azim0, ux, uy, uz)

use   types_mod, only : r8, deg2rad

implicit none

real(r8), intent(in)  :: lon0, lat0, azim0
real(r8), intent(out) :: ux, uy, uz

real(r8) :: zz0(3), lon, lat, azim, rtp(3), rnm(3), rno(3), uon(3), vlen0

zz0(1) = 0.0_r8  ;  zz0(2) = 0.0_r8  ;  zz0(3) = 1.0_r8
lon = lon0 * deg2rad  ;  lat = lat0 * deg2rad  ;  azim = azim0 * deg2rad

rtp(1) = cos(lat) * cos(lon)
rtp(2) = cos(lat) * sin(lon)
rtp(3) = sin(lat)

!  compute unit vector normal to merdion plane through tangent point
call vprod(rtp, zz0, rnm)
vlen0 = sqrt(rnm(1)*rnm(1) + rnm(2)*rnm(2) + rnm(3)*rnm(3))
rnm(:) = rnm(:) / vlen0

!  compute unit vector toward north from perigee point
call vprod(rnm, rtp, rno)
vlen0 = sqrt(rno(1)*rno(1) + rno(2)*rno(2) + rno(3)*rno(3))
rno(:) = rno(:) / vlen0

!  rotate the vector rno around rtp for a single azim to get tangent vector
call spin(rno, rtp, azim, uon)
vlen0 = sqrt(uon(1)*uon(1) + uon(2)*uon(2) + uon(3)*uon(3))
ux = uon(1) / vlen0  ;  uy = uon(2) / vlen0  ;  uz = uon(3) / vlen0

return
end subroutine tanvec01

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   spin - subroutine that rotates vector v1 around vs clockwise by 
!          by a specified angle.
!
!    v1 - vector to rotate
!    vs - vector to rotate about
!     a - angle to rotate v1 around
!    v2 - output vector after rotation
!
!     created Hui Liu NCAR/MMM
!     modified June 2008, Ryan Torn NCAR/MMM
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine spin(v1, vs, a, v2)

use   types_mod, only : r8, deg2rad

implicit none

real(r8), intent(in)  :: v1(3), vs(3), a
real(r8), intent(out) :: v2(3)

real(r8) :: vsabs, vsn(3), a1, a2, a3, s(3,3) 

! Calculation of the unit vector for the rotation
vsabs  = sqrt(vs(1)*vs(1) + vs(2)*vs(2) + vs(3)*vs(3))
vsn(:) = vs(:) / vsabs

! Calculation the rotation matrix
a1 = cos(a)  ;  a2 = 1.0_r8 - a1  ;  a3 = sin(a)
s(1,1) = a2 * vsn(1) * vsn(1) + a1
s(1,2) = a2 * vsn(1) * vsn(2) - a3 * vsn(3)
s(1,3) = a2 * vsn(1) * vsn(3) + a3 * vsn(2)
s(2,1) = a2 * vsn(2) * vsn(1) + a3 * vsn(3)
s(2,2) = a2 * vsn(2) * vsn(2) + a1
s(2,3) = a2 * vsn(2) * vsn(3) - a3 * vsn(1)
s(3,1) = a2 * vsn(3) * vsn(1) - a3 * vsn(2)
s(3,2) = a2 * vsn(3) * vsn(2) + a3 * vsn(1)
s(3,3) = a2 * vsn(3) * vsn(3) + a1

!  Compute the rotated vector
v2(:) = s(:,1) * v1(1) + s(:,2) * v1(2) + s(:,3) * v1(3)

return
end subroutine spin

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   vprod - subroutine that computes the vector product of two vectors
!
!    x - first vector to take product of
!    y - second vector to take product of
!    z - vector product
!
!     created Hui Liu NCAR/MMM
!     modified June 2008, Ryan Torn NCAR/MMM
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine vprod(x, y, z)
 
use   types_mod, only : r8

implicit none

real(r8), intent(in)  :: x(3), y(3)
real(r8), intent(out) :: z(3)

z(1) = x(2)*y(3) - x(3)*y(2)
z(2) = x(3)*y(1) - x(1)*y(3)
z(3) = x(1)*y(2) - x(2)*y(1)

return
end subroutine vprod

end program

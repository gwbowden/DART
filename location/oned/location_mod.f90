module location_mod
!
! $Source$ 
! $Revision$ 
! $Date$ 
! $Author$ 
!
! Implements location interfaces for a one dimensional periodic domain. Initial 
! implementation has domain 'longitude' running from 0 to 1. May want to investigate
! allowing an arbitrary real domain size at some point.

use      types_mod, only : r8
use  utilities_mod, only : error_handler, E_ERR
use random_seq_mod, only : random_seq_type, init_random_seq, random_uniform

implicit none
private

public location_type, get_dist, get_location, set_location, &
       write_location, read_location, interactive_location, &
       LocationDims, LocationName, LocationLName, &
! FOLLOWING INTERFACES ARE TEMPORARY LINK PATHCES, SHOULD BE REMOVED
      vert_is_level, read_ncep_obs_location

! CVS Generated file description for error handling, do not edit
character(len=128) :: &
source   = "$Source$", &
revision = "$Revision$", &
revdate  = "$Date$"

type location_type
   private
   real(r8) :: x
end type location_type

type(random_seq_type) :: ran_seq
logical :: ran_seq_init = .false.

integer,              parameter :: LocationDims = 1
character(len = 129), parameter :: LocationName = "loc1d"
character(len = 129), parameter :: LocationLName = "one-dimensional location"


contains


function get_dist(loc1, loc2)
!----------------------------------------------------------------------------

implicit none

type(location_type), intent(in) :: loc1, loc2
real(r8) :: get_dist

! Reentrant domain, if distance is greater than half wraparound the other way.
get_dist = abs(loc1%x - loc2%x)
if(get_dist > 0.5_r8) get_dist = 1.0_r8 - get_dist

end function get_dist



function get_location(loc)
!---------------------------------------------------------------------------
!
! Given a location type, return the x coordinate

implicit none

type(location_type), intent(in) :: loc
real(r8) :: get_location

get_location = loc%x

end function get_location



function set_location(x)
!----------------------------------------------------------------------------
!
! Given a location type and a double precision value between 0 and 1
! puts this value into the location.

implicit none

type (location_type) :: set_location
real(r8), intent(in) :: x

if(x < 0.0_r8 .or. x > 1.0_r8) call error_handler(E_ERR, 'set_location', &
         'Value of x is out of 0->1 range', source, revision, revdate)

set_location%x = x

end function set_location



subroutine write_location(locfile, loc)
!----------------------------------------------------------------------------
!
! Writes a oned location to the file. Implemented as a subroutine but  could
! rewrite as a function with error control info returned. For initial implementation,
! file is just an integer file unit number. Probably want to replace this with file
! as a file_type allowing more flexibility for IO at later point. file_type and 
! associated operations would have to be supported. The mpp_io intefaces are a good
! place to head with this, perhaps, when we need to extend to supporting parallel
! platforms. 

implicit none

integer, intent(in) :: locfile
type(location_type), intent(in) :: loc

! For now, output a character tag followed by the r8 value. 

write(locfile, '(''loc1d'')' ) 
write(locfile, *) loc%x

end subroutine write_location



function read_location(locfile)
!----------------------------------------------------------------------------
!
! Reads a oned location from file that was written by write_location. 
! See write_location for additional discussion.

implicit none

integer, intent(in) :: locfile
type(location_type) :: read_location

character(len=5) :: header

! Will want to add additional error checks on the read
read(locfile, '(a5)' ) header
if(header /= 'loc1d') call error_handler(E_ERR, 'read_location', &
    'Expected location header "loc1d" in input file', source, revision, revdate)

! Now read the location data value
read(locfile, *) read_location%x

end function read_location



subroutine interactive_location(location)
!--------------------------------------------------------------------------
!
! Allows for interactive input of a location. Also gives option of selecting
! a uniformly distributed random location (what the heck).

implicit none

type(location_type), intent(out) :: location

real(r8) :: x

write(*, *) 'Input location for this obs: value 0 to 1 or a negative number for '
write(*, *) 'Uniformly distributed random location'
read(*, *) x

do while(x > 1.0_r8)
   write(*, *) 'Input value greater than 1.0 is illegal, please try again'
   read(*, *) x
end do

if(x < 0.0_r8) then

   ! Need to make sure random sequence is initialized

   if(.not. ran_seq_init) then
      call init_random_seq(ran_seq)
      ran_seq_init = .TRUE.
   endif

   ! Uniform location from 0 to 1 for this location type

   location%x = random_uniform(ran_seq)
   write(*, *) 'random location is ', location%x

else
   location%x = x
end if

end subroutine interactive_location



function vert_is_level(loc)
!---------------------------------------------------------------------------
!
! Stub needed for temporary linking

logical :: vert_is_level
type(location_type), intent(in) :: loc

vert_is_level = .false.

call error_handler(E_ERR, 'vert_is_level', &
           '"vert_is_level" is not supported for 1D location module', &
            source, revision, revdate)

end function vert_is_level



subroutine read_ncep_obs_location(location, obsunit, obsindex, var)
!---------------------------------------------------------------------------
!
! Stub needed for temporary linking

implicit none

type(location_type)    :: location 
integer                :: obs_prof
integer,   intent(in)  :: obsunit
integer,   intent(out) :: obsindex
real (r8), intent(out) :: var

call error_handler(E_ERR, 'read_ncep_obs_location', &
           '"read_ncep_obs_location" is not supported for 1D location module', &
            source, revision, revdate)

end subroutine read_ncep_obs_location


!----------------------------------------------------------------------------
! end of location/oned/location_mod.f90
!----------------------------------------------------------------------------

end module location_mod

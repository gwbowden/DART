! Data Assimilation Research Testbed -- DART
! Copyright 2004, Data Assimilation Initiative, University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html
 
program ps_rand_local

! <next three lines automatically updated by CVS, do not edit>
! $Source$
! $Revision$
! $Date$

use      types_mod, only : r8, PI
use  utilities_mod, only : get_unit, error_handler, E_ERR
use random_seq_mod, only : random_seq_type, init_random_seq, random_uniform

implicit none

! CVS Generated file description for error handling, do not edit
character(len=128) :: &
source   = "$Source$", &
revision = "$Revision$", &
revdate  = "$Date$"

integer  :: num_sets, level, obs_kind, num, num_done, iunit
real(r8) :: err_var, bot_lat, top_lat, bot_lon, top_lon, lat, lon
type(random_seq_type) :: r

! Initialize the random sequence
call init_random_seq(r)

! Set up constants
num_sets =  1
level    = -1
obs_kind =  3

! Open an output file and write header info
iunit = get_unit()
open(unit = iunit, file = 'ps_rand.out')

write(*, *) 'input the number of observations'
read(*, *) num

write(*, *) 'input the obs error variance'
read(*, *) err_var

write(*, *) 'input a lower bound on latitude -90 to 90'
read(*, *) bot_lat
write(*, *) 'input an upper bound on latitude -90 to 90'
read(*, *) top_lat
write(*, *) 'input a lower bound on longitude: no wraparounds for now '
read(*, *) bot_lon
write(*, *) 'input an upper bound on longitude '
read(*, *) top_lon

! Simple error check to let people know limits
if(top_lat <= bot_lat .or. top_lon <= bot_lon) then
   call error_handler(E_ERR,'ps_rand_local', 'lat lon range error', source, revision, revdate)
endif

! Input number of obs
write(iunit, *) num
! No obs values or qc
write(iunit, *) 0
write(iunit, *) 0

! The radar question percolates through, want no radars
write(iunit, *) 0

num_done = 0
do while(num_done < num)
   ! There are more obs
   write(iunit, *) 0

   ! Kind is ps
   write(iunit, *) obs_kind

   ! Put this on model level -1
   write(iunit, *) 1
   write(iunit, *) level

   ! Want randomly located in horizontal
   write(iunit, *) -1

   ! Input longitude and latitude bounds
   write(iunit, *) bot_lon
   write(iunit, *) top_lon
   write(iunit, *) bot_lat
   write(iunit, *) top_lat

   ! Time is 0 days and 0 seconds for create_obs_sequence base
   write(iunit, *) 0, 0

   ! Error variance
   write(iunit, *) err_var

   num_done = num_done + 1

end do

! File name default is set_def.out
write(iunit, *) 'set_def.out'

end program ps_rand_local

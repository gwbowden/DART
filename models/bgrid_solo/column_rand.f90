! Data Assimilation Research Testbed -- DART
! Copyright 2004, Data Assimilation Initiative, University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html
 
program column_rand

! <next four lines automatically updated by CVS, do not edit>
! $Source$
! $Revision$
! $Date$

! Allows creation of input file for generating a set of randomly located
! observation stations with full column of obs for b-grid model. Should be
! nearly identical to similar thing for CAM, etc.

use      types_mod, only : r8, PI
use random_seq_mod, only : random_seq_type, init_random_seq, random_uniform
use  utilities_mod, only : get_unit

implicit none

! CVS Generated file description for error handling, do not edit
character(len=128) :: &
source   = "$Source$", &
revision = "$Revision$", &
revdate  = "$Date$"

integer  :: num_sets, level, num_cols, num_levs, i, iunit
real(r8) :: lat, lon, t_err_var, uv_err_var, ps_err_var
type(random_seq_type) :: r

! Initialize the random sequence
call init_random_seq(r)

! Set up constants
num_sets = 1

! Open an output file and write header info
iunit = get_unit()
open(unit = iunit, file = 'column_rand.out')
write(iunit, *) 'set_def.out'
write(iunit, *) num_sets

write(*, *) 'input the number of columns'
read(*, *) num_cols

write(*, *) 'input the number of model levels'
read(*, *) num_levs

! Output the total number of obs
write(*, *) 'total num is ', num_cols * (num_levs * 3 + 1)
write(iunit, *) num_cols * (num_levs * 3 + 1)

! First get error variance for surface pressure
write(*, *) 'Input error VARIANCE for surface pressure obs'
read(*, *) ps_err_var

! Get error variance for t, and u and v
write(*, *) 'Input error VARIANCE for T obs'
read(*, *) t_err_var
write(*, *) 'Input error VARIANCE for U and V obs'
read(*, *) uv_err_var


! Loop through each column
do i = 1, num_cols
   ! Get a random lon lat location for this column
   ! Longitude is random from 0 to 360
   lon = random_uniform(r) * 360.0

   ! Latitude must be area weighted
   lat = asin(random_uniform(r) * 2.0 - 1.0)

   ! Now convert from radians to degrees latitude
   lat = lat * 360.0 / (2.0 * pi)

   ! Do ps ob
   write(iunit, *) ps_err_var
   write(iunit, *) -1

   ! Level is -1 for ps
   write(iunit, *) -1
   write(iunit, *) lon
   write(iunit, *) lat

   ! Kind for surface pressure is 3
   write(iunit, *) 3

   ! Loop through each observation in the column
   do level = 1, num_levs

      ! Write out the t observation
      write(iunit, *) t_err_var
      write(iunit, *) -1
      write(iunit, *) level
      write(iunit, *) lon
      write(iunit, *) lat

      ! Kind for t is 4
      write(iunit, *) 4

      ! Write out the u observation
      write(iunit, *) uv_err_var
      write(iunit, *) -1
      write(iunit, *) level
      write(iunit, *) lon
      write(iunit, *) lat

      ! Kind for u is 1
      write(iunit, *) 1

      ! Write out the t observation
      write(iunit, *) uv_err_var
      write(iunit, *) -1
      write(iunit, *) level
      write(iunit, *) lon
      write(iunit, *) lat

      ! Kind for v is 2
      write(iunit, *) 2
   end do
end do

end program column_rand

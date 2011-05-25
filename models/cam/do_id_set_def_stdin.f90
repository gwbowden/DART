! DART software - Copyright 2004 - 2011 UCAR. This open source software is
! provided by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download

program main

! <next few lines under version control, do not edit>
! $URL$
! $Id$
! $Revision$
! $Date$

implicit none

! version controlled file description for error handling, do not edit
character(len=128), parameter :: &
   source   = "$URL$", &
   revision = "$Revision$", &
   revdate  = "$Date$"

integer :: i
integer, parameter :: interval = 105

write(*, *) 'set_def.out'
write(*, *) 1
write(*, *) 13440 / interval

do i = 1, 13440, interval
   write(*, *) 100.0
   write(*, *) i
end do

end program main

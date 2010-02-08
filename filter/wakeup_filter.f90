! DART software - Copyright � 2004 - 2010 UCAR. This open source software is
! provided by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download

program wakeup_filter

! <next few lines under version control, do not edit>
! $URL$
! $Id$
! $Revision$
! $Date$

! spread out on the processors in the same order as the executable
! model and filter programs, and echo into the fifo (named pipe)
! a message to wake up the sleeping filter program.

use mpi_utilities_mod, only : initialize_mpi_utilities, &
                              finalize_mpi_utilities,   &
                              restart_task


call initialize_mpi_utilities("Wakeup_Filter")

call restart_task()

call finalize_mpi_utilities()


end program wakeup_filter

! Data Assimilation Research Testbed -- DART
! Copyright 2004, Data Assimilation Initiative, University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html

program integrate_model

! <next four lines automatically updated by CVS, do not edit>
! $Source$
! $Revision$
! $Date$
! $Author$
!

! Program to integrate assimilation model forward for asynchronous filter
! execution.

use        types_mod, only : r8
use time_manager_mod, only : time_type, set_time, print_time, operator(/=), &
                             operator(>), operator(<), read_time
use    utilities_mod, only : get_unit, open_file, close_file, check_nml_error, &
                             file_exist, initialize_utilities, register_module, &
                             error_handler, logfileunit, E_MSG
use  assim_model_mod, only : assim_model_type, static_init_assim_model, &
   get_model_size, get_initial_condition, get_closest_state_time_to, &
   set_model_time, get_model_time, init_diag_output, &
   output_diagnostics, init_assim_model, get_state_vector_ptr, &
   write_state_restart, read_state_restart, open_restart_read, &
   open_restart_write, close_restart, awrite_state_restart, aread_state_restart

use ensemble_manager_mod, only : init_ensemble_manager, put_ensemble_member, &
   end_ensemble_manager, Aadvance_state, ensemble_type, get_ensemble_member

implicit none

! CVS Generated file description for error handling, do not edit
character(len=128) :: &
source   = "$Source$", &
revision = "$Revision$", &
revdate  = "$Date$"

type(time_type)         :: time, target_time, model_time
real(r8), allocatable   :: x(:)
integer :: iunit, ierr, io, model_size
type(ensemble_type) :: ens_handle

character (len=129)    :: adv_ens_command = ''
!----------------------------------------------------------------
! Namelist input with default values
!
integer :: target_time_days = -1, target_time_seconds = -1
character(len = 129) :: ic_file_name = "temp_ic", &
                        ud_file_name = 'temp_ud'

namelist /integrate_model_nml/ target_time_days, target_time_seconds, &
   ic_file_name, ud_file_name
!----------------------------------------------------------------

call initialize_utilities
call register_module(source,revision,revdate)
call error_handler(E_MSG,'integrate_model','STARTING ...',source,revision,revdate)

! Begin by reading the namelist input
if(file_exist('integrate_model.nml')) then
   iunit = open_file('input.nml', action = 'read')
   ierr = 1
   do while(ierr /= 0)
      read(iunit, nml = integrate_model_nml, iostat = io, end = 11)
      ierr = check_nml_error(io, 'integrate_model_nml')
   enddo
 11 continue
   call close_file(iunit)
endif

! Record the namelist values used for the run ...
call error_handler(E_MSG,'integrate_model','integrate_model_nml values are',' ',' ',' ')
write(logfileunit, nml=integrate_model_nml)
write(     *     , nml=integrate_model_nml)

! Initialize the model class data now that obs_sequence is all set up
call static_init_assim_model()
model_size = get_model_size()

!------------------- Read restart from file ----------------------
iunit = open_restart_read(ic_file_name)
! Read in the target time
allocate(x(model_size))
call aread_state_restart(model_time, x, iunit, target_time)
call close_restart(iunit)
!-----------------  Restart read in --------------------------------

! Put this into and ensemble_manager type
call init_ensemble_manager(ens_handle, 1, model_size)
call put_ensemble_member(ens_handle, 1, x, model_time)

! Advance this state to the target time (which comes from namelist)
! If the model time is past the obs set time, just need to skip
!call print_time(target_time, 'target time is')
!call print_time(model_time, 'model time is')
if(model_time < target_time) then
   call Aadvance_state(ens_handle, target_time, 0, adv_ens_command)
endif

! Output the restart file if requested
iunit = open_restart_write(ud_file_name)
call get_ensemble_member(ens_handle, 1, x, model_time)
call awrite_state_restart(model_time, x, iunit)
call close_restart(iunit)

end program integrate_model

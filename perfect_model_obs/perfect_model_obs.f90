! Data Assimilation Research Testbed -- DART
! Copyright 2004-2007, Data Assimilation Research Section
! University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html

program perfect_model_obs

! <next few lines under version control, do not edit>
! $URL$
! $Id$
! $Revision$
! $Date$

! Program to build an obs_sequence file from simulated observations.

use        types_mod,     only : r8, metadatalength
use    utilities_mod,     only : initialize_utilities, register_module, error_handler, &
                                 find_namelist_in_file, check_namelist_read,           &
                                 E_ERR, E_MSG, E_DBG, nmlfileunit, timestamp,          &
                                 do_nml_file, do_nml_term, logfileunit
use time_manager_mod,     only : time_type, get_time, set_time, operator(/=), print_time
use obs_sequence_mod,     only : read_obs_seq, obs_type, obs_sequence_type,                 &
                                 get_obs_from_key, set_copy_meta_data, get_obs_def,         &
                                 get_time_range_keys, set_obs_values, set_qc, set_obs,      &
                                 write_obs_seq, get_num_obs, init_obs, assignment(=),       &
                                 static_init_obs_sequence, get_num_qc, read_obs_seq_header, &
                                 set_qc_meta_data, get_expected_obs, delete_seq_head,       &
                                 delete_seq_tail, set_obs_def, destroy_obs

use      obs_def_mod,     only : obs_def_type, get_obs_def_error_variance, &
                                 set_obs_def_error_variance, get_obs_def_time
use    obs_model_mod,     only : move_ahead, advance_state, set_obs_model_trace
use  assim_model_mod,     only : static_init_assim_model, get_model_size,                    &
                                 aget_initial_condition, netcdf_file_type, init_diag_output, &
                                 aoutput_diagnostics, finalize_diag_output
   
use mpi_utilities_mod,    only : initialize_mpi_utilities, finalize_mpi_utilities, &
                                 task_count, task_sync

use   random_seq_mod,     only : random_seq_type, init_random_seq, random_gaussian
use ensemble_manager_mod, only : init_ensemble_manager, write_ensemble_restart,              &
                                 end_ensemble_manager, ensemble_type, read_ensemble_restart, &
                                 get_my_num_copies, get_ensemble_time

implicit none

! version controlled file description for error handling, do not edit
character(len=128), parameter :: &
   source   = "$URL$", &
   revision = "$Revision$", &
   revdate  = "$Date$"

! Module storage for message output
character(len=129) :: msgstring
integer            :: trace_level, timestamp_level

!-----------------------------------------------------------------------------
! Namelist with default values
!
logical  :: start_from_restart = .false.
logical  :: output_restart     = .false.
integer  :: async              = 0
logical  :: trace_execution    = .false.
logical  :: output_timestamps  = .false.
logical  :: silence            = .false.
! if init_time_days and seconds are negative initial time is 0, 0
! for no restart or comes from restart if restart exists
integer  :: init_time_days     = 0
integer  :: init_time_seconds  = 0
! Time of first and last observations to be used from obs_sequence
! If negative, these are not used
integer  :: first_obs_days     = -1
integer  :: first_obs_seconds  = -1
integer  :: last_obs_days      = -1
integer  :: last_obs_seconds   = -1
integer  :: obs_window_days    = -1
integer  :: obs_window_seconds = -1
integer  :: tasks_per_model_advance = 1
integer  :: output_interval = 1
character(len = 129) :: restart_in_file_name  = 'perfect_ics',     &
                        restart_out_file_name = 'perfect_restart', &
                        obs_seq_in_file_name  = 'obs_seq.in',      &
                        obs_seq_out_file_name = 'obs_seq.out',     &
                        adv_ens_command       = './advance_model.csh'

namelist /perfect_model_obs_nml/ start_from_restart, output_restart, async,         &
                                 init_time_days, init_time_seconds,                 &
                                 first_obs_days, first_obs_seconds,                 &
                                 last_obs_days,  last_obs_seconds, output_interval, &
                                 restart_in_file_name, restart_out_file_name,       &
                                 obs_seq_in_file_name, obs_seq_out_file_name,       &
                                 adv_ens_command, tasks_per_model_advance,          & 
                                 obs_window_days, obs_window_seconds, silence,      &
                                 trace_execution, output_timestamps

!------------------------------------------------------------------------------

! Doing this allows independent scoping for subroutines in main program file
call perfect_main()

!------------------------------------------------------------------------------

contains

subroutine perfect_main()

type(obs_sequence_type) :: seq
type(obs_type)          :: obs
type(obs_def_type)      :: obs_def
type(random_seq_type)   :: random_seq
type(ensemble_type)     :: ens_handle
type(netcdf_file_type)  :: StateUnit
type(time_type)         :: first_obs_time, last_obs_time
type(time_type)         :: window_time, curr_ens_time, next_ens_time

integer, allocatable    :: keys(:)
integer                 :: j, iunit, time_step_number, obs_seq_file_id
integer                 :: cnum_copies, cnum_qc, cnum_obs, cnum_max
integer                 :: additional_qc, additional_copies
integer                 :: ierr, io, istatus, num_obs_in_set
integer                 :: model_size, key_bounds(2), num_qc, last_key_used

real(r8)                :: true_obs(1), obs_value(1), qc(1), errvar

character(len=129)      :: copy_meta_data(2), qc_meta_data, obs_seq_read_format
character(len=metadatalength) :: state_meta(1)

logical                 :: assimilate_this_ob, evaluate_this_ob, pre_I_format
logical                 :: all_gone

! Initialize all modules used that require it
call perfect_initialize_modules_used()

! Read the namelist entry
call find_namelist_in_file("input.nml", "perfect_model_obs_nml", iunit)
read(iunit, nml = perfect_model_obs_nml, iostat = io)
call check_namelist_read(iunit, io, "perfect_model_obs_nml")

! Record the namelist values used for the run ...
if (do_nml_file()) write(nmlfileunit, nml=perfect_model_obs_nml)
if (do_nml_term()) write(     *     , nml=perfect_model_obs_nml)

! Don't let this run with more than one task; just a waste of resource
if(task_count() > 1) then
   write(msgstring, *) 'Only use one mpi process here: ', task_count(), ' were requested'
   call error_handler(E_ERR, 'perfect_main', msgstring,  &
      source, revision, revdate)
endif
call task_sync()

! set the level of output
call set_trace(trace_execution, output_timestamps, silence)

! Find out how many data copies are in the obs_sequence 
call read_obs_seq_header(obs_seq_in_file_name, cnum_copies, cnum_qc, cnum_obs, cnum_max, &
   obs_seq_file_id, obs_seq_read_format, pre_I_format, close_the_file = .true.)

! First two copies of output will be truth and observation;
! Will overwrite first two existing copies in file if there are any
additional_copies = 2 - cnum_copies
if(additional_copies < 0) additional_copies = 0

! Want to have a qc field available in case forward op wont work
if(cnum_qc == 0) then
   additional_qc = 1
else
   additional_qc = 0
endif

! Read in definition part of obs sequence; expand to include observation and truth field
call read_obs_seq(obs_seq_in_file_name, additional_copies, additional_qc, 0, seq)

! Initialize an obs type variable
call init_obs(obs, cnum_copies + additional_copies, cnum_qc + additional_qc)

! Need metadata for added qc field
if(additional_qc == 1) then
   qc_meta_data = 'Quality Control'
   call set_qc_meta_data(seq, 1, qc_meta_data)
endif

! Need space to put in the obs_values in the sequence;
copy_meta_data(1) = 'observations'
copy_meta_data(2) = 'truth'
call set_copy_meta_data(seq, 1, copy_meta_data(1))
call set_copy_meta_data(seq, 2, copy_meta_data(2))

! Initialize the model now that obs_sequence is all set up
model_size = get_model_size()
write(msgstring,*)'Model size = ',model_size
call error_handler(E_MSG,'perfect_main',msgstring)

! Set up the ensemble storage and read in the restart file
call perfect_read_restart(ens_handle, model_size)

state_meta(1) = 'true state'
! Set up output of truth for state
StateUnit = init_diag_output('True_State', 'true state from control', 1, state_meta)

! Initialize a repeatable random sequence for perturbations
call init_random_seq(random_seq)

! Get the time of the first observation in the sequence
write(msgstring, *) 'total number of obs in sequence is ', get_num_obs(seq)
call error_handler(E_MSG,'perfect_main',msgstring)

num_qc = get_num_qc(seq)
write(msgstring, *) 'number of qc values is ',num_qc
call error_handler(E_MSG,'perfect_main',msgstring)

! Need to find first obs with appropriate time, delete all earlier ones
if(first_obs_seconds > 0 .or. first_obs_days > 0) then
   first_obs_time = set_time(first_obs_seconds, first_obs_days)
   call delete_seq_head(first_obs_time, seq, all_gone)
   if(all_gone) then
      msgstring = 'All obs in sequence are before first_obs_days:first_obs_seconds'
      call error_handler(E_ERR,'perfect_main',msgstring,source,revision,revdate)
   endif
endif

last_key_used = -99

! Also get rid of observations past the last_obs_time if requested
if(last_obs_seconds >= 0 .or. last_obs_days >= 0) then
   last_obs_time = set_time(last_obs_seconds, last_obs_days)
   call delete_seq_tail(last_obs_time, seq, all_gone)
   if(all_gone) then
      msgstring = 'All obs in sequence are after last_obs_days:last_obs_seconds'
      call error_handler(E_ERR,'perfect_main',msgstring,source,revision,revdate)
   endif
endif

! Time step number is used to do periodic diagnostic output
time_step_number = -1
window_time = set_time(0,0)

! Advance model to the closest time to the next available observations
AdvanceTime: do
   time_step_number = time_step_number + 1

   write(msgstring , '(A,I5)') 'Main evaluation loop, starting iteration', time_step_number
   if (.not.silence) call error_handler(E_MSG,'', ' ')
   if (.not.silence) call error_handler(E_MSG,'perfect_model_obs:', msgstring)

   ! Get the model to a good time to use a next set of observations
   call move_ahead(ens_handle, 1, seq, last_key_used, window_time, &
      key_bounds, num_obs_in_set, curr_ens_time, next_ens_time)
   if(key_bounds(1) < 0) then
      call error_handler(E_MSG,'perfect_model_obs:', 'No more obs to evaluate, exiting main loop')
      exit AdvanceTime
   endif
 
   if (curr_ens_time /= next_ens_time) then
      if (.not.silence) call error_handler(E_MSG,'perfect_model_obs:', 'Ready to run model to advance data time')
      call advance_state(ens_handle, 1, next_ens_time, async, &
         adv_ens_command, tasks_per_model_advance)
   else
      if (.not.silence) call error_handler(E_MSG,'perfect_model_obs:', 'Model does not need to run; data already at required time')
   endif

   ! Allocate storage for observation keys for this part of sequence
   allocate(keys(num_obs_in_set))

   ! Get all the keys associated with this set of observations
   call get_time_range_keys(seq, key_bounds, num_obs_in_set, keys)

   ! Output the true state to the netcdf file
   if(time_step_number / output_interval * output_interval == time_step_number) &
      call aoutput_diagnostics(StateUnit, ens_handle%time(1), ens_handle%vars(:, 1), 1)

   write(msgstring, '(A,I8,A)') 'Ready to evaluate up to', size(keys), ' observations'
   if (.not.silence) call error_handler(E_MSG,'perfect_model_obs:', msgstring)

   ! How many observations in this set
   write(msgstring, *) 'num_obs_in_set is ', num_obs_in_set
   call error_handler(E_DBG,'perfect_main',msgstring,source,revision,revdate)

   ! Compute the forward observation operator for each observation in set
   do j = 1, num_obs_in_set

      ! Compute the observations from the state
      call get_expected_obs(seq, keys(j:j), ens_handle%vars(:, 1), &
         true_obs(1:1), istatus, assimilate_this_ob, evaluate_this_ob)
      ! If observation is not being evaluated or assimilated, skip it
      ! Ends up setting a 1000 qc field so observation is not used again.

      ! Get the observational error covariance (diagonal at present)
      ! Generate the synthetic observations by adding in error samples
      call get_obs_from_key(seq, keys(j), obs)
      call get_obs_def(obs, obs_def)

      if(istatus == 0 .and. (assimilate_this_ob .or. evaluate_this_ob)) then
         ! DEBUG: try this out to see if it's useful.  if the incoming error
         ! variance is negative, add no noise to the values, but do switch the
         ! sign on the error so the file is useful in subsequent runs.
         errvar = get_obs_def_error_variance(obs_def)
         if (errvar > 0.0_r8) then
            obs_value(1) = random_gaussian(random_seq, true_obs(1), errvar)
         else
            obs_value(1) = true_obs(1)
            call set_obs_def_error_variance(obs_def, -errvar)
            call set_obs_def(obs, obs_def)
         endif

         ! Set qc to 0 if none existed before
         if(cnum_qc == 0) then
            qc(1) = 0.0_r8
            call set_qc(obs, qc, 1)
         endif
      else
         obs_value(1) = true_obs(1)
         qc(1) = 1000.0_r8
         call set_qc(obs, qc, 1)
      endif

      call set_obs_values(obs, obs_value, 1)
      call set_obs_values(obs, true_obs, 2)

! Insert the observations into the sequence first copy
      call set_obs(seq, obs, keys(j))

   end do

! Deallocate the keys storage
   deallocate(keys)

! The last key used is updated to move forward in the observation sequence
   last_key_used = key_bounds(2)

end do AdvanceTime

call error_handler(E_MSG,'perfect_model_obs:', 'End of main filter evaluation loop, starting cleanup')

! properly dispose of the diagnostics files
ierr = finalize_diag_output(StateUnit)

! Write out the sequence
call write_obs_seq(seq, obs_seq_out_file_name)

! Output a restart file if requested
if(output_restart) &
   call write_ensemble_restart(ens_handle, restart_out_file_name, 1, 1, &
      force_single_file = .true.)

!  Release storage for ensemble
call end_ensemble_manager(ens_handle)

call error_handler(E_MSG,'perfect_main','FINISHED',source,revision,revdate)

! closes the log file.
call timestamp(string1=source,string2=revision,string3=revdate,pos='end')

call finalize_mpi_utilities()

end subroutine perfect_main

!=====================================================================

subroutine perfect_initialize_modules_used()

! Fire up mpi so we can use the ensemble manager
call initialize_mpi_utilities('Perfect_model_obs')

! Initialize modules used that require it
call register_module(source,revision,revdate)

! Initialize the obs sequence module
call static_init_obs_sequence()
! Initialize the model class data now that obs_sequence is all set up
call static_init_assim_model()

end subroutine perfect_initialize_modules_used

!---------------------------------------------------------------------

subroutine perfect_read_restart(ens_handle, model_size)

type(ensemble_type), intent(inout) :: ens_handle
integer,             intent(in)    :: model_size

type(time_type) :: time1
integer         :: secs, days

! First initialize the ensemble manager storage, only 1 copy for perfect
call init_ensemble_manager(ens_handle, 1, model_size, 1)

! If not start_from_restart, use model to get ics for state and time
if(.not. start_from_restart) then
   call aget_initial_condition(ens_handle%time(1), ens_handle%vars(:, 1))
else

   ! Read in initial conditions from restart file
   if(init_time_days >= 0) then
      time1 = set_time(init_time_seconds, init_time_days)
      call read_ensemble_restart(ens_handle, 1, 1, &
         start_from_restart, restart_in_file_name, time1, force_single_file = .true.)
   else
      call read_ensemble_restart(ens_handle, 1, 1, &
         start_from_restart, restart_in_file_name, force_single_file = .true.)
   endif
endif

! Temporary print of initial model time
call get_time(ens_handle%time(1),secs,days)
write(msgstring, *) 'initial model time of perfect_model member (days,seconds) ',days,secs
call error_handler(E_DBG,'perfect_read_restart',msgstring,source,revision,revdate)

end subroutine perfect_read_restart

!-------------------------------------------------------------------------

subroutine set_trace(trace_execution, output_timestamps, silence)

logical, intent(in) :: trace_execution
logical, intent(in) :: output_timestamps
logical, intent(in) :: silence

! Set whether other modules trace execution with messages
! and whether they output timestamps to trace overall performance

! defaults
trace_level     = 0
timestamp_level = 0

! selectively turn stuff back on
if (trace_execution)   trace_level     = 1
if (output_timestamps) timestamp_level = 1

! turn as much off as possible
if (silence) then
   trace_level     = -1
   timestamp_level = -1
endif

call set_obs_model_trace(trace_level, timestamp_level)

end subroutine set_trace

!-------------------------------------------------------------------------

subroutine trace_message(msg, label, threshold)

character(len=*), intent(in)           :: msg
character(len=*), intent(in), optional :: label
integer,          intent(in), optional :: threshold

! Write message to stdout and log file.
integer :: t

t = 0
if (present(threshold)) t = threshold

if (trace_level <= t) return

if (present(label)) then
   call error_handler(E_MSG,trim(label),trim(msg))
else
   call error_handler(E_MSG,'p_m_o trace:',trim(msg))
endif

end subroutine trace_message

!-------------------------------------------------------------------------

subroutine timestamp_message(msg, sync)

character(len=*), intent(in) :: msg
logical, intent(in), optional :: sync

! Write current time and message to stdout and log file. 
! if sync is present and true, sync mpi jobs before printing time.

if (timestamp_level <= 0) return

if (present(sync)) then
  if (sync) call task_sync()
endif

call timestamp(trim(msg), pos='debug')

end subroutine timestamp_message

!-------------------------------------------------------------------------

subroutine print_ens_time(ens_handle, msg)

type(ensemble_type), intent(in) :: ens_handle
character(len=*), intent(in) :: msg

! Write message to stdout and log file.
type(time_type) :: mtime

if (trace_level <= 0) return

if (get_my_num_copies(ens_handle) < 1) return

call get_ensemble_time(ens_handle, 1, mtime)
call print_time(mtime, msg, logfileunit)
call print_time(mtime, msg)

end subroutine print_ens_time

!-------------------------------------------------------------------------

subroutine print_obs_time(seq, key, msg)

type(obs_sequence_type), intent(in) :: seq
integer, intent(in) :: key
character(len=*), intent(in), optional :: msg

! Write time of an observation to stdout and log file.
type(obs_type) :: obs
type(obs_def_type) :: obs_def
type(time_type) :: mtime

if (trace_level <= 0) return

call init_obs(obs, 0, 0)
call get_obs_from_key(seq, key, obs)
call get_obs_def(obs, obs_def)
mtime = get_obs_def_time(obs_def)
call print_time(mtime, msg, logfileunit)
call print_time(mtime, msg)
call destroy_obs(obs)

end subroutine print_obs_time

!-------------------------------------------------------------------------

end program perfect_model_obs

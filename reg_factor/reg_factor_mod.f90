! Data Assimilation Research Testbed -- DART
! Copyright 2004, Data Assimilation Initiative, University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html
 
module reg_factor_mod

! <next four lines automatically updated by CVS, do not edit>
! $Source$
! $Revision$
! $Date$
! $Author$
!

use     types_mod, only : r8
use utilities_mod, only : get_unit, file_exist, open_file, check_nml_error, &
                          close_file, error_handler, E_ERR

implicit none
private

public comp_reg_factor


!============================================================================

logical :: namelist_initialized = .false.

!---- namelist with default values

integer :: select_regression = 1
! Value 1 selects default: Compute using sampling theory for any ensemble size
! Value 2 selects L96 file format: Works for archived 40 observation L96 files
! Value 3 selects bgrid archive default: Reads in file from bgrid experiments
character(len = 129) :: input_reg_file = "time_mean_reg"

namelist / reg_factor_nml / select_regression

!============================================================================


! Flags for loading startup
logical :: first_call = .true.
! Size of regression input files
integer :: num_obs, model_size

! Global storage for time mean regression factors from file
real(r8), allocatable :: time_mean_reg(:, :)

! Global storage for bgrid mean regression factor file
real(r8), allocatable :: obs_state_reg(:)

! CVS Generated file description for error handling, do not edit
character(len=128) :: &
source   = "$Source$", &
revision = "$Revision$", &
revdate  = "$Date$"

CONTAINS

function comp_reg_factor(num_groups, regress, time_index, &
   obs_index, state_index, obs_state_ind, obs_state_max)

! Computes factor by which to multiply regression coefficients
! for a given distribution of sample regressions OR computes
! factor for a single sample of a regression using some other
! methodology (for instance time mean from previous runs). Could
! also implement the standard distance dependence method, too.

integer, intent(in) :: num_groups, time_index, obs_index, state_index
integer, intent(in), optional :: obs_state_ind, obs_state_max
real(r8), intent(in) :: regress(num_groups)
real(r8) :: comp_reg_factor

real(r8) :: sum_reg2, mean_reg, var_reg, sum_reg_reg

integer :: i, j, ii, jj, iunit, ierr, io 

!--------------------------------------------------------
! Initialize namelist if not already done
if(.not. namelist_initialized) then
   namelist_initialized = .true.
   if(file_exist('input.nml')) then
      iunit = open_file('input.nml', action = 'read')
      ierr = 1

      READBLOCK: do while(ierr /= 0)
         read(iunit, nml = reg_factor_nml, iostat = io)
         if ( io < 0 ) exit READBLOCK          ! end-of-file
         ierr = check_nml_error(io, 'reg_factor_nml')
      enddo READBLOCK

      call close_file(iunit)
   endif
endif
!---------------------------------------------------------

!_____________________________________________________________________
if(select_regression == 1) then

! Get regression directly from sampling theory
! If only one group, don't know what else to do
   if(num_groups == 1) then
      comp_reg_factor = 1
   else

      sum_reg_reg = 0.0
      sum_reg2 = sum(regress * regress)
      do i = 1, num_groups
         do j = i + 1, num_groups
            sum_reg_reg = sum_reg_reg + regress(i) * regress(j)
         end do                                               
      end do
      comp_reg_factor = 2 * sum_reg_reg / (sum_reg2 * (num_groups - 1))

      if(comp_reg_factor < 0.0) comp_reg_factor = 0.0

!!!      if(obs_index == 14) write(44, *) time_index, obs_index, state_index, &
!!!         comp_reg_factor

   endif

!___________________________________________________________________

else if(select_regression == 2) then

! Table lookup version for time mean, temporary implementation
! This only works for a model with a time invariant observation set
   if(first_call) then
      first_call = .false.
! Read in the regression statistics file
      iunit = get_unit()
      open(unit = iunit, file = input_reg_file)
      read(iunit, *) num_obs, model_size
      allocate(time_mean_reg(num_obs, model_size))
      do j = 1, num_obs
         do i = 1, model_size
            read(iunit, *) jj, ii, time_mean_reg(j, i)
         end do
      end do
      close(iunit)
   endif

   comp_reg_factor = time_mean_reg(obs_index, state_index)

   if(comp_reg_factor < 0.0) comp_reg_factor = 0.0

!_____________________________________________________________________

else if(select_regression == 3) then

   if(first_call) then
      allocate(obs_state_reg(obs_state_max))
      first_call = .false.
      do i = 1, obs_state_max
! WARNING: PLEASE USE OPEN_FILE
         open(unit = 51, file = 'obs_state_reg_file')
         read(51, 11) obs_state_reg(i)
         close(unit = 51)
11    format(f5.3)
      end do 
   end if

   comp_reg_factor = obs_state_reg(obs_state_ind)

!_____________________________________________________________________

else
   call error_handler(E_ERR,'comp_reg_factor', &
      'Illegal value for namelist parameter select_regression',source, revision, revdate)
endif

end function comp_reg_factor

end module reg_factor_mod

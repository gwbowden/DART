! Data Assimilation Research Testbed -- DART
! Copyright 2004, Data Assimilation Initiative, University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html

module assim_model_mod

! <next four lines automatically updated by CVS, do not edit>
! $Source$ 
! $Revision$ 
! $Date$ 
! $Author$ 
!
! This module is used to wrap around the basic portions of existing dynamical models to
! add capabilities needed by the standard assimilation methods.

use    types_mod, only : r8
use location_mod, only : location_type, get_dist, write_location, read_location, &
                         LocationDims, LocationName, LocationLName
! I've had a problem with putting in the only for time_manager on the pgf90 compiler (JLA).
use time_manager_mod, only : time_type, get_time, read_time, write_time, get_calendar_type, &
                             THIRTY_DAY_MONTHS, JULIAN, GREGORIAN, NOLEAP, NO_CALENDAR, &
                             operator(<), operator(>), operator(+), operator(-), &
                             operator(/), operator(*), operator(==), operator(/=)
use utilities_mod, only : get_unit, file_exist, open_file, check_nml_error, close_file, &
                          register_module, error_handler, E_ERR, E_WARN, E_MSG, E_DBG, logfileunit
use     model_mod, only : get_model_size, static_init_model, get_state_meta_data, &
            get_model_time_step, model_interpolate, init_conditions, init_time, adv_1step, &
            end_model, model_get_close_states, nc_write_model_atts, nc_write_model_vars, &
            pert_model_state

implicit none
private

public :: static_init_assim_model, init_diag_output, get_model_size, get_closest_state_time_to, &
   get_initial_condition, get_state_meta_data, get_close_states, get_num_close_states, &
   get_model_time, get_model_state_vector, copy_assim_model, interpolate, &
   set_model_time, set_model_state_vector, write_state_restart, read_state_restart, &
   output_diagnostics, end_assim_model, assim_model_type, init_diag_input, input_diagnostics, &
   get_diag_input_copy_meta_data, init_assim_model, get_state_vector_ptr, &
   finalize_diag_output, aoutput_diagnostics, aread_state_restart, aget_closest_state_time_to, &
   awrite_state_restart, pert_model_state, &
   netcdf_file_type, nc_append_time, nc_write_calendar_atts, nc_get_tindex, &
   get_model_time_step, open_restart_read, open_restart_write, close_restart, adv_1step, &
   aget_initial_condition

! CVS Generated file description for error handling, do not edit
character(len=128) :: &
source   = "$Source$", &
revision = "$Revision$", &
revdate  = "$Date$"


! Eventually need to be very careful to implement this to avoid state vector copies which
! will be excruciatingly costly (storage at least) in big models. 
type assim_model_type
   private
   real(r8), pointer :: state_vector(:)
   type(time_type) :: time
   integer :: model_size       ! TJH request
   integer :: copyID           ! TJH request
! would like to include character string to indicate which netCDF variable --
! replace "state" in output_diagnostics ...
end type assim_model_type

!----------------------------------------------------------------
! output (netcdf) file descriptor
! basically, we want to keep a local mirror of the unlimited dimension
! coordinate variable (i.e. time) because dynamically querying it
! causes unacceptable performance degradation over "long" integrations.

type netcdf_file_type
   integer :: ncid                       ! the "unit" -- sorta
   integer :: Ntimes                     ! the current working length
   integer :: NtimesMAX                  ! the allocated length.
   real(r8),        pointer :: rtimes(:) ! times -- as real*8
   type(time_type), pointer :: times(:)  ! times -- as the models use
   character(len=80)        :: fname     ! filename ...
end type netcdf_file_type

! Permanent class storage for model_size
integer :: model_size

! Global storage for restart formats
character(len = 16) :: read_format = "unformatted", write_format = "unformatted"

type(time_type) :: time_step

!-------------------------------------------------------------
! Namelist with default values
! binary_restart_files  == .true.  -> use unformatted file format. 
!                                     Full precision, faster, smaller,
!                                     but not as portable.
! binary_restart_files  == .false.  -> use ascii file format. 
!                                     Portable, but loses precision,
!                                     slower, and larger.

logical  :: read_binary_restart_files = .true.
logical  :: write_binary_restart_files = .true.

namelist /assim_model_nml/ read_binary_restart_files, write_binary_restart_files
!-------------------------------------------------------------

contains

!======================================================================


subroutine init_assim_model(state)
!----------------------------------------------------------------------
!
! Allocates storage for an instance of an assim_model_type. With this
! implementation, need to be VERY careful about assigment and maintaining
! permanent storage locations. Need to revisit the best way to do 
! assim_model_copy below.

implicit none

type(assim_model_type), intent(inout) :: state

! Get the model_size from the model
model_size = get_model_size()

allocate(state%state_vector(model_size))
state%model_size = model_size

end subroutine init_assim_model




subroutine static_init_assim_model()
!----------------------------------------------------------------------
! subroutine static_init_assim_model()
!
! Initializes class data for the assim_model. Also calls the static
! initialization for the underlying model. So far, this simply 
! is initializing the position of the state variables as location types.

implicit none

integer :: iunit, ierr, io

! First thing to do is echo info to logfile ... 

call register_module(source, revision, revdate)

! Read the namelist input
if(file_exist('input.nml')) then
   iunit = open_file('input.nml', action = 'read')
   ierr = 1
   do while(ierr /= 0)
      read(iunit, nml = assim_model_nml, iostat = io, end = 11)
      ierr = check_nml_error(io, 'assim_model_nml')
   enddo
 11 continue
   call close_file(iunit)
endif

! Record the namelist values used for the run ... 
write(logfileunit, nml=assim_model_nml)

! Set the read and write formats for restart files
if(read_binary_restart_files) then
   read_format = "unformatted"
else
   read_format = "formatted"
endif

if(write_binary_restart_files) then
   write_format = "unformatted"
else
   write_format = "formatted"
endif

! Call the underlying model's static initialization
call static_init_model()

end subroutine static_init_assim_model



function init_diag_output(FileName, global_meta_data, &
                  copies_of_field_per_time, meta_data_per_copy) result(ncFileID)
!--------------------------------------------------------------------------------
!
! Typical sequence:
! NF90_OPEN             ! create netCDF dataset: enter define mode
!    NF90_def_dim       ! define dimenstions: from name and length
!    NF90_def_var       ! define variables: from name, type, and dims
!    NF90_put_att       ! assign attribute values
! NF90_ENDDEF           ! end definitions: leave define mode
!    NF90_put_var       ! provide values for variable
! NF90_CLOSE            ! close: save updated netCDF dataset
!
! Time is a funny beast ... 
! Many packages decode the time:units attribute to convert the offset to a calendar
! date/time format. Using an offset simplifies many operations, but is not the
! way we like to see stuff plotted. The "approved" calendars are:
! gregorian or standard 
!      Mixed Gregorian/Julian calendar as defined by Udunits. This is the default. 
!  noleap   Modern calendar without leap years, i.e., all years are 365 days long. 
!  360_day  All years are 360 days divided into 30 day months. 
!  julian   Julian calendar. 
!  none     No calendar. 
!
! location is another one ...
!

use typeSizes
use netcdf
implicit none

character(len=*), intent(in) :: FileName, global_meta_data
integer,          intent(in) :: copies_of_field_per_time
character(len=*), intent(in) :: meta_data_per_copy(copies_of_field_per_time)
type(netcdf_file_type)       :: ncFileID

character(len=129)   :: msgstring
integer             :: i, metadata_length

integer ::   MemberDimID,   MemberVarID     ! for each "copy" or ensemble member
integer ::     TimeDimID,     TimeVarID
integer :: LocationDimID
integer :: MetadataDimID, MetadataVarID


if(.not. byteSizesOK()) then
    call error_handler(E_ERR,'init_diag_output', &
   'Compiler does not support required kinds of variables.',source,revision,revdate) 
end if

metadata_length = LEN(meta_data_per_copy(1))

! Create the file
ncFileID%fname = trim(adjustl(FileName))//".nc"
call check(nf90_create(path = trim(ncFileID%fname), cmode = nf90_share, ncid = ncFileID%ncid))

write(msgstring,*)trim(ncFileID%fname), ' is ncFileID ',ncFileID%ncid
call error_handler(E_MSG,'init_diag_output',msgstring,source,revision,revdate)

! Define the dimensions
call check(nf90_def_dim(ncid=ncFileID%ncid, &
             name="metadatalength", len = metadata_length,        dimid = metadataDimID))

call check(nf90_def_dim(ncid=ncFileID%ncid, &
             name="locationrank",   len = LocationDims,           dimid = LocationDimID))

call check(nf90_def_dim(ncid=ncFileID%ncid, &
             name="copy",           len=copies_of_field_per_time, dimid = MemberDimID))

call check(nf90_def_dim(ncid=ncFileID%ncid, &
             name="time",           len = nf90_unlimited,         dimid = TimeDimID))

!-------------------------------------------------------------------------------
! Write Global Attributes 
!-------------------------------------------------------------------------------

call check(nf90_put_att(ncFileID%ncid, NF90_GLOBAL, "title", global_meta_data))
call check(nf90_put_att(ncFileID%ncid, NF90_GLOBAL, "assim_model_source", source ))
call check(nf90_put_att(ncFileID%ncid, NF90_GLOBAL, "assim_model_revision", revision ))
call check(nf90_put_att(ncFileID%ncid, NF90_GLOBAL, "assim_model_revdate", revdate ))

!-------------------------------------------------------------------------------
! Create variables and attributes.
! The locations are part of the model (some models have multiple grids).
! They are written by model_mod:nc_write_model_atts
!-------------------------------------------------------------------------------

!    Copy ID
call check(nf90_def_var(ncid=ncFileID%ncid, name="copy", xtype=nf90_int, dimids=MemberDimID, &
                                                                    varid=MemberVarID))
call check(nf90_put_att(ncFileID%ncid, MemberVarID, "long_name", "ensemble member or copy"))
call check(nf90_put_att(ncFileID%ncid, MemberVarID, "units",     "nondimensional") )
call check(nf90_put_att(ncFileID%ncid, MemberVarID, "valid_range", (/ 1, copies_of_field_per_time /)))


!    Metadata for each Copy
call check(nf90_def_var(ncid=ncFileID%ncid,name="CopyMetaData", xtype=nf90_char,    &
                        dimids = (/ metadataDimID, MemberDimID /),  varid=metadataVarID))
call check(nf90_put_att(ncFileID%ncid, metadataVarID, "long_name",       &
                        "Metadata for each copy/member"))

!    Time -- the unlimited dimension
call check(nf90_def_var(ncFileID%ncid, name="time", xtype=nf90_double, dimids=TimeDimID, &
                                                                  varid =TimeVarID) )
i = nc_write_calendar_atts(ncFileID, TimeVarID)     ! comes from time_manager_mod
if ( i /= 0 ) then
   write(msgstring, *)'nc_write_calendar_atts  bombed with error ', i
   call error_handler(E_MSG,'init_diag_output',msgstring,source,revision,revdate)
endif

! Create the time "mirror" with a static length. There is another routine
! to increase it if need be. For now, just pick something.
ncFileID%Ntimes    = 0
ncFileID%NtimesMAX = 1000
allocate(ncFileID%rtimes(ncFileID%NtimesMAX), ncFileID%times(ncFileID%NtimesMAX) )

!-------------------------------------------------------------------------------
! Leave define mode so we can fill
!-------------------------------------------------------------------------------
call check(nf90_enddef(ncFileID%ncid))

!-------------------------------------------------------------------------------
! Fill the coordinate variables.
! The time variable is filled as time progresses.
!-------------------------------------------------------------------------------

call check(nf90_put_var(ncFileID%ncid, MemberVarID,   (/ (i,i=1,copies_of_field_per_time) /) ))
call check(nf90_put_var(ncFileID%ncid, metadataVarID, meta_data_per_copy ))

!-------------------------------------------------------------------------------
! sync to disk, but leave open
!-------------------------------------------------------------------------------

call check(nf90_sync(ncFileID%ncid))

!-------------------------------------------------------------------------------
! Define the model-specific components
!-------------------------------------------------------------------------------

i =  nc_write_model_atts( ncFileID%ncid )
if ( i /= 0 ) then
   write(msgstring, *)'nc_write_model_atts  bombed with error ', i
   call error_handler(E_MSG,'init_diag_output',msgstring,source,revision,revdate)
endif

!-------------------------------------------------------------------------------
call check(nf90_sync(ncFileID%ncid))               ! sync to disk, but leave open
!-------------------------------------------------------------------------------

write(logfileunit,*)trim(ncFileID%fname), ' is ncid ',ncFileID%ncid
write(logfileunit,*)'ncFileID%NtimesMAX is ',ncFileID%NtimesMAX
write(logfileunit,*)'ncFileID%Ntimes    is ',ncFileID%Ntimes

contains

  ! Internal subroutine - checks error status after each netcdf, prints 
  !                       text message each time an error code is returned. 
  subroutine check(status)
    integer, intent ( in) :: status
    if(status /= nf90_noerr) call error_handler(E_ERR,'init_diag_output', &
                                  trim(nf90_strerror(status)), source, revision, revdate)
  end subroutine check  

end function init_diag_output



function finalize_diag_output(ncFileID) result(ierr)
!--------------------------------------------------------------------------------
!

use netcdf
implicit none

type(netcdf_file_type), intent(inout) :: ncFileID
integer             :: ierr

ierr = NF90_close(ncFileID%ncid)

ncFileID%fname     = "notinuse"
ncFileID%ncid      = -1
ncFileID%Ntimes    = -1
ncFileID%NtimesMax = -1
deallocate(ncFileID%rtimes, ncFileID%times )

end function finalize_diag_output



function init_diag_input(file_name, global_meta_data, model_size, copies_of_field_per_time)
!--------------------------------------------------------------------------
!
! Initializes a model state diagnostic file for input. A file id is
! returned which for now is just an integer unit number.

implicit none

integer :: init_diag_input
character(len = *), intent(in)  :: file_name
character(len = *), intent(out) :: global_meta_data
integer,            intent(out) :: model_size, copies_of_field_per_time

init_diag_input = get_unit()
open(unit = init_diag_input, file = file_name)
read(init_diag_input, *) global_meta_data

! Read the model size
read(init_diag_input, *) model_size

! Read the number of copies of field per time
read(init_diag_input, *) copies_of_field_per_time

end function init_diag_input



subroutine get_diag_input_copy_meta_data(file_id, model_size_out, num_copies, &
   location, meta_data_per_copy)
!-------------------------------------------------------------------------
!
! Returns the meta data associated with each copy of data in
! a diagnostic input file. Should be called immediately after 
! function init_diag_input.

implicit none

integer, intent(in) :: file_id, model_size_out, num_copies
type(location_type), intent(out) :: location(model_size_out)
character(len = *) :: meta_data_per_copy(num_copies)

character(len=129) :: header, errstring
integer :: i, j

! Should have space checks, etc here
! Read the meta data associated with each copy
do i = 1, num_copies
   read(file_id, *) j, meta_data_per_copy(i)
end do

! Will need other metadata, too; Could be as simple as writing locations
read(file_id, *) header
if(header /= 'locat') then
   write(errstring,*)'expected to read "locat" got ',trim(adjustl(header))
   call error_handler(E_ERR,'get_diag_input_copy_meta_data', &
        errstring, source, revision, revdate)
endif

! Read in the locations
do i = 1, model_size_out
   location(i) =  read_location(file_id)
end do

end subroutine get_diag_input_copy_meta_data




function get_closest_state_time_to(assim_model, time)
!----------------------------------------------------------------------
!
! Returns the time closest to the given time that the model can reach
! with its state. Initial implementation just assumes fixed timestep.
! Need to describe potentially more general time-stepping capabilities
! from the underlying model in the long run.

implicit none

type(assim_model_type), intent(in) :: assim_model
type(time_type), intent(in) :: time
type(time_type) :: get_closest_state_time_to

type(time_type) :: model_time

model_time = assim_model%time

get_closest_state_time_to = aget_closest_state_time_to(model_time, time)

end function get_closest_state_time_to



function aget_closest_state_time_to(model_time, time)
!----------------------------------------------------------------------
!
! Returns the time closest to the given time that the model can reach
! with its state. Initial implementation just assumes fixed timestep.
! Need to describe potentially more general time-stepping capabilities
! from the underlying model in the long run.

implicit none

type(time_type), intent(in) :: model_time, time
type(time_type) :: aget_closest_state_time_to

type(time_type) :: time_step

character(len=129) :: errstring
integer :: is1,is2,id1,id2

! Get the model time step capabilities
time_step = get_model_time_step()

if(model_time > time) then
   call get_time(model_time,is1,id1)
   call get_time(time,is2,id2)
   write(errstring, *)'model time (',is1,id1,') > time (',is2,id2,')'
   call error_handler(E_ERR,'aget_closest_state_time_to', errstring, source, revision, revdate)
endif

aget_closest_state_time_to = model_time

do while((time_step + 2*aget_closest_state_time_to) < 2*time)
   aget_closest_state_time_to = aget_closest_state_time_to + time_step
enddo

end function aget_closest_state_time_to



subroutine get_initial_condition(x)
!----------------------------------------------------------------------
! function get_initial_condition()
!
! Initial conditions. This returns an initial assim_model_type
! which includes both a state vector and a time. Design of exactly where this 
! stuff should come from is still evolving (12 July, 2002) but for now can 
! start at time offset 0 with the initial state.
! Need to carefully coordinate this with the times for observations.

implicit none

type(assim_model_type), intent(inout) :: x

call aget_initial_condition(x%time, x%state_vector)

end subroutine get_initial_condition



subroutine aget_initial_condition(time, x)
!----------------------------------------------------------------------
! function get_initial_condition()
!
! Initial conditions. This returns an initial assim_model_type
! which includes both a state vector and a time. Design of exactly where this 
! stuff should come from is still evolving (12 July, 2002) but for now can 
! start at time offset 0 with the initial state.
! Need to carefully coordinate this with the times for observations.

implicit none

type(time_type), intent(out) :: time
real(r8), intent(inout) :: x(:)

call init_conditions(x)

call init_time(time)

end subroutine aget_initial_condition




subroutine get_close_states(location, radius, numinds, indices, dist, x)
!---------------------------------------------------------------------
! subroutine get_close_states(location, radius, numinds, indices)
!
! Returns a list of indices for model state vector points that are
! within distance radius of the location. Might want to add an option
! to return the distances, too. This is written in a model independent
! form at present, hence it is in assim_model_mod. HOWEVER, for
! efficiency in large models, this will have to be model specific at
! some point. At that time, need a way to test to see if this 
! generic form should be over loaded (how to do this in F90 ) by 
! some model specific method.

implicit none

type(location_type), intent(in)  :: location
real(r8),            intent(in)  :: radius
integer,             intent(out) :: numinds, indices(:)
real(r8),            intent(out) :: dist(:)
real(r8),            intent(in)  :: x(:)

type(location_type) :: state_loc
integer :: indx, i
real(r8) :: this_dist

! If model provides a working get_close_states, use it; otherwise search
! Direct use of model dependent stuff, needs to be automated (F90 can't do this
call model_get_close_states(location, radius, numinds, indices, dist, x)

! If numinds returns as -1, not implemented
if(numinds == -1) then
   indx = 0
   model_size = get_model_size()
   do i = 1, model_size
      call get_state_meta_data(i, state_loc)
      this_dist = get_dist(location, state_loc)
      if(this_dist < radius) then
         indx = indx + 1
         if(indx <= size(indices)) indices(indx) = i
         if(indx <= size(dist)) dist(indx) = this_dist
      end if
   end do
   numinds = indx
endif

! If size has overflowed, indicate this with negative size return
if(numinds > size(indices) .or. numinds > size(dist)) then
   numinds = -1 * numinds
end if

end subroutine get_close_states



function get_num_close_states(location, radius, x)
!-----------------------------------------------------------------------
!
! Returns number of state vector points located within distance radius
! of the location.

implicit none

integer :: get_num_close_states
type(location_type), intent(in) :: location
real(r8),            intent(in) :: radius
real(r8),            intent(in) :: x(:)

type(location_type) :: state_loc
integer             :: i, indices(1)
real(r8)            :: dist(1)


! call direct model get close with storage that is too 
! small and get size from this
! model_get_close_states returns -1 if it is not implemented
call model_get_close_states(location, radius, get_num_close_states, indices, dist, x)

if(get_num_close_states == -1) then
   ! Do exhaustive search
   get_num_close_states = 0
   do i = 1, model_size
      call get_state_meta_data(i, state_loc)
      ! INTERESTING NOTE: Because of floating point round-off in comps
      ! this can give a 'variable' number of num close for certain obs, should fix
      if(get_dist(location, state_loc) < radius) get_num_close_states= get_num_close_states + 1
   end do

endif
   
end function get_num_close_states



function get_model_time(assim_model)
!-----------------------------------------------------------------------
!
! Returns the time component of a assim_model extended state.

implicit none

type(time_type) :: get_model_time
type(assim_model_type), intent(in) :: assim_model

get_model_time = assim_model%time

end function get_model_time



function get_state_vector_ptr(assim_model)
!------------------------------------------------------------------------
!
! Returns a pointer directly into the assim_model state vector storage.

implicit none

real(r8), pointer :: get_state_vector_ptr(:)
type(assim_model_type), intent(in) :: assim_model

get_state_vector_ptr => assim_model%state_vector

end function get_state_vector_ptr





subroutine copy_assim_model(model_out, model_in)
!-------------------------------------------------------------------------
!
! Does a copy of assim_model, should be overloaded to =? Still need to be
! very careful about trying to limit copies of the potentially huge state
! vectors for big models.  Interaction with pointer storage?

implicit none

type(assim_model_type), intent(out) :: model_out
type(assim_model_type), intent(in)  :: model_in

integer :: i

! Need to make sure to copy the actual storage and not just the pointer (verify)
model_out%time       = model_in%time
model_out%model_size = model_in%model_size

do i = 1, model_in%model_size
   model_out%state_vector(i) = model_in%state_vector(i)
end do

end subroutine copy_assim_model





subroutine interpolate(x, location, loctype, obs_vals, istatus)
!---------------------------------------------------------------------
!
! Interpolates from the state vector in an assim_model_type to the
! location. Will need to be generalized for more complex state vector
! types. It might be better to be passing an assim_model_type with
! the associated time through here, but that requires changing the
! entire observation side of the class tree. Reconsider this at a 
! later date (JLA, 15 July, 2002). loctype for now is an integer that
! specifies what sort of variable from the model should be interpolated.

implicit none

real(r8),            intent(in) :: x(:)
type(location_type), intent(in) :: location
integer,             intent(in) :: loctype
real(r8),           intent(out) :: obs_vals
integer,            intent(out) :: istatus 

istatus = 0

call model_interpolate(x, location, loctype, obs_vals, istatus)

end subroutine interpolate



subroutine set_model_time(assim_model, time)
!-----------------------------------------------------------------------
!
! Sets the time in an assim_model type

implicit none

type(assim_model_type), intent(inout) :: assim_model
type(time_type),        intent(in)    :: time

assim_model%time = time

end subroutine set_model_time



subroutine set_model_state_vector(assim_model, state)
!-----------------------------------------------------------------------
!
! Sets the state vector part of an assim_model_type

implicit none

type(assim_model_type), intent(inout) :: assim_model
real(r8),               intent(in)    :: state(:)

character(len=129) :: errstring

! Check the size for now
if(size(state) /= get_model_size()) then
   write(errstring,*)'state vector has length ',size(state), &
                     ' model size (',get_model_size(),') does not match.'
   call error_handler(E_ERR,'set_model_state_vector', errstring, source, revision, revdate)
endif

assim_model%state_vector = state

end subroutine set_model_state_vector



subroutine write_state_restart(assim_model, funit, target_time)
!----------------------------------------------------------------------
!
! Write a restart file given a model extended state and a unit number 
! opened to the restart file. (Need to reconsider what is passed to 
! identify file or if file can even be opened within this routine).

implicit none

type (assim_model_type), intent(in)           :: assim_model
integer,                 intent(in)           :: funit
type(time_type), intent(in), optional         :: target_time

if(present(target_time)) then
   call awrite_state_restart(assim_model%time, assim_model%state_vector, funit, target_time)
else
   call awrite_state_restart(assim_model%time, assim_model%state_vector, funit)
endif

end subroutine write_state_restart




subroutine awrite_state_restart(model_time, model_state, funit, target_time)
!----------------------------------------------------------------------
!
! Write a restart file given a model extended state and a unit number 
! opened to the restart file. (Need to reconsider what is passed to 
! identify file or if file can even be opened within this routine).

implicit none

type(time_type), intent(in)                   :: model_time
real(r8), intent(in)                          :: model_state(:)
integer,                 intent(in)           :: funit
type(time_type), intent(in), optional         :: target_time

! Write the state vector
SELECT CASE (write_format)
   CASE ("unf","UNF","unformatted","UNFORMATTED")
      if(present(target_time)) call write_time(funit, target_time, "unformatted")
      call write_time(funit, model_time, "unformatted")
      write(funit) model_state
   CASE DEFAULT
      if(present(target_time)) call write_time(funit, target_time)
      call write_time(funit, model_time)
      write(funit, *) model_state
END SELECT  

end subroutine awrite_state_restart



subroutine read_state_restart(assim_model, funit, target_time)
!----------------------------------------------------------------------
!
! Read a restart file given a unit number (see write_state_restart)

implicit none

type(assim_model_type), intent(out)          :: assim_model
integer,                intent(in)           :: funit
type(time_type), intent(out), optional       :: target_time

if(present(target_time)) then
   call aread_state_restart(assim_model%time, assim_model%state_vector, funit, target_time)
else
   call aread_state_restart(assim_model%time, assim_model%state_vector, funit)
endif

end subroutine read_state_restart




subroutine aread_state_restart(model_time, model_state, funit, target_time)
!----------------------------------------------------------------------
!
! Read a restart file given a unit number (see write_state_restart)

implicit none

type(time_type), intent(out)                 :: model_time
real(r8), intent(out)                        :: model_state(:)
integer,                intent(in)           :: funit
type(time_type), intent(out), optional       :: target_time

print *,'assim_model_mod:aread_state_restart ... reading from unit',funit

! Read the time
! Read the state vector

SELECT CASE (read_format)
   CASE ("unf","UNF","unformatted","UNFORMATTED")
      if(present(target_time)) target_time = read_time(funit, form = "unformatted")
      model_time = read_time(funit, form = "unformatted")
      read(funit) model_state
   CASE DEFAULT
      if(present(target_time)) target_time = read_time(funit)
      model_time = read_time(funit)
      read(funit, *) model_state
END SELECT  

end subroutine aread_state_restart



function open_restart_write(file_name)
!----------------------------------------------------------------------
!
! Opens a restart file for writing

character(len = *), intent(in) :: file_name
integer :: open_restart_write

open_restart_write = get_unit()
write(*, *) 'the format for ouput writing is ', write_format
open(unit = open_restart_write, file = file_name, form = write_format)

end function open_restart_write


function open_restart_read(file_name)
!----------------------------------------------------------------------
!
! Opens a restart file for reading

character(len = *), intent(in) :: file_name
integer :: open_restart_read

open_restart_read = get_unit()
open(unit = open_restart_read, file = file_name, form = read_format)

end function open_restart_read



subroutine close_restart(file_unit)
!----------------------------------------------------------------------
!
! Closes a restart file
integer, intent(in) :: file_unit

call close_file(file_unit)

end subroutine close_restart






subroutine output_diagnostics(ncFileID, state, copy_index)
!-------------------------------------------------------------------
! Outputs the "state" to the supplied netCDF file. 
!
! the time, and an optional index saying which
! copy of the metadata this state is associated with.
!
! ncFileID       the netCDF file identifier
! state          the copy of the state vector
! copy_index     which copy of the state vector (ensemble member ID)
!
! TJH 28 Aug 2002 original netCDF implementation 
! TJH  7 Feb 2003 [created time_manager_mod:nc_get_tindex] 
!     substantially modified to handle time in a much better manner
! TJH 24 Jun 2003 made model_mod do all the netCDF writing.
!                 Still need an error handler for nc_write_model_vars
!
! Note -- ncFileId may be modified -- the time mirror needs to
! track the state of the netCDF file. This must be "inout".

implicit none

type(netcdf_file_type), intent(inout) :: ncFileID
type(assim_model_type), intent(in) :: state
integer, optional,      intent(in) :: copy_index

if(present(copy_index)) then
   call aoutput_diagnostics(ncFileID, state%time, state%state_vector, copy_index)
else
   call aoutput_diagnostics(ncFileID, state%time, state%state_vector)
endif

end subroutine output_diagnostics




subroutine aoutput_diagnostics(ncFileID, model_time, model_state, copy_index)
!-------------------------------------------------------------------
! Outputs the "state" to the supplied netCDF file. 
!
! the time, and an optional index saying which
! copy of the metadata this state is associated with.
!
! ncFileID       the netCDF file identifier
! model_time     the time associated with the state vector
! model_state    the copy of the state vector
! copy_index     which copy of the state vector (ensemble member ID)
!
! TJH 28 Aug 2002 original netCDF implementation 
! TJH  7 Feb 2003 [created time_manager_mod:nc_get_tindex] 
!     substantially modified to handle time in a much better manner
! TJH 24 Jun 2003 made model_mod do all the netCDF writing.
!                 Still need an error handler for nc_write_model_vars
!      
! Note -- ncFileId may be modified -- the time mirror needs to
! track the state of the netCDF file. This must be "inout".

use typeSizes
use netcdf
implicit none

type(netcdf_file_type), intent(inout) :: ncFileID
type(time_type),   intent(in) :: model_time
real(r8),          intent(in) :: model_state(:)
integer, optional, intent(in) :: copy_index

integer :: i, timeindex, copyindex

character(len=129) :: errstring
integer :: is1,id1

if (.not. present(copy_index) ) then     ! we are dependent on the fact
   copyindex = 1                         ! there is a copyindex == 1
else                                     ! if the optional argument is
   copyindex = copy_index                ! not specified, we'd better
endif                                    ! have a backup plan

timeindex = nc_get_tindex(ncFileID, model_time)
if ( timeindex < 0 ) then
   call get_time(model_time,is1,id1)
   write(errstring,*)'model time (d,s)',id1,is1,' not in ',ncFileID%fname
   write(errstring,'(''model time (d,s) ('',i5,i5,'') is index '',i6, '' in ncFileID '',i3)') &
          id1,is1,timeindex,ncFileID%ncid
   call error_handler(E_ERR,'aoutput_diagnostics', errstring, source, revision, revdate)
endif

call get_time(model_time,is1,id1)
write(errstring,'(''model time (d,s) ('',i5,i5,'') is index '',i6, '' in ncFileID '',i3)') &
     id1,is1,timeindex,ncFileID%ncid
call error_handler(E_DBG,'aoutput_diagnostics', errstring, source, revision, revdate)

! model_mod:nc_write_model_vars knows nothing about assim_model_types,
! so we must pass the components.

i = nc_write_model_vars(ncFileID%ncid, model_state, copyindex, timeindex) 

end subroutine aoutput_diagnostics




subroutine input_diagnostics(file_id, state, copy_index)
!------------------------------------------------------------------
!
! Reads in diagnostic state output from file_id for copy_index
! copy. Need to make this all more rigorously enforced.

implicit none

integer,                intent(in)    :: file_id
! MAYBE SHOULDN'T use assim model type here, but just state and time ?
type(assim_model_type), intent(inout) :: state
integer,                intent(out)   :: copy_index

call ainput_diagnostics(file_id, state%time, state%state_vector, copy_index)

end subroutine input_diagnostics



subroutine ainput_diagnostics(file_id, model_time, model_state, copy_index)
!------------------------------------------------------------------
!
! Reads in diagnostic state output from file_id for copy_index
! copy. Need to make this all more rigorously enforced.

implicit none

integer,         intent(in)    :: file_id
type(time_type), intent(inout) :: model_time
real(r8),        intent(inout) :: model_state(:)
integer,         intent(out)   :: copy_index

character(len=5)   :: header
character(len=129) :: errstring

! Read in the time
model_time = read_time(file_id)

! Read in the copy index
read(file_id, *) header
if(header /= 'fcopy')  then
   write(errstring,*)'expected "copy", got ',header
   call error_handler(E_ERR,'ainput_diagnostics', errstring, source, revision, revdate)
endif

read(file_id, *) copy_index

! Read in the state vector
read(file_id, *) model_state

end subroutine ainput_diagnostics




subroutine end_assim_model()
!--------------------------------------------------------------------
!
! Closes down assim_model; nothing to do for L96

implicit none

call end_model()

end subroutine end_assim_model



function get_model_state_vector(assim_model)
!--------------------------------------------------------------------
!
! Returns the state vector component of an assim_model extended state.

real(r8) :: get_model_state_vector(model_size)
type(assim_model_type), intent(in) :: assim_model

get_model_state_vector = assim_model%state_vector

end function get_model_state_vector




function nc_append_time(ncFileID, time) result(lngth)
!------------------------------------------------------------------------
! The current time is appended to the "time" coordinate variable.
! The new length of the "time" variable is returned.
! 
! This REQUIRES that "time" is a coordinate variable AND it is the
! unlimited dimension. If not ... bad things happen.
!
! TJH Wed Aug 28 15:40:25 MDT 2002

use typeSizes
use netcdf
implicit none

type(netcdf_file_type), intent(inout) :: ncFileID
type(time_type), intent(in) :: time
integer                     :: lngth

integer  :: nDimensions, nVariables, nAttributes, unlimitedDimID
integer  :: TimeVarID
integer  :: secs, days, ncid
real(r8) :: r8time         ! gets promoted to nf90_double ...

character(len=NF90_MAX_NAME)          :: varname
integer                               :: xtype, ndims, nAtts
integer, dimension(NF90_MAX_VAR_DIMS) :: dimids
character(len=129)                    :: msgstring

type(time_type), allocatable, dimension(:) :: temptime    ! only to reallocate mirror
real(r8),        allocatable, dimension(:) :: tempR8time  ! only to reallocate mirror

lngth = -1 ! assume a bad termination

ncid = ncFileID%ncid

call check(NF90_Inquire(ncid, nDimensions, nVariables, nAttributes, unlimitedDimID))
call check(NF90_Inq_Varid(ncid, "time", TimeVarID))
call check(NF90_Inquire_Variable(ncid, TimeVarID, varname, xtype, ndims, dimids, nAtts))

if ( ndims /= 1 ) call error_handler(E_ERR,'nc_append_time', &
           '"time" expected to be rank-1',source,revision,revdate)

if ( dimids(1) /= unlimitedDimID ) call error_handler(E_ERR,'nc_append_time', &
           'unlimited dimension expected to be slowest-moving',source,revision,revdate)

! make sure the mirror and the netcdf file are in sync
call check(NF90_Inquire_Dimension(ncid, unlimitedDimID, varname, lngth ))

if (lngth /= ncFileId%Ntimes) call error_handler(E_ERR,'nc_append_time', &
           'time mirror and netcdf file time dimension out-of-sync',source,revision,revdate)

! make sure the time mirror can handle another entry.
if ( lngth == ncFileID%NtimesMAX ) then   

   write(msgstring,*)'doubling mirror length of ',lngth,' of ',ncFileID%fname
   call error_handler(E_DBG,'nc_append_time',msgstring,source,revision,revdate)

   allocate(temptime(ncFileID%NtimesMAX), tempR8time(ncFileID%NtimesMAX)) 
   temptime   = ncFileID%times             ! preserve
   tempR8time = ncFileID%rtimes            ! preserve

   deallocate(ncFileID%times, ncFileID%rtimes)

   ncFileID%NtimesMAX = 2 * ncFileID%NtimesMAX  ! double length of exising arrays

   allocate(ncFileID%times(ncFileID%NtimesMAX), ncFileID%rtimes(ncFileID%NtimesMAX) )

   ncFileID%times(1:lngth)  = temptime     ! reinstate
   ncFileID%rtimes(1:lngth) = tempR8time   ! reinstate

endif

call get_time(time, secs, days)    ! get time components to append
r8time = days + secs/86400.0_r8    ! time base is "days since ..."
lngth           = lngth + 1        ! index of new time 
ncFileID%Ntimes = lngth            ! new working length of time mirror

call check(nf90_put_var(ncid, TimeVarID, r8time, start=(/ lngth /) ))

ncFileID%times( lngth) = time
ncFileID%rtimes(lngth) = r8time

write(msgstring,*)'ncFileID (',ncid,') : ',trim(adjustl(varname)), &
         ' (should be "time") has length ',lngth, ' appending t= ',r8time
call error_handler(E_DBG,'nc_append_time',msgstring,source,revision,revdate)

contains

  ! Internal subroutine - checks error status after each netcdf, prints
  !                       text message each time an error code is returned.
  subroutine check(status)
    integer, intent ( in) :: status
    if(status /= nf90_noerr) call error_handler(E_ERR,'nc_append_time', &
        trim(nf90_strerror(status)), source,revision,revdate)
  end subroutine check

end function nc_append_time



function nc_get_tindex(ncFileID, statetime) result(timeindex)
!------------------------------------------------------------------------
! 
! We need to compare the time of the current assim_model to the 
! netcdf time coordinate variable (the unlimited dimension).
! If they are the same, no problem ...
! If it is earlier, we need to find the right index and insert ...
! If it is the "future", we need to add another one ...
! If it is in the past but does not match any we have, we're in trouble.
! The new length of the "time" variable is returned.
! 
! This REQUIRES that "time" is a coordinate variable AND it is the
! unlimited dimension. If not ... bad things happen.
!
! TJH  7 Feb 2003
!
! Revision by TJH 24 Nov 2003:
! A new array "times" has been added to mirror the times that are stored
! in the netcdf time coordinate variable. While somewhat unpleasant, it
! is SUBSTANTIALLY faster than reading the netcdf time variable at every
! turn -- which caused a geometric or exponential increase in overall 
! netcdf I/O. (i.e. this was really bad)
!
! The time mirror is maintained as a time_type, so the comparison with
! the state time uses the operators for the time_type. The netCDF file,
! however, has time units of a different convention. The times are
! converted only when appending to the time coordinate variable.    
!
! Revision by TJH 4 June 2004:
! Implementing a "file type" for output that contains a unique time
! mirror for each file.

use typeSizes
use netcdf

implicit none

type(netcdf_file_type), intent(inout) :: ncFileID
type(time_type), intent(in) :: statetime
integer                     :: timeindex

integer  :: nDimensions, nVariables, nAttributes, unlimitedDimID, TimeVarID
integer  :: xtype, ndims, nAtts, nTlen
character(len=NF90_MAX_NAME)          :: varname
integer, dimension(NF90_MAX_VAR_DIMS) :: dimids

integer         :: i
integer         :: secs, days, ncid
real(r8)        :: r8time          ! same as "statetime", different base
character(len=129) :: msgstring

timeindex = -1  ! assume bad things are going to happen

ncid = ncFileID%ncid

! Make sure we're looking at the most current version of the netCDF file.
! Get the length of the (unlimited) Time Dimension 
! If there is no length -- simply append a time to the dimension and return ...
! Else   get the existing times ["days since ..."] and convert to time_type 
!        if the statetime < earliest netcdf time ... we're in trouble
!        if the statetime does not match any netcdf time ... we're in trouble
!        if the statetime > last netcdf time ... append a time ... 

call check(NF90_Sync(ncid))    
call check(NF90_Inquire(ncid, nDimensions, nVariables, nAttributes, unlimitedDimID))
call check(NF90_Inq_Varid(ncid, "time", TimeVarID))
call check(NF90_Inquire_Variable(ncid, TimeVarID, varname, xtype, ndims, dimids, nAtts))
call check(NF90_Inquire_Dimension(ncid, unlimitedDimID, varname, nTlen))

! Sanity check all cases first.

if ( ndims /= 1 ) then
   write(msgstring,*)'"time" expected to be rank-1' 
   call error_handler(E_WARN,'nc_get_tindex',msgstring,source,revision,revdate)
   timeindex = timeindex -   1
endif
if ( dimids(1) /= unlimitedDimID ) then
   write(msgstring,*)'"time" must be the unlimited dimension'
   call error_handler(E_WARN,'nc_get_tindex',msgstring,source,revision,revdate)
   timeindex = timeindex -  10
endif
if ( timeindex < -1 ) then
   write(msgstring,*)'trouble deep ... can go no farther. Stopping.'
   call error_handler(E_ERR,'nc_get_tindex',msgstring,source,revision,revdate)
endif

! convert statetime to time base of "days since ..."
call get_time(statetime, secs, days)
r8time = days + secs/(60*60*24.0_r8)   ! netCDF timebase ... what about calendar?!
                                       ! does get_time handle that?


if (ncFileID%Ntimes < 1) then          ! First attempt at writing a state ...

   write(msgstring,*)'current unlimited  dimension length',nTlen, &
                     'for ncFileID ',trim(ncFileID%fname)
   call error_handler(E_DBG,'nc_get_tindex',msgstring,source,revision,revdate)
   write(msgstring,*)'current time array dimension length',ncFileID%Ntimes
   call error_handler(E_DBG,'nc_get_tindex',msgstring,source,revision,revdate)

   nTlen = nc_append_time(ncFileID, statetime)

   write(msgstring,*)'Initial time array dimension length',ncFileID%Ntimes
   call error_handler(E_DBG,'nc_get_tindex',msgstring,source,revision,revdate)

endif



TimeLoop : do i = 1,ncFileId%Ntimes

   if ( statetime == ncFileID%times(i) ) then
      timeindex = i
      exit TimeLoop
   endif

enddo TimeLoop



if ( timeindex <= 0 ) then   ! There was no match. Either the model
                             ! time preceeds the earliest file time - or - 
                             ! model time is somewhere in the middle  - or - 
                             ! model time needs to be appended.

   if (statetime < ncFileID%times(1) ) then

      call error_handler(E_MSG,'nc_get_tindex', &
              'Model time preceeds earliest netCDF time.', source,revision,revdate)

      write(msgstring,*)'          model time (days, seconds) ',days,secs
      call error_handler(E_MSG,'nc_get_tindex',msgstring,source,revision,revdate)

      call get_time(ncFileID%times(1),secs,days)
      write(msgstring,*)'earliest netCDF time (days, seconds) ',days,secs
      call error_handler(E_MSG,'nc_get_tindex',msgstring,source,revision,revdate)

      call error_handler(E_ERR,'nc_get_tindex', &
              'Model time preceeds earliest netCDF time.', source,revision,revdate)
      timeindex = -2

   else if ( statetime < ncFileID%times(ncFileID%Ntimes) ) then  

      ! It is somewhere in the middle without actually matching an existing time.
      ! This is very bad.

      write(msgstring,*)'model time does not match any netCDF time.'
      call error_handler(E_MSG,'nc_get_tindex',msgstring,source,revision,revdate)
      write(msgstring,*)'model time (days, seconds) is ',days,secs
      call error_handler(E_MSG,'nc_get_tindex',msgstring,source,revision,revdate)

      BadLoop : do i = 1,ncFileId%Ntimes   ! just find times to print before exiting

         if ( ncFileId%times(i) > statetime ) then
            call get_time(ncFileID%times(i-1),secs,days)
            write(msgstring,*)'preceeding netCDF time (days, seconds) ',days,secs
            call error_handler(E_MSG,'nc_get_tindex',msgstring,source,revision,revdate)

            call get_time(ncFileID%times(i),secs,days)
            write(msgstring,*)'subsequent netCDF time (days, seconds) ',days,secs
            call error_handler(E_ERR,'nc_get_tindex',msgstring,source,revision,revdate)
            timeindex = -3
            exit BadLoop
         endif

      enddo BadLoop

   else ! we must need to append ... 

      timeindex = nc_append_time(ncFileID, statetime)

      write(msgstring,'(''appending model time (d,s) ('',i5,i5,'') as index '',i6, '' in ncFileID '',i3)') &
          days,secs,timeindex,ncid
      call error_handler(E_DBG,'nc_get_tindex',msgstring,source,revision,revdate)

   endif
   
endif

contains

  ! Internal subroutine - checks error status after each netcdf, prints
  !                       text message each time an error code is returned.
  subroutine check(status)
    integer, intent ( in) :: status
    if(status /= nf90_noerr) call error_handler(E_ERR,'nc_get_tindex',&
      trim(nf90_strerror(status)), source,revision,revdate)
  end subroutine check

end function nc_get_tindex



function nc_write_calendar_atts(ncFileID, TimeVarID) result(ierr)
!------------------------------------------------------------------------
!
! Need this to follow conventions for netCDF output files.

use typeSizes
use netcdf

implicit none

type(netcdf_file_type), intent(in) :: ncFileID
integer,                intent(in) :: TimeVarID
integer                            :: ierr

integer  :: unlimitedDimID
integer  :: ncid, length
character(len=NF90_MAX_NAME) :: varname

ierr = 0

ncid = ncFileID%ncid

!call check(NF90_Sync(ncid))    
!call check(NF90_Inquire_Dimension(ncid, unlimitedDimID, varname, length))
!
!if ( TimeVarID /= unlimitedDimID ) then
!   call error_handler(E_ERR,'nc_write_calendar_atts',&
!      'unlimited dimension is not time', source,revision,revdate)
!endif

call check(nf90_put_att(ncid, TimeVarID, "long_name", "time"))
call check(nf90_put_att(ncid, TimeVarID, "axis", "T"))
call check(nf90_put_att(ncid, TimeVarID, "cartesian_axis", "T"))

select case( get_calendar_type() )
case(THIRTY_DAY_MONTHS)
!  call get_date_thirty(time, year, month, day, hour, minute, second)
case(GREGORIAN)
   call check(nf90_put_att(ncid, TimeVarID, "calendar", "gregorian" ))
   call check(nf90_put_att(ncid, TimeVarID, "units", "days since 1601-01-01 00:00:00"))
case(JULIAN)
   call check(nf90_put_att(ncid, TimeVarID, "calendar", "julian" ))
case(NOLEAP)
   call check(nf90_put_att(ncid, TimeVarID, "calendar", "no_leap" ))
case default
   call check(nf90_put_att(ncid, TimeVarID, "calendar", "no calendar" ))
   call check(nf90_put_att(ncid, TimeVarID, "units", "days since 0000-00-00 00:00:00"))
end select

contains

  ! Internal subroutine - checks error status after each netcdf, prints
  !                       text message each time an error code is returned.
  subroutine check(status)
    integer, intent ( in) :: status
    if(status /= nf90_noerr) call error_handler(E_ERR,'nc_write_calendar_atts', &
         trim(nf90_strerror(status)), source,revision,revdate )
  end subroutine check

end function nc_write_calendar_atts


!
!===================================================================
! End of assim_model_mod
!===================================================================
!
end module assim_model_mod

! DART software - Copyright 2004 - 2013 UCAR. This open source software is
! by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download


! BEGIN DART PREPROCESS KIND LIST
! MOPITT_CO_RETRIEVAL, KIND_CO
! IASI_CO_RETRIEVAL, KIND_CO
! GEO_CO_ASI, KIND_CO
! GEO_CO_NAM, KIND_CO
! GEO_CO_EUR, KIND_CO
! END DART PREPROCESS KIND LIST

! BEGIN DART PREPROCESS USE OF SPECIAL OBS_DEF MODULE
!   use obs_def_mopitt_mod, only : write_mopitt_co, read_mopitt_co, &
!                                  interactive_mopitt_co, get_expected_mopitt_co, &
!                                  set_obs_def_mopitt_co, get_expected_iasi_co
! END DART PREPROCESS USE OF SPECIAL OBS_DEF MODULE

! BEGIN DART PREPROCESS GET_EXPECTED_OBS_FROM_DEF
!         case(MOPITT_CO_RETRIEVAL)                                                           
!            call get_expected_mopitt_co(state, location, obs_def%key, obs_val, istatus) 
!         case(IASI_CO_RETRIEVAL) 
!            call get_expected_iasi_co(state, location, obs_def%key, obs_val, istatus)
!         case(GEO_CO_ASI) 
!            call get_expected_mopitt_co(state, location, obs_def%key, obs_val, istatus)
!         case(GEO_CO_NAM) 
!            call get_expected_mopitt_co(state, location, obs_def%key, obs_val, istatus)
!         case(GEO_CO_EUR) 
!            call get_expected_mopitt_co(state, location, obs_def%key, obs_val, istatus)
! END DART PREPROCESS GET_EXPECTED_OBS_FROM_DEF

! BEGIN DART PREPROCESS READ_OBS_DEF
!      case(MOPITT_CO_RETRIEVAL, IASI_CO_RETRIEVAL, GEO_CO_ASI, GEO_CO_NAM, GEO_CO_EUR)
!         call read_mopitt_co(obs_def%key, ifile, fileformat)
! END DART PREPROCESS READ_OBS_DEF

! BEGIN DART PREPROCESS WRITE_OBS_DEF
!      case(MOPITT_CO_RETRIEVAL, IASI_CO_RETRIEVAL, GEO_CO_ASI, GEO_CO_NAM, GEO_CO_EUR)
!         call write_mopitt_co(obs_def%key, ifile, fileformat)
! END DART PREPROCESS WRITE_OBS_DEF

! BEGIN DART PREPROCESS INTERACTIVE_OBS_DEF
!      case(MOPITT_CO_RETRIEVAL, IASI_CO_RETRIEVAL, GEO_CO_ASI, GEO_CO_NAM, GEO_CO_EUR)
!         call interactive_mopitt_co(obs_def%key)
! END DART PREPROCESS INTERACTIVE_OBS_DEF

! BEGIN DART PREPROCESS SET_OBS_DEF_MOPITT_CO
!      case(MOPITT_CO_RETRIEVAL, IASI_CO_RETRIEVAL, GEO_CO_ASI, GEO_CO_NAM, GEO_CO_EUR)
!         call set_obs_def_mopitt_co(obs_def%key)
! END DART PREPROCESS SET_OBS_DEF_MOPITT_CO


! BEGIN DART PREPROCESS MODULE CODE

module obs_def_mopitt_mod

use typeSizes
use        types_mod, only : r8, MISSING_R8
use    utilities_mod, only : register_module, error_handler, E_ERR, E_MSG
use     location_mod, only : location_type, set_location, get_location, &
                             VERTISPRESSURE, VERTISLEVEL, VERTISSURFACE
use  assim_model_mod, only : interpolate
use     obs_kind_mod, only : KIND_CO, KIND_PRESSURE, KIND_SURFACE_PRESSURE

implicit none

public :: write_mopitt_co, read_mopitt_co, interactive_mopitt_co, &
          get_expected_mopitt_co, get_expected_iasi_co, set_obs_def_mopitt_co

! Storage for the special information required for observations of this type
integer, parameter               :: max_mopitt_co_obs = 10000000
integer, parameter               :: mopitt_dim = 10
integer, parameter               :: max_model_levs = 100
integer                          :: num_mopitt_co_obs = 0
! KDR replace 10 with mopitt_dim?
! real(r8), dimension(max_mopitt_co_obs,10) :: avg_kernel
real(r8), dimension(max_mopitt_co_obs,mopitt_dim) :: avg_kernel
real(r8) :: mopitt_pressure(mopitt_dim) = &
            (/ 95000.,90000.,80000.,70000.,60000.,50000.,40000.,30000.,20000.,10000. /)
real(r8), dimension(max_mopitt_co_obs) :: mopitt_prior
real(r8), dimension(max_mopitt_co_obs) :: mopitt_psurf
integer,  dimension(max_mopitt_co_obs) :: mopitt_nlevels

! For now, read in all info on first read call, write all info on first write call
logical :: already_read = .false., already_written = .false.

! version controlled file description for error handling, do not edit
character(len=*), parameter :: source   = 'obs_def_NADIR_CO_mod.f90'
character(len=*), parameter :: revision = ''
character(len=*), parameter :: revdate  = ''

logical, save :: module_initialized = .false.
integer  :: counts1 = 0

contains


!-------------------------------------------------------------------------------
!>

subroutine initialize_module

call register_module(source, revision, revdate)
module_initialized = .true.

end subroutine initialize_module


!-------------------------------------------------------------------------------
!>

subroutine read_mopitt_co(key, ifile, fform)

integer,          intent(out)          :: key
integer,          intent(in)           :: ifile
character(len=*), intent(in), optional :: fform
character(len=32) :: fileformat

integer  :: mopitt_nlevels_1
real(r8) :: mopitt_prior_1
real(r8) :: mopitt_psurf_1
real(r8) :: avg_kernels_1(mopitt_dim)
integer  :: keyin

if ( .not. module_initialized ) call initialize_module

fileformat = "ascii"   ! supply default
if(present(fform)) fileformat = trim(adjustl(fform))

! Philosophy, read ALL information about this special obs_type at once???
! For now, this means you can only read ONCE (that's all we're doing 3 June 05)
! Toggle the flag to control this reading

avg_kernels_1(:) = 0.0_r8

SELECT CASE (fileformat)

   CASE ("unf", "UNF", "unformatted", "UNFORMATTED")
   mopitt_nlevels_1 = read_mopitt_nlevels(ifile, fileformat)
   mopitt_prior_1   = read_mopitt_prior(  ifile, fileformat)
   mopitt_psurf_1   = read_mopitt_psurf(  ifile, fileformat)
   avg_kernels_1(1:mopitt_nlevels_1) = read_mopitt_avg_kernels(ifile, mopitt_nlevels_1, fileformat)
   read(ifile) keyin

   CASE DEFAULT
   mopitt_nlevels_1 = read_mopitt_nlevels(ifile, fileformat)
   mopitt_prior_1   = read_mopitt_prior(  ifile, fileformat)
   mopitt_psurf_1   = read_mopitt_psurf(  ifile, fileformat)
   avg_kernels_1(1:mopitt_nlevels_1) = read_mopitt_avg_kernels(ifile, mopitt_nlevels_1, fileformat)
   read(ifile, *) keyin
END SELECT

counts1 = counts1 + 1
key = counts1
call set_obs_def_mopitt_co(key, avg_kernels_1, mopitt_prior_1, mopitt_psurf_1, &
                           mopitt_nlevels_1)

end subroutine read_mopitt_co


!-------------------------------------------------------------------------------
!>

subroutine write_mopitt_co(key, ifile, fform)

integer,          intent(in)           :: key
integer,          intent(in)           :: ifile
character(len=*), intent(in), optional :: fform

character(len=32) :: fileformat
real(r8) :: avg_kernels_temp(mopitt_dim)

if ( .not. module_initialized ) call initialize_module

fileformat = "ascii"   ! supply default
if(present(fform)) fileformat = trim(adjustl(fform))

! Philosophy, read ALL information about this special obs_type at once???
! For now, this means you can only read ONCE (that's all we're doing 3 June 05)
! Toggle the flag to control this reading
   
avg_kernels_temp=avg_kernel(key,:)

SELECT CASE (fileformat)
   
   CASE ("unf", "UNF", "unformatted", "UNFORMATTED")
   call write_mopitt_nlevels(ifile, mopitt_nlevels(key), fileformat)
   call write_mopitt_prior(ifile, mopitt_prior(key), fileformat)
   call write_mopitt_psurf(ifile, mopitt_psurf(key), fileformat)
   call write_mopitt_avg_kernels(ifile, avg_kernels_temp, mopitt_nlevels(key), fileformat)
   write(ifile) key

   CASE DEFAULT
   call write_mopitt_nlevels(ifile, mopitt_nlevels(key), fileformat)
   call write_mopitt_prior(ifile, mopitt_prior(key), fileformat)
   call write_mopitt_psurf(ifile, mopitt_psurf(key), fileformat)
   call write_mopitt_avg_kernels(ifile, avg_kernels_temp, mopitt_nlevels(key), fileformat)
   write(ifile, *) key
END SELECT 

end subroutine write_mopitt_co


!-------------------------------------------------------------------------------
!> Initializes the specialized part of a MOPITT observation
!> Passes back up the key for this one

subroutine interactive_mopitt_co(key)

integer, intent(out) :: key

character(len=129) :: msgstring

if ( .not. module_initialized ) call initialize_module

! Make sure there's enough space, if not die for now (clean later)
if(num_mopitt_co_obs >= max_mopitt_co_obs) then
   ! PUT IN ERROR HANDLER CALL
   write(msgstring, *)'Not enough space for a mopitt CO obs.'
   call error_handler(E_MSG,'interactive_mopitt_co',msgstring,source,revision,revdate)
   write(msgstring, *)'Can only have max_mopitt_co_obs (currently ',max_mopitt_co_obs,')'
   call error_handler(E_ERR,'interactive_mopitt_co',msgstring,source,revision,revdate)
endif

! Increment the index
num_mopitt_co_obs = num_mopitt_co_obs + 1
key = num_mopitt_co_obs

! Otherwise, prompt for input for the three required beasts
write(*, *) 'Creating an interactive_mopitt_co observation'
write(*, *) 'Input the MOPITT Prior '
read(*, *) mopitt_prior(key)
write(*, *) 'Input MOPITT Surface Pressure '
read(*, *) mopitt_psurf(key)
write(*, *) 'Input the 10 Averaging Kernel Weights '
read(*, *) avg_kernel(key,:)

end subroutine interactive_mopitt_co


!-------------------------------------------------------------------------------
!>

subroutine get_expected_iasi_co(state, location, key, val, istatus)

real(r8),            intent(in)  :: state(:)
type(location_type), intent(in)  :: location
integer,             intent(in)  :: key
real(r8),            intent(out) :: val
integer,             intent(out) :: istatus

integer :: i,j
integer :: num_levs, lev
type(location_type) :: loc3,locS
real(r8)            :: mloc(3)
real(r8)            :: obs_val, obs_val_int
real(r8)            :: top_pres, bot_pres, coef, mop_layer_wght
real(r8)            :: i_top_pres, i_bot_pres
real(r8)            :: p_col(max_model_levs)
real(r8)            :: mopitt_pres_local(mopitt_dim)
integer             :: nlevels, start_i, end_i

if ( .not. module_initialized ) call initialize_module
val = 0.0_r8

mloc = get_location(location)
if (mloc(2)>90.0_r8) then
    mloc(2)=90.0_r8
elseif (mloc(2)<-90.0_r8) then
    mloc(2)=-90.0_r8
endif

mopitt_pres_local = mopitt_pressure

nlevels = mopitt_nlevels(key)
! Modify AFAJ (072513)
start_i = mopitt_dim-nlevels+1
!mopitt_pres_local(start_i)=mopitt_psurf(key)
! KDR Redefining one element of a global array probably wasn't a good idea.
end_i = mopitt_dim

! Find the number of model levels and the pressures on them.
istatus = 0
p_col = MISSING_R8
lev = 1
model_levels: do
   locS = set_location(mloc(1),mloc(2),real(lev,r8),VERTISLEVEL)
   call interpolate(state, locS, KIND_PRESSURE, p_col(lev), istatus)
   if (istatus /= 0) then
      p_col(lev) = MISSING_R8
      num_levs = lev - 1
      exit model_levels
   endif
   lev = lev + 1
enddo model_levels

! KDR: see comments in the same place in get_expected_mopitt_co.

!Barre'; here p_col is the pressure levels at the grid points, we will need to have in
!the future the pressure values at the mid-points (need to create a new function
!plevs_cam in model_mod using the the mid-levels hybrid coefs)
locS = set_location(mloc(1),mloc(2),0.0_r8,VERTISSURFACE)
call interpolate(state, locS, KIND_SURFACE_PRESSURE, p_col(num_levs), istatus)

mopitt_pres_local(1) = p_col(num_levs)
! KDR Should we really be redefining this global array element?

do i=start_i, end_i
   obs_val=0.0_r8

   bot_pres=mopitt_pres_local(i)
   if (i == mopitt_dim) then
      top_pres=mopitt_pres_local(i)/2.0_r8
   else
      top_pres=mopitt_pres_local(i+1)
   endif
!  This is used in all coefs, below.
   mop_layer_wght = 1.0_r8/abs(bot_pres-top_pres)

   do j=1,num_levs
      i_bot_pres=p_col(j)
      if (j == 1) then
         i_top_pres=0.0_r8
      else
         i_top_pres=p_col(j-1)
      endif

      coef=0.0_r8
      obs_val_int=0.0_r8
      if (bot_pres > top_pres) then
         loc3 = set_location(mloc(1),mloc(2),real(j,r8), VERTISLEVEL)
         call interpolate(state, loc3, KIND_CO, obs_val_int, istatus)
         if (istatus /= 0) then
            write(*,*) 'Interpolation failure at ',mloc(1),mloc(2),j
            return
         endif

         if (i_bot_pres <= bot_pres .and. i_bot_pres > top_pres) then
            if (i_top_pres <= top_pres) then
               coef=abs(i_bot_pres-top_pres) * mop_layer_wght
            else 
               coef=abs(i_bot_pres-i_top_pres) * mop_layer_wght
            endif
         else if (i_bot_pres > bot_pres .and. i_top_pres < bot_pres) then
            if (i_top_pres <= top_pres) then
               coef=abs(bot_pres-top_pres) * mop_layer_wght
            else 
               coef=abs(bot_pres-i_top_pres) * mop_layer_wght
            endif
         endif
      endif

      obs_val = obs_val + obs_val_int * coef
      if (coef<0 .or. coef>1) write(*,*) 'coef', coef, i, j, mloc(1),mloc(2)
      if (coef<0 .or. coef>1) write(*,*) 'pres', i_bot_pres,i_top_pres,bot_pres,top_pres
      !if (obs_val_int<0) write(*,*) 'inerp neg', obs_val_int, i, j,mloc(1),mloc(2)

   enddo
   if (obs_val > 0.0_r8) val = val + avg_kernel(key,i) * (obs_val)
enddo
val = val + mopitt_prior(key)
! KDR Should this now be MISSING_R8?
! if (val < 0.0_r8) val=-777.0_r8
if (val < 0.0_r8) then
   val=MISSING_R8
   istatus = 7
endif

end subroutine get_expected_iasi_co


!-------------------------------------------------------------------------------
!>

subroutine get_expected_mopitt_co(state, location, key, val, istatus)
real(r8),            intent(in)  :: state(:)
type(location_type), intent(in)  :: location
integer,             intent(in)  :: key
real(r8),            intent(out) :: val
integer,             intent(out) :: istatus

integer :: i,j
type(location_type) :: loc3,locS
real(r8)            :: mloc(3)
real(r8)            :: obs_val, obs_val_int
integer             :: nlevels, start_i, end_i

real(r8)            :: top_pres, bot_pres, coef, mop_layer_wght
real(r8)            :: i_top_pres, i_bot_pres
integer             :: num_levs, lev
real(r8)            :: p_col(max_model_levs)
real(r8)            :: mopitt_pres_local(mopitt_dim)

if ( .not. module_initialized ) call initialize_module
mloc = get_location(location)

! Apply MOPITT Column Averaging kernel vector a_t and MOPITT Prior xa- a_t xa
! x = a_t xm + xa- a_t xa , where x is a 10 element vector 
! xm is the 10-element partial columnis at MOPITT grid
! also here, the averaging kernel is operated in log VMR.
! i.e. the state vector CO is in log VMR 
! edit dart_to_cam and cam_to_dart for the transformation
! also, it turns our xa - a_txa is a scalar quantity  
! KDR Why not initialize to mopitt_prior(key), instead of adding it after 
!     the end of the i-loop?
val = 0.0_r8

if (mloc(2)>90.0_r8) then
    mloc(2)=90.0_r8
elseif (mloc(2)<-90.0_r8) then
    mloc(2)=-90.0_r8
endif

mopitt_pres_local = mopitt_pressure

nlevels = mopitt_nlevels(key)
! Modify AFAJ (072513)
! KDR start_i >= 1
start_i = mopitt_dim-nlevels+1
! KDR Ack! redefining one element of a global array.
!     Various elements will be redefined during various calls to this subroutine,
!     because the array is initialized in the specification statement.
mopitt_pres_local(start_i)=mopitt_psurf(key)
end_i = mopitt_dim

!JB: do partial columns aproximations
! Find the number of model levels and the pressures on them.
istatus = 0
p_col = MISSING_R8
lev = 1
model_levels: do 
   locS = set_location(mloc(1),mloc(2),real(lev,r8),VERTISLEVEL)
   call interpolate(state, locS, KIND_PRESSURE, p_col(lev), istatus)
   if (istatus /= 0) then
      p_col(lev) = MISSING_R8
      num_levs = lev - 1
      exit model_levels
   endif
   lev = lev + 1
enddo model_levels

!Barre: here p_col is the pressure levels at the grid points, we will need to have in
!the future the pressure values at the mid-points (need to create a new function
!plevs_cam in model_mod using the the mid-levels hybrid coefs)
! KDR This comment looks confused.  plevs_cam returns pressures on what CESM refers to
!     as layer midpoints.  Maybe MOPITT needs pressures on the model interfaces,
!     in which case a new subroutine using hyai and hybi would replace hyam and hybm.
!     Anyway, p_col(30) is being redefined as the CAM surface pressure,
!     but the rest of the p_col is not redefined.
!     This all may be fine, since val is an accumulation of contributions 
!     from pressure sub-layers.
locS = set_location(mloc(1),mloc(2),0.0_r8,VERTISSURFACE)
call interpolate(state, locS, KIND_SURFACE_PRESSURE, p_col(num_levs), istatus)

! KDR Ack! redefining one element of a global array.
!     This may be the 2nd redefinition of (1), or the first, if start_i /= 1.
mopitt_pres_local(1) = p_col(num_levs)

! KDR; Algorithm; 
!      Work through the MOPITT pressure level layers. (i loop)
!      Find CAM levels that are in each layer. (j loop)
!      Calculate CO from CAM state using level as the vertical location.
!      Accumulate contributions of CO from the CAM layers,
!         weighted by the the thickness of the CAM layer that lies within the MOPITT layer.
! Work through the MOPITT pressure level layers. (i loop)
! Loop from some number to 10; the mopitt pressure layers above the ground at this location.
do i=start_i, end_i
   obs_val=0.0_r8

   bot_pres=mopitt_pres_local(i)
   if (i == 10) then
      top_pres=mopitt_pres_local(i)/2.0_r8 
   else
      top_pres=mopitt_pres_local(i+1)
   endif
!  This is used in all 'coef's, below.
   mop_layer_wght = 1.0_r8/abs(bot_pres-top_pres)
   
!  KDR Search through CAM layers for the ones which overlap the current mopitt layer.
   do j=1,num_levs
      i_bot_pres=p_col(j)
      if (j == 1) then
         i_top_pres=0.0_r8
      else
         i_top_pres=p_col(j-1)
      endif

      coef=0.0_r8
      obs_val_int=0.0_r8
      if (bot_pres > top_pres) then
         loc3 = set_location(mloc(1),mloc(2),real(j,r8), VERTISLEVEL)
         call interpolate(state, loc3, KIND_CO, obs_val_int, istatus)
         if (istatus /= 0) then
             write(*,*) 'Interpolation failure at ',mloc(1),mloc(2),j
             return
         endif

         if (i_bot_pres <= bot_pres .and. i_bot_pres > top_pres) then
!           KDR CAM bottom P is bracketed by the current MOPITT pressures...
            if (i_top_pres <= top_pres) then
               coef=abs(i_bot_pres-  top_pres) * mop_layer_wght
            else
               coef=abs(i_bot_pres-i_top_pres) * mop_layer_wght
            endif
         else if (i_bot_pres > bot_pres .and. i_top_pres < bot_pres) then
!           KDR CAM pressures bracket this MOPITT bottom pressure.
            if (i_top_pres <= top_pres) then 
!              KDR Whole MOPITT layer is within CAM layer.
               coef=abs(bot_pres-  top_pres) * mop_layer_wght
            else
               coef=abs(bot_pres-i_top_pres) * mop_layer_wght
            endif
         endif
      endif

!     KDR This calc is done even if neither of the bracket if-blocks is entered.
!         It's an accumulation of pieces, most of which are 0.
      obs_val = obs_val + obs_val_int * coef

      if (coef<0 .or. coef>1) write(*,*) 'coef', coef, i, j, mloc(1),mloc(2)
      if (coef<0 .or. coef>1) write(*,*) 'pres', i_bot_pres,i_top_pres,bot_pres,top_pres
   enddo 

   !write(*,*) obs_val, log10(obs_val)
   ! KDR get_expected_iasi_co line:
   !val = val + avg_kernel(key,i) * (obs_val)
   !if (obs_val <= 0.0) then 
   !write(*,*) 'neg!', obs_val, bot_pres, i_bot_pres, i_top_pres
   !endif
   ! KDR different from get_expected_iasi_co line
   if (obs_val > 0.0_r8 .and. avg_kernel(key,i) > -700) val = val + avg_kernel(key,i) * log10(obs_val)
enddo
!val = val + 10.0_r8**mopitt_prior(key)
!write(*,*) 'xm', val 
!write(*,*) 'xa', mopitt_prior(key)
val = val + mopitt_prior(key)
!write(*,*) 'before 10^', val
val=10.0**val
!write(*,*) 'after 10^', val

! if (val < 0.0_r8) val=-777.0_r8
if (val < 0.0_r8) then
   val=MISSING_R8
   istatus = 6
endif

end subroutine get_expected_mopitt_co


!-------------------------------------------------------------------------------
!> Allows passing of obs_def special information 

subroutine set_obs_def_mopitt_co(key, co_avgker, co_prior, co_psurf, co_nlevels)

integer,  intent(in) :: key, co_nlevels
real(r8), intent(in) :: co_avgker(10)
real(r8), intent(in) :: co_prior
real(r8), intent(in) :: co_psurf

character(len=129) :: msgstring

if ( .not. module_initialized ) call initialize_module

if(num_mopitt_co_obs >= max_mopitt_co_obs) then
   ! PUT IN ERROR HANDLER CALL
   write(msgstring, *)'Not enough space for a mopitt CO obs.'
   call error_handler(E_MSG,'set_obs_def_mopitt_co',msgstring,source,revision,revdate)
   write(msgstring, *)'Can only have max_mopitt_co_obs (currently ',max_mopitt_co_obs,')'
   call error_handler(E_ERR,'set_obs_def_mopitt_co',msgstring,source,revision,revdate)
endif

avg_kernel(key,:)   = co_avgker(:)
mopitt_prior(key)   = co_prior
mopitt_psurf(key)   = co_psurf
mopitt_nlevels(key) = co_nlevels

end subroutine set_obs_def_mopitt_co


!-------------------------------------------------------------------------------
!>

function read_mopitt_prior(ifile, fform)

integer,                    intent(in) :: ifile
character(len=*), optional, intent(in) :: fform
real(r8)                               :: read_mopitt_prior

character(len=32)  :: fileformat

if ( .not. module_initialized ) call initialize_module

fileformat = "ascii"    ! supply default
if(present(fform)) fileformat = trim(adjustl(fform))

SELECT CASE (fileformat)
   CASE("unf", "UNF", "unformatted", "UNFORMATTED")
      read(ifile) read_mopitt_prior
   CASE DEFAULT
      read(ifile, *) read_mopitt_prior
END SELECT

end function read_mopitt_prior


!-------------------------------------------------------------------------------
!>

function read_mopitt_nlevels(ifile, fform)

integer,                    intent(in) :: ifile
character(len=*), optional, intent(in) :: fform
integer                                :: read_mopitt_nlevels

character(len=32)  :: fileformat

if ( .not. module_initialized ) call initialize_module

fileformat = "ascii"    ! supply default
if(present(fform)) fileformat = trim(adjustl(fform))

SELECT CASE (fileformat)
   CASE("unf", "UNF", "unformatted", "UNFORMATTED")
      read(ifile) read_mopitt_nlevels
   CASE DEFAULT
      read(ifile, *) read_mopitt_nlevels
END SELECT

end function read_mopitt_nlevels


!-------------------------------------------------------------------------------
!>

subroutine write_mopitt_prior(ifile, mopitt_prior_temp, fform)

integer,          intent(in) :: ifile
real(r8),         intent(in) :: mopitt_prior_temp
character(len=*), intent(in) :: fform

character(len=32)  :: fileformat

if ( .not. module_initialized ) call initialize_module

fileformat = trim(adjustl(fform))

SELECT CASE (fileformat)
   CASE("unf", "UNF", "unformatted", "UNFORMATTED")
      write(ifile) mopitt_prior_temp
   CASE DEFAULT
      write(ifile, *) mopitt_prior_temp
END SELECT

end subroutine write_mopitt_prior


!-------------------------------------------------------------------------------
!>

subroutine write_mopitt_nlevels(ifile, mopitt_nlevels_temp, fform)

integer,          intent(in) :: ifile
integer,          intent(in) :: mopitt_nlevels_temp
character(len=*), intent(in) :: fform

character(len=32)  :: fileformat

if ( .not. module_initialized ) call initialize_module

fileformat = trim(adjustl(fform))

SELECT CASE (fileformat)
   CASE("unf", "UNF", "unformatted", "UNFORMATTED")
      write(ifile) mopitt_nlevels_temp
   CASE DEFAULT
      write(ifile, *) mopitt_nlevels_temp
END SELECT

end subroutine write_mopitt_nlevels


!-------------------------------------------------------------------------------
!>

function read_mopitt_psurf(ifile, fform)

integer,                    intent(in) :: ifile
character(len=*), optional, intent(in) :: fform
real(r8)                               :: read_mopitt_psurf

character(len=32)  :: fileformat

if ( .not. module_initialized ) call initialize_module

fileformat = "ascii"    ! supply default
if(present(fform)) fileformat = trim(adjustl(fform))

SELECT CASE (fileformat)
   CASE("unf", "UNF", "unformatted", "UNFORMATTED")
      read(ifile) read_mopitt_psurf
   CASE DEFAULT
      read(ifile, *) read_mopitt_psurf
END SELECT

end function read_mopitt_psurf


!-------------------------------------------------------------------------------
!>

subroutine write_mopitt_psurf(ifile, mopitt_psurf_temp, fform)

integer,          intent(in) :: ifile
real(r8),         intent(in) :: mopitt_psurf_temp
character(len=*), intent(in) :: fform

character(len=32)  :: fileformat

if ( .not. module_initialized ) call initialize_module

fileformat = trim(adjustl(fform))

SELECT CASE (fileformat)
   CASE("unf", "UNF", "unformatted", "UNFORMATTED")
      write(ifile) mopitt_psurf_temp
   CASE DEFAULT
      write(ifile, *) mopitt_psurf_temp
END SELECT

end subroutine write_mopitt_psurf


!-------------------------------------------------------------------------------
!>

function read_mopitt_avg_kernels(ifile, nlevels, fform)

integer,                    intent(in) :: ifile, nlevels
character(len=*), optional, intent(in) :: fform
real(r8)                               :: read_mopitt_avg_kernels(10)

character(len=32)  :: fileformat

read_mopitt_avg_kernels(:) = 0.0_r8

if ( .not. module_initialized ) call initialize_module

fileformat = "ascii"    ! supply default
if(present(fform)) fileformat = trim(adjustl(fform))

SELECT CASE (fileformat)
   CASE("unf", "UNF", "unformatted", "UNFORMATTED")
      read(ifile) read_mopitt_avg_kernels(1:nlevels)
   CASE DEFAULT
      read(ifile, *) read_mopitt_avg_kernels(1:nlevels)
END SELECT

end function read_mopitt_avg_kernels


!-------------------------------------------------------------------------------
!>

subroutine write_mopitt_avg_kernels(ifile, avg_kernels_temp, nlevels_temp, fform)

integer,          intent(in) :: ifile, nlevels_temp
real(r8),         intent(in) :: avg_kernels_temp(10)
character(len=*), intent(in) :: fform

character(len=32)  :: fileformat

if ( .not. module_initialized ) call initialize_module

fileformat = trim(adjustl(fform))

SELECT CASE (fileformat)
   CASE("unf", "UNF", "unformatted", "UNFORMATTED")
      write(ifile) avg_kernels_temp(1:nlevels_temp)
   CASE DEFAULT
      write(ifile, *) avg_kernels_temp(1:nlevels_temp)
END SELECT

end subroutine write_mopitt_avg_kernels

!----------------------------------------------------------------------

end module obs_def_mopitt_mod

! END DART PREPROCESS MODULE CODE

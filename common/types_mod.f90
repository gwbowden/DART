! Data Assimilation Research Testbed -- DART
! Copyright 2004, Data Assimilation Initiative, University Corporation for Atmospheric Research
! Licensed under the GPL -- www.gpl.org/licenses/gpl.html

MODULE types_mod

! <next four lines automatically updated by CVS, do not edit>
! $Source$ 
! $Revision$ 
! $Date$ 
! $Author$ 

implicit none
private 

public :: r8, pi, deg2rad, rad2deg, missing_r

! CVS Generated file description for error handling, do not edit
character(len=128) :: &
source   = "$Source$", &
revision = "$Revision$", &
revdate  = "$Date$"

SAVE

!----------------------------------------------------------------------------
! Attributes for variable kinds -- no need to rely on -r8 switch in compiler
! all real variables are 64bit, ditto for all integer variables.
!----------------------------------------------------------------------------
! These are TJH's favorites
! integer, parameter :: i4 = SELECTED_INT_KIND(8)
! integer, parameter :: i8 = SELECTED_INT_KIND(17)
! integer, parameter :: r4 = SELECTED_REAL_KIND(6,30)
! integer, parameter :: c4 = SELECTED_REAL_KIND(6,30)
! integer, parameter :: r8 = SELECTED_REAL_KIND(12,100)
! integer, parameter :: c8 = SELECTED_REAL_KIND(12,100)

! These comply with the CCM4 standard, as far as I can tell.

  integer, parameter :: i4 = SELECTED_INT_KIND(8)
  integer, parameter :: i8 = SELECTED_INT_KIND(13)
  integer, parameter :: r4 = SELECTED_REAL_KIND(6,30)
  integer, parameter :: c4 = SELECTED_REAL_KIND(6,30)
  integer, parameter :: r8 = SELECTED_REAL_KIND(12)
  integer, parameter :: c8 = SELECTED_REAL_KIND(12)

!----------------------------------------------------------------------------
! Constants ... 
!----------------------------------------------------------------------------

real(kind=r8), parameter :: pi = 3.1415926535897932346_r8
real(kind=r8), parameter :: deg2rad = pi / 180.0_r8
real(kind=r8), parameter :: rad2deg = 180.0_r8 / pi

integer,       PARAMETER ::  missing   = -888888
real(kind=r8), PARAMETER ::  missing_r = -888888.0_r8

END MODULE types_mod

program simple_test_extr_frac
include 'simple_lib.f08'
use simple_decay_funs
implicit none

integer, parameter :: MAXITS = 100 ! upper iteration bound
real    :: update_frac
integer :: nsampl, i, nsampl_fromto(2), nptcls

! nptcls = 5000
! print *, calc_nsampl_fromto( nptcls )
! nptcls = 10000
! print *, calc_nsampl_fromto( nptcls )
nptcls = 36000
! print *, calc_nsampl_fromto( nptcls )
! nptcls = 80000
! print *, calc_nsampl_fromto( nptcls )
! nptcls = 200000
! print *, calc_nsampl_fromto( nptcls )
! nptcls = 1000000
! print *, calc_nsampl_fromto( nptcls )

! do i = 1,MAXITS
!     nsampl      = nsampl_decay( i, MAXITS, NPTCLS)
!     update_frac = real(nsampl) / real(NPTCLS)
!     print *, i, nsampl, update_frac
! end do


! do i = 1,MAXITS
!     print *, i, inv_cos_decay( i, maxits, [0.5,1.0] )
! end do

do i = 1,MAXITS
    nsampl      = inv_nsampl_decay( i, MAXITS, NPTCLS)
    update_frac = real(nsampl) / real(NPTCLS)
    print *, i, nsampl, update_frac
end do

end program simple_test_extr_frac

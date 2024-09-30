! fast cross-correlation calculation between Fourier volumes using defined sampling space geometries
module simple_volpft_corrcalc
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_projector, only: projector
implicit none

public :: volpft_corrcalc
private
#include "simple_local_flags.inc"

type :: volpft_corrcalc
    private
    class(projector), pointer :: vol_ref    => null()   !< pointer to reference volume
    class(projector), pointer :: vol_target => null()   !< pointer to target volume
    integer                   :: nspace          = 0    !< number of vec:s in representation
    integer                   :: nspace_nonred   = 0    !< number of non-redundant vec:s in representation
    integer                   :: kfromto_vpft(2) = 0    !< Fourier index range
    real                      :: sqsum_ref              !< memoized square sum 4 corrcalc (ref)
    complex, allocatable      :: vpft_ref_nonred(:,:)   !< reference lines 4 matching, nonredundant elements only
    real,    allocatable      :: locs_ref(:,:,:)        !< nspace x nk x 3 matrix of positions (reference)
    real,    allocatable      :: locs_ref_nonred(:,:,:) !<nspace_nonred x nk x 3 matrix of positions (reference), nonredundant elements
    logical                   :: existence = .false.    !< to indicate existence
  contains
    ! CONSTRUCTOR
    procedure          :: new
    ! GETTERS
    procedure          :: get_nspace
    procedure          :: get_nspace_nonred
    procedure          :: get_kfromto
    ! INTERPOLATION METHODS
    procedure, private :: extract_ref
    procedure, private :: extract_target_1
    procedure, private :: extract_target_2
    generic            :: extract_target => extract_target_1, extract_target_2
    ! CORRELATORS
    procedure, private :: corr_1
    procedure, private :: corr_2
    generic            :: corr => corr_1, corr_2
    ! DESTRUCTOR
    procedure          :: kill
end type volpft_corrcalc

! numerically found vector that will result in even sampling of unit sphere under i operations
real, parameter :: i_startvec(3) = (/.2259467440, .3054884673, .9249998733/)

contains

    !>  \brief  is a constructor
    subroutine new( self, vol_ref, hp, lp, alpha, vol_target )
        class(volpft_corrcalc),             intent(inout) :: self
        class(projector), target,           intent(in)    :: vol_ref
        real,                               intent(in)    :: hp, lp, alpha
        class(projector), target, optional, intent(in)    :: vol_target
        integer   :: ispace, k
        real      :: vec(3), rmat(3,3)
        type(ori) :: e
        type(sym) :: ico
        call self%kill
        if( vol_ref.eqdims.vol_target )then
            ! all good
        else
            THROW_HARD('The volumes to be matched are not of the same dimension; new_1')
        endif
        ! set pointers, we assume that the volumes have been masked and prepared
        self%vol_ref => vol_ref
        if( present(vol_target) )then
            self%vol_target => vol_target
        else
            self%vol_target => self%vol_ref
        endif
        ! make the icosahedral group
        call ico%new('ico')
        self%nspace = ico%get_nsym()
        self%nspace_nonred = self%nspace/2
        ! set other stuff
        self%kfromto_vpft(1) = vol_ref%get_find(hp)
        self%kfromto_vpft(2) = vol_ref%get_find(lp)
        allocate( self%vpft_ref_nonred(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace_nonred  ), &
                  self%locs_ref       (self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace,       3), &
                  self%locs_ref_nonred(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace_nonred,3))
        ! generate sampling space
        do ispace=1,self%nspace
            ! get sampling space rotation matrix
            call ico%get_symori(ispace, e)
            rmat = e%get_mat()
            ! loop over resolution shells
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                ! calculate sampling location
                vec(1) = real(k)*i_startvec(1)
                vec(2) = real(k)*i_startvec(2)
                vec(3) = real(k)*i_startvec(3)
                self%locs_ref(k,ispace,:) = matmul(vec,rmat)
            end do
        end do
        ! record the non-redundant lines (note they are slightly fragmented)
        do ispace=1,5
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                self%locs_ref_nonred(k,ispace,:) = self%locs_ref(k,ispace,:)
            end do
        end do
        do ispace=11,35
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                self%locs_ref_nonred(k,ispace-5,:) = self%locs_ref(k,ispace,:)
            end do
        end do
        ! prepare for fast interpolation
        call self%vol_ref%fft()
        call self%vol_ref%expand_cmat(alpha)
        if( present(vol_target) )then
            call self%vol_target%fft()
            call self%vol_target%expand_cmat(alpha)
        endif
        ! extract the reference lines
        call self%extract_ref
        ! destruct
        call e%kill
        call ico%kill
        ! flag existence
        self%existence = .true.
    end subroutine new

    ! GETTERS

    pure function get_nspace( self ) result( nspace )
        class(volpft_corrcalc), intent(in) :: self
        integer :: nspace
        nspace = self%nspace
    end function get_nspace

    pure function get_nspace_nonred( self ) result( nspace_nonred )
        class(volpft_corrcalc), intent(in) :: self
        integer :: nspace_nonred
        nspace_nonred = self%nspace_nonred
    end function get_nspace_nonred

    pure function get_kfromto( self ) result( kfromto )
        class(volpft_corrcalc), intent(in) :: self
        integer :: kfromto(2)
        kfromto(1) = self%kfromto_vpft(1)
        kfromto(2) = self%kfromto_vpft(2)
    end function get_kfromto

    ! INTERPOLATION METHODS

    !>  \brief  extracts the lines defined by the sampling space from the reference
    subroutine extract_ref( self )
        class(volpft_corrcalc), intent(inout) :: self
        real    :: loc(3)
        integer :: ispace, k
        do ispace=1,self%nspace_nonred
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                loc = self%locs_ref_nonred(k,ispace,:)
                self%vpft_ref_nonred(k,ispace) =&
                self%vol_ref%interp_fcomp_trilinear(loc)
            end do
        end do
        self%sqsum_ref = sum(csq(self%vpft_ref_nonred))
    end subroutine extract_ref

    subroutine extract_target_1( self, rmat, vpft_target, sqsum_target )
        class(volpft_corrcalc), intent(inout) :: self
        real,                   intent(in)    :: rmat(3,3)
        complex,                intent(out)   :: vpft_target(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace_nonred)
        real,                   intent(out)   :: sqsum_target
        real    :: loc(3)
        integer :: ispace, k
        do ispace=1,self%nspace_nonred
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                loc = matmul(self%locs_ref_nonred(k,ispace,:),rmat)
                vpft_target(k,ispace) = self%vol_target%interp_fcomp_trilinear(loc)
            end do
        end do
        sqsum_target = sum(csq(vpft_target))
    end subroutine extract_target_1

    subroutine extract_target_2( self, rmat, shvec, vpft_target, sqsum_target )
        class(volpft_corrcalc), intent(inout) :: self
        real,                   intent(in)    :: rmat(3,3)
        real,                   intent(in)    :: shvec(3)
        complex,                intent(out)   :: vpft_target(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace_nonred)
        real,                   intent(out)   :: sqsum_target
        real    :: loc(3)
        integer :: ispace, k
        do ispace=1,self%nspace_nonred
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                loc  = matmul(self%locs_ref_nonred(k,ispace,:),rmat)
                vpft_target(k,ispace) = self%vol_target%interp_fcomp_trilinear(loc) * self%vol_target%oshift(loc, shvec)
            end do
        end do
        sqsum_target = sum(csq(vpft_target))
    end subroutine extract_target_2

    function corr_1( self, rmat ) result( cc )
        class(volpft_corrcalc), intent(inout) :: self
        real,                   intent(in)    :: rmat(3,3)
        complex :: vpft_target(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace_nonred)
        real    :: sqsum_target, cc
        call self%extract_target_1(rmat, vpft_target, sqsum_target)
        cc = sum(real(self%vpft_ref_nonred * conjg(vpft_target)))
        cc = cc / sqrt(self%sqsum_ref * sqsum_target)
    end function corr_1

    function corr_2( self, rmat, shvec ) result( cc )
        class(volpft_corrcalc), intent(inout) :: self
        real,                   intent(in)    :: rmat(3,3)
        real,                   intent(in)    :: shvec(3)
        complex :: vpft_target(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace_nonred)
        real    :: sqsum_target, cc
        call self%extract_target_2(rmat, shvec, vpft_target, sqsum_target)
        cc = sum(real(self%vpft_ref_nonred * conjg(vpft_target)))
        cc = cc / sqrt(self%sqsum_ref * sqsum_target)
    end function corr_2

    subroutine kill( self )
        class(volpft_corrcalc), intent(inout) :: self
        if( self%existence )then
            self%vol_ref    => null()
            self%vol_target => null()
            deallocate(self%vpft_ref_nonred,self%locs_ref,self%locs_ref_nonred)
            self%existence = .false.
        endif
    end subroutine kill

end module simple_volpft_corrcalc

program simple_test_line_shiftsrch
include 'simple_lib.f08'
use simple_polarft_corrcalc,  only: polarft_corrcalc
use simple_cmdline,           only: cmdline
use simple_builder,           only: builder
use simple_image,             only: image
use simple_parameters,        only: parameters, params_glob
use simple_polarizer,         only: polarizer
use simple_pftcc_shsrch_grad, only: pftcc_shsrch_grad  ! gradient-based in-plane angle and shift search
use simple_commander_volops,  only: reproject_commander
use simple_optimizer,         only: optimizer
use simple_opt_factory,       only: opt_factory
use simple_opt_spec,          only: opt_spec
implicit none
type(cmdline)                 :: cline, cline_projection
type(builder)                 :: b
type(parameters)              :: p
type(polarft_corrcalc)        :: pftcc
type(polarizer)               :: img_copy
type(pftcc_shsrch_grad)       :: grad_shsrch_obj           !< origin shift search object, L-BFGS with gradient
type(reproject_commander)     :: xreproject
character(len=:), allocatable :: cmd
logical                :: be_verbose=.false.
real,    parameter     :: SHMAG=1.0
integer, parameter     :: N_PTCLS = 9
real,    allocatable   :: corrs(:), norm_const(:, :)
real                   :: corrmax, corr, cxy(3), lims(2,2), shvec(2), cur_sh(2), grad(2)
real(dp)               :: curval, maxval
integer                :: xsh, ysh, xbest, ybest, i, j, irot, rc, line_irot, cur_irot, nrots, prev_irot
real, allocatable      :: sigma2_noise(:,:)      !< the sigmas for alignment & reconstruction (from groups)
logical                :: mrc_exists
class(optimizer), pointer   :: opt_ptr=>null()      ! the generic optimizer object
integer,          parameter :: NDIM=2, NRESTARTS=1
type(opt_factory) :: ofac                           ! the optimization factory object
type(opt_spec)    :: spec                           ! the optimizer specification object
character(len=8)  :: str_opts                       ! string descriptors for the NOPTS optimizers
real              :: lowest_cost
if( command_argument_count() < 3 )then
    write(logfhandle,'(a)',advance='no') 'ERROR! Usage: simple_test_shiftsrch stk=<particles.ext> mskdiam=<mask radius(in pixels)>'
    write(logfhandle,'(a)') ' smpd=<sampling distance(in A)> [nthr=<number of threads{1}>] [verbose=<yes|no{no}>]'
    write(logfhandle,'(a)') 'Example: https://www.rcsb.org/structure/1jyx with smpd=1. mskdiam=180'
    write(logfhandle,'(a)') 'DEFAULT TEST (example above) is running now...'
    inquire(file="1JYX.mrc", exist=mrc_exists)
    if( .not. mrc_exists )then
        write(*, *) 'Downloading the example dataset...'
        cmd = 'curl -s -o 1JYX.pdb https://files.rcsb.org/download/1JYX.pdb'
        call execute_command_line(cmd, exitstat=rc)
        write(*, *) 'Converting .pdb to .mrc...'
        cmd = 'e2pdb2mrc.py 1JYX.pdb 1JYX.mrc'
        call execute_command_line(cmd, exitstat=rc)
        cmd = 'rm 1JYX.pdb'
        call execute_command_line(cmd, exitstat=rc)
        write(*, *) 'Projecting 1JYX.mrc...'
        call cline_projection%set('vol1'      , '1JYX.mrc')
        call cline_projection%set('smpd'      , 1.)
        call cline_projection%set('pgrp'      , 'c1')
        call cline_projection%set('mskdiam'   , 180.)
        call cline_projection%set('nspace'    , 6.)
        call cline_projection%set('nthr'      , 16.)
        call xreproject%execute(cline_projection)
        call cline%set('stk'    , 'reprojs.mrcs')
        call cline%set('smpd'   , 1.)
        call cline%set('nthr'   , 16.)
        call cline%set('stk'    , 'reprojs.mrcs')
        call cline%set('mskdiam', 180.)
    endif
endif
call cline%parse_oldschool
call cline%checkvar('stk',      1)
call cline%checkvar('mskdiam',  2)
call cline%checkvar('smpd',     3)
call cline%check
be_verbose = .false.
if( cline%defined('verbose') )then
    if( trim(cline%get_carg('verbose')) .eq. 'yes' )then
        be_verbose = .true.
    endif
endif
call p%new(cline)
allocate( sigma2_noise(p%kfromto(1):p%kfromto(2), 1:N_PTCLS), source=1. )
call b%build_general_tbox(p, cline)
call pftcc%new(N_PTCLS, [1,N_PTCLS], p%kfromto)
call pftcc%assign_sigma2_noise(sigma2_noise)
allocate(corrs(pftcc%get_nrots()), norm_const(pftcc%get_nrots(), 2))
call img_copy%new([p%box_crop,p%box_crop,1],p%smpd_crop)
call img_copy%init_polarizer(pftcc, p%alpha)
call b%img%read(p%stk, 1)
call b%img%norm
call b%img%fft
call b%img%clip_inplace([p%box_crop,p%box_crop,1])
call img_copy%polarize(pftcc, b%img, 1, isptcl=.false., iseven=.true., mask=b%l_resmsk)
call img_copy%polarize(pftcc, b%img, 1, isptcl=.true.,  iseven=.true., mask=b%l_resmsk)
call pftcc%shift_ptcl(1, [SHMAG,0.,0.]) ! left
call img_copy%polarize(pftcc, b%img, 2, isptcl=.false., iseven=.true., mask=b%l_resmsk)
call img_copy%polarize(pftcc, b%img, 2, isptcl=.true.,  iseven=.true., mask=b%l_resmsk)
call pftcc%shift_ptcl(2, [0.,SHMAG,0.]) ! down
call img_copy%polarize(pftcc, b%img, 3, isptcl=.false., iseven=.true., mask=b%l_resmsk)
call img_copy%polarize(pftcc, b%img, 3, isptcl=.true.,  iseven=.true., mask=b%l_resmsk)
call pftcc%shift_ptcl(3, [-SHMAG,0.,0.]) ! right
call img_copy%polarize(pftcc, b%img, 4, isptcl=.false., iseven=.true., mask=b%l_resmsk)
call img_copy%polarize(pftcc, b%img, 4, isptcl=.true.,  iseven=.true., mask=b%l_resmsk)
call pftcc%shift_ptcl(4, [0.,SHMAG,0.]) ! up
call img_copy%polarize(pftcc, b%img, 5, isptcl=.false., iseven=.true., mask=b%l_resmsk)
call img_copy%polarize(pftcc, b%img, 5, isptcl=.true.,  iseven=.true., mask=b%l_resmsk)
call pftcc%shift_ptcl(5, [SHMAG,SHMAG,0.]) ! left + down
call img_copy%polarize(pftcc, b%img, 6, isptcl=.false., iseven=.true., mask=b%l_resmsk)
call img_copy%polarize(pftcc, b%img, 6, isptcl=.true.,  iseven=.true., mask=b%l_resmsk)
call pftcc%shift_ptcl(6, [-SHMAG,-SHMAG,0.]) ! right + up
call img_copy%polarize(pftcc, b%img, 7, isptcl=.false., iseven=.true., mask=b%l_resmsk)
call img_copy%polarize(pftcc, b%img, 7, isptcl=.true.,  iseven=.true., mask=b%l_resmsk)
call pftcc%shift_ptcl(7, [-SHMAG,SHMAG,0.]) ! right + down
call img_copy%polarize(pftcc, b%img, 8, isptcl=.false., iseven=.true., mask=b%l_resmsk)
call img_copy%polarize(pftcc, b%img, 8, isptcl=.true.,  iseven=.true., mask=b%l_resmsk)
call pftcc%shift_ptcl(8, [SHMAG,-SHMAG,0.]) ! left + up
call img_copy%polarize(pftcc, b%img, 9, isptcl=.false., iseven=.true., mask=b%l_resmsk)
call img_copy%polarize(pftcc, b%img, 9, isptcl=.true.,  iseven=.true., mask=b%l_resmsk)
call pftcc%shift_ptcl(9, [0.,0.,0.]) ! no shift
call img_copy%ifft()
call img_copy%write('shifted.mrc', 1)
call pftcc%set_with_ctf(.false.)
call pftcc%memoize_refs
do i = 1, N_PTCLS
    call pftcc%memoize_sqsum_ptcl(i)
enddo
call pftcc%memoize_ptcls
lims(1,1) = -6.
lims(1,2) =  6.
lims(2,1) = -6.
lims(2,2) =  6.
call grad_shsrch_obj%new(lims, opt_angle=.false.)
call grad_shsrch_obj%set_indices(1, 5)
irot = 1
cxy  = grad_shsrch_obj%minimize(irot)
print *, cxy(1), cxy(2:3)
! shifting ref
shvec = [1., -1.]
call pftcc%shift_ref(9, shvec)
! inplane irot searching
line_irot = 25
nrots     = pftcc%get_nrots()
maxval    = 0._dp
cur_irot  = 1
do i = 1, nrots
    curval = pftcc%gencorr_euclid_line_for_rot(line_irot, 9, 9, i, real(shvec, dp))
    if( curval >= maxval )then
        maxval   = curval
        cur_irot = i
    endif
enddo
print *, 'nrots         = ', nrots
print *, 'truth    irot = ', line_irot
print *, 'searched irot = ', cur_irot
print *, 'truth    val  = ', pftcc%gencorr_euclid_line_for_rot(line_irot, 9, 9, line_irot, real(shvec, dp))
print *, 'searched val  = ', maxval
! shift searching
cur_sh    = [0.5, -0.5]
str_opts  = 'lbfgsb'
lims(1,1) = -5.
lims(1,2) =  5.
lims(2,1) = -5.
lims(2,2) =  5.
call spec%specify(str_opts, NDIM, limits=lims, nrestarts=NRESTARTS, factr  = 1.0d+5, pgtol = 1.0d-7)
call spec%set_costfun_8(costfct)                                    ! set pointer to costfun
call spec%set_gcostfun_8(gradfct)                                   ! set pointer to gradient of costfun
call spec%set_fdfcostfun_8(costgradfct)
call ofac%new(spec, opt_ptr)                                        ! generate optimizer object with the factory
prev_irot = 1
do j = 1, 10
    maxval    = 0._dp
    cur_irot  = 1
    do i = 1, nrots
        curval = pftcc%gencorr_euclid_line_for_rot(line_irot, 9, 9, i, real(cur_sh, dp))
        if( curval >= maxval )then
            maxval   = curval
            cur_irot = i
        endif
    enddo
    spec%x(1) = cur_sh(1)
    spec%x(2) = cur_sh(2)
    spec%x_8  = real(spec%x, dp)
    call opt_ptr%minimize(spec, opt_ptr, lowest_cost)                   ! minimize the test function
    cur_sh = real(spec%x_8(1:2))
    if( cur_irot == prev_irot )exit
    prev_irot = cur_irot
    print *, 'iter = ', j, '; cost/shifts: ', lowest_cost, spec%x_8
enddo
print *, 'found irot   = ', cur_irot
print *, 'found shifts = ', cur_sh
print *, 'val at this irot/shift = ', pftcc%gencorr_euclid_line_for_rot(line_irot, 9, 9, cur_irot, real(cur_sh, dp))
call opt_ptr%kill
deallocate(opt_ptr)

contains

    function costfct( fun_self, x, d ) result( r )
        class(*), intent(inout) :: fun_self
        integer,  intent(in)    :: d
        real(dp), intent(in)    :: x(d)
        real(dp)                :: r
        r = - pftcc%gencorr_euclid_line_for_rot(line_irot, 9, 9, cur_irot, x)
    end function

    subroutine gradfct( fun_self, x, grad, d )
        class(*), intent(inout) :: fun_self
        integer,  intent(in)    :: d
        real(dp), intent(inout) :: x(d)
        real(dp), intent(out)   :: grad(d)
        call pftcc%gencorr_euclid_line_grad_for_rot(line_irot, 9, 9, cur_irot, curval, grad, x)
        grad = -grad
    end subroutine

    subroutine costgradfct( fun_self, x, f, grad, d )
        class(*), intent(inout) :: fun_self
        integer,  intent(in)    :: d
        real(dp), intent(out)   :: f
        real(dp), intent(inout) :: x(d)
        real(dp), intent(out)   :: grad(d)
        call pftcc%gencorr_euclid_line_grad_for_rot(line_irot, 9, 9, cur_irot, f, grad, x)
        f    = -f
        grad = -grad
    end subroutine

end program simple_test_line_shiftsrch

module simple_polarops
include 'simple_lib.f08'
!$ use omp_lib
!$ use omp_lib_kinds
use simple_builder,           only: builder, build_glob
use simple_parameters,        only: params_glob
use simple_sp_project,        only: sp_project
use simple_image,             only: image
use simple_polarft_corrcalc,  only: polarft_corrcalc
use simple_strategy2D_utils
implicit none

public :: polar_cavger_new, polar_cavger_update_sums, polar_cavger_merge_eos_and_norm
public :: polar_cavger_calc_and_write_frcs_and_eoavg, polar_cavger_gen2Dclassdoc
public :: polar_cavger_write, polar_cavger_writeall, polar_cavger_writeall_cartrefs
public :: polar_cavger_restore_classes, polar_cavger_kill
public :: test_polarops
private
#include "simple_local_flags.inc"


complex(dp), allocatable :: pfts_even(:,:,:), pfts_odd(:,:,:), pfts_refs(:,:,:)
real(dp),    allocatable :: ctf2_even(:,:,:), ctf2_odd(:,:,:) 
integer,     allocatable :: prev_eo_pops(:,:), eo_pops(:,:)
real                     :: smpd       = 0.          !< pixel size
integer                  :: ncls       = 0           !< # classes
integer                  :: kfromto(2) = 0           ! Resoliution range
integer                  :: pftsz      = 0           ! size of PFT in pftcc along rotation dimension

contains

    subroutine polar_cavger_new( pftcc )
        class(polarft_corrcalc), target, intent(in) :: pftcc
        ncls    = params_glob%ncls
        pftsz   = pftcc%get_pftsz()
        kfromto = pftcc%get_kfromto()
        ! dimensions
        smpd          = params_glob%smpd
        allocate(prev_eo_pops(ncls,2), eo_pops(ncls,2), source=0)
        ! Arrays        
        allocate(pfts_even(pftsz,kfromto(1):kfromto(2),ncls),pfts_odd(pftsz,kfromto(1):kfromto(2),ncls),&
            &ctf2_even(pftsz,kfromto(1):kfromto(2),ncls),ctf2_odd(pftsz,kfromto(1):kfromto(2),ncls),&
            &pfts_refs(pftsz,kfromto(1):kfromto(2),ncls))
        call polar_cavger_zero_pft_refs
        pfts_refs = DCMPLX_ZERO
    end subroutine polar_cavger_new

    subroutine polar_cavger_zero_pft_refs
        pfts_even = DCMPLX_ZERO
        pfts_odd  = DCMPLX_ZERO
        ctf2_even = 0.d0
        ctf2_odd  = 0.d0
    end subroutine polar_cavger_zero_pft_refs

    subroutine polar_cavger_update_sums( nptcls, pinds, spproj, pftcc, incr_shifts )
        integer,                         intent(in)    :: nptcls
        integer,                         intent(in)    :: pinds(nptcls)
        class(sp_project),               intent(inout) :: spproj
        class(polarft_corrcalc), target, intent(inout) :: pftcc
        real,                            intent(in)    :: incr_shifts(2,nptcls)
        class(oris), pointer :: spproj_field
        complex(sp), pointer :: pptcls(:,:,:), rptcl(:,:)
        real(sp),    pointer :: pctfmats(:,:,:), rctf(:,:)
        real(dp) :: w
        real     :: incr_shift(2)
        integer  :: eopops(ncls,2), i, icls, iptcl, irot
        logical  :: l_ctf, l_even
        ! retrieve particle info & pointers
        call spproj%ptr2oritype(params_glob%oritype, spproj_field)
        l_ctf = pftcc%is_with_ctf()
        call pftcc%get_ptcls_ptr(pptcls)
        if( l_ctf )call pftcc%get_ctfmats_ptr(pctfmats)
        ! update classes
        eopops = 0
        !$omp parallel do schedule(guided) proc_bind(close) default(shared)&
        !$omp private(i,iptcl,w,l_even,icls,irot,incr_shift,rptcl,rctf)&
        !$omp reduction(+:eopops,pfts_even,ctf2_even,pfts_odd,ctf2_odd)
        do i = 1,nptcls
            ! particles parameters
            iptcl = pinds(i)
            if( spproj_field%get_state(iptcl) == 0  ) cycle
            w = real(spproj_field%get(iptcl,'w'),dp)
            if( w < DSMALL ) cycle
            l_even = spproj_field%get_eo(iptcl)==0
            icls   = spproj_field%get_class(iptcl)
            irot   = pftcc%get_roind(spproj_field%e3get(iptcl))
            incr_shift = incr_shifts(:,i)
            ! weighted restoration
            if( any(abs(incr_shift) > 1.e-6) ) call pftcc%shift_ptcl(iptcl, -incr_shift)
            call pftcc%get_work_pft_ptr(rptcl)
            call pftcc%rotate_pft(pptcls(:,:,i), irot, rptcl)
            if( l_ctf )then
                call pftcc%get_work_rpft_ptr(rctf)
                call pftcc%rotate_pft(pctfmats(:,:,i), irot, rctf)
                if( l_even )then
                    pfts_even(:,:,icls) = pfts_even(:,:,icls) + w * cmplx(rptcl,kind=dp) * real(rctf,kind=dp)
                    ctf2_even(:,:,icls) = ctf2_even(:,:,icls) + w * real(rctf,kind=dp)**2
                else
                    pfts_odd(:,:,icls)  = pfts_odd(:,:,icls)  + w * cmplx(rptcl,kind=dp) * real(rctf,kind=dp)
                    ctf2_odd(:,:,icls)  = ctf2_odd(:,:,icls)  + w * real(rctf,kind=dp)**2
                endif
            else
                if( l_even )then
                    pfts_even(:,:,icls) = pfts_even(:,:,icls) + w * cmplx(rptcl,kind=dp)
                    ctf2_even(:,:,icls) = ctf2_even(:,:,icls) + w
                else
                    pfts_odd(:,:,icls)  = pfts_odd(:,:,icls)  + w * cmplx(rptcl,kind=dp)
                    ctf2_odd(:,:,icls)  = ctf2_odd(:,:,icls)  + w
                endif
            endif
            ! total population
            if( l_even )then
                eopops(icls,1) = eo_pops(icls,1) + 1
            else
                eopops(icls,2) = eo_pops(icls,2) + 1
            endif
        enddo
        !$omp end parallel do
        eo_pops = eo_pops + eopops
        ! cleanup
        nullify(spproj_field,rptcl,rctf,pptcls,pctfmats)
    end subroutine polar_cavger_update_sums

    subroutine polar_cavger_merge_eos_and_norm
        real, parameter :: EPSILON = 0.1
        complex(dp) :: numerator(pftsz,kfromto(1):kfromto(2))
        real(dp)    :: denominator(pftsz,kfromto(1):kfromto(2))
        integer     :: icls, eo_pop(2), pop
        pfts_refs = DCMPLX_ZERO
        !$omp parallel do default(shared), schedule(static) proc_bind(close)&
        !$omp private(icls,eo_pop,pop,numerator,denominator)
        do icls=1,ncls
            eo_pop = prev_eo_pops(icls,:) + eo_pops(icls,:) ! eo_pops has to be calculated differently
            pop    = sum(eo_pop)
            if(pop == 0)then
                pfts_even(:,:,icls) = DCMPLX_ZERO
                pfts_odd(:,:,icls)  = DCMPLX_ZERO
                ctf2_even(:,:,icls) = 0.d0
                ctf2_odd(:,:,icls)  = 0.d0
            else
                ! w*CTF**2 density correction
                if(pop > 1)then
                    numerator   = pfts_even(:,:,icls) + pfts_odd(:,:,icls)
                    denominator = ctf2_even(:,:,icls) + ctf2_odd(:,:,icls)
                    if( pop <= 5 ) denominator = denominator + real(EPSILON/real(pop),dp)
                    where( abs(denominator) > DSMALL ) pfts_refs(:,:,icls) = numerator / denominator
                endif
                if(eo_pop(1) > 1)then
                    where( abs(ctf2_even(:,:,icls)) > DSMALL ) pfts_even(:,:,icls) = pfts_even(:,:,icls) / ctf2_even(:,:,icls)
                endif
                if(eo_pop(2) > 1)then
                    where( abs(ctf2_odd(:,:,icls)) > DSMALL )  pfts_odd(:,:,icls)  = pfts_odd(:,:,icls)  / ctf2_odd(:,:,icls)
                endif
            endif
        end do
        !$omp end parallel do
    end subroutine polar_cavger_merge_eos_and_norm

    !>  \brief  calculates Fourier ring correlations
    subroutine polar_cavger_calc_and_write_frcs_and_eoavg( fname )
        character(len=*), intent(in) :: fname
        real, allocatable :: frc(:)
        integer           :: eo_pop(2), icls, find, pop, filtsz
        filtsz = fdim(params_glob%box_crop) - 1
        allocate(frc(filtsz),source=0.)
        !$omp parallel do default(shared) private(icls,frc,find,pop,eo_pop) schedule(static) proc_bind(close)
        do icls = 1,ncls
            eo_pop = prev_eo_pops(icls,:) + eo_pops(icls,:) ! eo_pops has to be calculated differently
            pop    = sum(eo_pop)
            if( pop == 0 )then
                frc = 0.
                call build_glob%clsfrcs%set_frc(icls, frc, 1)
            else
                ! calculate FRC
                call calc_frc(pfts_even(:,:,icls), pfts_odd(:,:,icls), filtsz, frc)
                call build_glob%clsfrcs%set_frc(icls, frc, 1)
                ! average low-resolution info between eo pairs to keep things in register
                find = build_glob%clsfrcs%estimate_find_for_eoavg(icls, 1)
                if( find >= kfromto(1) )then
                    pfts_even(:,kfromto(1):find,icls) = pfts_refs(:,kfromto(1):find,icls)
                    pfts_odd(:,kfromto(1):find,icls)  = pfts_refs(:,kfromto(1):find,icls)
                endif
            endif
        end do
        !$omp end parallel do
        !!!!!!!!!!!!!! NOT WRITTEN AT THE MOMENT, TESTING UNDERWAY
        !! write FRCs
        ! call build_glob%clsfrcs%write(fname)
        !!!!!!!!!!!!! TODO: REMOVE
    end subroutine polar_cavger_calc_and_write_frcs_and_eoavg

    subroutine polar_cavger_refs2cartesian( pftcc, cavgs, which )
        use simple_image
        class(polarft_corrcalc), intent(in)    :: pftcc
        type(image),             intent(inout) :: cavgs(ncls)
        character(len=*),        intent(in)    :: which
        complex(dp), allocatable :: cmat(:,:)
        real(dp),    allocatable :: norm(:,:)
        complex(dp) :: pft(1:pftsz,kfromto(1):kfromto(2)), fc
        real        :: phys(2), dh,dk
        integer     :: k,c,irot,physh,physk,box,icls
        box = params_glob%box_crop
        c   = box/2+1
        allocate(cmat(c,box),norm(c,box))
        do icls = 1, ncls
            select case(trim(which))
            case('even')
                pft = pfts_even(1:pftsz,kfromto(1):kfromto(2),icls)
            case('odd')
                pft = pfts_odd(1:pftsz,kfromto(1):kfromto(2),icls)
            case('merged')
                pft = pfts_refs(1:pftsz,kfromto(1):kfromto(2),icls)
            end select
            ! Bi-linear interpolation
            cmat = DCMPLX_ZERO
            norm = 0.d0
            do irot = 1,pftsz
                do k = kfromto(1),kfromto(2)
                    phys  = pftcc%get_coord(irot,k) + [1.,real(c)]
                    fc    = cmplx(pft(irot,k),kind=dp)
                    physh = floor(phys(1))
                    physk = floor(phys(2))
                    dh = phys(1) - real(physh)
                    dk = phys(2) - real(physk)
                    if( physh > 0 .and. physh <= c )then
                        if( physk <= box )then
                            cmat(physh,physk) = cmat(physh,physk) + (1.-dh)*(1-dk)*fc
                            norm(physh,physk) = norm(physh,physk) + (1.-dh)*(1-dk)
                            if( physk+1 <= box )then
                                cmat(physh,physk+1) = cmat(physh,physk+1) + (1.-dh)*dk*fc
                                norm(physh,physk+1) = norm(physh,physk+1) + (1.-dh)*dk
                            endif
                        endif
                    endif
                    physh = physh + 1
                    if( physh > 0 .and. physh <= c )then
                        if( physk <= box )then
                            cmat(physh,physk) = cmat(physh,physk) + dh*(1-dk)*fc
                            norm(physh,physk) = norm(physh,physk) + dh*(1-dk)
                            if( physk+1 <= box )then
                                cmat(physh,physk+1) = cmat(physh,physk+1) + dh*dk*fc
                                norm(physh,physk+1) = norm(physh,physk+1) + dh*dk
                            endif
                        endif
                    endif
                end do
            end do
            where( norm > DTINY )
                cmat = cmat / norm
            elsewhere
                cmat = 0.d0
            end where
            ! irot = self%pftsz+1, eg. angle=180.
            do k = 1,box/2-1
                cmat(1,k+c) = conjg(cmat(1,c-k))
            enddo
            ! arbitrary magnitude
            cmat(1,c) = DCMPLX_ZERO
            call cavgs(icls)%new([box,box,1],smpd)
            call cavgs(icls)%set_cmat(cmplx(cmat,kind=sp))
            call cavgs(icls)%shift_phorig()
            call cavgs(icls)%ifft
            ! call cavgs(icls)%div_w_instrfun('linear')
        enddo
    end subroutine polar_cavger_refs2cartesian

    ! I/O

    subroutine polar_cavger_write( fname, which )
        character(len=*),  intent(in) :: fname, which
        character(len=:), allocatable :: fname_here
        fname_here  = trim(fname)
        select case(which)
            case('even')
                call write_pft_array(pfts_even, fname_here)
            case('odd')
                call write_pft_array(pfts_odd,  fname_here)
            case('merged')
                call write_pft_array(pfts_refs, fname_here)
            case DEFAULT
                THROW_HARD('unsupported which flag')
        end select
    end subroutine polar_cavger_write

    subroutine polar_cavger_writeall( tmpl_fname )
        character(len=*),  intent(in) :: tmpl_fname
        call polar_cavger_write(trim(tmpl_fname)//'_even'//BIN_EXT,'even')
        call polar_cavger_write(trim(tmpl_fname)//'_odd'//BIN_EXT, 'odd')
        call polar_cavger_write(trim(tmpl_fname)//BIN_EXT,         'merged')
    end subroutine polar_cavger_writeall

    subroutine polar_cavger_writeall_cartrefs( pftcc, tmpl_fname )
        class(polarft_corrcalc), intent(in) :: pftcc
        character(len=*),  intent(in)       :: tmpl_fname
        type(image), allocatable :: imgs(:)
        call alloc_imgarr(ncls, [params_glob%box_crop, params_glob%box_crop,1], smpd, imgs)
        call polar_cavger_refs2cartesian( pftcc, imgs, 'even' )
        call write_cavgs(imgs, trim(tmpl_fname)//'_even'//params_glob%ext)
        call polar_cavger_refs2cartesian( pftcc, imgs, 'odd' )
        call write_cavgs(imgs, trim(tmpl_fname)//'_odd'//params_glob%ext)
        call polar_cavger_refs2cartesian( pftcc, imgs, 'merged' )
        call write_cavgs(imgs, trim(tmpl_fname)//params_glob%ext)
        call dealloc_imgarr(imgs)
    end subroutine polar_cavger_writeall_cartrefs

    subroutine polar_cavger_read( fname, which )
        character(len=*),  intent(in) :: fname, which
        character(len=:), allocatable :: fname_here
        fname_here  = trim(fname)
        select case(which)
            case('even')
                call read_pft_array(fname_here, pfts_even)
            case('odd')
                call read_pft_array(fname_here, pfts_odd)
            case('merged')
                call read_pft_array(fname_here, pfts_refs)
            case DEFAULT
                THROW_HARD('unsupported which flag')
        end select
    end subroutine polar_cavger_read

    !>  \brief  writes partial class averages to disk (distributed execution)
    subroutine polar_cavger_readwrite_partial_sums( which )
        character(len=*), intent(in)  :: which
        character(len=:), allocatable :: cae, cao, cte, cto
        allocate(cae, source='cavgs_even_part'//int2str_pad(params_glob%part,params_glob%numlen)//BIN_EXT)
        allocate(cao, source='cavgs_odd_part'//int2str_pad(params_glob%part,params_glob%numlen)//BIN_EXT)
        allocate(cte, source='ctfsqsums_even_part'//int2str_pad(params_glob%part,params_glob%numlen)//BIN_EXT)
        allocate(cto, source='ctfsqsums_odd_part'//int2str_pad(params_glob%part,params_glob%numlen)//BIN_EXT)
        select case(trim(which))
            case('read')
                call read_pft_array(cae, pfts_even)
                call read_pft_array(cao, pfts_odd)
                call read_ctf2_array(cte, ctf2_even)
                call read_ctf2_array(cto, ctf2_odd)
            case('write')
                call write_pft_array(pfts_even, cae)
                call write_pft_array(pfts_odd,  cao)
                call write_ctf2_array(ctf2_even, cte)
                call write_ctf2_array(ctf2_odd,  cto)
            case DEFAULT
                THROW_HARD('unknown which flag; only read & write supported; cavger_readwrite_partial_sums')
        end select
        deallocate(cae, cao, cte, cto)
    end subroutine polar_cavger_readwrite_partial_sums

    !>  \brief prepares a 2D class document with class index, resolution,
    !!         population, average correlation and weight
    subroutine polar_cavger_gen2Dclassdoc( spproj )
        use simple_sp_project, only: sp_project
        class(sp_project), target, intent(inout) :: spproj
        class(oris), pointer :: ptcl_field, cls_field
        integer  :: pops(ncls)
        real(dp) :: corrs(ncls), ws(ncls)
        real     :: frc05, frc0143, rstate, w
        integer  :: iptcl, icls, pop, nptcls
        ptcl_field => spproj%os_ptcl2D
        cls_field  => spproj%os_cls2D
        nptcls = ptcl_field%get_noris()
        pops   = 0
        corrs  = 0.d0
        ws     = 0.d0
        !$omp parallel do default(shared) private(iptcl,rstate,icls,w) schedule(static)&
        !$omp proc_bind(close) reduction(+:pops,corrs,ws)
        do iptcl=1,nptcls
            rstate = ptcl_field%get(iptcl,'state')
            if( rstate < 0.5 ) cycle
            w = ptcl_field%get(iptcl,'w')
            if( w < SMALL ) cycle
            icls = ptcl_field%get_class(iptcl)
            if( icls<1 .or. icls>params_glob%ncls )cycle
            pops(icls)  = pops(icls)  + 1
            corrs(icls) = corrs(icls) + real(ptcl_field%get(iptcl,'corr'),dp)
            ws(icls)    = ws(icls)    + real(w,dp)
        enddo
        !$omp end parallel do
        where(pops>1)
            corrs = corrs / real(pops)
            ws    = ws / real(pops)
        elsewhere
            corrs = -1.
            ws    = 0.
        end where
        call cls_field%new(ncls, is_ptcl=.false.)
        do icls=1,ncls
            pop = pops(icls)
            call build_glob%clsfrcs%estimate_res(icls, frc05, frc0143)
            call cls_field%set(icls, 'class',     icls)
            call cls_field%set(icls, 'pop',       pop)
            call cls_field%set(icls, 'res',       frc0143)
            call cls_field%set(icls, 'corr',      corrs(icls))
            call cls_field%set(icls, 'w',         ws(icls))
            call cls_field%set_state(icls, 1) ! needs to be default val if no selection has been done
            if( pop == 0 )call cls_field%set_state(icls, 0)
        end do
    end subroutine polar_cavger_gen2Dclassdoc

    subroutine polar_cavger_restore_classes( pinds )
        use simple_ctf,                 only: ctf
        use simple_strategy2D3D_common, only: discrete_read_imgbatch, killimgbatch, prepimgbatch
        use simple_timer
        integer,   intent(in)    :: pinds(:)
        type(ctfparams)          :: ctfparms
        type(polarft_corrcalc)   :: pftcc
        type(ctf)                :: tfun
        type(image), allocatable :: cavgs(:)
        real,        allocatable :: incr_shifts(:,:)
        integer(timer_int_kind)  :: t
        real    :: sdevnoise
        integer :: iptcl, ithr, i, nptcls
        logical :: eo, l_ctf
        ! Dimensions
        params_glob%kfromto = [2, nint(real(params_glob%box_crop)/2.)-1]
        ! Use pftcc to hold particles
        t = tic()
        nptcls = size(pinds)
        call pftcc%new(params_glob%ncls, [1,nptcls], params_glob%kfromto)
        l_ctf = build_glob%spproj%get_ctfflag('ptcl2D',iptcl=params_glob%fromp).ne.'no'
        call build_glob%img_crop_polarizer%init_polarizer(pftcc, params_glob%alpha)
        ! read images
        t = tic()
        call prepimgbatch(nptcls)
        call discrete_read_imgbatch(nptcls, pinds, [1,nptcls])
        call pftcc%reallocate_ptcls(nptcls, pinds)
        print *,'read: ',toc(t)
        ! ctf
        t = tic()
        if( l_ctf ) call pftcc%create_polar_absctfmats(build_glob%spproj, 'ptcl2D')
        allocate(incr_shifts(2,nptcls),source=0.)
        print *,'ctf: ',toc(t)
        t = tic()
        !$omp parallel do default(shared) private(iptcl,i,ithr,eo,sdevnoise,ctfparms,tfun)&
        !$omp schedule(static) proc_bind(close)
        do i = 1,nptcls
            ithr  = omp_get_thread_num() + 1
            iptcl = pinds(i)
            ! normalization
            call build_glob%imgbatch(i)%norm_noise(build_glob%lmsk, sdevnoise)
            if( trim(params_glob%gridding).eq.'yes' )then
                call build_glob%img_crop_polarizer%div_by_instrfun(build_glob%imgbatch(i))
            endif
            call build_glob%imgbatch(i)%fft
            ! shift
            incr_shifts(:,i) = build_glob%spproj_field%get_2Dshift(iptcl)
            ! phase-flipping
            ctfparms = build_glob%spproj%get_ctfparams(params_glob%oritype, iptcl)
            select case(ctfparms%ctfflag)
                case(CTFFLAG_NO, CTFFLAG_FLIP)
                case(CTFFLAG_YES)
                    tfun = ctf(ctfparms%smpd, ctfparms%kv, ctfparms%cs, ctfparms%fraca)
                    call tfun%apply_serial(build_glob%imgbatch(i), 'flip', ctfparms)
                case DEFAULT
                    THROW_HARD('unsupported CTF flag: '//int2str(ctfparms%ctfflag)//' polar_cavger_restore_classes')
            end select
            ! even/odd
            eo = build_glob%spproj_field%get_eo(iptcl) < 0.5
            ! polar transform
            call build_glob%img_crop_polarizer%polarize(pftcc, build_glob%imgbatch(i), iptcl, .true., eo, mask=build_glob%l_resmsk)
        end do
        !$omp end parallel do
        print *,'loop: ',toc(t)
        call killimgbatch
        t = tic()
        call polar_cavger_new(pftcc)
        print *,'polar_cavger_new: ',toc(t)
        t = tic()
        call polar_cavger_update_sums(nptcls, pinds, build_glob%spproj, pftcc, incr_shifts)
        print *,'polar_cavger_update_sums: ',toc(t)
        t = tic()
        call polar_cavger_merge_eos_and_norm
        print *,'polar_cavger_merge_eos_and_norm: ',toc(t)
        t = tic()
        call polar_cavger_calc_and_write_frcs_and_eoavg(FRCS_FILE)
        print *,'polar_cavger_calc_and_write_frcs_and_eoavg: ',toc(t)
        call polar_cavger_gen2Dclassdoc(build_glob%spproj)
        ! write
        call polar_cavger_write('cavgs_even.bin', 'even')
        call polar_cavger_write('cavgs_odd.bin',  'odd')
        call polar_cavger_write('cavgs.bin',      'merged')
        allocate(cavgs(params_glob%ncls))
        call polar_cavger_refs2cartesian(pftcc, cavgs, 'even')
        call write_cavgs(cavgs, 'cavgs_even.mrc')
        call polar_cavger_refs2cartesian(pftcc, cavgs, 'odd')
        call write_cavgs(cavgs, 'cavgs_odd.mrc')
        call polar_cavger_refs2cartesian(pftcc, cavgs, 'merged')
        call write_cavgs(cavgs, 'cavgs_merged.mrc')
        call pftcc%kill
        call polar_cavger_kill
        call dealloc_imgarr(cavgs)
    end subroutine polar_cavger_restore_classes

    subroutine polar_cavger_kill
        if( allocated(pfts_even) )then
            deallocate(pfts_even,pfts_odd,ctf2_even,ctf2_odd,pfts_refs,eo_pops,prev_eo_pops)
        endif
        smpd       = 0.
        ncls       = 0
        kfromto(2) = 0
        pftsz      = 0
    end subroutine polar_cavger_kill

    ! PRIVATE UTILITIES

    subroutine calc_frc( pft1, pft2, n, frc )
        complex(dp), intent(in)    :: pft1(pftsz,kfromto(1):kfromto(2)), pft2(pftsz,kfromto(1):kfromto(2))
        integer,     intent(in)    :: n
        real(sp),    intent(inout) :: frc(1:n)
        real(dp) :: denom
        integer  :: k
        frc(1:kfromto(1)-1) = 0.999
        do k = kfromto(1), kfromto(2)
            denom = sum(csq_fast(pft1(:,k))) * sum(csq_fast(pft2(:,k)))
            if( denom > DTINY )then
                frc(k) = real(sum(pft1(:,k)*conjg(pft2(:,k))) / sqrt(denom), sp)
            else
                frc(k) = 0.0
            endif
        enddo
        if( kfromto(2) < n ) frc(kfromto(2)+1:) = 0.0
    end subroutine calc_frc

    ! Format for PFT I/O
    ! First  integer: PFTSZ
    ! Second integer: KFROMTO(1)
    ! Third  integer: KFROMTO(2)
    ! Fourth integer: NCLS
    subroutine write_pft_array( array, fname )
        complex(dp),      intent(in) :: array(pftsz,kfromto(1):kfromto(2),ncls)
        character(len=*), intent(in) :: fname
        integer :: funit,io_stat
        call fopen(funit, fname, access='STREAM', action='WRITE', status='REPLACE', iostat=io_stat)
        call fileiochk("write_pft_array: "//trim(fname),io_stat)
        write(unit=funit,pos=1) [pftsz, kfromto(1), kfromto(2), ncls]
        write(unit=funit,pos=(4*sizeof(funit)+1)) array
        call fclose(funit)
    end subroutine write_pft_array

    subroutine write_ctf2_array( array, fname )
        real(dp),         intent(in) :: array(pftsz,kfromto(1):kfromto(2),ncls)
        character(len=*), intent(in) :: fname
        integer :: funit,io_stat
        call fopen(funit, fname, access='STREAM', action='WRITE', status='REPLACE', iostat=io_stat)
        call fileiochk("write_pft_array: "//trim(fname),io_stat)
        write(unit=funit,pos=1) [pftsz, kfromto(1), kfromto(2), ncls]
        write(unit=funit,pos=(4*sizeof(funit)+1)) array
        call fclose(funit)
    end subroutine write_ctf2_array

    subroutine read_pft_array( fname, array )
        character(len=*),         intent(in)    :: fname
        complex(dp), allocatable, intent(inout) :: array(:,:,:)
        complex(dp), allocatable :: tmp(:,:,:)
        integer :: dims(4), funit,io_stat, k
        logical :: samedims
        if( .not.file_exists(trim(fname)) ) THROW_HARD(trim(fname)//' does not exist')
        call fopen(funit, fname, access='STREAM', action='READ', status='OLD', iostat=io_stat)
        call fileiochk('read_pft_array; fopen failed: '//trim(fname), io_stat)
        read(unit=funit,pos=1) dims
        if( .not.allocated(array) )then
            allocate(array(pftsz,kfromto(1):kfromto(2),ncls))
        endif
        samedims = all(dims == [pftsz, kfromto(1), kfromto(2), ncls])
        if( samedims )then
            read(unit=funit, pos=(sizeof(dims)+1)) array
        else
            if( pftsz /= dims(1) )then
                THROW_HARD('Incompatible PFT size in '//trim(fname)//': '//int2str(pftsz)//' vs '//int2str(dims(1)))
            endif
            if( ncls /= dims(4) )then
                THROW_HARD('Incompatible NCLS in '//trim(fname)//': '//int2str(ncls)//' vs '//int2str(dims(4)))
            endif
            allocate(tmp(dims(1),dims(2):dims(3),dims(4)))
            read(unit=funit, pos=(sizeof(dims)+1)) tmp
            do k = kfromto(1),kfromto(2)
                if( (k >= dims(2)) .or. (k <= dims(3)) )then
                    array(:,k,:) = tmp(:,k,:)   ! from stored array
                else
                    array(:,k,:) = 0.d0         ! pad with zeros
                endif
            enddo
            deallocate(tmp)
        endif
        call fclose(funit)
    end subroutine read_pft_array

    subroutine read_ctf2_array( fname, array )
        character(len=*),      intent(in)    :: fname
        real(dp), allocatable, intent(inout) :: array(:,:,:)
        real(dp), allocatable :: tmp(:,:,:)
        integer :: dims(4), funit,io_stat, k
        logical :: samedims
        if( .not.file_exists(trim(fname)) ) THROW_HARD(trim(fname)//' does not exist')
        call fopen(funit, fname, access='STREAM', action='READ', status='OLD', iostat=io_stat)
        call fileiochk('read_pft_array; fopen failed: '//trim(fname), io_stat)
        read(unit=funit,pos=1) dims
        if( .not.allocated(array) )then
            allocate(array(pftsz,kfromto(1):kfromto(2),ncls))
        endif
        samedims = all(dims == [pftsz, kfromto(1), kfromto(2), ncls])
        if( samedims )then
            read(unit=funit, pos=(sizeof(dims)+1)) array
        else
            if( pftsz /= dims(1) )then
                THROW_HARD('Incompatible PFT size in '//trim(fname)//': '//int2str(pftsz)//' vs '//int2str(dims(1)))
            endif
            if( ncls /= dims(4) )then
                THROW_HARD('Incompatible NCLS in '//trim(fname)//': '//int2str(ncls)//' vs '//int2str(dims(4)))
            endif
            allocate(tmp(dims(1),dims(2):dims(3),dims(4)))
            read(unit=funit, pos=(sizeof(dims)+1)) tmp
            do k = kfromto(1),kfromto(2)
                if( (k >= dims(2)) .or. (k <= dims(3)) )then
                    array(:,k,:) = tmp(:,k,:)   ! from stored array
                else
                    array(:,k,:) = 0.d0         ! pad with zeros
                endif
            enddo
            deallocate(tmp)
        endif
        call fclose(funit)
    end subroutine read_ctf2_array

    ! TEST UNIT

    subroutine test_polarops
        use simple_cmdline,    only: cmdline
        use simple_parameters, only: parameters
        integer,     parameter :: N=128
        integer,     parameter :: NIMGS=200
        integer,     parameter :: NCLS=5
        type(image)            :: tmpl_img, img, cavgs(NCLS)
        type(cmdline)          :: cline
        type(polarft_corrcalc) :: pftcc
        type(parameters)       :: p
        type(builder)          :: b
        real    :: ang, shift(2), shifts(2,NIMGS)
        integer :: pinds(NIMGS), i, eo, icls
        ! dummy structure
        call tmpl_img%soft_ring([N,N,1], 1., 8.)
        call tmpl_img%fft
        call tmpl_img%shift2Dserial([ 8.,-16.])
        call img%soft_ring([N,N,1], 1., 12.)
        call img%fft
        call img%shift2Dserial([ 32., 0.])
        call tmpl_img%add(img)
        call img%soft_ring([N,N,1], 1., 16.)
        call img%fft
        call img%shift2Dserial([ -16., 8.])
        call tmpl_img%add(img)
        call img%soft_ring([N,N,1], 1., 32.)
        call img%fft
        call tmpl_img%add(img)
        call tmpl_img%ifft
        call tmpl_img%write('template.mrc')
        ! init of options & parameters
        call cline%set('prg',    'xxx')
        call cline%set('objfun', 'cc')
        call cline%set('smpd',   1.0)
        call cline%set('box',    N)
        call cline%set('ctf',    'no')
        call cline%set('oritype','ptcl2D')
        call cline%set('ncls',    NCLS)
        call cline%set('nptcls',  NIMGs)
        call cline%set('lp',      3.)
        call cline%set('nthr',    8)
        call cline%set('mskdiam', real(N)/2-10.)
        ! Calculators
        call b%init_params_and_build_strategy2D_tbox(cline, p)
        call pftcc%new(NCLS, [1,NIMGS], p%kfromto)
        pinds = (/(i,i=1,NIMGS)/)
        call b%img_crop_polarizer%init_polarizer(pftcc, p%alpha)
        do i = 1,NIMGS
            shift = 10.*[ran3(), ran3()] - 5.
            ! ang   = 360. * ran3()
            ang   = 0.
            eo    = 0
            if( .not.is_even(i) ) eo = 1
            icls  = ceiling(ran3()*4.)
            call img%copy_fast(tmpl_img)
            call img%fft
            call img%shift2Dserial(-shift)
            call img%ifft
            call img%rtsq(ang, 0.,0.)
            call img%add_gauran(2.)
            call img%write('rotimgs.mrc', i)
            call img%fft
            call b%spproj_field%set_euler(i, [0.,0.,ang])
            call b%spproj_field%set_shift(i, shift)
            call b%spproj_field%set(i,'w',1.0)
            call b%spproj_field%set(i,'state',1)
            call b%spproj_field%set(i,'class', icls)
            call b%spproj_field%set(i,'eo',eo)
            shifts(:,i) = -shift
            call b%img_crop_polarizer%polarize(pftcc, img, i, isptcl=.true., iseven=eo==0, mask=b%l_resmsk)
        enddo
        call polar_cavger_new(pftcc)
        call polar_cavger_update_sums(NIMGS, pinds, b%spproj, pftcc, shifts)
        call polar_cavger_merge_eos_and_norm
        call polar_cavger_calc_and_write_frcs_and_eoavg(FRCS_FILE)
        ! write
        call polar_cavger_write('cavgs_even.bin', 'even')
        call polar_cavger_write('cavgs_odd.bin',  'odd')
        call polar_cavger_write('cavgs.bin',      'merged')
        call polar_cavger_refs2cartesian(pftcc, cavgs, 'even')
        call write_cavgs(cavgs, 'cavgs_even.mrc')
        call polar_cavger_refs2cartesian(pftcc, cavgs, 'odd')
        call write_cavgs(cavgs, 'cavgs_odd.mrc')
        call polar_cavger_refs2cartesian(pftcc, cavgs, 'merged')
        call write_cavgs(cavgs, 'cavgs_merged.mrc')
        call polar_cavger_kill
        ! read & write again
        call polar_cavger_new(pftcc)
        call polar_cavger_read('cavgs_even.bin', 'even')
        call polar_cavger_read('cavgs_odd.bin',  'odd')
        call polar_cavger_read('cavgs.bin',      'merged')
        call polar_cavger_refs2cartesian(pftcc, cavgs, 'even')
        call write_cavgs(cavgs, 'cavgs2_even.mrc')
        call polar_cavger_refs2cartesian(pftcc, cavgs, 'odd')
        call write_cavgs(cavgs, 'cavgs2_odd.mrc')
        call polar_cavger_refs2cartesian(pftcc, cavgs, 'merged')
        call write_cavgs(cavgs, 'cavgs2_merged.mrc')
        call polar_cavger_kill
    end subroutine test_polarops

end module simple_polarops

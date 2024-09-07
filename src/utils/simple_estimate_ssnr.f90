! spectral signal-to-noise ratio estimation routines
module simple_estimate_ssnr
!$ use omp_lib
!$ use omp_lib_kinds
use simple_defs
use simple_defs_conv
use simple_srch_sort_loc
use simple_syslib
use simple_math_ft
use simple_strings
use simple_fileio
implicit none

public :: fsc2ssnr, fsc2optlp, fsc2optlp_sub, ssnr2fsc, ssnr2optlp
public :: lowpass_from_klim, mskdiam2lplimits, calc_dose_weights, get_resolution
public :: lpstages
private
#include "simple_local_flags.inc"

contains

    !> \brief  converts the FSC to SSNR (the 2.* is because of the division of the data)
    function fsc2ssnr( corrs ) result( ssnr )
        real, intent(in)  :: corrs(:) !< FSC
        real, allocatable :: ssnr(:)  !< SSNR
        integer :: nyq, k
        real    :: fsc
        nyq = size(corrs)
        allocate( ssnr(nyq) )
        do k=1,nyq
            fsc     = min(abs(corrs(k)), 0.999)
            ssnr(k) = (2. * fsc) / (1. - fsc)
        end do
    end function fsc2ssnr

    !> \brief  converts the FSC to the optimal low-pass filter
    function fsc2optlp( corrs ) result( filt )
        real, intent(in)  :: corrs(:) !< fsc plot (correlations)
        real, allocatable :: filt(:)  !< output filter coefficients
        integer :: nyq
        nyq = size(corrs)
        allocate( filt(nyq) )
        filt = 0.
        where( corrs > 0. )     filt = 2. * corrs / (corrs + 1.)
        where( filt  > 0.99999 ) filt = 0.99999
    end function fsc2optlp

    !> \brief  converts the FSC to the optimal low-pass filter
    subroutine fsc2optlp_sub( filtsz, corrs, filt, merged )
        integer, intent(in)  :: filtsz        !< sz of filter
        real,    intent(in)  :: corrs(filtsz) !< fsc plot (correlations)
        real,    intent(out) :: filt(filtsz)  !< output filter coefficients
        logical, optional, intent(in) :: merged
        logical :: l_merged
        l_merged = .false.
        if( present(merged) ) l_merged = merged
        filt = 0.
        if( l_merged )then
            where( corrs > 0. ) filt = corrs
        else
            where( corrs > 0. ) filt = 2. * corrs / (corrs + 1.)
        endif
        where( filt  > 0.99999 ) filt = 0.99999
    end subroutine fsc2optlp_sub

    !> \brief  converts the SSNR to FSC
    function ssnr2fsc( ssnr ) result( corrs )
        real, intent(in)  :: ssnr(:)  !< input SSNR array
        real, allocatable :: corrs(:) !< output FSC result
        integer :: nyq, k
        nyq = size(ssnr)
        allocate( corrs(nyq) )
        do k=1,nyq
            corrs(k) = ssnr(k) / (ssnr(k) + 1.)
        end do
    end function ssnr2fsc

    ! !> \brief  converts the SSNR 2 the optimal low-pass filter
    function ssnr2optlp( ssnr ) result( w )
        real, intent(in)  :: ssnr(:) !<  instrument SSNR
        real, allocatable :: w(:) !<  FIR low-pass filter
        integer :: nyq, k
        nyq = size(ssnr)
        allocate( w(nyq) )
        do k=1,nyq
            w(k) = ssnr(k) / (ssnr(k) + 1.)
        end do
    end function ssnr2optlp

    subroutine lowpass_from_klim( klim, nyq, filter, width )
        integer,        intent(in)    :: klim, nyq
        real,           intent(inout) :: filter(nyq)
        real, optional, intent(in)    :: width
        real    :: freq, lplim_freq, wwidth
        integer :: k
        wwidth = 10.
        if( present(width) ) wwidth = width
        lplim_freq = real(klim)
        do k = 1,nyq
            freq = real(k)
            if( k > klim )then
                filter(k) = 0.
            else if(k .ge. klim - wwidth)then
                filter(k) = (cos(((freq-(lplim_freq-wwidth))/wwidth)*pi)+1.)/2.
            else
                filter(k) = 1.
            endif
        end do
    end subroutine lowpass_from_klim

    subroutine mskdiam2lplimits( mskdiam, lpstart,lpstop, lpcen )
        real, intent(in)    :: mskdiam
        real, intent(inout) :: lpstart,lpstop, lpcen
        lpstart = max(min(mskdiam/12., 15.),  8.)
        lpstop  = min(max(mskdiam/22.,  5.),  8.)
        lpcen   = min(max(mskdiam/6.,  20.), 30.)
    end subroutine mskdiam2lplimits

    ! Following Grant & Grigorieff; eLife 2015;4:e06980
    subroutine calc_dose_weights( nframes, box, smpd, kV, total_dose, weights )
        integer,           intent(in)    :: nframes, box
        real,              intent(in)    :: smpd, kV, total_dose
        real, allocatable, intent(inout) :: weights(:,:)
        real, parameter :: A=0.245, B=-1.665, C=2.81
        real            :: acc_doses(nframes), spaFreq
        real            :: twoNe, limksq, dose_per_frame
        integer         :: filtsz, iframe, k
        filtsz = fdim(box) - 1
        ! accumulated doses
        dose_per_frame = total_dose / real(nframes) ! e-/Angs2/frame
        do iframe=1,nframes
            acc_doses(iframe) = real(iframe) * dose_per_frame ! e-/Angs2
        end do
        ! voltage scaling
        if( is_equal(kV,200.) )then
            acc_doses = acc_doses / 0.8
        else if( is_equal(kV,100.) )then
            acc_doses = acc_doses / 0.64
        endif
        if( allocated(weights) ) deallocate( weights )
        allocate( weights(nframes,filtsz), source=0.)
        ! dose normalization
        limksq = real(box*smpd)**2.
        do k = 1,filtsz
            spaFreq      = sqrt(real(k*k)/limksq)
            twoNe        = 2.*(A * spaFreq**B + C)
            weights(:,k) = exp(-acc_doses / twoNe)
            weights(:,k) = weights(:,k) / sqrt(sum(weights(:,k) * weights(:,k)))
        enddo
    end subroutine calc_dose_weights

    !>   calculates the resolution values given corrs and res params
    !! \param corrs Fourier shell correlations
    !! \param res resolution value
    subroutine get_resolution( corrs, res, fsc05, fsc0143 )
        real, intent(in)  :: corrs(:), res(:) !<  corrs Fourier shell correlation
        real, intent(out) :: fsc05, fsc0143   !<  fsc05 resolution at FSC=0.5,  fsc0143 resolution at FSC=0.143
        integer           :: n, ires0143, ires05
        n = size(corrs)
        ires0143 = 1
        do while( ires0143 <= n )
            if( corrs(ires0143) >= 0.143 )then
                ires0143 = ires0143 + 1
                cycle
            else
                exit
            endif
        end do
        ires0143 = ires0143 - 1
        if( ires0143 == 0 )then
            fsc0143 = 0.
        else
            fsc0143 = res(ires0143)
        endif
        ires05 = 1
        do while( ires05 <= n )
            if( corrs(ires05) >= 0.5 )then
                ires05 = ires05+1
                cycle
            else
                exit
            endif
        end do
        ires05 = ires05 - 1
        if( ires05 == 0 )then
            fsc05 = 0.
        else
            fsc05 = res(ires05)
        endif
    end subroutine get_resolution

    subroutine lpstages( box, nstages, frcs_avg, smpd, lpstart_lb, lpstart_default, lpfinal, lpinfo, verbose )
        use simple_magic_boxes
        integer,           intent(in)  :: box, nstages
        real,              intent(in)  :: frcs_avg(:), smpd, lpstart_lb, lpstart_default, lpfinal
        type(lp_crop_inf), intent(out) :: lpinfo(nstages)
        logical, optional, intent(in)  :: verbose
        real, parameter :: FRCLIMS_DEFAULT(2) = [0.8,0.05], LP2SMPD_TARGET = 1./3.
        integer :: findlims(2), istage, box_stepsz, box_trial
        real    :: frclims(2), frc_stepsz, lp_max, lp_min, lp_stepsz
        logical :: l_verbose
        l_verbose = .false.
        if( present(verbose) ) l_verbose = verbose
        ! (1) calculate FRC values at the inputted boundaries
        findlims(1) = calc_fourier_index(lpstart_lb, box, smpd)
        findlims(2) = calc_fourier_index(lpfinal,    box, smpd)
        ! -- letting the shape of the FRC influence the limit choice, if needed

        print *, 'frclim1', frcs_avg(findlims(1))
        print *, 'frclim2', frcs_avg(findlims(2))

        frclims(1)  = max(frcs_avg(findlims(1)),FRCLIMS_DEFAULT(1)) ! always moving the limit towards lower resolution
        frclims(2)  = max(frcs_avg(findlims(2)),FRCLIMS_DEFAULT(2))

        print *, 'frclim1', frclims(1)
        print *, 'frclim2', frclims(2)

        ! (3) calculate critical FRC limits and corresponding low-pass limits for the nstages
        call calc_lpinfo(1, frclims(1))
        frc_stepsz = (frclims(1) - frclims(2)) / real(nstages - 1)
        do istage = 2, nstages
            call calc_lpinfo(istage, lpinfo(istage-1)%frc_crit - frc_stepsz)
        end do
        lpinfo(nstages)%lp      = lpfinal
        lpinfo(nstages)%l_lpset = .true.
        if( l_verbose )then
            print *, '########## 1st pass'
            call print_lpinfo
        endif
        ! (4) gather low-pass limit information
        if( all(lpinfo(:)%l_lpset) )then
            ! nothing to do
        else

            print *, 'reverting to linear scheme'

            ! revert to linear scheme
            lpinfo(1)%lp      = lpstart_default
            lpinfo(1)%l_lpset = .true.
            do istage = 2, nstages
                lpinfo(istage)%lp      = lpinfo(istage-1)%lp - (lpinfo(istage-1)%lp - lpfinal) / 2.
                lpinfo(istage)%l_lpset = .true.
            end do
        endif
        if( l_verbose )then
            print *, '########## 2nd pass'
            call print_lpinfo
        endif
        if( .not. all(lpinfo(:)%l_lpset) ) THROW_HARD('Not all lp limits set')
        ! (4) gather downscaling information
        call calc_scaleinfo(1)
        call calc_scaleinfo(nstages)
        box_stepsz = nint(real(lpinfo(nstages)%box_crop - lpinfo(1)%box_crop)/real(nstages - 1))
        do istage = 2, nstages - 1 ! linear box_crop scheme
            box_trial                = lpinfo(istage-1)%box_crop + box_stepsz
            lpinfo(istage)%box_crop  = find_magic_box(box_trial)
            lpinfo(istage)%scale     = real(lpinfo(istage)%box_crop) / real(box)
            lpinfo(istage)%smpd_crop = smpd / lpinfo(istage)%scale
            lpinfo(istage)%trslim    = min(8.,max(2.0, AHELIX_WIDTH / lpinfo(istage)%smpd_crop))
        end do
        if( l_verbose )then
            print *, '########## scale info'
            call print_scaleinfo
        endif
        
        contains

            subroutine calc_lpinfo( stage, thres )
                integer, intent(in) :: stage
                real,    intent(in) :: thres
                integer :: find
                lpinfo(stage)%frc_crit = thres
                lpinfo(stage)%l_lpset  = .false.
                if( all(frcs_avg > thres) ) return
                if( any(frcs_avg > thres) )then           
                    find = get_find_at_corr(frcs_avg, thres)
                    lpinfo(stage)%lp = max(lpfinal,calc_lowpass_lim(find, box, smpd))
                    lpinfo(stage)%l_lpset = .true.
                endif
            end subroutine calc_lpinfo

            subroutine print_lpinfo
                do istage = 1, nstages
                    print *, 'frc_crit/l_lpset/lp ', lpinfo(istage)%frc_crit, lpinfo(istage)%l_lpset, lpinfo(istage)%lp
                end do
            end subroutine print_lpinfo

            subroutine calc_scaleinfo( istage )
                integer, intent(in) :: istage
                real :: smpd_target
                smpd_target                = max(smpd, (lpinfo(istage)%lp * LP2SMPD_TARGET))
                call autoscale(box, smpd, smpd_target, lpinfo(istage)%box_crop, lpinfo(istage)%smpd_crop, lpinfo(istage)%scale, minbox=64)
                lpinfo(istage)%trslim      = min(8.,max(2.0, AHELIX_WIDTH / lpinfo(istage)%smpd_crop))
                lpinfo(istage)%l_autoscale = lpinfo(istage)%box_crop < box
            end subroutine calc_scaleinfo

            subroutine print_scaleinfo
                do istage = 1, nstages
                    print *, 'scale/box_crop/smpd_crop/trslim ',lpinfo(istage)%scale, lpinfo(istage)%box_crop, lpinfo(istage)%smpd_crop, lpinfo(istage)%trslim
                end do
            end subroutine print_scaleinfo

    end subroutine lpstages

end module simple_estimate_ssnr

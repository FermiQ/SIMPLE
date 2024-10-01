program simple_test_val_rescale_map
include 'simple_lib.f08' 
use simple_atoms, only: atoms
use simple_image
implicit none
#include "simple_local_flags.inc"
character(len=STDLEN)         :: pdb_file, pdb_out, exp_vol_file, sim_vol_file, even_vol_file, odd_vol_file
type(atoms)                   :: molecule 
type(image)                   :: exp_vol, sim_vol, even_vol, odd_vol 
real                          :: smpd, smpd_target, smpd_new, upscaling_factor
logical                       :: pdb_exists
integer                       :: rc, slen, i
character(len=:), allocatable :: cmd
integer                       :: ifoo, ldim(3), ldim1(3), ldim2(3), ldim_new(3), box, box_new
character(len=:), allocatable :: smpd_char
if( command_argument_count() /= 3 )then
     write(logfhandle,'(a)') 'ERROR! Usage: simple_test_val_map coords.pdb smpd smpd_target'
     write(logfhandle,'(a)') 'coords.pdb: PDB with the cartesian coordinates of the molecule'
     write(logfhandle,'(a)') 'vol.mrc: 3D recontrusted volume'
     write(logfhandle,'(a)') 'smpd               : SMPD value in Angstrom per voxel '     
     write(logfhandle,'(a)') 'smpd_target        : SMPD value in Angstrom per voxel used in scaling'     
else
    call get_command_argument(1, pdb_file)
    call get_command_argument(2, length=slen)
    allocate(character(slen) :: smpd_char)
    call get_command_argument(2, smpd_char)
    read(smpd_char, *) smpd
    deallocate(smpd_char)
    call get_command_argument(3, length=slen)
    allocate(character(slen) :: smpd_char)
    call get_command_argument(3, smpd_char)
    read(smpd_char, *) smpd_target
endif
exp_vol_file  = swap_suffix(pdb_file,'mrc','pdb')
sim_vol_file  = trim(get_fbody(pdb_file,'pdb'))//'_sim.mrc'
even_vol_file = trim(get_fbody(pdb_file,'pdb'))//'_even.mrc'
odd_vol_file  = trim(get_fbody(pdb_file,'pdb'))//'_odd.mrc'
pdb_out       = trim(get_fbody(pdb_file,'pdb'))//'_centered.pdb'
! the dimensions of all volumes need to be consisted
call find_ldim_nptcls(exp_vol_file,  ldim, ifoo)
call find_ldim_nptcls(odd_vol_file,  ldim1, ifoo)
call find_ldim_nptcls(even_vol_file, ldim2, ifoo)
write(logfhandle,'(a,3i6,a,f8.3,a)') 'Original dimensions (', ldim,' ) voxels, smpd: ', smpd, ' Angstrom'
if( any(ldim /= ldim1) .or. any(ldim /= ldim2) .or. any(ldim1 /= ldim2) ) THROW_HARD('Volume density maps no conforming in dimensions')
box = ldim(1)
upscaling_factor = smpd / smpd_target
box_new          = round2even(real(ldim(1)) * upscaling_factor)
ldim_new(:)      = box_new
upscaling_factor = real(box_new) / real(box)
smpd_new         = smpd / upscaling_factor
write(logfhandle,'(a,3i6,a,f8.3,a)') 'Scaled dimensions   (', ldim_new,' ) voxels, smpd: ', smpd_new, ' Angstrom'
call molecule%new(pdb_file)
call molecule%pdb2mrc(pdb_file, sim_vol_file, smpd_new, vol_dim=ldim_new)
call sim_vol%new(ldim_new, smpd_new)
call sim_vol%read(sim_vol_file)
call molecule%atom_validation(sim_vol, 'sim_val_corr')
write(logfhandle,'(a)') "Done simulated map validation"
! experimental volume - even and odd
call exp_vol%read_and_crop(exp_vol_file, smpd, box_new, smpd_new)
call exp_vol%write('upscaled.mrc')
call molecule%atom_validation(exp_vol, 'exp_val_corr')
call exp_vol%kill()
write(logfhandle,'(a)') "Done experimental map validation"
! even
call exp_vol%read_and_crop(even_vol_file, smpd, ldim_new(1), smpd_new)
call molecule%atom_validation(exp_vol, 'even_val_corr')
call exp_vol%kill()
write(logfhandle,'(a)') "Done experimental even map validation"
! odd
call exp_vol%read_and_crop(odd_vol_file, smpd, ldim_new(1), smpd_new)
call molecule%atom_validation(exp_vol, 'odd_val_corr')
call exp_vol%kill()
write(logfhandle,'(a)') "Done experimental odd map validation"
! exp vol vs sim vol per atom
call exp_vol%read_and_crop(exp_vol_file, smpd, ldim_new(1), smpd_new)
call molecule%map_validation(exp_vol, sim_vol, 'exp_sim_val_corr')
call exp_vol%kill()
call sim_vol%kill()
call molecule%kill()
write(logfhandle,'(a)') "Done experimental vs simulated map validation"
end program simple_test_val_rescale_map






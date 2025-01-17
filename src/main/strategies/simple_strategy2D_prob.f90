module simple_strategy2D_prob
include 'simple_lib.f08'
use simple_strategy2D_alloc
use simple_strategy2D,       only: strategy2D
use simple_strategy2D_srch,  only: strategy2D_spec
use simple_builder,          only: build_glob
use simple_parameters,       only: params_glob
implicit none

public :: strategy2D_prob
private

#include "simple_local_flags.inc"

type, extends(strategy2D) :: strategy2D_prob
  contains
    procedure :: new  => new_prob
    procedure :: srch => srch_prob
    procedure :: kill => kill_prob
end type strategy2D_prob

contains

    subroutine new_prob( self, spec )
        class(strategy2D_prob), intent(inout) :: self
        class(strategy2D_spec),   intent(inout) :: spec
        call self%s%new( spec )
        self%spec = spec
    end subroutine new_prob

    subroutine srch_prob( self )
        use simple_eul_prob_tab, only: eulprob_corr_switch
        class(strategy2D_prob), intent(inout) :: self
        if( build_glob%spproj_field%get_state(self%s%iptcl) > 0 )then
            ! Prep
            call self%s%prep4srch
            ! Assignment
            self%s%best_class = self%spec%eulprob%assgn_map(self%s%iptcl_map)%iproj
            self%s%best_corr  = eulprob_corr_switch(self%spec%eulprob%assgn_map(self%s%iptcl_map)%dist)
            self%s%best_rot   = self%spec%eulprob%assgn_map(self%s%iptcl_map)%inpl
            self%s%best_shvec = 0.
            if( s2D%do_inplsrch(self%s%iptcl_map) )then
                if( self%spec%eulprob%assgn_map(self%s%iptcl_map)%has_sh )then
                    self%s%best_shvec = [self%spec%eulprob%assgn_map(self%s%iptcl_map)%x,&
                    &                    self%spec%eulprob%assgn_map(self%s%iptcl_map)%y]
                endif
            endif
            self%s%nrefs_eval = self%s%nrefs
            call self%s%store_solution
        else
            call build_glob%spproj_field%reject(self%s%iptcl)
        endif
    end subroutine srch_prob

    subroutine kill_prob( self )
        class(strategy2D_prob), intent(inout) :: self
        call self%s%kill
    end subroutine kill_prob

end module simple_strategy2D_prob

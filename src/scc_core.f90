! This file is part of xtb.
!
! Copyright (C) 2017-2020 Stefan Grimme
!
! xtb is free software: you can redistribute it and/or modify it under
! the terms of the GNU Lesser General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! xtb is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!
! You should have received a copy of the GNU Lesser General Public License
! along with xtb.  If not, see <https://www.gnu.org/licenses/>.

!! ========================================================================
!  GENERAL FUNCTIONS FOR CORE FUNCTIONALITIES OF THE SCC
!! ------------------------------------------------------------------------
!  GFN1:
!  -> build_h0_gfn1
!  GFN2:
!  -> build_h0_gfn2
!! ========================================================================
module xtb_scc_core
   use xtb_mctc_accuracy, only : wp
   use xtb_mctc_la, only : sygvd,gemm,symm
   use xtb_type_environment, only : TEnvironment
   use xtb_xtb_data
   use xtb_broyden
   implicit none

   integer, private, parameter :: mmm(*)=(/1,2,2,2,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,4/)

contains

subroutine getSelfEnergy(hData, nShell, at, cn, qat, selfEnergy, dSEdcn, dSEdq)
   type(THamiltonianData), intent(in) :: hData
   integer, intent(in) :: nShell(:)
   integer, intent(in) :: at(:)
   real(wp), intent(in), optional :: cn(:)
   real(wp), intent(in), optional :: qat(:)
   real(wp), intent(out) :: selfEnergy(:)
   real(wp), intent(out), optional :: dSEdcn(:)
   real(wp), intent(out), optional :: dSEdq(:)

   integer :: ind, iAt, iZp, iSh, lang

   selfEnergy(:) = 0.0_wp
   if (present(dSEdcn)) dSEdcn(:) = 0.0_wp
   if (present(dSEdq)) dSEdq(:) = 0.0_wp
   ind = 0
   do iAt = 1, size(cn)
      iZp = at(iAt)
      do iSh = 1, nShell(iZp)
         selfEnergy(ind+iSh) = hData%selfEnergy(iSh, iZp)
      end do
      ind = ind + nShell(iZp)
   end do
   if (present(dSEdq) .and. present(qat)) then
      ind = 0
      do iAt = 1, size(cn)
         iZp = at(iAt)
         do iSh = 1, nShell(iZp)
            lAng = hData%angShell(iSh, iZp)+1
            selfEnergy(ind+iSh) = selfEnergy(ind+iSh) &
               & - hData%kQShell(lAng,iZp)*qat(iAt) - hData%kQAtom(iZp)*qat(iAt)**2
            dSEdq(ind+iSh) = -hData%kQShell(lAng,iZp) - hData%kQAtom(iZp)*2*qat(iAt)
         end do
         ind = ind + nShell(iZp)
      end do
      if (present(dSEdcn) .and. present(cn)) then
         ind = 0
         do iAt = 1, size(cn)
            iZp = at(iAt)
            do iSh = 1, nShell(iZp)
               lAng = hData%angShell(iSh, iZp)+1
               selfEnergy(ind+iSh) = selfEnergy(ind+iSh) &
                  & - hData%kCN(lAng+1, iZp) * cn(iAt)
               dSEdcn(ind+iSh) = -hData%kCN(iSh, iZp)
            end do
            ind = ind + nShell(iZp)
         end do
      end if
   else
      if (present(dSEdcn) .and. present(cn)) then
         ind = 0
         do iAt = 1, size(cn)
            iZp = at(iAt)
            do iSh = 1, nShell(iZp)
               lAng = hData%angShell(iSh, iZp)+1
               selfEnergy(ind+iSh) = selfEnergy(ind+iSh) &
                  & - hData%kCN(iSh, iZp) * cn(iAt)
               dSEdcn(ind+iSh) = -hData%kCN(iSh, iZp)
            end do
            ind = ind + nShell(iZp)
         end do
      end if
   end if

end subroutine getSelfEnergy

!! ========================================================================
!  build GFN2 core Hamiltonian
!! ========================================================================
subroutine build_h0(hData,H0,n,at,ndim,nmat,matlist, &
   &                xyz,selfEnergy,S,aoat2,lao2,valao2,aoexp,ao2sh)
   type(THamiltonianData), intent(in) :: hData
   real(wp),intent(out) :: H0(ndim*(ndim+1)/2)
   integer, intent(in)  :: n
   integer, intent(in)  :: at(n)
   integer, intent(in)  :: ndim
   integer, intent(in)  :: nmat
   integer, intent(in)  :: matlist(2,nmat)
   real(wp),intent(in)  :: xyz(3,n)
   real(wp),intent(in)  :: selfEnergy(:)
   real(wp),intent(in)  :: S(ndim,ndim)
   integer, intent(in)  :: aoat2(ndim)
   integer, intent(in)  :: lao2(ndim)
   integer, intent(in)  :: valao2(ndim)
   integer, intent(in)  :: ao2sh(ndim)
   real(wp),intent(in)  :: aoexp(ndim)

   integer  :: i,j,k,m
   integer  :: iat,jat,ish,jsh,il,jl,iZp,jZp
   real(wp) :: hdii,hdjj,hav
   real(wp) :: km
   real(wp),parameter :: aot = -0.5d0 ! AO exponent dep. H0 scal

   H0=0.0_wp

   do m = 1, nmat
      i = matlist(1,m)
      j = matlist(2,m)
      k = j+i*(i-1)/2
      iat = aoat2(i)
      jat = aoat2(j)
      ish = ao2sh(i)
      jsh = ao2sh(j)
      iZp = at(iat)
      jZp = at(jat)
      il = mmm(lao2(i))
      jl = mmm(lao2(j))
      hdii = selfEnergy(ish)
      hdjj = selfEnergy(jsh)
      call h0scal(hData,n,at,i,j,il,jl,iat,jat,valao2(i).ne.0,valao2(j).ne.0, &
      &           km)
      km = km*(2*sqrt(aoexp(i)*aoexp(j))/(aoexp(i)+aoexp(j)))**hData%wExp
      hav = 0.5d0*(hdii+hdjj)* &
      &      shellPoly(hData%shellPoly(il, iZp), hData%shellPoly(jl, jZp), &
      &                hData%atomicRad(iZp), hData%atomicRad(jZp),xyz(:,iat),xyz(:,jat))
      H0(k) = S(j,i)*km*hav
   enddo
!  diagonal
   k=0
   do i=1,ndim
      k=k+i
      iat = aoat2(i)
      ish = ao2sh(i)
      il = mmm(lao2(i))
      H0(k) = selfEnergy(ish)
   enddo

end subroutine build_h0

!! ========================================================================
!  build GFN1 Fockian
!! ========================================================================
subroutine build_h1_gfn1(jData,n,at,ndim,nshell,nmat,matlist,H,H1,H0,S,ves,q, &
      & gam3at,cm5,fgb,fhb,aoat2,ao2sh)
   use xtb_mctc_convert, only : autoev,evtoau
   use xtb_solv_gbobc, only : lgbsa
   type(TCoulombData), intent(in) :: jData
   integer, intent(in)  :: n
   integer, intent(in)  :: at(n)
   integer, intent(in)  :: ndim
   integer, intent(in)  :: nshell
   integer, intent(in)  :: nmat
   integer, intent(in)  :: matlist(2,nmat)
   real(wp),intent(in)  :: H0(ndim*(1+ndim)/2)
   real(wp),intent(in)  :: S(ndim,ndim)
   real(wp),intent(in)  :: ves(nshell)
   real(wp),intent(in)  :: q(n)
   real(wp),intent(in)  :: gam3at(n)
   real(wp),intent(in)  :: cm5(n)
   real(wp),intent(in)  :: fgb(n,n)
   real(wp),intent(in)  :: fhb(n)
   integer, intent(in)  :: aoat2(ndim)
   integer, intent(in)  :: ao2sh(ndim)
   real(wp),intent(out) :: H(ndim,ndim)
   real(wp),intent(out) :: H1(ndim*(1+ndim)/2)

   integer  :: m,i,j,k
   integer  :: ishell,jshell
   integer  :: ii,jj,kk
   real(wp) :: dum
   real(wp) :: eh1,t8,t9,tgb

   H = 0.0_wp
   H1 = 0.0_wp

   do m = 1, nmat
      i = matlist(1,m)
      j = matlist(2,m)
      k = j+i*(i-1)/2
      ishell = ao2sh(i)
      jshell = ao2sh(j)
      dum = S(j,i)
!     SCC terms
!     2nd order ES term (optional: including point charge potential)
      eh1 = ves(ishell) + ves(jshell)
!     3rd order and set-up of H
      ii = aoat2(i)
      jj = aoat2(j)
      dum = S(j,i)
!     third-order diagonal term, unscreened
      t8 = q(ii)**2 * gam3at(ii)
      t9 = q(jj)**2 * gam3at(jj)
      eh1 = eh1 + autoev*(t8+t9)
      H1(k) = -dum*eh1*0.5_wp
      H(j,i) = H0(k)+H1(k)
      H(i,j) = H(j,i)
   enddo
!  add the gbsa SCC term
   if (lgbsa) then
!     hbpow=2.d0*c3-1.d0
      do m=1,nmat
         i=matlist(1,m)
         j=matlist(2,m)
         k=j+i*(i-1)/2
         ii=aoat2(i)
         jj=aoat2(j)
         dum=S(j,i)
!        GBSA SCC terms
         eh1=0.0_wp
         do kk=1,n
            eh1=eh1+cm5(kk)*(fgb(kk,ii)+fgb(kk,jj))
         enddo
         t8=fhb(ii)*cm5(ii)+fhb(jj)*cm5(jj)
         tgb=-dum*(0.5_wp*eh1+t8)
         H1(k)=H1(k)+tgb
         H(j,i)=H(j,i)+tgb
         H(i,j)=H(j,i)
      enddo
   endif

end subroutine build_h1_gfn1

!! ========================================================================
!  build GFN1 Fockian
!! ========================================================================
subroutine build_h1_gfn2(n,at,ndim,nshell,nmat,ndp,nqp,matlist,mdlst,mqlst,&
                         H,H1,H0,S,dpint,qpint,ves,vs,vd,vq,q,qsh,gam3sh, &
                         hdisp,fgb,fhb,aoat2,ao2sh)
   use xtb_mctc_convert, only : autoev,evtoau
   use xtb_solv_gbobc, only : lgbsa
   integer, intent(in)  :: n
   integer, intent(in)  :: at(n)
   integer, intent(in)  :: ndim
   integer, intent(in)  :: nshell
   integer, intent(in)  :: nmat
   integer, intent(in)  :: ndp
   integer, intent(in)  :: nqp
   integer, intent(in)  :: matlist(2,nmat)
   integer, intent(in)  :: mdlst(2,ndp)
   integer, intent(in)  :: mqlst(2,nqp)
   real(wp),intent(in)  :: H0(ndim*(1+ndim)/2)
   real(wp),intent(in)  :: S(ndim,ndim)
   real(wp),intent(in)  :: dpint(3,ndim*(1+ndim)/2)
   real(wp),intent(in)  :: qpint(6,ndim*(1+ndim)/2)
   real(wp),intent(in)  :: ves(nshell)
   real(wp),intent(in)  :: vs(n)
   real(wp),intent(in)  :: vd(3,n)
   real(wp),intent(in)  :: vq(6,n)
   real(wp),intent(in)  :: q(n)
   real(wp),intent(in)  :: qsh(nshell)
   real(wp),intent(in)  :: gam3sh(nshell)
   real(wp),intent(in)  :: hdisp(n)
   real(wp),intent(in)  :: fgb(n,n)
   real(wp),intent(in)  :: fhb(n)
   integer, intent(in)  :: aoat2(ndim)
   integer, intent(in)  :: ao2sh(ndim)
   real(wp),intent(out) :: H(ndim,ndim)
   real(wp),intent(out) :: H1(ndim*(1+ndim)/2)

   integer, external :: lin
   integer  :: m,i,j,k,l
   integer  :: ii,jj,kk
   integer  :: ishell,jshell
   real(wp) :: dum,eh1,t8,t9,tgb

   H1=0.0_wp
   H =0.0_wp
! --- set up of Fock matrix
!  overlap dependent terms
!  on purpose, vs is NOT added to H1 (gradient is calculated separately)
   do m=1,nmat
      i=matlist(1,m)
      j=matlist(2,m)
      k=j+i*(i-1)/2
      ii=aoat2(i)
      jj=aoat2(j)
      ishell=ao2sh(i)
      jshell=ao2sh(j)
      dum=S(j,i)
!     SCC terms
!     2nd order ES term (optional: including point charge potential)
      eh1=ves(ishell)+ves(jshell)
!     SIE term
!     t6=gsie(at(ii))*pi*sin(2.0d0*pi*q(ii))
!     t7=gsie(at(jj))*pi*sin(2.0d0*pi*q(jj))
!     eh1=eh1+autoev*(t6+t7)*gscal
!     third order term
      t8=qsh(ishell)**2*gam3sh(ishell)
      t9=qsh(jshell)**2*gam3sh(jshell)
      eh1=eh1+autoev*(t8+t9)
      H1(k)=-dum*eh1*0.5d0
! SAW start - - - - - - - - - - - - - - - - - - - - - - - - - - - - 1801
!     Dispersion contribution to Hamiltionian
      H1(k)=H1(k) - 0.5d0*dum*autoev*(hdisp(ii)+hdisp(jj))
! SAW end - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 1801
      H(j,i)=H0(k)+H1(k)
!     CAMM potential
      eh1=0.50d0*dum*(vs(ii)+vs(jj))*autoev
      H(j,i)=H(j,i)+eh1
      H(i,j)=H(j,i)
   enddo
!  quadrupole-dependent terms
   do m=1,nqp
      i=mqlst(1,m)
      j=mqlst(2,m)
      ii=aoat2(i)
      jj=aoat2(j)
      k=lin(j,i)
      eh1=0.0d0
      ! note: these come in the following order
      ! xx, yy, zz, xy, xz, yz
      do l=1,6
         eh1=eh1+qpint(l,k)*(vq(l,ii)+vq(l,jj))
      enddo
      eh1=0.50d0*eh1*autoev
!     purposely, do NOT add dip/qpole-int terms onto H1
!     (due to gradient computation later on)
      H(i,j)=H(i,j)+eh1
      H(j,i)=H(i,j)
   enddo
!  dipolar terms
   do m=1,ndp
      i=mdlst(1,m)
      j=mdlst(2,m)
      k=lin(j,i)
      ii=aoat2(i)
      jj=aoat2(j)
      eh1=0.0d0
      do l=1,3
         eh1=eh1+dpint(l,k)*(vd(l,ii)+vd(l,jj))
      enddo
      eh1=0.50d0*eh1*autoev
!     purposely, do NOT add dip/qpole-int terms onto H1
!     (due to gradient computation later on)
      H(i,j)=H(i,j)+eh1
      H(j,i)=H(i,j)
   enddo
!                                          call timing(t2,w2)
!                           call prtime(6,t2-t1,w2-w1,'Fmat')
!  add the gbsa SCC term
   if(lgbsa) then
!     hbpow=2.d0*c3-1.d0
      do m=1,nmat
         i=matlist(1,m)
         j=matlist(2,m)
         k=j+i*(i-1)/2
         ii=aoat2(i)
         jj=aoat2(j)
         dum=S(j,i)
!        GBSA SCC terms
         eh1=0.0d0
         do kk=1,n
            eh1=eh1+q(kk)*(fgb(kk,ii)+fgb(kk,jj))
         enddo
         t8=fhb(ii)*q(ii)+fhb(jj)*q(jj)
         tgb=-dum*(0.5d0*eh1+t8)
         H1(k)=H1(k)+tgb
         H(j,i)=H(j,i)+tgb
         H(i,j)=H(j,i)
      enddo
   endif

end subroutine build_h1_gfn2

!! ========================================================================
!  self consistent charge iterator for GFN1 Hamiltonian
!! ========================================================================
subroutine scc_gfn1(env,xtbData,n,nel,nopen,ndim,nmat,nshell, &
   &                at,matlist,aoat2,ao2sh,ash, &
   &                q,qq,qlmom,qsh,zsh, &
   &                gbsa,fgb,fhb,cm5,cm5a,gborn, &
   &                broy,broydamp,damp0, &
   &                pcem,ves,vpc, &
   &                et,focc,focca,foccb,efa,efb, &
   &                eel,ees,epcem,egap,emo,ihomo,ihomoa,ihomob, &
   &                H0,H1,H,S,X,P,jab,gam3at, &
   &                maxiter,startpdiag,scfconv,qconv, &
   &                minpr,pr, &
   &                fail,jter)
   use xtb_mctc_convert, only : autoev,evtoau

   use xtb_solv_gbobc, only : lgbsa,lhb,TSolvent
   use xtb_embedding, only : electro_pcem

   character(len=*), parameter :: source = 'scc_gfn1'

   type(TEnvironment), intent(inout) :: env

   type(TxTBData), intent(in) :: xtbData

   integer, intent(in)  :: n
   integer, intent(in)  :: nel
   integer, intent(in)  :: nopen
   integer, intent(in)  :: ndim
   integer, intent(in)  :: nmat
   integer, intent(in)  :: nshell
!! ------------------------------------------------------------------------
!  general options for the iterator
   integer, intent(in)  :: maxiter
   integer, intent(in)  :: startpdiag
   real(wp),intent(in)  :: scfconv
   real(wp),intent(in)  :: qconv
   logical, intent(in)  :: minpr
   logical, intent(in)  :: pr
   logical, intent(out) :: fail
!! ------------------------------------------------------------------------
   integer, intent(in)  :: at(n)
!! ------------------------------------------------------------------------
   integer, intent(in)  :: matlist(2,nmat)
   integer, intent(in)  :: aoat2(ndim)
   integer, intent(in)  :: ao2sh(ndim)
   integer, intent(in)  :: ash(:)
   real(wp),intent(in) :: gam3at(n)
!! ------------------------------------------------------------------------
!  a bunch of charges
   real(wp),intent(inout) :: q(n)
   real(wp),intent(inout) :: qq(n)
   real(wp),intent(inout) :: qlmom(3,n)
   real(wp),intent(inout) :: qsh(nshell)
   real(wp),intent(in)    :: zsh(nshell)
!! ------------------------------------------------------------------------
!  continuum solvation model GBSA
   type(TSolvent),intent(inout) :: gbsa
   real(wp),intent(inout) :: fgb(n,n)
   real(wp),intent(inout) :: fhb(n)
   real(wp),intent(in)    :: cm5a(n)
   real(wp),intent(inout) :: cm5(n)
   real(wp),intent(inout) :: gborn
!! ------------------------------------------------------------------------
!  point charge embedding potentials
   logical, intent(in)    :: pcem
   real(wp),intent(inout) :: ves(nshell)
   real(wp),intent(inout) :: vpc(nshell)
!! ------------------------------------------------------------------------
!  Fermi-smearing
   real(wp),intent(in)    :: et
   real(wp),intent(inout) :: focc(ndim)
   real(wp),intent(inout) :: foccb(ndim),focca(ndim)
   real(wp),intent(inout) :: efa,efb
!! ------------------------------------------------------------------------
!  Convergence accelerators, a simple damping as well as a Broyden mixing
!  are available. The Broyden mixing is used by default seems reliable.
   real(wp),intent(in)    :: damp0
   real(wp)               :: damp
!  Broyden
   logical, intent(in)    :: broy
   real(wp),intent(inout) :: broydamp
   real(wp)               :: omegap
   real(wp),allocatable   :: df(:,:)
   real(wp),allocatable   :: u(:,:)
   real(wp),allocatable   :: a(:,:)
   real(wp),allocatable   :: q_in(:)
   real(wp),allocatable   :: dq(:)
   real(wp),allocatable   :: qlast_in(:)
   real(wp),allocatable   :: dqlast(:)
   real(wp),allocatable   :: omega(:)
!! ------------------------------------------------------------------------
!  results of the SCC iterator
   real(wp),intent(out)   :: eel
   real(wp),intent(out)   :: epcem
   real(wp),intent(out)   :: ees
   real(wp),intent(out)   :: egap
   real(wp),intent(out)   :: emo(ndim)
   integer, intent(inout) :: ihomoa
!! ------------------------------------------------------------------------
   real(wp),intent(in)    :: H0(ndim*(ndim+1)/2)
   real(wp),intent(out)   :: H1(ndim*(ndim+1)/2)
   real(wp),intent(out)   :: H(ndim,ndim)
   real(wp),intent(inout) :: P(ndim,ndim)
   real(wp),intent(inout) :: X(ndim,ndim)
   real(wp),intent(in)    :: S(ndim,ndim)
   real(wp),intent(inout) :: jab(nshell,nshell)

   integer, intent(inout) :: jter
!! ------------------------------------------------------------------------
!  local variables
   integer,external :: lin
   integer  :: i,ii,j,jj,k,kk,l,m
   integer  :: ishell,jshell
   integer  :: ihomo,ihomob
   real(wp) :: t8,t9
   real(wp) :: eh1,dum,tgb
   real(wp) :: eold
   real(wp) :: ga,gb
   real(wp) :: rmsq
   real(wp) :: nfoda,nfodb
   logical  :: fulldiag
   logical  :: lastdiag
   integer  :: iter
   integer  :: thisiter
   logical  :: converged
   logical  :: econverged
   logical  :: qconverged

   converged = .false.
   lastdiag = .false.
   ! number of iterations for this iterator
   thisiter = maxiter - jter

   damp = damp0
!  broyden data storage and init
   allocate( df(thisiter,nshell),u(thisiter,nshell), &
   &         a(thisiter,thisiter),dq(nshell),dqlast(nshell), &
   &         qlast_in(nshell),omega(thisiter),q_in(nshell), &
   &         source = 0.0_wp )

!! ------------------------------------------------------------------------
!  iteration entry point
   scc_iterator: do iter = 1, thisiter
!! ------------------------------------------------------------------------
!  build the Fockian from current ES potential and partial charges
!  includes GBSA contribution to Fockian
   call build_H1_gfn1(xtbData%coulomb,n,at,ndim,nshell,nmat,matlist,H,H1,H0,S,ves, &
      & q,gam3at,cm5,fgb,fhb,aoat2,ao2sh)

!! ------------------------------------------------------------------------
!  solve HC=SCemo(X,P are scratch/store)
!  solution is in H(=C)/emo
!! ------------------------------------------------------------------------
   fulldiag=.false.
   if (iter.lt.startpdiag) fulldiag=.true.
   if (lastdiag )          fulldiag=.true.
   call solve(fulldiag,ndim,ihomo,scfconv,H,S,X,P,emo,fail)

   if (fail) then
      call env%error("Diagonalization of Hamiltonian failed", source)
      return
   endif

   if ((ihomo+1.le.ndim).and.(ihomo.ge.1)) egap = emo(ihomo+1)-emo(ihomo)
!  automatic reset to small value
   if ((egap.lt.0.1_wp).and.(iter.eq.0)) broydamp = 0.03_wp

!! ------------------------------------------------------------------------
!  Fermi smearing
   if (et.gt.0.1_wp) then
!     convert restricted occ first to alpha/beta
      if(nel.gt.0) then
         call occu(ndim,nel,nopen,ihomoa,ihomob,focca,foccb)
      else
         focca=0.0_wp
         foccb=0.0_wp
         ihomoa=0
         ihomob=0
      endif
      if(ihomoa+1.le.ndim) then
         call fermismear(.false.,ndim,ihomoa,et,emo,focca,nfoda,efa,ga)
      endif
      if(ihomob+1.le.ndim) then
         call fermismear(.false.,ndim,ihomob,et,emo,foccb,nfodb,efb,gb)
      endif
      focc = focca + foccb
   else
      ga = 0.0_wp
      gb = 0.0_wp
   endif
!! ------------------------------------------------------------------------

!  save q
   q_in(1:nshell)=qsh(1:nshell)
   k=nshell

!  density matrix
   call dmat(ndim,focc,H,P)

!  new q
   call mpopsh (n,ndim,nshell,ao2sh,S,P,qsh)
   qsh = zsh - qsh

!  qat from qsh
   call qsh2qat(ash,qsh,q)

   eold=eel
   call electro(n,at,ndim,nshell,jab,H0,P,q,gam3at,qsh,ees,eel)

!  point charge contribution
   if (pcem) call electro_pcem(nshell,qsh,Vpc,epcem,eel)

!  new cm5 charges and gborn energy
   if(lgbsa) then
      cm5=q+cm5a
      call electro_gbsa(n,at,fgb,fhb,cm5,gborn,eel)
   endif

!  ad el. entropies*T
   eel=eel+ga+gb

!! ------------------------------------------------------------------------
!  check for energy convergence
   econverged = abs(eel - eold) < scfconv
!! ------------------------------------------------------------------------

   dq(1:nshell)=qsh(1:nshell)-q_in(1:nshell)
   rmsq=sum(dq(1:nshell)**2)/dble(n)
   rmsq=sqrt(rmsq)

!! ------------------------------------------------------------------------
!  end of SCC convergence part
   qconverged = rmsq < qconv
!! ------------------------------------------------------------------------

!  SCC convergence acceleration
   if (.not.broy) then

!     simple damp
      if(iter.gt.0) then
         omegap=egap
         ! monopoles only
         do i=1,nshell
            qsh(i)=damp*qsh(i)+(1.0_wp-damp)*q_in(i)
         enddo
         if(eel-eold.lt.0) then
            damp=damp*1.15_wp
         else
            damp=damp0
         endif
         damp=min(damp,1.0_wp)
         if (egap.lt.1.0_wp) damp=min(damp,0.5_wp)
      endif

   else

!     Broyden mixing
      omegap=0.0_wp
      call broyden(nshell,q_in,qlast_in,dq,dqlast, &
      &            iter,thisiter,broydamp,omega,df,u,a)
      qsh(1:nshell)=q_in(1:nshell)
      if(iter.gt.1) omegap=omega(iter-1)
   endif ! Broyden?

   call qsh2qat(ash,qsh,q) !new qat

   if(minpr) write(env%unit,'(i4,F15.7,E14.6,E11.3,f8.2,2x,f8.1,l3)') &
   &         iter+jter,eel,eel-eold,rmsq,egap,omegap,fulldiag
   qq=q

   if(lgbsa) cm5=q+cm5a
!  set up ES potential
   if(pcem) then
      ves(1:nshell)=Vpc(1:nshell)
   else
      ves=0.0_wp
   endif
   call setespot(nshell,qsh,jab,ves)

!! ------------------------------------------------------------------------
   if (econverged.and.qconverged) then
      converged = .true.
      if (lastdiag) exit scc_iterator
      lastdiag = .true.
   endif
!! ------------------------------------------------------------------------

   enddo scc_iterator

   jter = jter + min(iter,maxiter-jter)
   fail = .not.converged

end subroutine scc_gfn1

!! ========================================================================
!  self consistent charge iterator for GFN2 Hamiltonian
!! ========================================================================
subroutine scc_gfn2(env,xtbData,n,nel,nopen,ndim,ndp,nqp,nmat,nshell, &
   &                at,matlist,mdlst,mqlst,aoat2,ao2sh,ash, &
   &                q,dipm,qp,qq,qlmom,qsh,zsh, &
   &                xyz,vs,vd,vq,gab3,gab5, &
   &                gbsa,fgb,fhb,cm5,cm5a,gborn, &
   &                newdisp,dispdim,g_a,g_c,gw,wdispmat,hdisp, &
   &                broy,broydamp,damp0, &
   &                pcem,ves,vpc, &
   &                et,focc,focca,foccb,efa,efb, &
   &                eel,ees,eaes,epol,ed,epcem,egap,emo,ihomo,ihomoa,ihomob, &
   &                H0,H1,H,S,dpint,qpint,X,P,jab,gam3sh, &
   &                maxiter,startpdiag,scfconv,qconv, &
   &                minpr,pr, &
   &                fail,jter)
   use xtb_mctc_convert, only : autoev,evtoau

   use xtb_solv_gbobc,  only : lgbsa,lhb,TSolvent
   use xtb_disp_dftd4,  only: disppot,edisp_scc
   use xtb_aespot, only : gfn2broyden_diff,gfn2broyden_out,gfn2broyden_save, &
   &                  mmompop,aniso_electro,setvsdq
   use xtb_embedding, only : electro_pcem

   character(len=*), parameter :: source = 'scc_gfn2'

   type(TEnvironment), intent(inout) :: env

   type(TxTBData), intent(in) :: xtbData

   integer, intent(in)  :: n
   integer, intent(in)  :: nel
   integer, intent(in)  :: nopen
   integer, intent(in)  :: ndim
   integer, intent(in)  :: ndp
   integer, intent(in)  :: nqp
   integer, intent(in)  :: nmat
   integer, intent(in)  :: nshell
!! ------------------------------------------------------------------------
!  general options for the iterator
   integer, intent(in)  :: maxiter
   integer, intent(in)  :: startpdiag
   real(wp),intent(in)  :: scfconv
   real(wp),intent(in)  :: qconv
   logical, intent(in)  :: minpr
   logical, intent(in)  :: pr
   logical, intent(out) :: fail
!! ------------------------------------------------------------------------
   integer, intent(in)  :: at(n)
!! ------------------------------------------------------------------------
   integer, intent(in)  :: matlist(2,nmat)
   integer, intent(in)  :: mdlst(2,ndp)
   integer, intent(in)  :: mqlst(2,nqp)
   integer, intent(in)  :: aoat2(ndim)
   integer, intent(in)  :: ao2sh(ndim)
   integer, intent(in)  :: ash(:)
!! ------------------------------------------------------------------------
!  a bunch of charges and CAMMs
   real(wp),intent(inout) :: q(n)
   real(wp),intent(inout) :: dipm(3,n)
   real(wp),intent(inout) :: qp(6,n)
   real(wp),intent(inout) :: qq(n)
   real(wp),intent(inout) :: qlmom(3,n)
   real(wp),intent(inout) :: qsh(nshell)
   real(wp),intent(in)    :: zsh(nshell)
!! ------------------------------------------------------------------------
!  anisotropic electrostatic
   real(wp),intent(in)    :: xyz(3,n)
   real(wp),intent(inout) :: vs(n)
   real(wp),intent(inout) :: vd(3,n)
   real(wp),intent(inout) :: vq(6,n)
   real(wp),intent(inout) :: gab3(n*(n+1)/2)
   real(wp),intent(inout) :: gab5(n*(n+1)/2)
!! ------------------------------------------------------------------------
!  continuum solvation model GBSA
   type(TSolvent),intent(inout) :: gbsa
   real(wp),intent(inout) :: fgb(n,n)
   real(wp),intent(inout) :: fhb(n)
   real(wp),intent(in)    :: cm5a(n)
   real(wp),intent(inout) :: cm5(n)
   real(wp),intent(inout) :: gborn
!! ------------------------------------------------------------------------
!  selfconsistent DFT-D4 dispersion correction
   logical, intent(in)    :: newdisp
   integer, intent(in)    :: dispdim
   real(wp),intent(in)    :: g_a,g_c
   real(wp),intent(in)    :: gw(dispdim)
   real(wp),intent(in)    :: wdispmat(dispdim,dispdim)
   real(wp),intent(inout) :: hdisp(n)
!! ------------------------------------------------------------------------
!  point charge embedding potentials
   logical, intent(in)    :: pcem
   real(wp),intent(inout) :: ves(nshell)
   real(wp),intent(inout) :: vpc(nshell)
!! ------------------------------------------------------------------------
!  Fermi-smearing
   real(wp),intent(in)    :: et
   real(wp),intent(inout) :: focc(ndim)
   real(wp),intent(inout) :: foccb(ndim),focca(ndim)
   real(wp),intent(inout) :: efa,efb
!! ------------------------------------------------------------------------
!  Convergence accelerators, a simple damping as well as a Broyden mixing
!  are available. The Broyden mixing is used by default seems reliable.
   real(wp),intent(in)    :: damp0
   real(wp)               :: damp
!  Broyden
   integer                :: nbr
   logical, intent(in)    :: broy
   real(wp),intent(inout) :: broydamp
   real(wp)               :: omegap
   real(wp),allocatable   :: df(:,:)
   real(wp),allocatable   :: u(:,:)
   real(wp),allocatable   :: a(:,:)
   real(wp),allocatable   :: q_in(:)
   real(wp),allocatable   :: dq(:)
   real(wp),allocatable   :: qlast_in(:)
   real(wp),allocatable   :: dqlast(:)
   real(wp),allocatable   :: omega(:)
!! ------------------------------------------------------------------------
!  results of the SCC iterator
   real(wp),intent(out)   :: eel
   real(wp),intent(out)   :: epcem
   real(wp),intent(out)   :: ees
   real(wp),intent(out)   :: eaes
   real(wp),intent(out)   :: epol
   real(wp),intent(out)   :: ed
   real(wp),intent(out)   :: egap
   real(wp),intent(out)   :: emo(ndim)
   integer, intent(inout) :: ihomo
   integer, intent(inout) :: ihomoa
   integer, intent(inout) :: ihomob
!! ------------------------------------------------------------------------
   real(wp),intent(in)    :: H0(ndim*(ndim+1)/2)
   real(wp),intent(out)   :: H1(ndim*(ndim+1)/2)
   real(wp),intent(out)   :: H(ndim,ndim)
   real(wp),intent(inout) :: P(ndim,ndim)
   real(wp),intent(inout) :: X(ndim,ndim)
   real(wp),intent(in)    :: S(ndim,ndim)
   real(wp),intent(in)    :: dpint(3,ndim*(ndim+1)/2)
   real(wp),intent(in)    :: qpint(6,ndim*(ndim+1)/2)
   real(wp),intent(inout) :: jab(nshell,nshell)
   real(wp),intent(in)    :: gam3sh(nshell)

   integer, intent(inout) :: jter
!! ------------------------------------------------------------------------
!  local variables
   integer,external :: lin
   integer  :: i,ii,j,jj,k,kk,l,m
   integer  :: ishell,jshell
   real(wp) :: t8,t9
   real(wp) :: eh1,dum,tgb
   real(wp) :: eold
   real(wp) :: ga,gb
   real(wp) :: rmsq
   real(wp) :: nfoda,nfodb
   logical  :: fulldiag
   logical  :: lastdiag
   integer  :: iter
   integer  :: thisiter
   logical  :: converged
   logical  :: econverged
   logical  :: qconverged

   converged = .false.
   lastdiag = .false.
   ! number of iterations for this iterator
   thisiter = maxiter - jter

   damp = damp0
   nbr = nshell + 9*n
!  broyden data storage and init
   allocate( df(thisiter,nbr),u(thisiter,nbr),a(thisiter,thisiter), &
   &         dq(nbr),dqlast(nbr),qlast_in(nbr),omega(thisiter), &
   &         q_in(nbr), source = 0.0_wp )

!! ------------------------------------------------------------------------
!  Iteration entry point
   scc_iterator: do iter = 1, thisiter
!! ------------------------------------------------------------------------
   call build_h1_gfn2(n,at,ndim,nshell,nmat,ndp,nqp,matlist,mdlst,mqlst,&
                      H,H1,H0,S,dpint,qpint,ves,vs,vd,vq,q,qsh,gam3sh, &
                      hdisp,fgb,fhb,aoat2,ao2sh)

!! ------------------------------------------------------------------------
!  solve HC=SCemo(X,P are scratch/store)
!  solution is in H(=C)/emo
!! ------------------------------------------------------------------------
   fulldiag=.false.
   if(iter.lt.startpdiag) fulldiag=.true.
   if(lastdiag )          fulldiag=.true.
!                                            call timing(t1,w1)
   call solve(fulldiag,ndim,ihomo,scfconv,H,S,X,P,emo,fail)
!                                            call timing(t2,w2)
!                            call prtime(6,t2-t1,w2-w1,'diag')

   if(fail)then
      call env%error("Diagonalization of Hamiltonian failed", source)
      return
   endif

   if(ihomo+1.le.ndim.and.ihomo.ge.1)egap=emo(ihomo+1)-emo(ihomo)
!  automatic reset to small value
   if(egap.lt.0.1.and.iter.eq.0) broydamp=0.03

!  Fermi smearing
   if(et.gt.0.1)then
!     convert restricted occ first to alpha/beta
      if(nel.gt.0) then
         call occu(ndim,nel,nopen,ihomoa,ihomob,focca,foccb)
      else
         focca=0.0d0
         foccb=0.0d0
         ihomoa=0
         ihomob=0
      endif
      if (ihomoa+1.le.ndim) then
         call fermismear(.false.,ndim,ihomoa,et,emo,focca,nfoda,efa,ga)
      endif
      if (ihomob+1.le.ndim) then
         call fermismear(.false.,ndim,ihomob,et,emo,foccb,nfodb,efb,gb)
      endif
      focc = focca + foccb
   else
      ga = 0.0_wp
      gb = 0.0_wp
   endif

!  save q
   q_in(1:nshell)=qsh(1:nshell)
   k=nshell
   call gfn2broyden_save(n,k,nbr,dipm,qp,q_in)

!  density matrix
   call dmat(ndim,focc,H,P)

!  new q
   call mpopsh (n,ndim,nshell,ao2sh,S,P,qsh)
   qsh = zsh - qsh

!  qat from qsh
   call qsh2qat(ash,qsh,q)

   eold=eel
   call electro2(n,at,ndim,nshell,jab,H0,P,q, &
   &                gam3sh,qsh,ees,eel)
!  multipole electrostatic
   call mmompop(n,ndim,aoat2,xyz,p,s,dpint,qpint,dipm,qp)
!  call scalecamm(n,at,dipm,qp)
!  DEBUG option: check, whether energy from Fock matrix coincides
!                w/ energy routine
!  include 'cammcheck.inc'
!  evaluate energy
   call aniso_electro(xtbData%multipole,n,at,xyz,q,dipm,qp,gab3,gab5,eaes,epol)
   eel=eel+eaes+epol
! SAW start - - - - - - - - - - - - - - - - - - - - - - - - - - - - 1804
   if (newdisp) then
      ed = edisp_scc(n,dispdim,at,q,g_a,g_c,wdispmat,gw)
      eel = eel + ed
   endif
! SAW end - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 1804

!  point charge contribution
   if(pcem) call electro_pcem(nshell,qsh,Vpc,epcem,eel)

!!  new cm5 charges and gborn energy
   if(lgbsa) then
      cm5=q+cm5a
      call electro_gbsa(n,at,fgb,fhb,cm5,gborn,eel)
   endif

!  ad el. entropies*T
   eel=eel+ga+gb

!! ------------------------------------------------------------------------
!  check for energy convergence
   econverged = abs(eel - eold) < scfconv
!! ------------------------------------------------------------------------

   dq(1:nshell)=qsh(1:nshell)-q_in(1:nshell)
   k=nshell
   call gfn2broyden_diff(n,k,nbr,dipm,qp,q_in,dq) ! CAMM case
   rmsq=sum(dq(1:nbr)**2)/dble(n)
   rmsq=sqrt(rmsq)

!! ------------------------------------------------------------------------
!  end of SCC convergence part
   qconverged = rmsq < qconv
!! ------------------------------------------------------------------------

!  SCC convergence acceleration
   if(.not.broy)then

!      simple damp
      if(iter.gt.0) then
         omegap=egap
         ! monopoles only
         do i=1,nshell
            qsh(i)=damp*qsh(i)+(1.0d0-damp)*q_in(i)
         enddo
         ! CAMM
         k=nshell
         do i=1,n
            do j=1,3
               k=k+1
               dipm(j,i)=damp*dipm(j,i)+(1.0d0-damp)*q_in(k)
            enddo
            do j=1,6
               k=k+1
               qp(j,i)=damp*qp(j,i)+(1.0d0-damp)*q_in(k)
            enddo
         enddo
         if(eel-eold.lt.0) then
            damp=damp*1.15
         else
            damp=damp0
         endif
         damp=min(damp,1.0)
         if(egap.lt.1.0)damp=min(damp,0.5)
      endif

   else

!     Broyden mixing
      omegap=0.0d0
      call broyden(nbr,q_in,qlast_in,dq,dqlast, &
     &             iter,thisiter,broydamp,omega,df,u,a)
      qsh(1:nshell)=q_in(1:nshell)
      k=nshell
      call gfn2broyden_out(n,k,nbr,q_in,dipm,qp) ! CAMM case
      if(iter.gt.1) omegap=omega(iter-1)
   endif ! Broyden?

   call qsh2qat(ash,qsh,q) !new qat

! SAW start - - - - - - - - - - - - - - - - - - - - - - - - - - - - 1801
   if(newdisp) call disppot(n,dispdim,at,q,g_a,g_c,wdispmat,gw,hdisp)
! SAW end - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 1801

   if(minpr)write(env%unit,'(i4,F15.7,E14.6,E11.3,f8.2,2x,f8.1,l3)') &
   &  iter+jter,eel,eel-eold,rmsq,egap,omegap,fulldiag
   qq=q

   if(lgbsa) cm5=q+cm5a
!  set up ES potential
   if(pcem) then
      ves(1:nshell)=Vpc(1:nshell)
   else
      ves=0.0d0
   endif
   call setespot(nshell,qsh,jab,ves)
!  compute potential intermediates
   call setvsdq(xtbData%multipole,n,at,xyz,q,dipm,qp,gab3,gab5,vs,vd,vq)

!  end of SCC convergence part

!! ------------------------------------------------------------------------
   if (econverged.and.qconverged) then
      converged = .true.
      if (lastdiag) exit scc_iterator
      lastdiag = .true.
   endif
!! ------------------------------------------------------------------------

   enddo scc_iterator

   jter = jter + min(iter,thisiter)
   fail = .not.converged

end subroutine scc_gfn2

!! ========================================================================
!  H0 off-diag scaling
!! ========================================================================
subroutine h0scal(hData,n,at,i,j,il,jl,iat,jat,valaoi,valaoj, &
   &              km)
   type(THamiltonianData), intent(in) :: hData
   integer, intent(in)  :: n
   integer, intent(in)  :: at(n)
   integer, intent(in)  :: i
   integer, intent(in)  :: j
   integer, intent(in)  :: il
   integer, intent(in)  :: jl
   integer, intent(in)  :: iat
   integer, intent(in)  :: jat
   logical, intent(in)  :: valaoi
   logical, intent(in)  :: valaoj
   real(wp),intent(out) :: km
   integer  :: ii,jj
   real(wp) :: den, enpoly

   km = 0.0_wp

!  valence
   if(valaoi.and.valaoj) then
      ii=at(iat)
      jj=at(jat)
      den=(hData%electronegativity(ii)-hData%electronegativity(jj))**2
      enpoly = (1.0_wp+hData%enScale(jl-1,il-1)*den*(1.0_wp+hData%enScale4*den))
      km=hData%kScale(jl-1,il-1)*enpoly*hData%pairParam(ii,jj)
      return
   endif

!  "DZ" functions (on H for GFN or 3S for EA calc on all atoms)
   if((.not.valaoi).and.(.not.valaoj)) then
      km=hData%kDiff
      return
   endif
   if(.not.valaoi.and.valaoj) then
      km=0.5*(hData%kScale(jl-1,jl-1)+hData%kDiff)
      return
   endif
   if(.not.valaoj.and.valaoi) then
      km=0.5*(hData%kScale(il-1,il-1)+hData%kDiff)
   endif


end subroutine h0scal

!! ========================================================================
!  total energy for GFN1
!! ========================================================================
pure subroutine electro(n,at,nbf,nshell,gab,H0,P,dq,gam3at,dqsh,es,scc)
   use xtb_mctc_convert, only : evtoau
   integer, intent(in) :: n
   integer, intent(in) :: at(n)
   integer, intent(in) :: nbf
   integer, intent(in) :: nshell
   real(wp),intent(in)  :: H0(nbf*(nbf+1)/2)
   real(wp),intent(in)  :: P (nbf,nbf)
   real(wp),intent(in)  :: gab(nshell,nshell)
   real(wp),intent(in)  :: dq(n)
   real(wp),intent(in)  :: gam3at(n)
   real(wp),intent(in)  :: dqsh(nshell)
   real(wp),intent(out) :: es
   real(wp),intent(out) :: scc
   real(wp) :: ehb ! not used

   integer  :: i,j,k
   real(wp) :: h,t

!  second order non-diagonal
   es =0.0d0
   do i=1,nshell-1
      do j=i+1,nshell
         es =es + dqsh(i)*dqsh(j)*gab(j,i)
      enddo
   enddo

   es=es*2.0_wp

!  second-order diagonal term
   do i=1,nshell
      es =es + dqsh(i)*dqsh(i)*gab(i,i)
   enddo

   t=0.0_wp
   do i=1,n
!     third-order diagonal term
      t = t + gam3at(i)*dq(i)**3
   enddo

!  ES energy in Eh (gam3 in Eh)
   es=0.50_wp*es*evtoau+t/3.0_wp

!  H0 part
   k=0
   h=0.0_wp
   do i=1,nbf
      do j=1,i-1
         k=k+1
         h=h+P(j,i)*H0(k)
      enddo
      k=k+1
      h=h+P(i,i)*H0(k)*0.5_wp
   enddo

!  Etotal in Eh
   scc = es + 2.0_wp*h*evtoau

end subroutine electro

!! ========================================================================
!  total energy for GFN2
!! ========================================================================
pure subroutine electro2(n,at,nbf,nshell,gab,H0,P,q,  &
   &                     gam3sh,dqsh,es,scc)
   use xtb_mctc_constants, only : pi
   use xtb_mctc_convert, only : evtoau
   integer,intent(in)  :: n
   integer,intent(in)  :: at(n)
   integer,intent(in)  :: nbf
   integer,intent(in)  :: nshell
   real(wp), intent(in)  :: H0(nbf*(nbf+1)/2)
   real(wp), intent(in)  :: P (nbf,nbf)
   real(wp), intent(in)  :: q (n) ! not used
   real(wp), intent(in)  :: gab(nshell,nshell)
   real(wp), intent(in)  :: gam3sh(nshell)
   real(wp), intent(in)  :: dqsh(nshell)
   real(wp), intent(out) :: scc
   real(wp), intent(out) :: es
   real(wp) :: ehb ! not used

   integer :: i,j,k
   real(wp)  :: h,t,esie

!  second order non-diagonal
   es =0.0d0
   do i=1,nshell-1
      do j=i+1,nshell
         es =es + dqsh(i)*dqsh(j)*gab(j,i)
      enddo
   enddo

   es=es*2.0d0

!  second-order diagonal term
   do i=1,nshell
      es =es + dqsh(i)*dqsh(i)*gab(i,i)
   enddo

   t=0.0d0
   do i=1,nshell
!     third-order diagonal term
      t = t + gam3sh(i)*dqsh(i)**3
   enddo

!  SIE diagonal term
!  esie=0
!  do i=1,n
!     esie=esie+gsie(at(i))*(sin(pi*q(i)))**2
!  enddo

!  ES energy in Eh (gam3 in Eh)
   es=0.50d0*es*evtoau+t/3.0d0

!  H0 part
   k=0
   h=0.0d0
   do i=1,nbf
      do j=1,i-1
         k=k+1
         h=h+P(j,i)*H0(k)
      enddo
      k=k+1
      h=h+P(i,i)*H0(k)*0.5d0
   enddo

!  Etotal in Eh
   scc = es + 2.0d0*h*evtoau

end subroutine electro2


!! ========================================================================
!  GBSA related subroutine
!! ========================================================================
pure subroutine electro_gbsa(n,at,gab,fhb,dqsh,es,scc)
   use xtb_mctc_convert, only : evtoau
   use xtb_solv_gbobc, only: lhb
   integer, intent(in)  :: n
   integer, intent(in)  :: at(n)
   real(wp),intent(in)  :: gab(n,n)
   real(wp),intent(in)  :: fhb(n)
   real(wp),intent(in)  :: dqsh(n)
   real(wp),intent(out) :: es
   real(wp),intent(inout) :: scc

   integer :: i,j,k
   real(wp)  :: h,t
   real(wp)  :: ehb

!  second order non-diagonal
   es =0
   do i=1,n-1
      do j=i+1,n
         es =es + dqsh(i)*dqsh(j)*gab(j,i)
      enddo
   enddo

   es=es*2.0d0

!  second-order diagonal term + HB contribution
   do i=1,n
      es =es + dqsh(i)*dqsh(i)*gab(i,i)
   enddo

!  HB energy
   ehb=0.d0
   if(lhb)then
      do i = 1, n
!        ehb = ehb + fhb(i)*(dqsh(i)**2)**c3
         ehb = ehb + fhb(i)*(dqsh(i)**2)
      enddo
   endif

!  ES energy in Eh
   es=0.5*es*evtoau

!  HB energy in Eh
   ehb=ehb*evtoau

!  Etotal in Eh
   scc = scc + es + ehb

end subroutine electro_gbsa

!! ========================================================================
!  S(R) enhancement factor
!! ========================================================================
pure function shellPoly(iPoly,jPoly,iRad,jRad,xyz1,xyz2)
   use xtb_mctc_convert, only : aatoau
   real(wp), intent(in) :: iPoly,jPoly
   real(wp), intent(in) :: iRad,jRad
   real(wp), intent(in) :: xyz1(3),xyz2(3)
   real(wp) :: shellPoly
   real(wp) :: rab,k1,rr,r,rf1,rf2,dx,dy,dz,a

   a=0.5           ! R^a dependence 0.5 in GFN1

   dx=xyz1(1)-xyz2(1)
   dy=xyz1(2)-xyz2(2)
   dz=xyz1(3)-xyz2(3)

   rab=sqrt(dx**2+dy**2+dz**2)

   ! this sloppy conv. factor has been used in development, keep it
   rr=jRad+iRad

   r=rab/rr

   rf1=1.0d0+0.01*iPoly*r**a
   rf2=1.0d0+0.01*jPoly*r**a

   shellPoly= rf1*rf2

end function shellPoly

!! ========================================================================
!  set up Coulomb potential due to 2nd order fluctuation
!! ========================================================================
pure subroutine setespot(nshell,qsh,jab,ves)
   integer, intent(in) :: nshell
   real(wp),intent(in) ::  qsh(nshell),jab(nshell,nshell)
!  ves possibly already contains with PC-potential
   real(wp),intent(inout) :: ves(nshell)
   real(wp) :: qshi,vesi
   integer  :: i,j,k
   do i=1,nshell
      qshi=qsh(i)
      vesi=0.0_wp
      do j=1,i-1
         ves(j)=ves(j)+qshi*jab(j,i)
         vesi=vesi+qsh(j)*jab(j,i)
      enddo
      vesi=vesi+qshi*jab(i,i)
      ves(i)=ves(i)+vesi
   enddo
end subroutine setespot

pure subroutine jpot_gfn1(jData,nat,nshell,ash,lsh,at,sqrab,alphaj,jab)
   use xtb_mctc_convert
   use xtb_lin
   type(TCoulombData), intent(in) :: jData
   integer, intent(in) :: nat
   integer, intent(in) :: nshell
   integer, intent(in) :: ash(nshell)
   integer, intent(in) :: lsh(nshell)
   integer, intent(in) :: at(nat)
   real(wp),intent(in) :: sqrab(nat*(nat+1)/2)
   real(wp),intent(in) :: alphaj
   real(wp),intent(inout) :: jab(nshell,nshell)

   integer  :: is,iat,ati,js,jat,atj,k
   real(wp) :: gi,gj,xj,rab

   do is=1,nshell
      iat=ash(is)
      ati=at(iat)
      gi=jData%chemicalHardness(ati)*(1.0_wp+jData%shellHardness(1+lsh(is),ati))
      do js=1,is
         jat=ash(js)
         atj=at(jat)
         k=lin(jat,iat)
         gj=jData%chemicalHardness(atj)*(1.0_wp+jData%shellHardness(1+lsh(js),atj))
         xj=2.0_wp/(1./gi+1./gj)
         if(is.eq.js)then
            jab(is,js)=xj*autoev
         else
            rab=sqrt(sqrab(k))
            jab(js,is)=autoev/(rab**alphaj &
               &  + 1._wp/xj**alphaj)**(1._wp/alphaj)
            jab(is,js)=jab(js,is)
         endif
      enddo
   enddo

end subroutine jpot_gfn1

pure subroutine jpot_gfn2(jData,nat,nshell,ash,lsh,at,sqrab,jab)
   use xtb_mctc_convert
   use xtb_lin
   type(TCoulombData), intent(in) :: jData
   integer, intent(in) :: nat
   integer, intent(in) :: nshell
   integer, intent(in) :: ash(nshell)
   integer, intent(in) :: lsh(nshell)
   integer, intent(in) :: at(nat)
   real(wp),intent(in) :: sqrab(nat*(nat+1)/2)
   real(wp),intent(inout) :: jab(nshell,nshell)

   integer  :: is,iat,ati,js,jat,atj,k
   real(wp) :: gi,gj,xj,rab

   do is=1,nshell
      iat=ash(is)
      ati=at(iat)
      gi=jData%chemicalHardness(ati)*(1.0_wp+jData%shellHardness(1+lsh(is),ati))
      do js=1,is-1
         jat=ash(js)
         atj=at(jat)
         k=lin(jat,iat)
         gj=jData%chemicalHardness(atj)*(1.0_wp+jData%shellHardness(1+lsh(js),atj))
         xj=0.5_wp*(gi+gj)
         jab(js,is)=autoev/sqrt(sqrab(k)+1._wp/xj**2)
         ! jab(js,is)=autoev/sqrt(sqrab(k)+1._wp/(gi*gj))  ! NEWAV
         jab(is,js)=jab(js,is)
      enddo
      jab(is,is)=autoev*gi
   enddo

end subroutine jpot_gfn2

!! ========================================================================
!  eigenvalue solver single-precision
!! ========================================================================
subroutine solve4(full,ndim,ihomo,acc,H,S,X,P,e,fail)
   use xtb_mctc_accuracy, only : sp
   integer, intent(in)   :: ndim
   logical, intent(in)   :: full
   integer, intent(in)   :: ihomo
   real(wp),intent(inout):: H(ndim,ndim)
   real(wp),intent(in)   :: S(ndim,ndim)
   real(wp),intent(out)  :: X(ndim,ndim)
   real(wp),intent(out)  :: P(ndim,ndim)
   real(wp),intent(out)  :: e(ndim)
   real(wp),intent(in)   :: acc
   logical, intent(out)  :: fail

   integer i,j,info,lwork,liwork,nfound,iu,nbf
   integer, allocatable :: iwork(:),ifail(:)
   real(wp),allocatable :: aux  (:)
   real(wp) w0,w1,t0,t1

   real(sp),allocatable :: H4(:,:)
   real(sp),allocatable :: S4(:,:)
   real(sp),allocatable :: X4(:,:)
   real(sp),allocatable :: P4(:,:)
   real(sp),allocatable :: e4(:)
   real(sp),allocatable :: aux4(:)


   allocate(H4(ndim,ndim),S4(ndim,ndim))
   allocate(X4(ndim,ndim),P4(ndim,ndim),e4(ndim))

   H4 = H
   S4 = S

   fail =.false.
!  standard first full diag call
   if(full) then
!                                                     call timing(t0,w0)
!     if(ndim.gt.0)then
!     USE DIAG IN NON-ORTHORGONAL BASIS
      allocate (aux4(1),iwork(1),ifail(ndim))
      P4 = s4
      call sygvd(1,'v','u',ndim,h4,ndim,p4,ndim,e4,aux4, &!workspace query
     &           -1,iwork,liwork,info)
      lwork=int(aux4(1))
      liwork=iwork(1)
      deallocate(aux4,iwork)
      allocate (aux4(lwork),iwork(liwork))              !do it
      call sygvd(1,'v','u',ndim,h4,ndim,p4,ndim,e4,aux4, &
     &           lwork,iwork,liwork,info)
      if(info.ne.0) then
         fail=.true.
         return
      endif
      X4 = H4 ! save
      deallocate(aux4,iwork,ifail)

!     else
!        USE DIAG IN ORTHOGONAL BASIS WITH X=S^-1/2 TRAFO
!        nbf = ndim
!        lwork  = 1 + 6*nbf + 2*nbf**2
!        allocate (aux(lwork))
!        call gemm('N','N',nbf,nbf,nbf,1.0d0,H,nbf,X,nbf,0.0d0,P,nbf)
!        call gemm('T','N',nbf,nbf,nbf,1.0d0,X,nbf,P,nbf,0.0d0,H,nbf)
!        call SYEV('V','U',nbf,H,nbf,e,aux,lwork,info)
!        if(info.ne.0) error stop 'diag error'
!        call gemm('N','N',nbf,nbf,nbf,1.0d0,X,nbf,H,nbf,0.0d0,P,nbf)
!        H = P
!        deallocate(aux)
!     endif
!                                                     call timing(t1,w1)
!                                    call prtime(6,t1-t0,w1-w0,'dsygvd')

   else
!                                                     call timing(t0,w0)
!     go to MO basis using trafo(X) from first iteration (=full diag)
!      call gemm('N','N',ndim,ndim,ndim,1.d0,H4,ndim,X4,ndim,0.d0,P4,ndim)
!      call gemm('T','N',ndim,ndim,ndim,1.d0,X4,ndim,P4,ndim,0.d0,H4,ndim)
!                                                     call timing(t1,w1)
!                       call prtime(6,1.5*(t1-t0),1.5*(w1-w0),'3xdgemm')
!                                                     call timing(t0,w0)
!      call pseudodiag(ndim,ihomo,H4,e4)
!                                                     call timing(t1,w1)
!                                call prtime(6,t1-t0,w1-w0,'pseudodiag')

!     C = X C', P=scratch
!      call gemm('N','N',ndim,ndim,ndim,1.d0,X4,ndim,H4,ndim,0.d0,P4,ndim)
!     save and output MO matrix in AO basis
!      H4 = P4
   endif

   H = H4
   P = P4
   X = X4
   e = e4

   deallocate(e4,P4,X4,S4,H4)

end subroutine solve4

!! ========================================================================
!  eigenvalue solver
!! ========================================================================
subroutine solve(full,ndim,ihomo,acc,H,S,X,P,e,fail)
   integer, intent(in)   :: ndim
   logical, intent(in)   :: full
   integer, intent(in)   :: ihomo
   real(wp),intent(inout):: H(ndim,ndim)
   real(wp),intent(in)   :: S(ndim,ndim)
   real(wp),intent(out)  :: X(ndim,ndim)
   real(wp),intent(out)  :: P(ndim,ndim)
   real(wp),intent(out)  :: e(ndim)
   real(wp),intent(in)   :: acc
   logical, intent(out)  :: fail

   integer i,j,info,lwork,liwork,nfound,iu,nbf
   integer, allocatable :: iwork(:),ifail(:)
   real(wp),allocatable :: aux  (:)
   real(wp) w0,w1,t0,t1

   fail =.false.

!  standard first full diag call
   if(full) then
!                                                     call timing(t0,w0)
!     if(ndim.gt.0)then
!     USE DIAG IN NON-ORTHORGONAL BASIS
      allocate (aux(1),iwork(1),ifail(ndim))
      P = s
      call sygvd(1,'v','u',ndim,h,ndim,p,ndim,e,aux, &!workspace query
     &           -1,iwork,liwork,info)
      lwork=int(aux(1))
      liwork=iwork(1)
      deallocate(aux,iwork)
      allocate (aux(lwork),iwork(liwork))              !do it
      call sygvd(1,'v','u',ndim,h,ndim,p,ndim,e,aux, &
     &           lwork,iwork,liwork,info)
      !write(*,*)'SYGVD INFO', info
      if(info.ne.0) then
         fail=.true.
         return
      endif
      X = H ! save
      deallocate(aux,iwork,ifail)

!     else
!        USE DIAG IN ORTHOGONAL BASIS WITH X=S^-1/2 TRAFO
!        nbf = ndim
!        lwork  = 1 + 6*nbf + 2*nbf**2
!        allocate (aux(lwork))
!        call gemm('N','N',nbf,nbf,nbf,1.0d0,H,nbf,X,nbf,0.0d0,P,nbf)
!        call gemm('T','N',nbf,nbf,nbf,1.0d0,X,nbf,P,nbf,0.0d0,H,nbf)
!        call SYEV('V','U',nbf,H,nbf,e,aux,lwork,info)
!        if(info.ne.0) error stop 'diag error'
!        call gemm('N','N',nbf,nbf,nbf,1.0d0,X,nbf,H,nbf,0.0d0,P,nbf)
!        H = P
!        deallocate(aux)
!     endif
!                                                     call timing(t1,w1)
!                                    call prtime(6,t1-t0,w1-w0,'dsygvd')

   else
!                                                     call timing(t0,w0)
!     go to MO basis using trafo(X) from first iteration (=full diag)
      call gemm('N','N',ndim,ndim,ndim,1.d0,H,ndim,X,ndim,0.d0,P,ndim)
      call gemm('T','N',ndim,ndim,ndim,1.d0,X,ndim,P,ndim,0.d0,H,ndim)
!                                                     call timing(t1,w1)
!                       call prtime(6,1.5*(t1-t0),1.5*(w1-w0),'3xdgemm')
!                                                     call timing(t0,w0)
      call pseudodiag(ndim,ihomo,H,e)
!                                                     call timing(t1,w1)
!                                call prtime(6,t1-t0,w1-w0,'pseudodiag')

!     C = X C', P=scratch
      call gemm('N','N',ndim,ndim,ndim,1.d0,X,ndim,H,ndim,0.d0,P,ndim)
!     save and output MO matrix in AO basis
      H = P
   endif

end subroutine solve

subroutine fermismear(prt,norbs,nel,t,eig,occ,fod,e_fermi,s)
   use xtb_mctc_convert, only : autoev
   use xtb_mctc_constants, only : kB
   integer, intent(in)  :: norbs
   integer, intent(in)  :: nel
   real(wp),intent(in)  :: eig(norbs)
   real(wp),intent(out) :: occ(norbs)
   real(wp),intent(in)  :: t
   real(wp),intent(out) :: fod
   real(wp),intent(out) :: e_fermi
   logical, intent(in)  :: prt

   real(wp) :: boltz,bkt,occt,total_number,thr
   real(wp) :: total_dfermi,dfermifunct,fermifunct,s,change_fermi

   parameter (boltz = kB*autoev)
   parameter (thr   = 1.d-9)
   integer :: ncycle,i,j,m,k,i1,i2

   bkt = boltz*t

   e_fermi = 0.5*(eig(nel)+eig(nel+1))
   occt=nel

   do ncycle = 1, 200  ! this loop would be possible instead of gotos
      total_number = 0.0
      total_dfermi = 0.0
      do i = 1, norbs
         fermifunct = 0.0
         if((eig(i)-e_fermi)/bkt.lt.50) then
            fermifunct = 1.0/(exp((eig(i)-e_fermi)/bkt)+1.0)
            dfermifunct = exp((eig(i)-e_fermi)/bkt) / &
            &       (bkt*(exp((eig(i)-e_fermi)/bkt)+1.0)**2)
         else
            dfermifunct = 0.0
         end if
         occ(i) = fermifunct
         total_number = total_number + fermifunct
         total_dfermi = total_dfermi + dfermifunct
      end do
      change_fermi = (occt-total_number)/total_dfermi
      e_fermi = e_fermi+change_fermi
      if (abs(occt-total_number).le.thr) exit
   enddo

   fod=0
   s  =0
   do i=1,norbs
      if(occ(i).gt.thr.and.1.0d00-occ(i).gt.thr) &
      &   s=s+occ(i)*log(occ(i))+(1.0d0-occ(i))*log(1.0d00-occ(i))
      if (eig(i).lt.e_fermi) then
         fod=fod+1.0d0-occ(i)
      else
         fod=fod+      occ(i)
      endif
   enddo
   s=s*kB*t

   if (prt) then
      write(*,'('' t,e(fermi),nfod : '',2f10.3,f10.6)') t,e_fermi,fod
   endif

end subroutine fermismear

subroutine occ(ndim,nel,nopen,ihomo,focc)
   integer  :: nel
   integer  :: nopen
   integer  :: ndim
   integer  :: ihomo
   real(wp) :: focc(ndim)
   integer  :: i,na,nb

   focc=0
!  even nel
   if(mod(nel,2).eq.0)then
      ihomo=nel/2
      do i=1,ihomo
         focc(i)=2.0d0
      enddo
      if(2*ihomo.ne.nel) then
         ihomo=ihomo+1
         focc(ihomo)=1.0d0
         if(nopen.eq.0)nopen=1
      endif
      if(nopen.gt.1)then
         do i=1,nopen/2
            focc(ihomo-i+1)=focc(ihomo-i+1)-1.0
            focc(ihomo+i)=focc(ihomo+i)+1.0
         enddo
      endif
!  odd nel
   else
      na=nel/2+(nopen-1)/2+1
      nb=nel/2-(nopen-1)/2
      do i=1,na
         focc(i)=focc(i)+1.
      enddo
      do i=1,nb
         focc(i)=focc(i)+1.
      enddo
   endif

   do i=1,ndim
      if(focc(i).gt.0.99) ihomo=i
   enddo

end subroutine occ

subroutine occu(ndim,nel,nopen,ihomoa,ihomob,focca,foccb)
   integer  :: nel
   integer  :: nopen
   integer  :: ndim
   integer  :: ihomoa
   integer  :: ihomob
   real(wp) :: focca(ndim)
   real(wp) :: foccb(ndim)
   integer  :: focc(ndim)
   integer  :: i,na,nb,ihomo

   focc=0
   focca=0
   foccb=0
!  even nel
   if(mod(nel,2).eq.0)then
      ihomo=nel/2
      do i=1,ihomo
         focc(i)=2
      enddo
      if(2*ihomo.ne.nel) then
         ihomo=ihomo+1
         focc(ihomo)=1
         if(nopen.eq.0)nopen=1
      endif
      if(nopen.gt.1)then
         do i=1,nopen/2
            focc(ihomo-i+1)=focc(ihomo-i+1)-1
            focc(ihomo+i)=focc(ihomo+i)+1
         enddo
      endif
!  odd nel
   else
      na=nel/2+(nopen-1)/2+1
      nb=nel/2-(nopen-1)/2
      do i=1,na
         focc(i)=focc(i)+1
      enddo
      do i=1,nb
         focc(i)=focc(i)+1
      enddo
   endif

   do i=1,ndim
      if(focc(i).eq.2)then
         focca(i)=1.0d0
         foccb(i)=1.0d0
      endif
      if(focc(i).eq.1)focca(i)=1.0d0
   enddo

   ihomoa=0
   ihomob=0
   do i=1,ndim
      if(focca(i).gt.0.99) ihomoa=i
      if(foccb(i).gt.0.99) ihomob=i
   enddo

end subroutine occu


!ccccccccccccccccccccccccccccccccccccccccccccc
! density matrix
! C: MO coefficient
! X: scratch
! P  dmat
!ccccccccccccccccccccccccccccccccccccccccccccc

subroutine dmat(ndim,focc,C,P)
   use xtb_mctc_la, only : gemm
   integer, intent(in)  :: ndim
   real(wp),intent(in)  :: focc(*)
   real(wp),intent(in)  :: C(ndim,ndim)
   real(wp),intent(out) :: P(ndim,ndim)
   integer :: i,m
   real(wp),allocatable :: Ptmp(:,:)

   allocate( Ptmp(ndim,ndim), source = 0.0_wp )

   do m=1,ndim
      do i=1,ndim
         Ptmp(i,m)=C(i,m)*focc(m)
      enddo
   enddo
   call gemm('n','t',ndim,ndim,ndim,1.0_wp,C,ndim,Ptmp,ndim,0.0_wp,P,ndim)

   deallocate(Ptmp)

end subroutine dmat

subroutine get_wiberg(n,ndim,at,xyz,P,S,wb,fila2)
   use xtb_mctc_la, only : gemm
   integer, intent(in)  :: n,ndim,at(n)
   real(wp),intent(in)  :: xyz(3,n)
   real(wp),intent(in)  :: P(ndim,ndim)
   real(wp),intent(in)  :: S(ndim,ndim)
   real(wp),intent(out) :: wb (n,n)
   integer, intent(in)  :: fila2(:,:)

   real(wp),allocatable :: Ptmp(:,:)
   real(wp) xsum,rab
   integer i,j,k,m

   allocate(Ptmp(ndim,ndim))
   call gemm('N','N',ndim,ndim,ndim,1.0d0,P,ndim,S,ndim,0.0d0,Ptmp,ndim)
   wb = 0
   do i = 1, n
      do j = 1, i-1
         xsum = 0.0_wp
         rab = sum((xyz(:,i) - xyz(:,j))**2)
         if(rab < 100.0_wp)then
            do k = fila2(1,i), fila2(2,i) ! AOs on atom i
               do m = fila2(1,j), fila2(2,j) ! AOs on atom j
                  xsum = xsum + Ptmp(k,m)*Ptmp(m,k)
               enddo
            enddo
         endif
         wb(i,j) = xsum
         wb(j,i) = xsum
      enddo
   enddo
   deallocate(Ptmp)

end subroutine get_wiberg

!cccccccccccccccccccccccccccccccccccccccc
!c Mulliken pop + AO pop
!cccccccccccccccccccccccccccccccccccccccc

subroutine mpopall(n,nao,aoat,S,P,qao,q)
   integer nao,n,aoat(nao)
   real(wp)  S (nao,nao)
   real(wp)  P (nao,nao)
   real(wp)  qao(nao),q(n),ps

   integer i,j,ii,jj,ij,is,js

   q  = 0
   qao= 0
   do i=1,nao
      ii=aoat(i)
      do j=1,i-1
         jj=aoat(j)
         ps=p(j,i)*s(j,i)
         q(ii)=q(ii)+ps
         q(jj)=q(jj)+ps
         qao(i)=qao(i)+ps
         qao(j)=qao(j)+ps
      enddo
      ps=p(i,i)*s(i,i)
      q(ii)=q(ii)+ps
      qao(i)=qao(i)+ps
   enddo

end subroutine mpopall

!cccccccccccccccccccccccccccccccccccccccc
!c Mulliken pop
!cccccccccccccccccccccccccccccccccccccccc

subroutine mpop0(n,nao,aoat,S,P,q)
   integer nao,n,aoat(nao)
   real(wp)  S (nao,nao)
   real(wp)  P (nao,nao)
   real(wp)  q(n),ps

   integer i,j,ii,jj,ij,is,js

   q = 0
   do i=1,nao
      ii=aoat(i)
      do j=1,i-1
         jj=aoat(j)
         ps=p(j,i)*s(j,i)
         q(ii)=q(ii)+ps
         q(jj)=q(jj)+ps
      enddo
      ps=p(i,i)*s(i,i)
      q(ii)=q(ii)+ps
   enddo

end subroutine mpop0

!cccccccccccccccccccccccccccccccccccccccc
!c Mulliken AO pop
!cccccccccccccccccccccccccccccccccccccccc

subroutine mpopao(n,nao,S,P,qao)
   integer nao,n
   real(wp)  S (nao,nao)
   real(wp)  P (nao,nao)
   real(wp)  qao(nao),ps

   integer i,j

   qao = 0
   do i=1,nao
      do j=1,i-1
         ps=p(j,i)*s(j,i)
         qao(i)=qao(i)+ps
         qao(j)=qao(j)+ps
      enddo
      ps=p(i,i)*s(i,i)
      qao(i)=qao(i)+ps
   enddo

end subroutine mpopao

!cccccccccccccccccccccccccccccccccccccccc
!c Mulliken pop
!cccccccccccccccccccccccccccccccccccccccc

subroutine mpop(n,nao,aoat,lao,S,P,q,ql)
   integer nao,n,aoat(nao),lao(nao)
   real(wp)  S (nao,nao)
   real(wp)  P (nao,nao)
   real(wp)  q(n),ps
   real(wp)  ql(3,n)

   integer i,j,ii,jj,ij,is,js,mmm(20)
   data    mmm/1,2,2,2,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,4/

   ql= 0
   q = 0
   do i=1,nao
      ii=aoat(i)
      is=mmm(lao(i))
      do j=1,i-1
         jj=aoat(j)
         js=mmm(lao(j))
         ps=p(j,i)*s(j,i)
         q(ii)=q(ii)+ps
         q(jj)=q(jj)+ps
         ql(is,ii)=ql(is,ii)+ps
         ql(js,jj)=ql(js,jj)+ps
      enddo
      ps=p(i,i)*s(i,i)
      q(ii)=q(ii)+ps
      ql(is,ii)=ql(is,ii)+ps
   enddo

end subroutine mpop

!cccccccccccccccccccccccccccccccccccccccc
!c Mulliken pop shell wise
!cccccccccccccccccccccccccccccccccccccccc

subroutine mpopsh(n,nao,nshell,ao2sh,S,P,qsh)
   integer nao,n,nshell,ao2sh(nao)
   real(wp)  S (nao,nao)
   real(wp)  P (nao,nao)
   real(wp)  qsh(nshell),ps

   integer i,j,ii,jj,ij

   qsh=0
   do i=1,nao
      ii =ao2sh(i)
      do j=1,i-1
         jj =ao2sh(j)
         ps=p(j,i)*s(j,i)
         qsh(ii)=qsh(ii)+ps
         qsh(jj)=qsh(jj)+ps
      enddo
      ps=p(i,i)*s(i,i)
      qsh(ii)=qsh(ii)+ps
   enddo

end subroutine mpopsh

subroutine qsh2qat(ash,qsh,qat)
   integer, intent(in) :: ash(:)
   real(wp), intent(in) :: qsh(:)
   real(wp), intent(out) :: qat(:)

   integer :: iSh

   qat(:) = 0.0_wp
   do iSh = 1, size(qsh)
      qat(ash(iSh)) = qat(ash(iSh)) + qsh(iSh)
   enddo

end subroutine qsh2qat


!cccccccccccccccccccccccccccccccccccccccc
!c Loewdin pop
!cccccccccccccccccccccccccccccccccccccccc

subroutine lpop(n,nao,aoat,lao,occ,C,f,q,ql)
   integer nao,n,aoat(nao),lao(nao)
   real(wp)  C (nao,nao)
   real(wp)  occ(nao)
   real(wp)  q(n)
   real(wp)  ql(3,n)
   real(wp)  f

   integer i,j,ii,jj,js,mmm(20)
   data    mmm/1,2,2,2,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,4/
   real(wp)  cc

   do i=1,nao
      if(occ(i).lt.1.d-8) cycle
      do j=1,nao
         cc=f*C(j,i)*C(j,i)*occ(i)
         jj=aoat(j)
         js=mmm(lao(j))
         q(jj)=q(jj)+cc
         ql(js,jj)=ql(js,jj)+cc
      enddo
   enddo

end subroutine lpop

!cccccccccccccccccccccccccccccccccccccccccccccccccccc
!c atomic valence shell pops and total atomic energy
!cccccccccccccccccccccccccccccccccccccccccccccccccccc

subroutine iniqshell(xtbData,n,at,z,nshell,q,qsh,gfn_method)
   type(TxTBData), intent(in) :: xtbData
   integer, intent(in)  :: n
   integer, intent(in)  :: at(n)
   integer, intent(in)  :: nshell
   integer, intent(in)  :: gfn_method
   real(wp),intent(in)  :: z(n)
   real(wp),intent(in)  :: q(n)
   real(wp),intent(out) :: qsh(nshell)
   real(wp) :: zshell
   real(wp) :: ntot,fracz
   integer  :: i,j,k,m,l,ll(0:3),iat,lll,iver
   data ll /1,3,5,7/

   qsh = 0.0_wp

   k=0
   do i=1,n
      iat=at(i)
      ntot=-1.d-6
      do m=1,xtbData%nShell(iat)
         l=xtbData%hamiltonian%angShell(m,iat)
         k=k+1
         zshell=xtbData%hamiltonian%referenceOcc(m,iat)
         ntot=ntot+zshell
         if(ntot.gt.z(i)) zshell=0
         fracz=zshell/z(i)
         qsh(k)=fracz*q(i)
      enddo
   enddo

end subroutine iniqshell


subroutine setzshell(xtbData,n,at,nshell,z,zsh,e,gfn_method)
   type(TxTBData), intent(in) :: xtbData
   integer, intent(in)  :: n
   integer, intent(in)  :: at(n)
   integer, intent(in)  :: nshell
   integer, intent(in)  :: gfn_method
   real(wp),intent(in)  :: z(n)
   real(wp),intent(out) :: zsh(nshell)
!   integer, intent(out) :: ash(nshell)
!   integer, intent(out) :: lsh(nshell)
   real(wp),intent(out) :: e

   real(wp)  ntot,fracz
   integer i,j,k,m,l,ll(0:3),iat,lll,iver
   data ll /1,3,5,7/

   k=0
   e=0.0_wp
   do i=1,n
      iat=at(i)
      ntot=-1.d-6
      do m=1,xtbData%nShell(iat)
         l=xtbData%hamiltonian%angShell(m,iat)
         k=k+1
         zsh(k)=xtbData%hamiltonian%referenceOcc(m,iat)
!         lsh(k)=l
!         ash(k)=i
         ntot=ntot+zsh(k)
         if(ntot.gt.z(i)) zsh(k)=0
         e=e+xtbData%hamiltonian%selfEnergy(m,iat)*zsh(k)
      enddo
   enddo

end subroutine setzshell

!cccccccccccccccccccccccccccccccccccccccccccccccccccc

end module xtb_scc_core

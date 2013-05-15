program testnavier3d
  use command_line
  use class_navier_3D
!$ use OMP_LIB
  implicit none
  type(cmd_line) :: cmd
  type(navier3d) :: nav
  type(mpi_data) :: mpid
  integer(ik) :: nx,ny,nz
  integer(ik) :: ite
  integer(ik) :: i,j,k,iaux
  real(rk),allocatable :: uex(:,:,:,:), pex(:,:,:)
  real(rk) ::x,y,z,t,error,aux,time,ref,errort
  integer(8) :: t1,t2,irate,subite
  logical :: test


  !-> get command line informations
  call commandline(cmd)

  allocate(uex(cmd%nx,cmd%ny,cmd%nz,3),pex(cmd%nx,cmd%ny,cmd%nz))

  !------------------------------------------------------------------------ 
  !-> pre-computation
  !------------------------------------------------------------------------ 
  call navier_initialization(cmd,mpid,nav)

  !-> write mesh
  call write_mesh('grid_x',nav%gridx,mpid)
  call write_mesh('grid_y',nav%gridy,mpid)
  call write_mesh('grid_z',nav%gridz,mpid)

  
  !-> read restart files if they exists
  call restart_read(mpid,nav)

  !------------------------------------------------------------------------ 
  !-> time loop
  !------------------------------------------------------------------------ 

call system_clock(t1,irate)
temps:  do ite=1,nav%ntime
     !print*,mpid%coord

     
     if (ite==20)  call system_clock(t1,irate)

     !-> time update
     call navier_time(nav)

!initialisation
     if(ite==1) then
     do iaux=0,nav%nt-1
     t=nav%time-(iaux+1)*nav%ts
!$OMP PARALLEL DO &
!$OMP DEFAULT(SHARED) PRIVATE(i,j,k,x,y,z) &
!$OMP SCHEDULE(RUNTIME)
     do k=1,nav%nz
        z=nav%gridz%grid1d(k)
        do j=1,nav%ny
           y=nav%gridy%grid1d(j)
           do i=1,nav%nx
             x=nav%gridx%grid1d(i)
             nav%u(nav%it(nav%nt-iaux))%f(i,j,k)=sol(x,y,z,t,'u',nav%rey)
             nav%v(nav%it(nav%nt-iaux))%f(i,j,k)=sol(x,y,z,t,'v',nav%rey)
             nav%w(nav%it(nav%nt-iaux))%f(i,j,k)=sol(x,y,z,t,'w',nav%rey)
             nav%p(nav%it(nav%nt-iaux))%f(i,j,k)=sol(x,y,z,t,'p',nav%rey)
!             if(nav%pt==1)
!             if(nav%pt==2)
             if(nav%pt==3) nav%phi(nav%it(nav%nt-iaux))%f(i,j,k)=nav%p(nav%it(nav%nt-iaux))%f(i,j,k)
!             if(nav%pt==4)
           enddo
        enddo
     enddo
!$OMP END PARALLEL DO
     enddo
     endif

     if (mpid%rank==0) print*,'Time : ',nav%time

subit:  do subite=1,nav%nsubite
     nav%subite=subite
     if (mpid%rank==0) print*,'Sub-iteration : ',subite

     !---------------------------------------------------------------------
!     if (mpid%rank==0) then
!        call color(ired);print'(a)','Time : ';call color(color_off)
!     endif
     !-> define bc
     call navier_bc_velocity(mpid,nav)
     
     !---------------------------------------------------------------------
     !-> compute rhs
     call navier_presolve_u(mpid,nav)
     call navier_presolve_v(mpid,nav)
     call navier_presolve_w(mpid,nav)

     !---------------------------------------------------------------------
     !-> solve intermediate u,v,w (pressure correction)

     if(nav%pt<=2) then
       if(nav%pt==1) call add_boundary_gradient(mpid,nav)
       call navier_solve_u(mpid,nav)
       call navier_solve_v(mpid,nav)
       call navier_solve_w(mpid,nav)
     endif

     call navier_presolve_phi(mpid,nav)
     call navier_bc_pressure(mpid,nav)

     !---------------------------------------------------------------------
     !-> solve pressure increment phi

     call navier_solve_phi(mpid,nav)

     !---------------------------------------------------------------------
     !-> compute u,v,w,p
     
     call navier_projection(mpid,nav)

     !---------------------------------------------------------------------
     !-> compute final u,v,w  (velocity correction)
     if(nav%pt>=3) then
       call navier_solve_u(mpid,nav)
       call navier_solve_v(mpid,nav)
       call navier_solve_w(mpid,nav)
     endif

     test=.false.
     if (subite>1) call testconv(mpid,nav,nav%u(nav%it(1)),&
                                          nav%v(nav%it(1)),&
                                          nav%w(nav%it(1)),&
                                          nav%p(nav%it(1)),&
                                          nav%sub_u,&
                                          nav%sub_v,&
                                          nav%sub_w,&
                                          nav%sub_p,nav%aux,test,1.d-9)
     if (test)     exit subit


     nav%sub_u=nav%u(nav%it(1))
     nav%sub_v=nav%v(nav%it(1))
     nav%sub_w=nav%w(nav%it(1))
     nav%sub_p=nav%p(nav%it(1))

     enddo subit

     !-> switch it
     iaux=nav%it(1)
     do i=1,nav%nt-1
       nav%it(i)=nav%it(i+1)
     enddo
     nav%it(nt)=iaux

     !---------------------------------------------------------------------
     !-> check solution

     t=nav%time
!$OMP PARALLEL DO &
!$OMP DEFAULT(SHARED) PRIVATE(i,j,k,x,y,z) &
!$OMP SCHEDULE(RUNTIME)
     do k=1,nav%nz
        do j=1,nav%ny
           do i=1,nav%nx
             x=nav%gridx%grid1d(i)
             y=nav%gridy%grid1d(j)
             z=nav%gridz%grid1d(k)
             uex(i,j,k,1)=sol(x,y,z,t,'u',nav%rey)
             uex(i,j,k,2)=sol(x,y,z,t,'v',nav%rey)
             uex(i,j,k,3)=sol(x,y,z,t,'w',nav%rey)
             pex(i,j,k)=sol(x,y,z,t,'p',nav%rey)
           enddo
        enddo
     enddo
!$OMP END PARALLEL DO
 
     nav%aux%f=0._rk
     nav%aux=derx(nav%dcx,nav%u(nav%it(nav%nt)))+&
          dery(nav%dcy,nav%v(nav%it(nav%nt)))+&
          derz(nav%dcz,nav%w(nav%it(nav%nt)))

    call field_zero_edges(nav%aux)
    if (mpid%rank==0) then
       print*,mpid%rank,'DIV',&
            maxval(abs(nav%aux%f(2:nav%nx-1,2:nav%ny-1,2:nav%nz-1))),&
            sum(abs(nav%aux%f(2:nav%nx-1,2:nav%ny-1,2:nav%nz-1)))/&
            ((nav%nx-2)*(nav%ny-2)*(nav%nz-2))
    endif

    nav%aux%f=0._rk
    nav%aux=derx(nav%dcx,nav%phi(nav%it(nav%nt)))
!    nav%aux=derx(nav%dcx,nav%p(nav%it(nav%nt)))


!    error=maxval(abs(nav%u(nav%it(nav%nt))%f)&
!         -abs(nav%u(nav%it(nav%nt-1))%f))/nav%ts
    call err(nav%u(nav%it(nav%nt))%f,uex,nav%nx,nav%ny,nav%nz,error) 
    print*,'rank : ',mpid%rank,', error : ',error 
    if (mpid%rank==0) write(1000+mpid%rank,*)nav%time,error

  enddo temps
  call system_clock(t2,irate)
  time=real(t2-t1)/real(irate)
  print*,'rank : ',mpid%rank,', time : ',time

  call restart_write(mpid,nav)
  !------------------------------------------------------------------------ 
  !-> time loop end
  !------------------------------------------------------------------------ 

  if (mpid%rank==0) then
     aux=nav%p(nav%it(nav%nt))%f(nav%nx/2,nav%ny/2,nav%nz/2)-&
          pex(nav%nx/2,nav%ny/2,nav%nz/2)
  endif
  call md_mpi_bcast_double(mpid,aux,0)
  pex=pex+aux

  call err(nav%p(nav%it(nav%nt))%f,pex,nav%nx,nav%ny,nav%nz,error) 
  print*,'rank : ',mpid%rank,', error P : ',error 

  goto 100
  j=nav%ny/2
  do k=1,nav%nz
     do i=1,nav%nx
        write(10+mpid%rank,*)nav%gridx%grid1d(i),nav%gridz%grid1d(k),&
             nav%u(nav%it(nav%nt))%f(i,j,k),nav%p(nav%it(nav%nt))%f(i,j,k),&
             uex(i,j,k,1),nav%aux%f(i,j,k),pex(i,j,k)
     enddo
     write(10+mpid%rank,*)
  enddo
  close(10+mpid%rank)
100 continue

  goto 100
  k=nav%nz-1
  do j=1,nav%ny
     do i=1,nav%nx
!        write(10+mpid%rank,*)nav%gridx%grid1d(i),nav%gridy%grid1d(j),&
!             nav%v(nav%it(nav%nt))%f(i,j,k),nav%p(nav%it(nav%nt))%f(i,j,k),&
!             uex(i,j,k,1),nav%aux%f(i,j,k),pex(i,j,k)
        write(10+mpid%rank,'(20es17.8)')nav%gridx%grid1d(i),nav%gridy%grid1d(j),&
             nav%u(nav%it(nav%nt))%f(i,j,k),nav%v(nav%it(nav%nt))%f(i,j,k),&
             nav%w(nav%it(nav%nt))%f(i,j,k),nav%p(nav%it(nav%nt))%f(i,j,k),&
!             nav%w(nav%it(nav%nt))%f(i,j,k),nav%phi(nav%it(nav%nt))%f(i,j,k),&
             nav%aux%f(i,j,k),pex(i,j,k),&
             uex(i,j,k,1),uex(i,j,k,2),uex(i,j,k,3)
     enddo
     write(10+mpid%rank,*)
  enddo
  close(10+mpid%rank)
!100 continue

  call write_field('vel_u',nav%u(nav%it(nav%nt)),mpid)
  call write_field('vel_v',nav%v(nav%it(nav%nt)),mpid)
  call write_field('vel_w',nav%w(nav%it(nav%nt)),mpid)
  call write_field('vel_p',nav%p(nav%it(nav%nt)),mpid)
  call write_field('vel_phi',nav%phi(nav%it(nav%nt)),mpid)


  !------------------------------------------------------------------------ 
  !-> post-computation
  !------------------------------------------------------------------------ 


  call navier_finalization(cmd,mpid,nav)

contains

subroutine testconv(mpid,nav,u,v,w,p,sub_u,sub_v,sub_w,sub_p,aux,test,eps)
  use class_md
  use class_field
  use class_navier_3D
  use precision
  implicit none
  type(mpi_data) :: mpid
  type(navier3d) :: nav
  type(field) :: aux,u,    v,    w,    p
  type(field) :: sub_u,sub_v,sub_w,sub_p
  logical  :: test
  real(rk) :: ref,error1,error2,eps

    aux%f=sqrt(u%f**2 + v%f**2 + w%f**2)
    ref=norme2(mpid,nav,aux)

    aux%f=sqrt((sub_u%f-u%f)**2 + (sub_v%f-v%f)**2 + (sub_w%f-w%f)**2)
    error1=norme2(mpid,nav,aux)/ref

    if (mpid%rank==0) print*,'conv tot V       : ',error1

    aux%f=1._rk         ;    ref=integrale(mpid,nav,aux)
    aux%f=p%f - sub_p%f ; error2=integrale(mpid,nav,aux)

    sub_p%f=sub_p%f + error2/ref
    aux%f=sub_p%f       ;    ref=norme2(mpid,nav,aux)
    aux%f=p%f - sub_p%f ; error2=norme2(mpid,nav,aux)/ref
    if (mpid%rank==0) print*,'conv tot P       : ',error2

    if (error1<eps.and.error2<eps)  test=.true.

end subroutine testconv

function integrale(mpid,nav,x)
  use class_field
  use class_navier_3D
  use class_md
  use precision
!$ use OMP_LIB
  implicit none
  type(field),intent(in) ::x
  type(navier3d),intent(in) :: nav
  type(mpi_data) :: mpid
  real(rk) :: integrale1,integrale,dx,dy,dz
  integer(ik) :: i,j,k

  integrale1=0._rk

!$OMP  PARALLEL DO &
!$OMP  DEFAULT(SHARED) PRIVATE(i,j,k,dx,dy,dz) &
!$OMP  SCHEDULE(RUNTIME) &
!$OMP  REDUCTION(+:integrale1)
  do k=2,x%nz-1
     do j=2,x%ny-1
        do i=2,x%nx-1
           integrale1=integrale1+x%f(i,j,k)
        enddo
     enddo
  enddo
!$OMP  END PARALLEL DO

  !-> x boundary
!$OMP  PARALLEL DO &
!$OMP  DEFAULT(SHARED) PRIVATE(i,j,k,dx,dy,dz) &
!$OMP  SCHEDULE(RUNTIME) &
!$OMP  REDUCTION(+:integrale1)
   do j=2,x%ny-1
      do k=2,x%nz-1
         dy=(nav%gridy%grid1d(j+1)-nav%gridy%grid1d(j-1))*0.5_rk
         dz=(nav%gridz%grid1d(k+1)-nav%gridz%grid1d(k-1))*0.5_rk
         dx=(nav%gridx%grid1d(2)-nav%gridx%grid1d(1))*0.5_rk
         integrale1=integrale1+x%f(1,j,k)*dx*dy*dz
         dx=(nav%gridx%grid1d(x%nx)-nav%gridx%grid1d(x%nx-1))*0.5_rk
         integrale1=integrale1+x%f(x%nx,j,k)*dx*dy*dz
      enddo
  enddo
!$OMP  END PARALLEL DO

  !-> y boundary
!$OMP  PARALLEL DO &
!$OMP  DEFAULT(SHARED) PRIVATE(i,j,k,dx,dy,dz) &
!$OMP  SCHEDULE(RUNTIME) &
!$OMP  REDUCTION(+:integrale1)
   do i=2,x%nx-1
      do k=2,x%nz-1
         dx=(nav%gridx%grid1d(i+1)-nav%gridx%grid1d(i-1))*0.5_rk
         dz=(nav%gridz%grid1d(k+1)-nav%gridz%grid1d(k-1))*0.5_rk
         dy=(nav%gridy%grid1d(2)-nav%gridy%grid1d(1))*0.5_rk
         integrale1=integrale1+x%f(i,1,k)*dx*dy*dz
         dy=(nav%gridy%grid1d(x%ny)-nav%gridy%grid1d(x%ny-1))*0.5_rk
         integrale1=integrale1+x%f(i,x%ny,k)*dx*dy*dz
      enddo
  enddo
!$OMP  END PARALLEL DO

  !-> z boundary
!$OMP  PARALLEL DO &
!$OMP  DEFAULT(SHARED) PRIVATE(i,j,k,dx,dy,dz) &
!$OMP  SCHEDULE(RUNTIME) &
!$OMP  REDUCTION(+:integrale1)
   do i=2,x%nx-1
      do j=2,x%ny-1
         dx=(nav%gridx%grid1d(i+1)-nav%gridx%grid1d(i-1))*0.5_rk
         dy=(nav%gridy%grid1d(j+1)-nav%gridy%grid1d(j-1))*0.5_rk
         dz=(nav%gridz%grid1d(2)-nav%gridz%grid1d(1))*0.5_rk
         integrale1=integrale1+x%f(i,j,1)*dx*dy*dz
         dz=(nav%gridz%grid1d(x%nz)-nav%gridz%grid1d(x%nz-1))*0.5_rk
         integrale1=integrale1+x%f(i,j,x%nz)*dx*dy*dz
      enddo
  enddo
!$OMP  END PARALLEL DO

  if (mpid%dims.ne.0) then
    call md_mpi_reduce_double(mpid,integrale1,integrale)
    call md_mpi_bcast_double(mpid,integrale,0)
  else
    integrale=integrale1
  endif

end function integrale


function norme2(mpid,nav,x)
  use class_field
  use class_navier_3D
  use class_md
  use precision
!$ use OMP_LIB
  implicit none
  type(field),intent(in) ::x
  type(mpi_data) :: mpid
  type(navier3d),intent(in) :: nav
  real(rk) :: norme2,som1,dx,dy,dz
  integer(ik) :: i,j,k

!dx=maxval(abs(x%f(2:x%nx-1,2:x%ny-1,:)))
!dy=maxval(abs(x%f(2:x%nx-1,:,2:x%nz-1)))
!dz=maxval(abs(x%f(:,2:x%ny-1,2:x%nz-1)))
!norme2=max(dx,dy,dz)
norme2=maxval(abs(x%f(2:x%nx-1,2:x%ny-1,2:x%nz-1)))
return

  som1=0._rk

!$OMP  PARALLEL DO &
!$OMP  DEFAULT(SHARED) PRIVATE(i,j,k,dx,dy,dz) &
!$OMP  SCHEDULE(RUNTIME) &
!$OMP  REDUCTION(+:som1)
  do k=2,x%nz-1
     do j=2,x%ny-1
        do i=2,x%nx-1
           dx=(nav%gridx%grid1d(i+1)-nav%gridx%grid1d(i-1))*0.5_rk
           dy=(nav%gridy%grid1d(j+1)-nav%gridy%grid1d(j-1))*0.5_rk
           dz=(nav%gridz%grid1d(k+1)-nav%gridz%grid1d(k-1))*0.5_rk
           som1=som1+x%f(i,j,k)**2*dx*dy*dz
        enddo
     enddo
  enddo
!$OMP  END PARALLEL DO

  !-> x boundary
!$OMP  PARALLEL DO &
!$OMP  DEFAULT(SHARED) PRIVATE(i,j,k,dx,dy,dz) &
!$OMP  SCHEDULE(RUNTIME) &
!$OMP  REDUCTION(+:som1)
   do j=2,x%ny-1
      do k=2,x%nz-1
         dy=(nav%gridy%grid1d(j+1)-nav%gridy%grid1d(j-1))*0.5_rk
         dz=(nav%gridz%grid1d(k+1)-nav%gridz%grid1d(k-1))*0.5_rk
         dx=(nav%gridx%grid1d(2)-nav%gridx%grid1d(1))*0.5_rk
         som1=som1+x%f(1,j,k)**2*dx*dy*dz
         dx=(nav%gridx%grid1d(x%nx)-nav%gridx%grid1d(x%nx-1))*0.5_rk
         som1=som1+x%f(x%nx,j,k)**2*dx*dy*dz
      enddo
  enddo
!$OMP  END PARALLEL DO

  !-> y boundary
!$OMP  PARALLEL DO &
!$OMP  DEFAULT(SHARED) PRIVATE(i,j,k,dx,dy,dz) &
!$OMP  SCHEDULE(RUNTIME) &
!$OMP  REDUCTION(+:som1)
   do i=2,x%nx-1
      do k=2,x%nz-1
         dx=(nav%gridx%grid1d(i+1)-nav%gridx%grid1d(i-1))*0.5_rk
         dz=(nav%gridz%grid1d(k+1)-nav%gridz%grid1d(k-1))*0.5_rk
         dy=(nav%gridy%grid1d(2)-nav%gridy%grid1d(1))*0.5_rk
         som1=som1+x%f(i,1,k)**2*dx*dy*dz
         dy=(nav%gridy%grid1d(x%ny)-nav%gridy%grid1d(x%ny-1))*0.5_rk
         som1=som1+x%f(i,x%ny,k)**2*dx*dy*dz
      enddo
  enddo
!$OMP  END PARALLEL DO

  !-> z boundary
!$OMP  PARALLEL DO &
!$OMP  DEFAULT(SHARED) PRIVATE(i,j,k,dx,dy,dz) &
!$OMP  SCHEDULE(RUNTIME) &
!$OMP  REDUCTION(+:som1)
   do i=2,x%nx-1
      do j=2,x%ny-1
         dx=(nav%gridx%grid1d(i+1)-nav%gridx%grid1d(i-1))*0.5_rk
         dy=(nav%gridy%grid1d(j+1)-nav%gridy%grid1d(j-1))*0.5_rk
         dz=(nav%gridz%grid1d(2)-nav%gridz%grid1d(1))*0.5_rk
         som1=som1+x%f(i,j,1)**2*dx*dy*dz
         dz=(nav%gridz%grid1d(x%nz)-nav%gridz%grid1d(x%nz-1))*0.5_rk
         som1=som1+x%f(i,j,x%nz)**2*dx*dy*dz
      enddo
  enddo
!$OMP  END PARALLEL DO

  if (mpid%dims.ne.0) then
    call md_mpi_reduce_double(mpid,som1,norme2)
    call md_mpi_bcast_double(mpid,norme2,0)
  else
    norme2=som1
  endif

  norme2=sqrt(norme2)

end function norme2

subroutine err(u,uex,nx,ny,nz,error)
  use precision
  implicit none
  integer(ik) :: nx,ny,nz,i,j,k
  real(rk) :: u(nx,ny,nz),uex(nx,ny,nz)
  real(rk) :: som1,som2,error

  som1=0._rk
  som2=0._rk
  do k=2,nz-1
     do j=2,ny-1
        do i=2,nx-1
           som1=som1+(u(i,j,k)-uex(i,j,k))**2
           som2=som2+uex(i,j,k)**2
        enddo
     enddo
  enddo

  !-> x boundary
  som1=som1+sum((u(1,2:ny-1,2:nz-1)-uex(1,2:ny-1,2:nz-1))**2)
  som2=som2+sum(uex(1,2:ny-1,2:nz-1)**2)
  som1=som1+sum((u(nx,2:ny-1,2:nz-1)-uex(nx,2:ny-1,2:nz-1))**2)
  som2=som2+sum(uex(nx,2:ny-1,2:nz-1)**2)

  !-> y boundary
  som1=som1+sum((u(2:nx-1,1,2:nz-1)-uex(2:nx-1,1,2:nz-1))**2)
  som2=som2+sum(uex(2:nx-1,1,2:nz-1)**2)
  som1=som1+sum((u(2:nx-1,ny,2:nz-1)-uex(2:nx-1,ny,2:nz-1))**2)
  som2=som2+sum(uex(2:nx-1,ny,2:nz-1)**2)

  !-> z boundary
  som1=som1+sum((u(2:nx-1,2:ny-1,1)-uex(2:nx-1,2:ny-1,1))**2)
  som2=som2+sum(uex(2:nx-1,2:ny-1,1)**2)
  som1=som1+sum((u(2:nx-1,2:ny-1,nz)-uex(2:nx-1,2:ny-1,nz))**2)
  som2=som2+sum(uex(2:nx-1,2:ny-1,nz)**2)

  error=sqrt(som1)/sqrt(som2)

!  som1=0._rk
!  som2=0._rk
!  do k=1,nz
!     do j=1,ny
!        do i=1,nx
!           som1=som1+(u(i,j,k)-uex(i,j,k))**2
!           som2=som2+uex(i,j,k)**2
!        enddo
!     enddo
!  enddo
!  error=sqrt(som1)/sqrt(som2)
  !error=sqrt(som1/(nx*ny*nz))

end subroutine err

subroutine error_stop(error_mesg)
!  use mpi_utils, only : code,rang
  implicit none
  character(*) :: error_mesg
!  call MPI_FINALIZE(code)
!  if (rang==0) then
     print'(a)',error_mesg(1:len_trim(error_mesg))
!  endif
!  stop
  
end subroutine error_stop

end program testnavier3d


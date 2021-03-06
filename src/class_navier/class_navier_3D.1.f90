module class_navier_3D
! -----------------------------------------------------------------------
! Name :
! class navier_3D
! -----------------------------------------------------------------------
! Object :
! Resolution of incompressible Navier-Stokes equations in 3D
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
  use class_field
  use class_mesh
  use class_derivatives
  use class_solver_3d
  use class_md
  use color_print
!  use command_line
  implicit none

  !-> time scheme order
  integer(ik),parameter :: nt=3

  type navier3d
     !-> number of time steps
     integer(ik) :: nt=nt
     !-> dimensions
     integer(ik) :: nx,ny,nz
     !-> velocity fields
     type(field) :: u(nt),v(nt),w(nt)
     !-> pressure
     type(field) :: p(nt),phi
     !-> velocity rhs
     type(field) :: fu(nt),fv(nt),fw(nt)
     !-> pressure rhs
     type(field) :: fp(nt),fphi
     !-> auxiliary field
     type(field) :: aux
     !-> velocity boundary conditions
!     type(boundary_condition) :: bcu(0:nt),bcv(0:nt),bcw(0:nt)
     type(boundary_condition) :: bcu(nt),bcv(nt),bcw(nt)
     !-> pressure boundary conditions
!     type(boundary_condition) :: bcp(0:nt),bcphi
     type(boundary_condition) :: bcp(nt),bcphi
     !-> mesh
     type(mesh_grid) :: gridx,gridy,gridz
     !-> derivatives coefficients
     type(derivatives_coefficients) :: dcx,dcy,dcz
     !-> sigma
     real(rk) :: sigmau,sigmap
     !-> solver coefs
     type(solver_coeffs_3d) :: scu,scv,scw,scp
     !-> influence matrixes
     type(mpi_inf_mat) :: infu,infv,infw,infp
     !-> time, time-step, and number of time steps
     real(rk) :: time,ts
     integer(ik) :: it(nt),ntime
     !-> reynolds number
     real(rk) :: rey
     !-> nonlinear type, projection type
     integer(ik) :: nlt,pt
  end type navier3d

contains

  subroutine navier_bc_pressure(mpid,nav)
! -----------------------------------------------------------------------
! navier : 
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    type(mpi_data) :: mpid
    type(navier3d) :: nav
    integer(ik) :: i,l,m,c(3),inter(3,2)
    
    !-> get interface type
    call md_mpi_getcoord(mpid,c)
    call md_get_interfaces_number(nav%infu,c,inter)

!    do i=0,nav%nt
!       nav%bcp(i)%bcx=0._rk
!       nav%bcp(i)%bcy=0._rk
!       nav%bcp(i)%bcz=0._rk
!    enddo

    nav%bcphi%bcx=0._rk
    nav%bcphi%bcy=0._rk
    nav%bcphi%bcz=0._rk

  end subroutine navier_bc_pressure

  subroutine navier_bc_velocity(mpid,nav)
! -----------------------------------------------------------------------
! navier : 
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 11/2012
!
    implicit none
    type(mpi_data) :: mpid
    type(navier3d) :: nav
    integer(ik) :: l,m,c(3),inter(3,2)
    
    !-> get interface type
    call md_mpi_getcoord(mpid,c)
    call md_get_interfaces_number(nav%infu,c,inter)

    call navier_bc_velocity_utils(inter,nav%bcu(nav%it(1)),&
         nav%gridx,nav%gridy,nav%gridz,nav%time,'u',&
         nav%nx,nav%ny,nav%nz,nav%rey)

    call navier_bc_velocity_utils(inter,nav%bcv(nav%it(1)),&
         nav%gridx,nav%gridy,nav%gridz,nav%time,'v',&
         nav%nx,nav%ny,nav%nz,nav%rey)

    call navier_bc_velocity_utils(inter,nav%bcw(nav%it(1)),&
         nav%gridx,nav%gridy,nav%gridz,nav%time,'w',&
         nav%nx,nav%ny,nav%nz,nav%rey)

!    call add_boundary_gradient(mpid,nav)

    call erase_boundary_inter(inter,nav%bcu(nav%it(1)))
    call erase_boundary_inter(inter,nav%bcv(nav%it(1)))
    call erase_boundary_inter(inter,nav%bcw(nav%it(1)))

  end subroutine navier_bc_velocity

  subroutine erase_boundary_inter(inter,bc)
! -----------------------------------------------------------------------
! navier : 
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 11/2012
!
    implicit none
    integer(ik) :: l,m,inter(3,2)
    type(boundary_condition) :: bc
    
    !-> m : left-right ; l : directions (x,y,z)
    do m=1,2
       do l=1,3
          if (inter(l,m)>0) then
             if (l==1.and.m==1) bc%bcx(:,:,1)=0._rk
             if (l==1.and.m==2) bc%bcx(:,:,2)=0._rk
             if (l==2.and.m==1) bc%bcy(:,:,1)=0._rk
             if (l==2.and.m==2) bc%bcy(:,:,2)=0._rk
             if (l==3.and.m==1) bc%bcz(:,:,1)=0._rk
             if (l==3.and.m==2) bc%bcz(:,:,2)=0._rk
          endif
       enddo
    enddo

  end subroutine erase_boundary_inter

  subroutine add_boundary_gradient(mpid,nav)
! -----------------------------------------------------------------------
! navier : 
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    type(navier3d) :: nav
    type(mpi_data) :: mpid
    integer(ik) :: it(nav%nt),nt
    real(rk) :: fac1,fac2,fac3
    integer(ik) :: l,m,c(3),inter(3,2)
    
    !-> get interface type
    call md_mpi_getcoord(mpid,c)
    call md_get_interfaces_number(nav%infu,c,inter)

    !-> put nav%nt in nt for ease of use
    nt=nav%nt
    it(:)=nav%it(:)
    
    fac1=1._rk !/sqrt(2._rk)
    fac2=1._rk/sqrt(2._rk)

!    goto 100
    !-> bcx
    nav%aux%f=0._rk
    nav%aux=dery(nav%dcy,nav%phi)
    nav%bcv(it(1))%bcx(:,:,1)=fac1*(nav%bcv(it(1))%bcx(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(1,2:nav%ny-1,2:nav%nz-1)/3._rk)
    nav%bcv(it(1))%bcx(:,:,2)=fac1*(nav%bcv(it(1))%bcx(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(nav%nx,2:nav%ny-1,2:nav%nz-1)/3._rk)

    nav%aux%f=0._rk
    nav%aux=derz(nav%dcz,nav%phi)
    nav%bcw(it(1))%bcx(:,:,1)=fac1*(nav%bcw(it(1))%bcx(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(1,2:nav%ny-1,2:nav%nz-1)/3._rk)
    nav%bcw(it(1))%bcx(:,:,2)=fac1*(nav%bcw(it(1))%bcx(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(nav%nx,2:nav%ny-1,2:nav%nz-1)/3._rk)

    !-> bcy
    nav%aux%f=0._rk
    nav%aux=derx(nav%dcx,nav%phi)
    nav%bcu(it(1))%bcy(:,:,1)=fac1*(nav%bcu(it(1))%bcy(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,1,2:nav%nz-1)/3._rk)
    nav%bcu(it(1))%bcy(:,:,2)=fac1*(nav%bcu(it(1))%bcy(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,nav%ny,2:nav%nz-1)/3._rk)
    
    nav%aux%f=0._rk
    nav%aux=derz(nav%dcz,nav%phi)
    nav%bcw(it(1))%bcy(:,:,1)=fac1*(nav%bcw(it(1))%bcy(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,1,2:nav%nz-1)/3._rk)
    nav%bcw(it(1))%bcy(:,:,2)=fac1*(nav%bcw(it(1))%bcy(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,nav%ny,2:nav%nz-1)/3._rk)

    !-> bcz
    nav%aux%f=0._rk
    nav%aux=derx(nav%dcx,nav%phi)
    nav%bcu(it(1))%bcz(:,:,1)=fac1*(nav%bcu(it(1))%bcz(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,1)/3._rk)
    nav%bcu(it(1))%bcz(:,:,2)=fac1*(nav%bcu(it(1))%bcz(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,nav%nz)/3._rk)

    nav%aux%f=0._rk
    nav%aux=dery(nav%dcy,nav%phi)
    nav%bcv(it(1))%bcz(:,:,1)=fac1*(nav%bcv(it(1))%bcz(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,1)/3._rk)
    nav%bcv(it(1))%bcz(:,:,2)=fac1*(nav%bcv(it(1))%bcz(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,nav%nz)/3._rk)
!100 continue

    goto 102

    fac1=1._rk/sqrt(3._rk)
    fac2=1._rk/sqrt(3._rk)
    fac3=1._rk/sqrt(3._rk)

    nav%aux=derx(nav%dcx,nav%phi)
    nav%bcu(it(1))%bcx(:,:,1)=fac1*(nav%bcu(it(1))%bcx(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(1,2:nav%ny-1,2:nav%nz-1)/3._rk)
    nav%bcu(it(1))%bcx(:,:,2)=-fac1*(nav%bcu(it(1))%bcx(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(nav%nx,2:nav%ny-1,2:nav%nz-1)/3._rk)

    nav%bcu(it(1))%bcy(:,:,1)=fac2*(nav%bcu(it(1))%bcy(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,1,2:nav%nz-1)/3._rk)
    nav%bcu(it(1))%bcy(:,:,2)=-fac2*(nav%bcu(it(1))%bcy(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,nav%ny,2:nav%nz-1)/3._rk)

    nav%bcu(it(1))%bcz(:,:,1)=fac3*(nav%bcu(it(1))%bcz(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,1)/3._rk)
    nav%bcu(it(1))%bcz(:,:,2)=-fac3*(nav%bcu(it(1))%bcz(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,nav%nz)/3._rk)

    nav%aux=dery(nav%dcy,nav%phi)
    nav%bcv(it(1))%bcx(:,:,1)=fac1*(nav%bcv(it(1))%bcx(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(1,2:nav%ny-1,2:nav%nz-1)/3._rk)
    nav%bcv(it(1))%bcx(:,:,2)=-fac1*(nav%bcv(it(1))%bcx(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(nav%nx,2:nav%ny-1,2:nav%nz-1)/3._rk)

    nav%bcv(it(1))%bcy(:,:,1)=fac2*(nav%bcv(it(1))%bcy(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,1,2:nav%nz-1)/3._rk)
    nav%bcv(it(1))%bcy(:,:,2)=-fac2*(nav%bcv(it(1))%bcy(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,nav%ny,2:nav%nz-1)/3._rk)

    nav%bcv(it(1))%bcz(:,:,1)=fac3*(nav%bcv(it(1))%bcz(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,1)/3._rk)
    nav%bcv(it(1))%bcz(:,:,2)=-fac3*(nav%bcv(it(1))%bcz(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,nav%nz)/3._rk)

    nav%aux=derz(nav%dcz,nav%phi)
    nav%bcw(it(1))%bcx(:,:,1)=fac1*(nav%bcw(it(1))%bcx(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(1,2:nav%ny-1,2:nav%nz-1)/3._rk)
    nav%bcw(it(1))%bcx(:,:,2)=-fac1*(nav%bcw(it(1))%bcx(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(nav%nx,2:nav%ny-1,2:nav%nz-1)/3._rk)

    nav%bcw(it(1))%bcy(:,:,1)=fac2*(nav%bcw(it(1))%bcy(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,1,2:nav%nz-1)/3._rk)
    nav%bcw(it(1))%bcy(:,:,2)=-fac2*(nav%bcw(it(1))%bcy(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,nav%ny,2:nav%nz-1)/3._rk)

    nav%bcw(it(1))%bcz(:,:,1)=fac3*(nav%bcw(it(1))%bcz(:,:,1)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,1)/3._rk)
    nav%bcw(it(1))%bcz(:,:,2)=-fac3*(nav%bcw(it(1))%bcz(:,:,2)&
         +2._rk*nav%ts*nav%aux%f(2:nav%nx-1,2:nav%ny-1,nav%nz)/3._rk)
102 continue

    call erase_boundary_inter(inter,nav%bcu(nav%it(1)))
    call erase_boundary_inter(inter,nav%bcv(nav%it(1)))
    call erase_boundary_inter(inter,nav%bcw(nav%it(1)))

  end subroutine add_boundary_gradient

  
  subroutine navier_bc_velocity_utils(inter,bc,gridx,gridy,gridz,t,&
       var,nx,ny,nz,rey)
! -----------------------------------------------------------------------
! navier : 
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    integer(ik) :: l,m,inter(3,2)
    type(boundary_condition) :: bc
    type(mesh_grid) :: gridx,gridy,gridz
    real(rk) :: x,y,z,t,rey
    integer(ik) :: i,j,k,nx,ny,nz
    character(*) :: var

    !-> boundary condition
    !-> x-direction
    do k=2,nz-1
       do j=2,ny-1
          y=gridy%grid1d(j)
          z=gridz%grid1d(k)
          
          x=gridx%grid1d(1)
          bc%bcx(j-1,k-1,1)=sol(x,y,z,t,var,rey)
!          bc%bcx(j-1,k-1,1)=0._rk
          x=gridx%grid1d(nx)
          bc%bcx(j-1,k-1,2)=sol(x,y,z,t,var,rey)
!          bc%bcx(j-1,k-1,2)=0._rk
       enddo
    enddo
    !print*,x,y,z,t
    !-> y-direction
    do k=2,nz-1
       do i=2,nx-1
          x=gridx%grid1d(i)
          z=gridz%grid1d(k)

          y=gridy%grid1d(1)
          bc%bcy(i-1,k-1,1)=sol(x,y,z,t,var,rey)
!          bc%bcy(i-1,k-1,1)=0._rk
          y=gridy%grid1d(ny)
          bc%bcy(i-1,k-1,2)=sol(x,y,z,t,var,rey)
!          if (var=='u') then
!             bc%bcy(i-1,k-1,2)=1._rk
!          else
!             bc%bcy(i-1,k-1,2)=0._rk
!          endif
       enddo
    enddo
    !-> z-direction
    do j=2,ny-1
       do i=2,nx-1
          x=gridx%grid1d(i)
          y=gridy%grid1d(j)
          
          z=gridz%grid1d(1)
          bc%bcz(i-1,j-1,1)=sol(x,y,z,t,var,rey)
!          bc%bcz(i-1,j-1,1)=0._rk
          z=gridz%grid1d(nz)
          bc%bcz(i-1,j-1,2)=sol(x,y,z,t,var,rey)
!          bc%bcz(i-1,j-1,2)=0._rk
       enddo
    enddo

    !-> m : left-right ; l : directions (x,y,z)
!    do m=1,2
!       do l=1,3
!          if (inter(l,m)>0) then
!             if (l==1.and.m==1) bc%bcx(:,:,1)=0._rk
!             if (l==1.and.m==2) bc%bcx(:,:,2)=0._rk
!             if (l==2.and.m==1) bc%bcy(:,:,1)=0._rk
!             if (l==2.and.m==2) bc%bcy(:,:,2)=0._rk
!             if (l==3.and.m==1) bc%bcz(:,:,1)=0._rk
!             if (l==3.and.m==2) bc%bcz(:,:,2)=0._rk
!          endif
!       enddo
!    enddo

  end subroutine navier_bc_velocity_utils

  function sol(x,y,z,t,type,rey)
! -----------------------------------------------------------------------
! exact solution : function, derivatives and rhs
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    real(rk) :: sol,rey
    real(rk) :: x,y,z,t,a,g,pi
    character(*) :: type
    
    pi=4._rk*atan(1._rk)
    a=1._rk*pi ; g=0.5_rk*pi

    if (type=="u") then
       sol=sin(a*x)*sin(a*y)*cos(a*z)*cos(g*t)
    endif
    if (type=="v") then
       sol=cos(a*x)*cos(a*y)*cos(a*z)*cos(g*t)*2
    endif
    if (type=="w") then
       sol=cos(a*x)*sin(a*y)*sin(a*z)*cos(g*t)
    endif
    if (type=="p") then
       sol=cos(a*x)*cos(a*y)*cos(a*z)*cos(g*t)
    endif
    if (type=="dxp") then
       sol=-a*cos(g*t)*sin(a*x)*cos(a*y)*cos(a*z)
    endif
    if (type=="dyp") then
       sol=-a*cos(g*t)*cos(a*x)*sin(a*y)*cos(a*z)
    endif
    if (type=="dzp") then
       sol=-a*cos(g*t)*cos(a*x)*cos(a*y)*sin(a*z)
    endif

    if (type=="rhsu") then
       sol=-a*cos(g*t)**2*cos(a*x)*sin(a*x)*sin(a*y)**2*sin(a*z)**2+a*&
            cos(g*t)**2*cos(a*x)*sin(a*x)*sin(a*y)**2*cos(a*z)**2+2*a*cos(g*t)**2*&
            cos(a*x)*sin(a*x)*cos(a*y)**2*cos(a*z)**2-g*sin(g*t)*sin(a*x)*sin(&
            a*y)*cos(a*z)+3*a**2*cos(g*t)*sin(a*x)*sin(a*y)*cos(a*z)/rey-a*cos&
            (g*t)*sin(a*x)*cos(a*y)*cos(a*z)
    endif
    if (type=="rhsv") then
       sol=-2*a*cos(g*t)**2*cos(a*x)**2*cos(a*y)*sin(a*y)*sin(a*z)**2-2*a*&
            cos(g*t)**2*sin(a*x)**2*cos(a*y)*sin(a*y)*cos(a*z)**2-4*a*cos(g*t)**2&
            *cos(a*x)**2*cos(a*y)*sin(a*y)*cos(a*z)**2-a*cos(g*t)*cos(a*x)*&
            sin(a*y)*cos(a*z)-2*g*sin(g*t)*cos(a*x)*cos(a*y)*cos(a*z)+6*a**2*&
            cos(g*t)*cos(a*x)*cos(a*y)*cos(a*z)/rey
    endif
    if (type=="rhsw") then
       sol=-a*cos(g*t)**2*sin(a*x)**2*sin(a*y)**2*cos(a*z)*sin(a*z)+a*cos(g*&
            t)**2*cos(a*x)**2*sin(a*y)**2*cos(a*z)*sin(a*z)+2*a*cos(g*t)**2*&
            cos(a*x)**2*cos(a*y)**2*cos(a*z)*sin(a*z)-g*sin(g*t)*cos(a*x)*sin(&
            a*y)*sin(a*z)+3*a**2*cos(g*t)*cos(a*x)*sin(a*y)*sin(a*z)/rey-a*&
            cos(g*t)*cos(a*x)*cos(a*y)*sin(a*z)
    endif
    if (type=="rhsp") then
       sol=-2*(a**2*cos(g*t)**2*sin(a*x)**2*sin(a*y)**2*sin(a*z)**2-2*a**2*&
            cos(g*t)**2*cos(a*x)**2*cos(a*y)**2*sin(a*z)**2-a**2*cos(g*t)**2*&
            cos(a*x)**2*sin(a*y)**2*cos(a*z)**2+2*a**2*cos(g*t)**2*sin(a*x)**2&
            *cos(a*y)**2*cos(a*z)**2)-3*a**2*cos(g*t)*cos(a*x)*cos(a*y)*cos(a*z)
    endif

  end function sol

  function f(nav,var)
! -----------------------------------------------------------------------
! field : compute first derivative in x direction
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    type(field) :: f
    type(navier3d),intent(in) :: nav
    integer(ik) :: i,j,k
    real(rk) :: x,y,z,t
    character(*) :: var
    call field_init(f,"F",nav%nx,nav%ny,nav%nz)

    t=nav%time
    do k=1,nav%nz
       do j=1,nav%ny
          do i=1,nav%nx
             x=nav%gridx%grid1d(i)
             y=nav%gridy%grid1d(j)
             z=nav%gridz%grid1d(k)
             f%f(i,j,k)=sol(x,y,z,t,var,nav%rey)
          enddo
       enddo
    enddo

  end function f

  subroutine navier_nonlinear(mpid,nav,x,f)
! -----------------------------------------------------------------------
! navier : solve u helmholtz problem
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 11/2012
!
    implicit none
    type(navier3d) :: nav
    type(mpi_data) :: mpid
    integer(ik) :: it(nav%nt),nt
    type(field) :: x(nav%nt),f
    
    !-> put nav%nt in nt for ease of use
    nt=nav%nt
    it(:)=nav%it(:)

    !-> nonlinear terms
    if (nav%nlt==1) then
       f=f+2._rk*(&
            nav%u(it(nt))*derx(nav%dcx,x(it(nt)))+&
            nav%v(it(nt))*dery(nav%dcy,x(it(nt)))+&
            nav%w(it(nt))*derz(nav%dcz,x(it(nt))))

       f=f-1._rk*(&
            nav%u(it(nt-1))*derx(nav%dcx,x(it(nt-1)))+&
            nav%v(it(nt-1))*dery(nav%dcy,x(it(nt-1)))+&
            nav%w(it(nt-1))*derz(nav%dcz,x(it(nt-1))))
    elseif (nav%nlt==2) then
       f=f+1._rk*(&
            nav%u(it(nt))*derx(nav%dcx,x(it(nt)))+&
            nav%v(it(nt))*dery(nav%dcy,x(it(nt)))+&
            nav%w(it(nt))*derz(nav%dcz,x(it(nt))))

       nav%aux=1._rk*x(it(nt))*nav%u(it(nt))
       f=f+derx(nav%dcx,nav%aux)
       nav%aux=1._rk*x(it(nt))*nav%v(it(nt))
       f=f+dery(nav%dcy,nav%aux)
       nav%aux=1._rk*x(it(nt))*nav%w(it(nt))
       f=f+derz(nav%dcz,nav%aux)

       f=f-0.5_rk*(&
            nav%u(it(nt-1))*derx(nav%dcx,x(it(nt-1)))+&
            nav%v(it(nt-1))*dery(nav%dcy,x(it(nt-1)))+&
            nav%w(it(nt-1))*derz(nav%dcz,x(it(nt-1))))

       nav%aux=(-0.5_rk)*x(it(nt-1))*nav%u(it(nt-1))
       f=f+derx(nav%dcx,nav%aux)
       nav%aux=(-0.5_rk)*x(it(nt-1))*nav%v(it(nt-1))
       f=f+dery(nav%dcy,nav%aux)
       nav%aux=(-0.5_rk)*x(it(nt-1))*nav%w(it(nt-1))
       f=f+derz(nav%dcz,nav%aux)
    endif


  end subroutine navier_nonlinear

  subroutine navier_solve_u(mpid,nav)
! -----------------------------------------------------------------------
! navier : solve u helmholtz problem
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    type(navier3d) :: nav
    type(mpi_data) :: mpid
    integer(ik) :: it(nav%nt),nt

    !-> put nav%nt in nt for ease of use
    nt=nav%nt
    it(:)=nav%it(:)

    !--------------------------------------------------------------------
    !-> compute rhs
    nav%fu(it(nt))%f=0._rk
    
    !-> time
!    nav%fu(it(nt))=-nav%u(it(nt))/nav%ts
    nav%fu(it(nt))=0.5_rk*(-4._rk*nav%u(it(nt))+nav%u(it(nt-1)))/nav%ts
    
    !-> pressure 
    if (nav%pt==2) then
       nav%fu(it(nt))=nav%fu(it(nt))+derx(nav%dcx,nav%p(it(nt)))
!       nav%fu(it(nt))=nav%fu(it(nt))+2._rk*derx(nav%dcx,nav%p(it(nt)))&
!            -derx(nav%dcx,nav%p(it(nt-1)))
    endif
    
    !-> nonlinear terms
    call navier_nonlinear(mpid,nav,nav%u,nav%fu(it(nt)))

    !-> function
    nav%fu(it(nt))=nav%fu(it(nt))-f(nav,'rhsu')

    !-> reynolds number multiplication
    nav%fu(it(nt))=nav%rey*nav%fu(it(nt))

    !--------------------------------------------------------------------
    !-> solve

    call multidomain_solve(mpid,nav%infu,nav%scu,nav%bcu(it(1)),nav%u(it(1)),&
          nav%fu(it(nt)),nav%aux,nav%sigmau,nav%dcx,nav%dcy,nav%dcz)

  end subroutine navier_solve_u

  subroutine navier_solve_v(mpid,nav)
! -----------------------------------------------------------------------
! navier : solve v helmholtz problem
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    type(navier3d) :: nav
    type(mpi_data) :: mpid
    integer(ik) :: it(nav%nt),nt
    
    !-> put nav%nt in nt for ease of use
    nt=nav%nt
    it(:)=nav%it(:)

    !--------------------------------------------------------------------
    !-> compute rhs
    nav%fv(it(nt))%f=0._rk
    
    !-> time
!    nav%fv(it(nt))=-nav%v(it(nt))/nav%ts
    nav%fv(it(nt))=0.5_rk*(-4._rk*nav%v(it(nt))+nav%v(it(nt-1)))/nav%ts
    
    !-> pressure 
    if (nav%pt==2) then
       nav%fv(it(nt))=nav%fv(it(nt))+dery(nav%dcy,nav%p(it(nt)))
!       nav%fv(it(nt))=nav%fv(it(nt))+2._rk*dery(nav%dcy,nav%p(it(nt)))&
!            -dery(nav%dcy,nav%p(it(nt-1)))
    endif
    
    !-> nonlinear terms
    call navier_nonlinear(mpid,nav,nav%v,nav%fv(it(nt)))

    !-> function
    nav%fv(it(nt))=nav%fv(it(nt))-f(nav,'rhsv')

    !-> reynolds number multiplication
    nav%fv(it(nt))=nav%rey*nav%fv(it(nt))

    !--------------------------------------------------------------------
    !-> solve

    call multidomain_solve(mpid,nav%infv,nav%scv,nav%bcv(it(1)),nav%v(it(1)),&
          nav%fv(it(nt)),nav%aux,nav%sigmau,nav%dcx,nav%dcy,nav%dcz)

  end subroutine navier_solve_v

  subroutine navier_solve_w(mpid,nav)
! -----------------------------------------------------------------------
! navier : solve w helmholtz problem
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    type(navier3d) :: nav
    type(mpi_data) :: mpid
    integer(ik) :: it(nav%nt),nt
    
    !-> put nav%nt in nt for ease of use
    nt=nav%nt
    it(:)=nav%it(:)

    !--------------------------------------------------------------------
    !-> compute rhs
    nav%fw(it(nt))%f=0._rk
    
    !-> time
!    nav%fw(it(nt))=-nav%w(it(nt))/nav%ts
    nav%fw(it(nt))=0.5_rk*(-4._rk*nav%w(it(nt))+nav%w(it(nt-1)))/nav%ts
    
    !-> pressure 
    if (nav%pt==2) then
       nav%fw(it(nt))=nav%fw(it(nt))+derz(nav%dcz,nav%p(it(nt))) 
!       nav%fw(it(nt))=nav%fw(it(nt))+2._rk*derz(nav%dcz,nav%p(it(nt)))&
!            -derz(nav%dcz,nav%p(it(nt-1)))
    endif
    
    !-> nonlinear terms
    call navier_nonlinear(mpid,nav,nav%w,nav%fw(it(nt)))

    !-> function
    nav%fw(it(nt))=nav%fw(it(nt))-f(nav,'rhsw')

    !-> reynolds number multiplication
    nav%fw(it(nt))=nav%rey*nav%fw(it(nt))

    !--------------------------------------------------------------------
    !-> solve

    call multidomain_solve(mpid,nav%infw,nav%scw,nav%bcw(it(1)),nav%w(it(1)),&
          nav%fw(it(nt)),nav%aux,nav%sigmau,nav%dcx,nav%dcy,nav%dcz)

  end subroutine navier_solve_w

  subroutine navier_solve_phi(mpid,nav)
! -----------------------------------------------------------------------
! navier : solve phi helmholtz problem
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    type(navier3d) :: nav
    type(mpi_data) :: mpid
    integer(ik) :: it(nav%nt),nt
    
    !-> put nav%nt in nt for ease of use
    nt=nav%nt
    it(:)=nav%it(:)

    !--------------------------------------------------------------------
    !-> compute rhs
    nav%fphi%f=0._rk
    nav%phi%f=0._rk
    
    !-> 
    nav%fphi=(1.5_rk/nav%ts)*(&
         derx(nav%dcx,nav%u(it(1)))+&
         dery(nav%dcy,nav%v(it(1)))+&
         derz(nav%dcz,nav%w(it(1))))
    
    goto 101
    nav%fphi=(1.5_rk/nav%ts)*(&
         derx(nav%dcx,nav%u(it(1)))+&
         dery(nav%dcy,nav%v(it(1)))+&
         derz(nav%dcz,nav%w(it(1))))

    nav%fphi=nav%fphi+(-2._rk/nav%ts)*(&
         derx(nav%dcx,nav%u(it(nt)))+&
         dery(nav%dcy,nav%v(it(nt)))+&
         derz(nav%dcz,nav%w(it(nt))))
    
    nav%fphi=nav%fphi+(0.5_rk/nav%ts)*(&
         derx(nav%dcx,nav%u(it(nt-1)))+&
         dery(nav%dcy,nav%v(it(nt-1)))+&
         derz(nav%dcz,nav%w(it(nt-1))))
101 continue

    !-> function
!    nav%fphi=nav%fphi+f(nav,'rhsp')
    
    !--------------------------------------------------------------------
    !-> solve

    call multidomain_solve(mpid,nav%infp,nav%scp,nav%bcphi,nav%phi,&
          nav%fphi,nav%aux,nav%sigmap,nav%dcx,nav%dcy,nav%dcz,null=1)

  end subroutine navier_solve_phi

  subroutine navier_projection(mpid,nav)
! -----------------------------------------------------------------------
! navier : compute divergence null u,v,w,p
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    type(mpi_data) :: mpid
    type(navier3d) :: nav
    real(rk) :: fac
    integer(ik) :: iaux,i,ex(3,2)
    integer(ik) :: it(nav%nt),nt
    integer(ik) :: l,m,c(3),inter(3,2)
    
    !-> get interface type
    call md_mpi_getcoord(mpid,c)
    call md_get_interfaces_number(nav%infu,c,inter)

    !-> put nav%nt in nt for ease of use
    nt=nav%nt
    it(:)=nav%it(:)

    !-> compute extrema
    ex(1,1)=2 ; ex(2,1)=2 ; ex(3,1)=2 
    ex(1,2)=nav%nx-1 ; ex(2,2)=nav%ny-1 ; ex(3,2)=nav%nz-1

    !-> coefficient
!    fac=nav%ts
    fac=2._rk*nav%ts/3._rk

    !-> pressure
    if (nav%pt==1) then
       nav%p(it(1))=nav%phi
    elseif(nav%pt==2) then
       nav%p(it(1))=nav%phi+nav%p(nav%it(nav%nt))
!       nav%p(it(1))=nav%phi+2._rk*nav%p(nav%it(nav%nt))-nav%p(nav%it(nav%nt-1))
    endif
    call field_zero_edges(nav%p(it(1)))

    !-> rotationnal
    nav%aux=(derx(nav%dcx,nav%u(it(1)))+&
         dery(nav%dcy,nav%v(it(1)))+&
         derz(nav%dcz,nav%w(it(1))))/nav%rey
!    nav%p(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))=&
!         nav%p(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))&
!         -nav%aux%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))
    nav%p(it(1))=nav%p(it(1))-nav%aux

 
    !-> Brown
!    nav%aux=fac*(dderx(nav%dcx,nav%phi)+&
!         ddery(nav%dcy,nav%phi)+&
!         dderz(nav%dcz,nav%phi))/nav%rey
!    nav%p(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))=&
!         nav%p(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))&
!         -nav%aux%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))
!    nav%p(it(1))=nav%p(it(1))-nav%aux

    call field_zero_edges(nav%p(it(1)))
   

!    goto 102
    do m=1,2
       do l=1,3
          if (inter(l,m)>0) then
             if (l==1.and.m==1) ex(l,m)=1
             if (l==1.and.m==2) ex(l,m)=nav%nx
             if (l==2.and.m==1) ex(l,m)=1
             if (l==2.and.m==2) ex(l,m)=nav%ny
             if (l==3.and.m==1) ex(l,m)=1
             if (l==3.and.m==2) ex(l,m)=nav%nz
          endif
       enddo
    enddo
!102 continue


!    call navier_bc_velocity(mpid,nav)
!    call field_put_boundary(nav%u(it(1)),nav%bcu(it(1)),inter)
!    call field_put_boundary(nav%v(it(1)),nav%bcv(it(1)),inter)
!    call field_put_boundary(nav%w(it(1)),nav%bcw(it(1)),inter)

    !-> velocity
!    goto 101
    nav%aux=derx(nav%dcx,nav%phi)
    nav%u(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))=&
         nav%u(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))&
         -fac*nav%aux%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))

    nav%aux=dery(nav%dcy,nav%phi)
    nav%v(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))=&
         nav%v(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))&
         -fac*nav%aux%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))

    nav%aux=derz(nav%dcz,nav%phi)
    nav%w(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))=&
         nav%w(it(1))%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))&
         -fac*nav%aux%f(ex(1,1):ex(1,2),ex(2,1):ex(2,2),ex(3,1):ex(3,2))
!101 continue

!    nav%u(it(1))=nav%u(it(1))-fac*derx(nav%dcx,nav%phi)
!    nav%v(it(1))=nav%v(it(1))-fac*dery(nav%dcy,nav%phi)
!    nav%w(it(1))=nav%w(it(1))-fac*derz(nav%dcz,nav%phi)

    call field_zero_edges(nav%u(it(1)))
    call field_zero_edges(nav%v(it(1)))
    call field_zero_edges(nav%w(it(1)))

    !-> switch it    
    iaux=nav%it(1)
    do i=1,nav%nt-1
       nav%it(i)=nav%it(i+1)
    enddo
    nav%it(nt)=iaux

  end subroutine navier_projection


  subroutine navier_time(nav)
! -----------------------------------------------------------------------
! navier : update time variable
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    implicit none
    type(navier3d) :: nav
    
    nav%time=nav%time+nav%ts

  end subroutine navier_time

  subroutine navier_initialization(cmd,mpid,nav)
! -----------------------------------------------------------------------
! navier : initialize navier type
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    use command_line
    implicit none
    type(cmd_line) :: cmd
    type(navier3d) :: nav
    type(mpi_data) :: mpid
    integer(ik) :: nx,ny,nz,i
    integer(ik) :: bctu(6),bctv(6),bctw(6),bctp(6)

    !--------------------------------------------------------------------
    !-> initialize mpi
    call md_mpi_init(mpid,cmd)
    !-> initialize petsc
    call md_petsc_initialize()

    if (mpid%rank==0) then
       call color(ired);print'(a)','Precomputation : ';call color(color_off)
    endif

    !-> put dimensions in variables for ease of use
    nav%nx=cmd%nx ; nav%ny=cmd%ny ; nav%nz=cmd%nz
    nx=cmd%nx ; ny=cmd%ny ; nz=cmd%nz

    !-> time, time step, nlt
    nav%time=0._rk
    nav%ts=cmd%ts
    nav%ntime=cmd%ntime
    nav%it(:)=(/(i,i=1,nt)/)
    nav%nlt=cmd%nlt
    nav%pt=cmd%pt

    !-> reynolds number 
    nav%rey=cmd%reynolds

    !--------------------------------------------------------------------
    !-> initialize mesh
    call mesh_init(nav%gridx,'gridx','x',nx,1,1)
    call mesh_init(nav%gridy,'gridy','y',1,ny,1)
    call mesh_init(nav%gridz,'gridz','z',1,1,nz)

    !-> initialize grid
    call mesh_grid_init(nav%gridx,'x',nx,1,1,mpid)
    call mesh_grid_init(nav%gridy,'y',nx,ny,1,mpid)
    call mesh_grid_init(nav%gridz,'z',1,1,nz,mpid)

    !-> compute sigma
    if (nav%nt==2.or.nav%nt==3) then
!       nav%sigmau=-nav%rey/nav%ts
       nav%sigmau=-nav%rey*1.5_rk/nav%ts
       nav%sigmap=0._rk
    endif

    !--------------------------------------------------------------------
    !-> start initialization of u influence matrix
    call influence_matrix_init_start(mpid,nav%infu,nav%scu,nav%bcu(1),&
         nav%u(1),nav%fu(1),nav%sigmau,nav%dcx,nav%dcy,nav%dcz,'u')

    !-> start initialization of u influence matrix
    call influence_matrix_init_start(mpid,nav%infv,nav%scv,nav%bcv(1),&
         nav%v(1),nav%fv(1),nav%sigmau,nav%dcx,nav%dcy,nav%dcz,'v')

    !-> start initialization of u influence matrix
    call influence_matrix_init_start(mpid,nav%infw,nav%scw,nav%bcw(1),&
         nav%w(1),nav%fw(1),nav%sigmau,nav%dcx,nav%dcy,nav%dcz,'w')

    !-> start initialization of pressure influence matrix
    call influence_matrix_init_start(mpid,nav%infp,nav%scp,nav%bcp(1),&
         nav%p(1),nav%fp(1),nav%sigmap,nav%dcx,nav%dcy,nav%dcz,'p')

    !--------------------------------------------------------------------
    !-> initialize poisson solver coefficient for u
    bctu=(/1,1,1,1,1,1/)
    call md_boundary_condition_init(mpid,nav%infu,bctu)
    call solver_init_3d(nav%gridx,nav%gridy,nav%gridz,nav%scu,bctu)

    !-> initialize poisson solver coefficient for v
    bctv=(/1,1,1,1,1,1/)
    call md_boundary_condition_init(mpid,nav%infv,bctv)
    call solver_init_3d(nav%gridx,nav%gridy,nav%gridz,nav%scv,bctv)

    !-> initialize poisson solver coefficient for w
    bctw=(/1,1,1,1,1,1/)
    call md_boundary_condition_init(mpid,nav%infw,bctw)
    call solver_init_3d(nav%gridx,nav%gridy,nav%gridz,nav%scw,bctw)

    !-> initialize poisson solver coefficient for pressure
    bctp=(/2,2,2,2,2,2/)
    call md_boundary_condition_init(mpid,nav%infp,bctp)
    call solver_init_3d(nav%gridx,nav%gridy,nav%gridz,nav%scp,bctp)

    !--------------------------------------------------------------------
    !-> initialize type field
    do i=1,nav%nt
       call field_init(nav%u(i),"U",nx,ny,nz)
       call field_init(nav%v(i),"V",nx,ny,nz)
       call field_init(nav%w(i),"W",nx,ny,nz)
       call field_init(nav%p(i),"P",nx,ny,nz)
       call field_init(nav%fu(i),"RHS_U",nx,ny,nz)
       call field_init(nav%fv(i),"RHS_V",nx,ny,nz)
       call field_init(nav%fw(i),"RHS_W",nx,ny,nz)
       call field_init(nav%fp(i),"RHS_P",nx,ny,nz)
    enddo
    call field_init(nav%phi,"PHI",nx,ny,nz)
    call field_init(nav%fphi,"RHS_PHI",nx,ny,nz)
    call field_init(nav%aux,"AUX",nx,ny,nz)

    !--------------------------------------------------------------------
    !-> initialize type boundary_condition for velocity
    do i=1,nav%nt
       call boundary_condition_init(nav%bcu(i),nx,ny,nz)
       call boundary_condition_init(nav%bcv(i),nx,ny,nz)
       call boundary_condition_init(nav%bcw(i),nx,ny,nz)
    enddo

    !-> initialize type boundary_condition for pressure
    do i=1,nav%nt
       call boundary_condition_init(nav%bcp(i),nx,ny,nz)
    enddo
    call boundary_condition_init(nav%bcphi,nx,ny,nz)

    !--------------------------------------------------------------------
    !-> initialisation of derivatives coefficients
    call derivatives_coefficients_init(nav%gridx,nav%dcx,nx,solver='yes')
    call derivatives_coefficients_init(nav%gridy,nav%dcy,ny,solver='yes')
    call derivatives_coefficients_init(nav%gridz,nav%dcz,nz,solver='yes')

    !--------------------------------------------------------------------
    !-> end initialize u influence matrix
    call influence_matrix_init_end(mpid,nav%infu,nav%scu,nav%bcu(1),&
         nav%u(1),nav%fu(1),nav%sigmau,nav%dcx,nav%dcy,nav%dcz,'u')

    !-> end initialize v influence matrix
    call influence_matrix_init_end(mpid,nav%infv,nav%scv,nav%bcv(1),&
         nav%v(1),nav%fv(1),nav%sigmau,nav%dcx,nav%dcy,nav%dcz,'v')

    !-> end initialize w influence matrix
    call influence_matrix_init_end(mpid,nav%infw,nav%scw,nav%bcw(1),&
         nav%w(1),nav%fw(1),nav%sigmau,nav%dcx,nav%dcy,nav%dcz,'w')

    !-> end initialize velocity influence matrix
    call influence_matrix_init_end(mpid,nav%infp,nav%scp,nav%bcp(1),&
         nav%p(1),nav%fp(1),nav%sigmap,nav%dcx,nav%dcy,nav%dcz,'p')

    !--------------------------------------------------------------------
    !-> initialize u multidomain solver
    call md_solve_init(mpid,nav%infu)
 
    !-> initialize v multidomain solver
    call md_solve_init(mpid,nav%infv)
 
    !-> initialize w multidomain solver
    call md_solve_init(mpid,nav%infw)
 
    !-> initialize pressuremultidomain solver
    call md_solve_init(mpid,nav%infp,null=1)

    !--------------------------------------------------------------------
    !-> initialize fields

    do i=1,nav%nt
       nav%u(i)%f=0._rk ; nav%v(i)%f=0._rk ; nav%w(i)%f=0._rk ; nav%p(i)%f=0._rk
       nav%fu(i)%f=0._rk ; nav%fv(i)%f=0._rk ; nav%fw(i)%f=0._rk ; nav%fp(i)%f=0._rk
    enddo
    nav%phi%f=0._rk ; nav%fphi%f=0._rk
    do i=1,nav%nt
!    do i=0,nav%nt
       nav%bcu(i)%bcx=0._rk ; nav%bcu(i)%bcy=0._rk ; nav%bcu(i)%bcz=0._rk
       nav%bcv(i)%bcx=0._rk ; nav%bcv(i)%bcy=0._rk ; nav%bcv(i)%bcz=0._rk 
       nav%bcw(i)%bcx=0._rk ; nav%bcw(i)%bcy=0._rk ; nav%bcw(i)%bcz=0._rk 
       nav%bcp(i)%bcx=0._rk ; nav%bcp(i)%bcy=0._rk ; nav%bcp(i)%bcz=0._rk  
    enddo
    nav%bcphi%bcx=0._rk ; nav%bcphi%bcy=0._rk ; nav%bcphi%bcz=0._rk

  end subroutine navier_initialization

  subroutine navier_finalization(cmd,mpid,nav)
! -----------------------------------------------------------------------
! navier : finalize navier type
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 10/2012
!
    use command_line
    implicit none
    type(cmd_line) :: cmd
    type(navier3d) :: nav
    type(mpi_data) :: mpid
    integer(ik) :: i

    !--------------------------------------------------------------------
    !-> deallocate velocity influence matrix
    call md_influence_matrix_destroy(mpid,nav%infu)

    !-> deallocate velocity influence matrix
    call md_influence_matrix_destroy(mpid,nav%infv)

    !-> deallocate velocity influence matrix
    call md_influence_matrix_destroy(mpid,nav%infw)

    !-> deallocate pressure influence matrix
    call md_influence_matrix_destroy(mpid,nav%infp)

    !--------------------------------------------------------------------
    !-> destroy type field
    do i=1,nav%nt
       call field_destroy(nav%u(i))
       call field_destroy(nav%v(i))
       call field_destroy(nav%w(i))
       call field_destroy(nav%p(i))
       call field_destroy(nav%fu(i))
       call field_destroy(nav%fv(i))
       call field_destroy(nav%fw(i))
       call field_destroy(nav%fp(i))
    enddo

    !--------------------------------------------------------------------
    !-> finalize petsc
    call md_petsc_finalize()
    !-> finalize mpi
    call md_mpi_finalize(mpid)

  end subroutine navier_finalization

end module class_navier_3D

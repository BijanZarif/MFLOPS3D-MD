program testnavier3d
  use command_line
  use class_navier_3D
  use class_io
  use netcdf
  use mpi
  implicit none
  type(cmd_line) :: cmd
  type(navier3d) :: nav
  type(mpi_data) :: mpid
  integer(ik) :: nx,ny,nz
  integer(ik) :: ite
  integer(ik) :: i,j,k,iaux
  real(rk) :: x,y,z,dx,dy,dz
  real(rk) ::error,aux,time,errort,ref,reft,err_vts_t,err_pre_t
  integer(8) :: t1,t2,irate,subite,t3
  logical :: test


  !-> get command line informations
  call commandline(cmd)

  !------------------------------------------------------------------------ 
  !-> pre-computation
  !------------------------------------------------------------------------ 
  call navier_initialization(cmd,mpid,nav)

  !-> read restart files if they exists
  call restart_read(mpid,nav,test)

!initialisation
if (.true..and..not.test) then
 call initialise_navier(nav,mpid)
endif
  
  nav%aux%f=1._rk ;     reft=integrale(mpid,nav,nav%aux)
  errort=integrale(mpid,nav,nav%u(nav%it(nav%nt)))
  if (mpid%rank==0) print*,'Debit             : ',errort/reft

  nav%aux=nav%u(nav%it(nav%nt))
  call navier_nullify_boundary(mpid,nav,nav%aux,0)
  error= maxval(nav%aux%f)
  call md_mpi_reduce_double_max(mpid,error,errort)
  if (mpid%rank==0) print*,'U Max             : ',errort

  call navier_write_fields(mpid,nav,1,0)

  !------------------------------------------------------------------------ 
  !-> time loop
  !------------------------------------------------------------------------ 

  err_vts_t=0._rk
  err_pre_t=0._rk
  call system_clock(t1,irate)
temps:  do ite=1,nav%ntime

  call system_clock(t3,irate)
     if (ite==20) then
       call system_clock(t1,irate)
       err_vts_t=0._rk
       err_pre_t=0._rk
     endif

     !-> time update
     call navier_time(nav)

     if (int((ite-1)/10)*10.eq.(ite-1).and.mpid%rank==0) write(*,'(17a)', advance= 'yes') &
     "   it","    time","  subit","  it  u   res","    it  v   res","   it   w   res",&
     "   it   p   res","    div","       max","      CFLx","       CFLy","       CFLz","     T_moy","    T_inst"
subit:  do subite=1,nav%nsubite
     nav%subite=int(subite,ik)

     if (mpid%rank==0) write(*,'(i5,X,es9.2,X,i2)', advance= 'no') ite,nav%time,subite
     !---------------------------------------------------------------------
!     if (mpid%rank==0) then
!        call color(ired);print'(a)','Time : ';call color(color_off)
!     endif
     !-> define bc
     call navier_bc_velocity(mpid,nav)
     call navier_LES(mpid,nav)
     
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
     nav%sub_u=nav%u(nav%it(1))
     nav%sub_v=nav%v(nav%it(1))
     nav%sub_w=nav%w(nav%it(1))
     nav%sub_p=nav%p(nav%it(1))

     !---------------------------------------------------------------------
     !-> check solution

     nav%aux%f=1._rk
     ref=norme(mpid,nav,nav%aux)

     reft=0.5_rk*(norme(mpid,nav,derxm(nav%dcm,nav%u(nav%it(1))))**2 &
                 +norme(mpid,nav,derym(nav%dcm,nav%v(nav%it(1))))**2 &
                 +norme(mpid,nav,derzm(nav%dcm,nav%w(nav%it(1)))))

     nav%aux%f=0._rk
     nav%aux=derxm(nav%dcm,nav%u(nav%it(1)))+&
             derym(nav%dcm,nav%v(nav%it(1)))+&
             derzm(nav%dcm,nav%w(nav%it(1)))

    error=norme(mpid,nav,nav%aux)
!    if (mpid%rank==0) print*,'error Div V       : ',error/ref error/reft
    if (mpid%rank==0) write(*,'(X,es9.2)', advance= 'no') error/ref
    if(error>1d10) exit temps

!    nav%aux%f=1._rk ;     reft=integrale(mpid,nav,nav%aux)
!    errort=integrale(mpid,nav,nav%u(nav%it(1)))
!    if (mpid%rank==0) print*,'Debit             : ',errort/reft
!    if (mpid%rank==0) write(*,'(X,es9.2)', advance= 'no') errort/reft
!    if(errort/reft>1d10) exit temps

    nav%aux=nav%u(nav%it(1))
    call navier_nullify_boundary(mpid,nav,nav%aux,0)
    error= maxval(nav%aux%f)
    call md_mpi_reduce_double_max(mpid,error,errort)

!    if (mpid%rank==0) print*,'U Max             : ',errort
    if (mpid%rank==0) write(*,'(X,es9.2)', advance= 'no') errort
    if(errort>1d10) exit temps

!    errort=0.5_rk*(norme(mpid,nav,nav%u(nav%it(1)))**2 &
!                  +norme(mpid,nav,nav%v(nav%it(1)))**2 &
!                  +norme(mpid,nav,nav%w(nav%it(1))))
!    if (mpid%rank==0) print*,'En Cinet  V       : ',errort/reft
!    if (mpid%rank==0) write(*,'(X,es9.2)', advance= 'no') errort/reft
!    if(errort/reft>1d10) exit temps

!    nav%aux=nav%p(nav%it(1))
!    call navier_nullify_boundary(mpid,nav,nav%aux,0)
!    error=integrale(mpid,nav,nav%aux)
!    nav%aux=nav%aux-error/ref
!    nav%p(nav%it(1))=nav%aux

!    nav%aux=nav%p(nav%it(1)) - nav%p(nav%it(nav%nt))
!    call navier_nullify_boundary(mpid,nav,nav%aux,0)
!    error=integrale(mpid,nav,nav%aux)
!    nav%aux=nav%aux- error/reft
!    error=norme(mpid,nav,nav%aux)
!    if (mpid%rank==0) print*,'Station   P       : ',error,error/(reft)
!    if (mpid%rank==0) write(*,'(X,es9.2)', advance= 'no') error
!    if(error>1d10) exit temps

!    errort=norme(mpid,nav,nav%u(nav%it(1))-nav%u(nav%it(nav%nt)))**2 &
!          +norme(mpid,nav,nav%v(nav%it(1))-nav%v(nav%it(nav%nt)))**2 &
!          +norme(mpid,nav,nav%w(nav%it(1))-nav%w(nav%it(nav%nt)))
!    if (mpid%rank==0) print*,'Station   V       : ',sqrt(errort),sqrt(errort)/(reft)
!    if (mpid%rank==0) write(*,'(X,es9.2)', advance= 'no') sqrt(errort)
!    if(sqrt(errort)>1d10) exit temps

!$OMP PARALLEL DO &
!$OMP DEFAULT(SHARED) PRIVATE(i,j,k,dx,dy,dz) &
!$OMP SCHEDULE(RUNTIME)
    do k=1,nav%nz
       dz= nav%gridz%dgrid1d(k)
       do j=1,nav%ny
          dy=nav%gridy%dgrid1d(j)
          do i=1,nav%nx
            dx= nav%gridx%dgrid1d(i)
            nav%aux%f(i,j,k) =nav%ts*nav%u(1)%f(i,j,k)/dx
            nav%aux1%f(i,j,k)=nav%ts*nav%v(1)%f(i,j,k)/dy
            nav%aux2%f(i,j,k)=nav%ts*nav%w(1)%f(i,j,k)/dz
          enddo
       enddo
    enddo
!$OMP END PARALLEL DO

    call navier_nullify_boundary(mpid,nav,nav%aux,0)
    error= maxval(nav%aux%f)
    call md_mpi_reduce_double_max(mpid,error,errort)
    if (mpid%rank==0) write(*,'(X,es9.2)', advance= 'no') errort

    call navier_nullify_boundary(mpid,nav,nav%aux1,0)
    error= maxval(nav%aux1%f)
    call md_mpi_reduce_double_max(mpid,error,errort)
    if (mpid%rank==0) write(*,'(X,es9.2)', advance= 'no') errort

    call navier_nullify_boundary(mpid,nav,nav%aux2,0)
    error= maxval(nav%aux2%f)
    call md_mpi_reduce_double_max(mpid,error,errort)
    if (mpid%rank==0) write(*,'(X,es9.2)', advance= 'no') errort
  call system_clock(t2,irate)
  time=real(t2-t1)/real(irate)
  if (mpid%rank==0) write(*,'(2(X,es9.2))', advance= 'yes') time/(ite-19),real(t2-t3)/real(irate)

     if (test)     exit subit
     enddo subit

     !-> switch it
     iaux=nav%it(1)
     do i=1,nav%nt-1
        nav%it(i)=nav%it(i+1)
     enddo
     nav%it(nt)=iaux

  if (int(ite/300)*300.eq.ite) then
    if (mpid%rank==0) print*,'Write fields'
    call restart_write(mpid,nav)
  endif
  call navier_write_fields(mpid,nav,300,ite)

  enddo temps
  !------------------------------------------------------------------------ 
  !-> time loop end
  !------------------------------------------------------------------------ 
  if (mpid%rank==0) write(*,'(a)', advance= 'yes') ' STOP '

  call system_clock(t2,irate)
  time=real(t2-t1)/real(irate)
  if (mpid%rank==0) print*,'time : ',time,time/(ite-19)

  call restart_write(mpid,nav)
  call navier_write_fields(mpid,nav,ite,ite)

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

!     nav%aux%f=0._rk
!     nav%aux=derxm(nav%dcm,nav%u(nav%it(1)))+&
!             derym(nav%dcm,nav%v(nav%it(1)))+&
!             derzm(nav%dcm,nav%w(nav%it(1)))
!    ref=norme(mpid,nav,nav%aux)
!    nav%aux=derxm(nav%dcm,nav%u(nav%it(1)))+&
!            derym(nav%dcm,nav%v(nav%it(1)))+&
!            derzm(nav%dcm,nav%w(nav%it(1)))-&
!            derxm(nav%dcm,nav%sub_u)-&
!            derym(nav%dcm,nav%sub_v)-&
!            derzm(nav%dcm,nav%sub_w)

!    error=norme(mpid,nav,nav%aux)/ref
!    if (mpid%rank==0) print*,'conv Div V       : ',error1

    aux%f=sqrt(u%f**2 + v%f**2 + w%f**2)
    ref=norme(mpid,nav,aux)

    aux%f=sqrt((sub_u%f-u%f)**2 + (sub_v%f-v%f)**2 + (sub_w%f-w%f)**2)
    error1=norme(mpid,nav,aux)/ref

!    if (mpid%rank==0) print*,'conv tot V       : ',error1

    aux%f=1._rk   ;    ref=integrale(mpid,nav,aux)
    aux=p - sub_p ; error2=integrale(mpid,nav,aux)

    sub_p=sub_p + error2/ref
    aux  =sub_p     ;    ref=norme(mpid,nav,aux)
    aux  =p - sub_p ; error2=norme(mpid,nav,aux)/ref
!    if (mpid%rank==0) print*,'conv tot P       : ',error2

    if (error1<eps.and.error2<eps)  test=.true.

end subroutine testconv

function norme(mpid,nav,x)
  use class_md

  use class_field
  use class_navier_3D
  use precision
  implicit none
  type(mpi_data) :: mpid
  type(navier3d) :: nav
  type(field) :: x
  real(rk) :: norme
norme=norme2(mpid,nav,x)
!norme=normeinf(mpid,nav,x)
end function norme

subroutine initialise_navier(nav,mpid)
  implicit none
  type(navier3d) :: nav
  type(mpi_data) :: mpid
  type(mesh_grid) :: gridxi,gridyi,gridzi
  character(len=512) :: fich_grid(3),var_grid(3),fich_vel(6),var_vel(6)


  if (mpid%rank==0)     write(*,'(a)',advance='no') 'Initialisation : '

fich_grid=""
fich_vel=""
var_grid=""
var_vel=""

if(.true.) then ! initialisation
if(.true.) then ! jimenez

  fich_grid="init/Re180.025.nc"
  fich_vel(1:4)="init/Re180.025.nc"

!  fich_grid="init/Re950.365.nc"
!  fich_vel(1:4)="init/Re950.365.nc"

  var_grid=(/'grid_x','grid_y','grid_z'/)
  var_vel(1:4)=(/'velocity_x','velocity_y','velocity_z','pressure  '/)

elseif(.false.) then ! our files (different mesh)

  fich_grid=(/"init/grid_x.nc","init/grid_y.nc","init/grid_z.nc"/)
  fich_vel=(/"init/vel_u.nc  ","init/vel_v.nc  ","init/vel_w.nc  ","init/vel_p.nc  ","init/vel_phi.nc","init/les_nu.nc "/)
  var_grid=(/'gridx','gridy','gridz'/)
  var_vel=(/'U     ','V     ','W     ','P     ','P     ','les_nu'/)

endif

  if (mpid%rank==0)     write(*,'(a)',advance='no') 'Read Files - '
  call read_initfiles(nav,fich_grid,var_grid,fich_vel,var_vel,mpid)
else
!$OMP PARALLEL DO &
!$OMP DEFAULT(SHARED) PRIVATE(i,j,k,x,y,z) &
!$OMP SCHEDULE(RUNTIME)
     do k=1,nav%nz
        z=nav%gridz%grid1d(k)
        do j=1,nav%ny
           y=nav%gridy%grid1d(j)
           do i=1,nav%nx
              x=nav%gridx%grid1d(i)
      nav%u(1)%f(i,j,k)=(5._rk*(1._rk - y**4)*0.25_rk &
                      + 0.3_rk*cos(12._rk*z)*exp(0.5_rk-32.4_rk*(1._rk-abs(y))**2)*(1._rk -abs(y)) )*0.9_rk
      nav%v(1)%f(i,j,k)= 0._rk
      nav%w(1)%f(i,j,k)=(21.6_rk*sin(12._rk*x)*exp(-32.4_rk*(1._rk-abs(y))**2)*(1._rk - abs(y)))*0.9_rk
      nav%p(1)%f(i,j,k)= 0._rk
      nav%phi(1)%f(i,j,k)= 0._rk
         enddo
      enddo
   enddo
!$OMP END PARALLEL DO

endif

!periodisation ! todo
!nettoyage
   call navier_nullify_boundary(mpid,nav,nav%u(1),0)
   call navier_nullify_boundary(mpid,nav,nav%v(1),0)
   call navier_nullify_boundary(mpid,nav,nav%w(1),0)
   call navier_nullify_boundary(mpid,nav,nav%p(1),0)
   call navier_nullify_boundary(mpid,nav,nav%phi(1),0)
   call navier_nullify_boundary(mpid,nav,nav%les_nu,0)
   do iaux=2,nav%nt 
      nav%u(iaux)=nav%u(1)
      nav%v(iaux)=nav%v(1)
      nav%w(iaux)=nav%w(1)
      nav%p(iaux)=nav%p(1)
      nav%phi(iaux)=nav%phi(1)
   enddo

  if (mpid%rank==0)     write(*,'(a)',advance='yes') 'OK'

end subroutine initialise_navier

subroutine interpol_initfiles(nav,gridxi,gridyi,gridzi,uo,u1)
  implicit none
  type(navier3d),intent(inout) :: nav
  type(mesh_grid),intent(in) :: gridxi,gridyi,gridzi
  type(field),intent(in)     :: uo
  type(field),intent(inout)     :: u1

  integer(ik) :: i,j,k,iaux,i0,j0,k0,i1,j1,k1,i2,j2,k2
  real(rk) :: x,y,z,x1,x2,y1,y2,z1,z2

! simple interpolation for uo -> u and others fields
!$OMP PARALLEL DO &
!$OMP DEFAULT(SHARED) PRIVATE(i,j,k,x,y,z) &
!$OMP SCHEDULE(RUNTIME)
   do k=1,nav%nz
      z=nav%gridz%grid1d(k)
!      z=nav%gridz%grid1d(k)*2._rk
!      z=nav%gridz%grid1d(k)*4._rk
      do k1=2,gridzi%nz
        k2=k1-1
        z1=gridzi%grid1d(k1)
        z2=gridzi%grid1d(k2)
        if (abs(abs(z1-z)+abs(z2-z)-abs(z1-z2))<1e-8) then
         do j=1,nav%ny
            y=nav%gridy%grid1d(j)
!            y=nav%gridy%grid1d(j)+1._rk
            do j1=2,gridyi%ny
              j2=j1-1
              y1=gridyi%grid1d(j1)
              y2=gridyi%grid1d(j2)
               if (abs(abs(y1-y)+abs(y2-y)-abs(y1-y2))<1e-8) then
               do i=1,nav%nx
                  x=nav%gridx%grid1d(i)
!                  x=nav%gridx%grid1d(i)*2._rk
!                  x=nav%gridx%grid1d(i)*4._rk
                  do i1=2,gridxi%nx
                    i2=i1-1
                    x1=gridxi%grid1d(i1)
                    x2=gridxi%grid1d(i2)
                    if (abs(abs(x1-x)+abs(x2-x)-abs(x1-x2))<1e-8) then 

!if(j.ne.1.and.j.ne.nav%ny) then !detection of null edges
!endif

      u1%f(i,j,k)= &
         uo%f(i1,j1,k1)*(x-x2)*(y-y2)*(z-z2)/((x1-x2)*(y1-y2)*(z1-z2)) &
       + uo%f(i1,j1,k2)*(x-x2)*(y-y2)*(z1-z)/((x1-x2)*(y1-y2)*(z1-z2)) &
       + uo%f(i1,j2,k1)*(x-x2)*(y1-y)*(z-z2)/((x1-x2)*(y1-y2)*(z1-z2)) &
       + uo%f(i1,j2,k2)*(x-x2)*(y1-y)*(z1-z)/((x1-x2)*(y1-y2)*(z1-z2)) &
       + uo%f(i2,j1,k1)*(x1-x)*(y-y2)*(z-z2)/((x1-x2)*(y1-y2)*(z1-z2)) &
       + uo%f(i2,j1,k2)*(x1-x)*(y-y2)*(z1-z)/((x1-x2)*(y1-y2)*(z1-z2)) &
       + uo%f(i2,j2,k1)*(x1-x)*(y1-y)*(z-z2)/((x1-x2)*(y1-y2)*(z1-z2)) &
       + uo%f(i2,j2,k2)*(x1-x)*(y1-y)*(z1-z)/((x1-x2)*(y1-y2)*(z1-z2))

                        exit
                      endif
                    enddo
                 enddo

                  exit
                endif
              enddo
           enddo

          exit
        endif
      enddo
   enddo
!$OMP END PARALLEL DO
end subroutine interpol_initfiles

subroutine read_initfiles(nav,fich_grid,var_grid,fich_vel,var_vel,mpid)
  implicit none
  type(navier3d),intent(inout) :: nav
  type(mpi_data) :: mpid
  character(len=512),intent(in) :: fich_grid(3),var_grid(3),fich_vel(6),var_vel(6)
  type(mesh_grid) :: gridxi,gridyi,gridzi
  type(field)     :: uo
  type(mesh_grid) :: gridxg,gridyg,gridzg
  character(len=512) :: dim_name(3)
  integer(ik) :: ncid, startv(3),countv(3), varid(1), dim_len(3)
  integer(ik) :: startvi(3),countvi(3)
  integer(ik) :: i,j,k,l
  real(rk) :: a,b
   
startvi=1
  if (mpid%rank==0)     write(*,'(a)',advance='no') 'grid'
do i=1,3 ! read grid
  if (mpid%rank==0)     write(*,'(I1)',advance='no') i
    call get_var3d_info(trim(fich_grid(i)),trim(var_grid(i)),dim_name(1),dim_len(1))

    startv=1
    countv=dim_len

    if(dim_len(i).le.1) then
       dim_len(i)=dim_len(1)
      do j=1,3
        if(j/=i) dim_len(j)=1
      enddo
    else
      do j=1,3
        if(j/=i) dim_len(j)=1
        if(j/=i) countv(j)=1
      enddo
    endif

    if(i==1) call mesh_init(gridxg,'gridx','x',dim_len(1),dim_len(2),dim_len(3))
    if(i==2) call mesh_init(gridyg,'gridy','y',dim_len(1),dim_len(2),dim_len(3))
    if(i==3) call mesh_init(gridzg,'gridz','z',dim_len(1),dim_len(2),dim_len(3))

    call io_check(nf90_open(path=trim(fich_grid(i)),mode=nf90_nowrite,ncid=ncid))

                            
    !-> get variable id
    call io_check(nf90_inq_varid(ncid,trim(var_grid(i)),varid(1)))
                                                        
    !-> read field variable
    if(i==1) call io_check(nf90_get_var(ncid,varid(1),gridxg%grid3d,start=startv,count=countv))
    if(i==2) call io_check(nf90_get_var(ncid,varid(1),gridyg%grid3d,start=startv,count=countv))
    if(i==3) call io_check(nf90_get_var(ncid,varid(1),gridzg%grid3d,start=startv,count=countv))

    !-> close file              
    call io_check(nf90_close(ncid))

    if(i==1) then
      a=nav%gridx%grid1d(1)
      b=nav%gridx%grid1d(nav%nx)
      do j=1,gridxg%nx
        if (a<gridxg%grid3d(j,1,1)) exit
      enddo
      startvi(i)=max(1,j-1)
      do j=startvi(i),gridxg%nx
        if (b<gridxg%grid3d(j,1,1)) exit
      enddo
     countvi(i)=min(j,gridxg%nx)-startvi(i)+1
    endif
    if(i==2) then
      a=nav%gridy%grid1d(1)
      b=nav%gridy%grid1d(nav%ny)
      do j=1,gridyg%ny
        if (a<gridyg%grid3d(1,j,1)) exit
      enddo
      startvi(i)=max(1,j-1)
      do j=startvi(i),gridyg%ny
        if (b<gridyg%grid3d(1,j,1)) exit
      enddo
     countvi(i)=min(j,gridyg%ny)-startvi(i)+1
    endif
    if(i==3) then
      a=nav%gridz%grid1d(1)
      b=nav%gridz%grid1d(nav%nz)
      do j=1,gridzg%nz
        if (a<gridzg%grid3d(1,1,j)) exit
      enddo
      startvi(i)=max(1,j-1)
      do j=1,gridzg%nz
        if (b<gridzg%grid3d(1,1,j)) exit
      enddo

     countvi(i)=min(j,gridzg%nz)-startvi(i)+1

    endif

    if(i==1) call mesh_init(gridxi,'gridx','x',countvi(1),1,1)
    if(i==2) call mesh_init(gridyi,'gridy','y',1,countvi(2),1)
    if(i==3) call mesh_init(gridzi,'gridz','z',1,1,countvi(3))

    if(i==1) gridxi%grid1d(:)=gridxg%grid3d(startvi(i):startvi(i)+countvi(i)-1,1,1)
    if(i==2) gridyi%grid1d(:)=gridyg%grid3d(1,startvi(i):startvi(i)+countvi(i)-1,1)
    if(i==3) gridzi%grid1d(:)=gridzg%grid3d(1,1,startvi(i):startvi(i)+countvi(i)-1)

    if(i==1) deallocate(gridxg%grid3d, gridxg%grid1d) 
    if(i==2) deallocate(gridyg%grid3d, gridyg%grid1d) 
    if(i==3) deallocate(gridzg%grid3d, gridzg%grid1d) 

enddo

  if (mpid%rank==0)     write(*,'(a)',advance='no') ' - Fields - '

!do i=0,mpid%ndom  ! one proc after another
!  if (mpid%rank==i)   then
!  write(*,'(a,i1)',advance='no') ',',i
  call field_init(uo,"U",countvi(1),countvi(2),countvi(3))

if(trim(fich_vel(1))/="") then
  call read_part_files(fich_vel(1),var_vel(1),startvi,countvi,uo)
  call interpol_initfiles(nav,gridxi,gridyi,gridzi,uo,nav%u(1))
endif
if(trim(fich_vel(2))/="") then
  call read_part_files(fich_vel(2),var_vel(2),startvi,countvi,uo)
  call interpol_initfiles(nav,gridxi,gridyi,gridzi,uo,nav%v(1))
endif
if(trim(fich_vel(3))/="") then
  call read_part_files(fich_vel(3),var_vel(3),startvi,countvi,uo)
  call interpol_initfiles(nav,gridxi,gridyi,gridzi,uo,nav%w(1))
endif
if(trim(fich_vel(4))/="") then
  call read_part_files(fich_vel(4),var_vel(4),startvi,countvi,uo)
  call interpol_initfiles(nav,gridxi,gridyi,gridzi,uo,nav%p(1))
endif
if(trim(fich_vel(5))/="") then
  call read_part_files(fich_vel(5),var_vel(5),startvi,countvi,uo)
  call interpol_initfiles(nav,gridxi,gridyi,gridzi,uo,nav%phi(1))
else
  nav%phi(1)=nav%p(1)
endif
if(trim(fich_vel(6))/="") then
  call read_part_files(fich_vel(6),var_vel(6),startvi,countvi,uo)
  call interpol_initfiles(nav,gridxi,gridyi,gridzi,uo,nav%les_nu)
endif
  call field_destroy(uo)

!endif
!call md_mpi_barrier(mpid)
!enddo

end subroutine read_initfiles

subroutine read_part_files(fich,var,start,count,uo,mpid)
  implicit none
  type(mpi_data),optional :: mpid
  character(len=512),intent(in) :: fich,var
  integer(ik),intent(in)   :: start(3),count(3)
  type(field),intent(inout)   :: uo
  integer(ik) :: ncid,varid(1)
  integer(ik) :: startvi(3),countvi(3)

    !-> open file
    if (present(mpid)) then
       call io_check(nf90_open(path=trim(fich),&
            mode=IOR(NF90_NOWRITE,NF90_MPIPOSIX),ncid=ncid,&
!            mode=IOR(NF90_NOWRITE,NF90_MPIIO),ncid=ncid,&
            comm=mpid%comm,info=MPI_INFO_NULL))
    else
       call io_check(nf90_open(path=trim(fich),mode=nf90_nowrite,ncid=ncid))
    endif

    !-> get variable id
    call io_check(nf90_inq_varid(ncid,trim(var),varid(1)))

    !-> read field variable
    call io_check(nf90_get_var(ncid,varid(1),uo%f,start=start,count=count))

    !-> close file              
    call io_check(nf90_close(ncid))

end subroutine read_part_files

end program testnavier3d

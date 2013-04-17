module class_derivatives_coefficient
! -----------------------------------------------------------------------
! Name :
! class derivatives 
! -----------------------------------------------------------------------
! Object : 
! Computation of first and second derivatives with an 8-order compact 
! finite difference scheme of maximum stencil 5-7 on irregular grid
! -----------------------------------------------------------------------
! Files :
! class_derivatives.f90
! class_derivatives_coefficient.f90
! -----------------------------------------------------------------------
! Public type :
! derivatives_coefficients -> coefficients for derivatives
! -----------------------------------------------------------------------
! Public Procedure :
! derivatives_coefficients_init -> initialize derivatives coefficients 
! derx,dery,derz -> compute first derivatives in x,y,z directions
! dderx,ddery,dderz -> compute second derivatives in x,y,z directions
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 05/2011
!
  use precision
  implicit none
!  private
  real(rk),private,save :: h(7)
  
contains
subroutine der_coeffs_c(a1,b1,c1,d1,e1,alpha,beta,gamma,delta,h1,h2,h3,h4)
! -----------------------------------------------------------------------
! Derivatives : Coefficients for first derivatives : non-uniform grid,centered 
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 04/2011
!
  implicit none
  real(rk),intent(out) :: a1,b1,c1,d1,e1,alpha,beta,gamma,delta
  real(rk),intent(in) :: h1,h2,h3,h4
  !
  ! n : size of linear system
  ! info : output of solver (zero is ok) 
  integer,parameter :: n=9
  character(len=1) :: fact,trans,equed
  integer(ik) :: nrhs,lda,ldb,ldaf,ldx
  real(rk) :: a(n,n),af(n,n),ipiv(n),b(n,1),r(n),c(n),x(n),work(4*n)
  real(rk) :: rcond,ferr,berr,dum
  integer(ik) :: iwork(n),info

  !-> space interval
  h(1)=h1 ; h(2)=h2 ; h(3)=h3 ; h(4)=h4

  !-> define matrix
  a(1,1)=0._rk;a(1,2)=0._rk;a(1,3)=0._rk;a(1,4)=0._rk;a(1,5)=1._rk;a(1,6)=1._rk;a(1,7)=1._rk;a(1,8)=1._rk;a(1,9)=1._rk
  
  a(2,1)=-1._rk;a(2,2)=-1._rk;a(2,3)=-1._rk;a(2,4)=-1._rk;a(2,5)=-h2-h1;a(2,6)=-h2;a(2,7)=0._rk
  a(2,8)=h3;a(2,9)=h4+h3
  
  a(3,1)=h2+h1;a(3,2)=h2;a(3,3)=-h3;a(3,4)=-h4-h3;a(3,5)=(h2+h1)**2/2.0_rk;a(3,6)=h2**2/2.0_rk
  a(3,7)=0._rk;a(3,8)=h3**2/2.0_rk;a(3,9)=(-h4-h3)**2/2.0_rk
  
  a(4,1)=-(h2+h1)**2/2.0_rk;a(4,2)=-h2**2/2.0_rk;a(4,3)=-h3**2/2.0_rk;a(4,4)=-(-h4-h3)**2/2.0_rk
  a(4,5)=-(h2+h1)**3/6.0_rk;a(4,6)=-h2**3/6.0_rk;a(4,7)=0._rk;a(4,8)=h3**3/6.0_rk
  a(4,9)=-(-h4-h3)**3/6.0_rk
  
  a(5,1)=(h2+h1)**3/6.0_rk;a(5,2)=h2**3/6.0_rk;a(5,3)=-h3**3/6.0_rk;a(5,4)=(-h4-h3)**3/6.0_rk
  a(5,5)=(h2+h1)**4/24.0_rk;a(5,6)=h2**4/24.0_rk;a(5,7)=0._rk;a(5,8)=h3**4/24.0_rk;a(5,9)=(-h4-h3)**4/24.0_rk
  
  a(6,1)=-(h2+h1)**4/24.0_rk;a(6,2)=-h2**4/24.0_rk;a(6,3)=-h3**4/24.0_rk;a(6,4)=-(-h4-h3)**4/24.0_rk
  a(6,5)=-(h2+h1)**5/120.0_rk;a(6,6)=-h2**5/120.0_rk;a(6,7)=0._rk;a(6,8)=h3**5/120.0_rk
  a(6,9)=-(-h4-h3)**5/120.0_rk

  a(7,1)=(h2+h1)**5/120.0_rk;a(7,2)=h2**5/120.0_rk;a(7,3)=-h3**5/120.0_rk;a(7,4)=(-h4-h3)**5/120.0_rk
  a(7,5)=(h2+h1)**6/720.0_rk;a(7,6)=h2**6/720.0_rk;a(7,7)=0._rk;a(7,8)=h3**6/720.0_rk
  a(7,9)=(-h4-h3)**6/720.0_rk

  a(8,1)=-(h2+h1)**6/720.0_rk;a(8,2)=-h2**6/720.0_rk;a(8,3)=-h3**6/720.0_rk;a(8,4)=-(-h4-h3)**6/720.0_rk
  a(8,5)=-(h2+h1)**7/5040.0_rk;a(8,6)=-h2**7/5040.0_rk;a(8,7)=0._rk;a(8,8)=h3**7/5040.0_rk
  a(8,9)=-(-h4-h3)**7/5040.0_rk

  a(9,1)=(h2+h1)**7/5040.0_rk;a(9,2)=h2**7/5040.0_rk;a(9,3)=-h3**7/5040.0_rk
  a(9,4)=(-h4-h3)**7/5040.0_rk;a(9,5)=(h2+h1)**8/40320.0_rk;a(9,6)=h2**8/40320.0_rk
  a(9,7)=0._rk;a(9,8)=h3**8/40320.0_rk;a(9,9)=(-h4-h3)**8/40320.0_rk

  !-> define rhs
  b(1,1)=0._rk ; b(2,1)=1._rk ; b(3,1)=0._rk ; b(4,1)=0._rk ; b(5,1)=0._rk ; b(6,1)=0._rk ; b(7,1)=0._rk
  b(8,1)=0._rk ; b(9,1)=0._rk

  fact='E' ; trans='N' ; nrhs=1 ; lda=n ; ldb=n ; ldaf=n ; equed='N' ; ldx=n
  call dgesvx( fact, trans, n, nrhs, a, lda, af, ldaf, ipiv,equed, r, c, b, ldb, x, &
       ldx, rcond, ferr, berr, work, iwork, info )

  !-> output coefficient
  alpha=x(1) ; beta=x(2) ; gamma=x(3) ; delta=x(4) 
  a1=x(5) ; b1=x(6) ; c1=x(7) ; d1=x(8) ; e1=x(9) 

  dum=0._rk
!  write(333,'(11es17.8,i4,4es17.8)')alpha,beta,1._rk,gamma,delta,a1,b1,c1,d1,e1,dum,&
!       info,rcond,ferr,berr,work(1)

end subroutine der_coeffs_c

subroutine der_coeffs_i1(a1,b1,c1,d1,e1,f1,g1,alpha,beta,gamma,delta,h1,h2,h3,h4,h5,h6)
! -----------------------------------------------------------------------
! Derivatives : Coefficients for first derivatives : non-uniform grid, first point
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 04/2011
!
  implicit none
  real(rk),intent(out) :: a1,b1,c1,d1,e1,f1,g1,alpha,beta,gamma,delta
  real(rk),intent(in) :: h1,h2,h3,h4,h5,h6
  !
  ! n : size of linear system
  ! info : output of solver (zero is ok) 
  integer,parameter :: n=9
  character(len=1) :: fact,trans,equed
  integer(ik) :: nrhs,lda,ldb,ldaf,ldx
  real(rk) :: a(n,n),af(n,n),ipiv(n),b(n,1),r(n),c(n),x(n),work(4*n)
  real(rk) :: rcond,ferr,berr
  integer(ik) :: iwork(n),info

  !-> space interval
  h(1)=h1 ; h(2)=h2 ; h(3)=h3 ; h(4)=h4 ; h(5)=h5 ; h(6)=h6

  !-> define matrix
  A(1,1)=0._rk;A(1,2)=0._rk;A(1,3)=0._rk;A(1,4)=1._rk;A(1,5)=1._rk;A(1,6)=1._rk;A(1,7)=1._rk;A(1,8)=1._rk;A(1,9)=1._rk !;A(1,10)=1._rk
  
  A(2,1)=-1._rk;A(2,2)=-1._rk;A(2,3)=-1._rk;A(2,4)=0._rk;A(2,5)=h1;A(2,6)=h2+h1;A(2,7)=h3+h2+h1
  A(2,8)=h4+h3+h2+h1;A(2,9)=h5+h4+h3+h2+h1 !;A(2,10)=h6+h5+h4+h3+h2+h1

  A(3,1)=-h1;A(3,2)=-h2-h1;A(3,3)=-h3-h2-h1;A(3,4)=0._rk;A(3,5)=h1**2/2.0_rk
  A(3,6)=(-h2-h1)**2/2.0_rk;A(3,7)=(-h3-h2-h1)**2/2.0_rk;A(3,8)=(-h4-h3-h2-h1)**2/2.0_rk
  A(3,9)=(-h5-h4-h3-h2-h1)**2/2.0_rk !;A(3,10)=(-h6-h5-h4-h3-h2-h1)**2/2.0_rk

  A(4,1)=-h1**2/2.0_rk;A(4,2)=-(-h2-h1)**2/2.0_rk;A(4,3)=-(-h3-h2-h1)**2/2.0_rk;A(4,4)=0._rk
  A(4,5)=h1**3/6.0_rk;A(4,6)=-(-h2-h1)**3/6.0_rk;A(4,7)=-(-h3-h2-h1)**3/6.0_rk
  A(4,8)=-(-h4-h3-h2-h1)**3/6.0_rk;A(4,9)=-(-h5-h4-h3-h2-h1)**3/6.0_rk
!  A(4,10)=-(-h6-h5-h4-h3-h2-h1)**3/6.0_rk

  A(5,1)=-h1**3/6.0_rk;A(5,2)=(-h2-h1)**3/6.0_rk;A(5,3)=(-h3-h2-h1)**3/6.0_rk
  A(5,4)=0._rk;A(5,5)=h1**4/24.0_rk;A(5,6)=(-h2-h1)**4/24.0_rk;A(5,7)=(-h3-h2-h1)**4/24.0_rk
  A(5,8)=(-h4-h3-h2-h1)**4/24.0_rk;A(5,9)=(-h5-h4-h3-h2-h1)**4/24.0_rk
!  A(5,10)=(-h6-h5-h4-h3-h2-h1)**4/24.0_rk

  A(6,1)=-h1**4/24.0_rk;A(6,2)=-(-h2-h1)**4/24.0_rk;A(6,3)=-(-h3-h2-h1)**4/24.0_rk
  A(6,4)=0._rk;A(6,5)=h1**5/120.0_rk;A(6,6)=-(-h2-h1)**5/120.0_rk;A(6,7)=-(-h3-h2-h1)**5/120.0_rk
  A(6,8)=-(-h4-h3-h2-h1)**5/120.0_rk;A(6,9)=-(-h5-h4-h3-h2-h1)**5/120.0_rk
!  A(6,10)=-(-h6-h5-h4-h3-h2-h1)**5/120.0_rk

  A(7,1)=-h1**5/120.0_rk;A(7,2)=(-h2-h1)**5/120.0_rk;A(7,3)=(-h3-h2-h1)**5/120.0_rk
  A(7,4)=0._rk;A(7,5)=h1**6/720.0_rk;A(7,6)=(-h2-h1)**6/720.0_rk;A(7,7)=(-h3-h2-h1)**6/720.0_rk
  A(7,8)=(-h4-h3-h2-h1)**6/720.0_rk;A(7,9)=(-h5-h4-h3-h2-h1)**6/720.0_rk
!  A(7,10)=(-h6-h5-h4-h3-h2-h1)**6/720.0_rk

  A(8,1)=-h1**6/720.0_rk;A(8,2)=-(-h2-h1)**6/720.0_rk;A(8,3)=-(-h3-h2-h1)**6/720.0_rk
  A(8,4)=0._rk;A(8,5)=h1**7/5040.0_rk;A(8,6)=-(-h2-h1)**7/5040.0_rk;A(8,7)=-(-h3-h2-h1)**7/5040.0_rk
  A(8,8)=-(-h4-h3-h2-h1)**7/5040.0_rk;A(8,9)=-(-h5-h4-h3-h2-h1)**7/5040.0_rk
!  A(8,10)=-(-h6-h5-h4-h3-h2-h1)**7/5040.0_rk
  
  A(9,1)=-h1**7/5040.0_rk;A(9,2)=(-h2-h1)**7/5040.0_rk;A(9,3)=(-h3-h2-h1)**7/5040.0_rk
  A(9,4)=0._rk;A(9,5)=h1**8/40320.0_rk;A(9,6)=(-h2-h1)**8/40320.0_rk;A(9,7)=(-h3-h2-h1)**8/40320.0_rk
  A(9,8)=(-h4-h3-h2-h1)**8/40320.0_rk;A(9,9)=(-h5-h4-h3-h2-h1)**8/40320.0_rk
!  A(9,10)=(-h6-h5-h4-h3-h2-h1)**8/40320.0_rk

!  A(10,1)=-h1**8/40320.0_rk;A(10,2)=-(-h2-h1)**8/40320.0_rk;A(10,3)=-(-h3-h2-h1)**8/40320.0_rk
!  A(10,4)=0._rk;A(10,5)=h1**9/362880.0_rk;A(10,6)=-(-h2-h1)**9/362880.0_rk
!  A(10,7)=-(-h3-h2-h1)**9/362880.0_rk;A(10,8)=-(-h4-h3-h2-h1)**9/362880.0_rk
!  A(10,9)=-(-h5-h4-h3-h2-h1)**9/362880.0_rk;A(10,10)=-(-h6-h5-h4-h3-h2-h1)**9/362880.0_rk

  !-> define rhs
  B(1,1)=0._rk ; B(2,1)=1._rk ; B(3,1)=0._rk ; B(4,1)=0._rk ; B(5,1)=0._rk ; B(6,1)=0._rk ; 
  B(7,1)=0._rk ; B(8,1)=0._rk ; B(9,1)=0._rk  !; B(10,1)=0._rk

  fact='E' ; trans='N' ; nrhs=1 ; lda=n ; ldb=n ; ldaf=n ; equed='N' ; ldx=n
  call dgesvx( fact, trans, n, nrhs, a, lda, af, ldaf, ipiv,equed, r, c, b, ldb, x, &
       ldx, rcond, ferr, berr, work, iwork, info )
  
  !-> output coefficient
  alpha=1._rk ; beta=x(1) ; gamma=x(2) ; delta=x(3) 
  a1=x(4) ; b1=x(5) ; c1=x(6) ; d1=x(7) ; e1=x(8) ; f1=x(9)  ; g1=0._rk !x(10) 

!  write(333,'(a,11es17.8,i4,4es17.8)')'di1',alpha,beta,gamma,delta,a1,b1,c1,d1,e1,f1,g1,&
!       info,rcond,ferr,berr,work(1)

end subroutine der_coeffs_i1

subroutine der_coeffs_i2(a1,b1,c1,d1,e1,f1,g1,alpha,beta,gamma,delta,h1,h2,h3,h4,h5,h6)
! -----------------------------------------------------------------------
! Derivatives : Coefficients for first derivatives : non-uniform grid, second point
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 04/2011
!
  implicit none
  real(rk),intent(out) :: a1,b1,c1,d1,e1,f1,g1,alpha,beta,gamma,delta
  real(rk),intent(in) :: h1,h2,h3,h4,h5,h6
  !
  ! n : size of linear system
  ! info : output of solver (zero is ok) 
  integer,parameter :: n=10
  character(len=1) :: fact,trans,equed
  integer(ik) :: nrhs,lda,ldb,ldaf,ldx
  real(rk) :: a(n,n),af(n,n),ipiv(n),b(n,1),r(n),c(n),x(n),work(4*n)
  real(rk) :: rcond,ferr,berr
  integer(ik) :: iwork(n),info

  !-> space interval
  h=0._rk
  h(1)=h1 ; h(2)=h2 ; h(3)=h3 ; h(4)=h4 ; h(5)=h5 ; h(6)=h6

  !-> define matrix
  A(1,1)=0._rk;A(1,2)=0._rk;A(1,3)=0._rk;A(1,4)=1._rk;A(1,5)=1._rk;A(1,6)=1._rk;A(1,7)=1._rk;A(1,8)=1._rk;A(1,9)=1._rk;A(1,10)=1._rk
  
  A(2,1)=-1._rk;A(2,2)=-1._rk;A(2,3)=-1._rk;A(2,4)=-h1;A(2,5)=0._rk;A(2,6)=h2;A(2,7)=h3+h2;A(2,8)=h4+h3+h2
  A(2,9)=h5+h4+h3+h2;A(2,10)=h6+h5+h4+h3+h2

  A(3,1)=h1;A(3,2)=-h2;A(3,3)=-h3-h2;A(3,4)=h1**2/2.0_rk;A(3,5)=0._rk;A(3,6)=h2**2/2.0_rk
  A(3,7)=(-h3-h2)**2/2.0_rk;A(3,8)=(-h4-h3-h2)**2/2.0_rk;A(3,9)=(-h5-h4-h3-h2)**2/2.0_rk
  A(3,10)=(-h6-h5-h4-h3-h2)**2/2.0_rk

  A(4,1)=-h1**2/2.0_rk;A(4,2)=-h2**2/2.0_rk;A(4,3)=-(-h3-h2)**2/2.0_rk;A(4,4)=-h1**3/6.0_rk
  A(4,5)=0._rk;A(4,6)=h2**3/6.0_rk;A(4,7)=-(-h3-h2)**3/6.0_rk;A(4,8)=-(-h4-h3-h2)**3/6.0_rk
  A(4,9)=-(-h5-h4-h3-h2)**3/6.0_rk;A(4,10)=-(-h6-h5-h4-h3-h2)**3/6.0_rk

  A(5,1)=h1**3/6.0_rk;A(5,2)=-h2**3/6.0_rk;A(5,3)=(-h3-h2)**3/6.0_rk;A(5,4)=h1**4/24.0_rk
  A(5,5)=0._rk;A(5,6)=h2**4/24.0_rk;A(5,7)=(-h3-h2)**4/24.0_rk;A(5,8)=(-h4-h3-h2)**4/24.0_rk
  A(5,9)=(-h5-h4-h3-h2)**4/24.0_rk;A(5,10)=(-h6-h5-h4-h3-h2)**4/24.0_rk

  A(6,1)=-h1**4/24.0_rk;A(6,2)=-h2**4/24.0_rk;A(6,3)=-(-h3-h2)**4/24.0_rk;A(6,4)=-h1**5/120.0_rk
  A(6,5)=0._rk;A(6,6)=h2**5/120.0_rk;A(6,7)=-(-h3-h2)**5/120.0_rk;A(6,8)=-(-h4-h3-h2)**5/120.0_rk
  A(6,9)=-(-h5-h4-h3-h2)**5/120.0_rk;A(6,10)=-(-h6-h5-h4-h3-h2)**5/120.0_rk

  A(7,1)=h1**5/120.0_rk;A(7,2)=-h2**5/120.0_rk;A(7,3)=(-h3-h2)**5/120.0_rk;A(7,4)=h1**6/720.0_rk
  A(7,5)=0._rk;A(7,6)=h2**6/720.0_rk;A(7,7)=(-h3-h2)**6/720.0_rk;A(7,8)=(-h4-h3-h2)**6/720.0_rk
  A(7,9)=(-h5-h4-h3-h2)**6/720.0_rk;A(7,10)=(-h6-h5-h4-h3-h2)**6/720.0_rk

  A(8,1)=-h1**6/720.0_rk;A(8,2)=-h2**6/720.0_rk;A(8,3)=-(-h3-h2)**6/720.0_rk;A(8,4)=-h1**7/5040.0_rk
  A(8,5)=0._rk;A(8,6)=h2**7/5040.0_rk;A(8,7)=-(-h3-h2)**7/5040.0_rk;A(8,8)=-(-h4-h3-h2)**7/5040.0_rk
  A(8,9)=-(-h5-h4-h3-h2)**7/5040.0_rk;A(8,10)=-(-h6-h5-h4-h3-h2)**7/5040.0_rk
  
  A(9,1)=h1**7/5040.0_rk;A(9,2)=-h2**7/5040.0_rk;A(9,3)=(-h3-h2)**7/5040.0_rk
  A(9,4)=h1**8/40320.0_rk;A(9,5)=0._rk;A(9,6)=h2**8/40320.0_rk;A(9,7)=(-h3-h2)**8/40320.0_rk
  A(9,8)=(-h4-h3-h2)**8/40320.0_rk;A(9,9)=(-h5-h4-h3-h2)**8/40320.0_rk
  A(9,10)=(-h6-h5-h4-h3-h2)**8/40320.0_rk

  A(10,1)=-h1**8/40320.0_rk;A(10,2)=-h2**8/40320.0_rk;A(10,3)=-(-h3-h2)**8/40320.0_rk
  A(10,4)=-h1**9/362880.0_rk;A(10,5)=0._rk;A(10,6)=h2**9/362880.0_rk;A(10,7)=-(-h3-h2)**9/362880.0_rk
  A(10,8)=-(-h4-h3-h2)**9/362880.0_rk;A(10,9)=-(-h5-h4-h3-h2)**9/362880.0_rk
  A(10,10)=-(-h6-h5-h4-h3-h2)**9/362880.0_rk

  !-> define rhs
  B(1,1)=0._rk ; B(2,1)=1._rk ; B(3,1)=0._rk ; B(4,1)=0._rk ; B(5,1)=0._rk ; B(6,1)=0._rk ; 
  B(7,1)=0._rk ; B(8,1)=0._rk ; B(9,1)=0._rk  ; B(10,1)=0._rk

  fact='E' ; trans='N' ; nrhs=1 ; lda=n ; ldb=n ; ldaf=n ; equed='N' ; ldx=n
  call dgesvx( fact, trans, n, nrhs, a, lda, af, ldaf, ipiv,equed, r, c, b, ldb, x, &
       ldx, rcond, ferr, berr, work, iwork, info )

  !-> output coefficient
  alpha=x(1) ; beta=1._rk ; gamma=x(2) ; delta=x(3) 
  a1=x(4) ; b1=x(5) ; c1=x(6) ; d1=x(7) ; e1=x(8) ; f1=x(9)  ; g1=x(10) 
  
!  write(333,'(a,11es17.8,i4,4es17.8)')'di2',alpha,beta,gamma,delta,a1,b1,c1,d1,e1,f1,g1,&
!       info,rcond,ferr,berr,work(1)

end subroutine der_coeffs_i2
  
subroutine dder_coeffs_c(a1,b1,c1,d1,e1,alpha,beta,gamma,delta,h1,h2,h3,h4)
! -----------------------------------------------------------------------
! Derivatives : Coefficients for second derivatives : non-uniform grid,centered 
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 04/2011
!
  implicit none
  real(rk),intent(out) :: a1,b1,c1,d1,e1,alpha,beta,gamma,delta
  real(rk),intent(in) :: h1,h2,h3,h4
  !
  ! n : size of linear system
  ! info : output of solver (zero is ok) 
  integer,parameter :: n=9
  character(len=1) :: fact,trans,equed
  integer(ik) :: nrhs,lda,ldb,ldaf,ldx
  real(rk) :: a(n,n),af(n,n),ipiv(n),b(n,1),r(n),c(n),x(n),work(4*n)
  real(rk) :: rcond,ferr,berr,dum
  integer(ik) :: iwork(n),info

  !-> space interval
  h(1)=h1 ; h(2)=h2 ; h(3)=h3 ; h(4)=h4

  !-> define matrix
  a(1,1)=0._rk;a(1,2)=0._rk;a(1,3)=0._rk;a(1,4)=0._rk;a(1,5)=1._rk;a(1,6)=1._rk;a(1,7)=1._rk;a(1,8)=1._rk;a(1,9)=1._rk
  
  a(2,1)=0._rk;a(2,2)=0._rk;a(2,3)=0._rk;a(2,4)=0._rk;a(2,5)=-h2-h1;a(2,6)=-h2;a(2,7)=0._rk;a(2,8)=h3;a(2,9)=h4+h3
  
  a(3,1)=-1._rk;a(3,2)=-1._rk;a(3,3)=-1._rk;a(3,4)=-1._rk;a(3,5)=(h2+h1)**2/2.0_rk;a(3,6)=h2**2/2.0_rk
  a(3,7)=0._rk;a(3,8)=h3**2/2.0_rk;a(3,9)=(-h4-h3)**2/2.0_rk
  
  a(4,1)=h2+h1;a(4,2)=h2;a(4,3)=-h3;a(4,4)=-h4-h3;a(4,5)=-(h2+h1)**3/6.0_rk;a(4,6)=-h2**3/6.0_rk
  a(4,7)=0._rk;a(4,8)=h3**3/6.0_rk;a(4,9)=-(-h4-h3)**3/6.0_rk
  
  a(5,1)=-(h2+h1)**2/2.0_rk;a(5,2)=-h2**2/2.0_rk;a(5,3)=-h3**2/2.0_rk;a(5,4)=-(-h4-h3)**2/2.0_rk
  a(5,5)=(h2+h1)**4/24.0_rk;a(5,6)=h2**4/24.0_rk;a(5,7)=0._rk;a(5,8)=h3**4/24.0_rk;a(5,9)=(-h4-h3)**4/24.0_rk
  
  a(6,1)=(h2+h1)**3/6.0_rk;a(6,2)=h2**3/6.0_rk;a(6,3)=-h3**3/6.0_rk;a(6,4)=(-h4-h3)**3/6.0_rk
  a(6,5)=-(h2+h1)**5/120.0_rk;a(6,6)=-h2**5/120.0_rk;a(6,7)=0._rk;a(6,8)=h3**5/120.0_rk;a(6,9)=-(-h4-h3)**5/120.0_rk
  
  a(7,1)=-(h2+h1)**4/24.0_rk;a(7,2)=-h2**4/24.0_rk;a(7,3)=-h3**4/24.0_rk;a(7,4)=-(-h4-h3)**4/24.0_rk
  a(7,5)=(h2+h1)**6/720.0_rk;a(7,6)=h2**6/720.0_rk;a(7,7)=0._rk;a(7,8)=h3**6/720.0_rk;a(7,9)=(-h4-h3)**6/720.0_rk
  
  a(8,1)=(h2+h1)**5/120.0_rk;a(8,2)=h2**5/120.0_rk;a(8,3)=-h3**5/120.0_rk;a(8,4)=(-h4-h3)**5/120.0_rk
  a(8,5)=-(h2+h1)**7/5040.0_rk;a(8,6)=-h2**7/5040.0_rk;a(8,7)=0._rk;a(8,8)=h3**7/5040.0_rk;a(8,9)=-(-h4-h3)**7/5040.0_rk
  
  a(9,1)=-(h2+h1)**6/720.0_rk;a(9,2)=-h2**6/720.0_rk;a(9,3)=-h3**6/720.0_rk;a(9,4)=-(-h4-h3)**6/720.0_rk
  a(9,5)=(h2+h1)**8/40320.0_rk;a(9,6)=h2**8/40320.0_rk;a(9,7)=0._rk;a(9,8)=h3**8/40320.0_rk
  a(9,9)=(-h4-h3)**8/40320.0_rk; 

  !-> define rhs
  b(1,1)=0._rk ; b(2,1)=0._rk ; b(3,1)=1._rk ; b(4,1)=0._rk ; b(5,1)=0._rk ; b(6,1)=0._rk ; b(7,1)=0._rk
  b(8,1)=0._rk ; b(9,1)=0._rk
 
  fact='E' ; trans='N' ; nrhs=1 ; lda=n ; ldb=n ; ldaf=n ; equed='N' ; ldx=n
  call dgesvx( fact, trans, n, nrhs, a, lda, af, ldaf, ipiv,equed, r, c, b, ldb, x, &
       ldx, rcond, ferr, berr, work, iwork, info )

  !-> output coefficient
  alpha=x(1) ; beta=x(2) ; gamma=x(3) ; delta=x(4) 
  a1=x(5) ; b1=x(6) ; c1=x(7) ; d1=x(8) ; e1=x(9) 

  dum=0._rk
  write(333,'(a,11es17.8,i4,4es17.8,a3)')'ddc',alpha,beta,1._rk,gamma,delta,a1,b1,c1,d1,e1,dum,&
       info,rcond,ferr,berr,work(1),equed

end subroutine dder_coeffs_c

subroutine dder_coeffs_i1(a1,b1,c1,d1,e1,f1,g1,alpha,beta,gamma,delta,h1,h2,h3,h4,h5,h6)
! -----------------------------------------------------------------------
! Derivatives : Coefficients for second derivatives : non-uniform grid, first point
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 04/2011
!
  implicit none
  real(rk),intent(out) :: a1,b1,c1,d1,e1,f1,g1,alpha,beta,gamma,delta
  real(rk),intent(in) :: h1,h2,h3,h4,h5,h6
  !
  ! n : size of linear system
  ! info : output of solver (zero is ok) 
  integer,parameter :: n=9
  character(len=1) :: fact,trans,equed
  integer(ik) :: nrhs,lda,ldb,ldaf,ldx
  real(rk) :: a(n,n),af(n,n),ipiv(n),b(n,1),r(n),c(n),x(n),work(4*n)
  real(rk) :: rcond,ferr,berr
  integer(ik) :: iwork(n),info

  !-> space interval
  h(1)=h1 ; h(2)=h2 ; h(3)=h3 ; h(4)=h4 ; h(5)=h5 ; h(6)=h6

  !-> define matrix
  A(1,1)=0._rk;A(1,2)=0._rk;A(1,3)=0._rk;A(1,4)=1._rk;A(1,5)=1._rk;A(1,6)=1._rk;A(1,7)=1._rk;A(1,8)=1._rk;A(1,9)=1._rk !;A(1,10)=1._rk

  A(2,1)=0._rk;A(2,2)=0._rk;A(2,3)=0._rk;A(2,4)=0._rk;A(2,5)=h1;A(2,6)=h2+h1;A(2,7)=h3+h2+h1
  A(2,8)=h4+h3+h2+h1;A(2,9)=h5+h4+h3+h2+h1 !;A(2,10)=h6+h5+h4+h3+h2+h1

  A(3,1)=-1._rk;A(3,2)=-1._rk;A(3,3)=-1._rk;A(3,4)=0._rk;A(3,5)=h1**2/2.0_rk;A(3,6)=(-h2-h1)**2/2.0_rk
  A(3,7)=(-h3-h2-h1)**2/2.0_rk;A(3,8)=(-h4-h3-h2-h1)**2/2.0_rk;A(3,9)=(-h5-h4-h3-h2-h1)**2/2.0_rk
!  A(3,10)=(-h6-h5-h4-h3-h2-h1)**2/2.0_rk

  A(4,1)=-h1;A(4,2)=-h2-h1;A(4,3)=-h3-h2-h1;A(4,4)=0._rk;A(4,5)=h1**3/6.0_rk;A(4,6)=-(-h2-h1)**3/6.0_rk
  A(4,7)=-(-h3-h2-h1)**3/6.0_rk;A(4,8)=-(-h4-h3-h2-h1)**3/6.0_rk;A(4,9)=-(-h5-h4-h3-h2-h1)**3/6.0_rk
!  A(4,10)=-(-h6-h5-h4-h3-h2-h1)**3/6.0_rk

  A(5,1)=-h1**2/2.0_rk;A(5,2)=-(-h2-h1)**2/2.0_rk;A(5,3)=-(-h3-h2-h1)**2/2.0_rk;A(5,4)=0._rk
  A(5,5)=h1**4/24.0_rk;A(5,6)=(-h2-h1)**4/24.0_rk;A(5,7)=(-h3-h2-h1)**4/24.0_rk
  A(5,8)=(-h4-h3-h2-h1)**4/24.0_rk;A(5,9)=(-h5-h4-h3-h2-h1)**4/24.0_rk
!  A(5,10)=(-h6-h5-h4-h3-h2-h1)**4/24.0_rk

  A(6,1)=-h1**3/6.0_rk;A(6,2)=(-h2-h1)**3/6.0_rk;A(6,3)=(-h3-h2-h1)**3/6.0_rk;A(6,4)=0._rk
  A(6,5)=h1**5/120.0_rk;A(6,6)=-(-h2-h1)**5/120.0_rk;A(6,7)=-(-h3-h2-h1)**5/120.0_rk
  A(6,8)=-(-h4-h3-h2-h1)**5/120.0_rk;A(6,9)=-(-h5-h4-h3-h2-h1)**5/120.0_rk
!  A(6,10)=-(-h6-h5-h4-h3-h2-h1)**5/120.0_rk

  A(7,1)=-h1**4/24.0_rk;A(7,2)=-(-h2-h1)**4/24.0_rk;A(7,3)=-(-h3-h2-h1)**4/24.0_rk
  A(7,4)=0._rk;A(7,5)=h1**6/720.0_rk;A(7,6)=(-h2-h1)**6/720.0_rk;A(7,7)=(-h3-h2-h1)**6/720.0_rk
  A(7,8)=(-h4-h3-h2-h1)**6/720.0_rk;A(7,9)=(-h5-h4-h3-h2-h1)**6/720.0_rk
!  A(7,10)=(-h6-h5-h4-h3-h2-h1)**6/720.0_rk

  A(8,1)=-h1**5/120.0_rk;A(8,2)=(-h2-h1)**5/120.0_rk;A(8,3)=(-h3-h2-h1)**5/120.0_rk
  A(8,4)=0._rk;A(8,5)=h1**7/5040.0_rk;A(8,6)=-(-h2-h1)**7/5040.0_rk;A(8,7)=-(-h3-h2-h1)**7/5040.0_rk
  A(8,8)=-(-h4-h3-h2-h1)**7/5040.0_rk;A(8,9)=-(-h5-h4-h3-h2-h1)**7/5040.0_rk
!  A(8,10)=-(-h6-h5-h4-h3-h2-h1)**7/5040.0_rk

  A(9,1)=-h1**6/720.0_rk;A(9,2)=-(-h2-h1)**6/720.0_rk;A(9,3)=-(-h3-h2-h1)**6/720.0_rk
  A(9,4)=0._rk;A(9,5)=h1**8/40320.0_rk;A(9,6)=(-h2-h1)**8/40320.0_rk;A(9,7)=(-h3-h2-h1)**8/40320.0_rk
  A(9,8)=(-h4-h3-h2-h1)**8/40320.0_rk;A(9,9)=(-h5-h4-h3-h2-h1)**8/40320.0_rk
!  A(9,10)=(-h6-h5-h4-h3-h2-h1)**8/40320.0_rk

!  A(10,1)=-h1**7/5040.0_rk;A(10,2)=(-h2-h1)**7/5040.0_rk;A(10,3)=(-h3-h2-h1)**7/5040.0_rk
!  A(10,4)=0._rk;A(10,5)=h1**9/362880.0_rk;A(10,6)=-(-h2-h1)**9/362880.0_rk
!  A(10,7)=-(-h3-h2-h1)**9/362880.0_rk;A(10,8)=-(-h4-h3-h2-h1)**9/362880.0_rk
!  A(10,9)=-(-h5-h4-h3-h2-h1)**9/362880.0_rk;A(10,10)=-(-h6-h5-h4-h3-h2-h1)**9/362880.0_rk

  !-> define rhs
  B(1,1)=0._rk ; B(2,1)=0._rk ; B(3,1)=1._rk ; B(4,1)=0._rk ; B(5,1)=0._rk ; B(6,1)=0._rk ; 
  B(7,1)=0._rk ; B(8,1)=0._rk ; B(9,1)=0._rk  !; B(10,1)=0._rk
 
  fact='E' ; trans='N' ; nrhs=1 ; lda=n ; ldb=n ; ldaf=n ; equed='N' ; ldx=n
  call dgesvx( fact, trans, n, nrhs, a, lda, af, ldaf, ipiv,equed, r, c, b, ldb, x, &
       ldx, rcond, ferr, berr, work, iwork, info )

  !-> output coefficient
  alpha=1._rk ; beta=x(1) ; gamma=x(2) ; delta=x(3) 
  a1=x(4) ; b1=x(5) ; c1=x(6) ; d1=x(7) ; e1=x(8) ; f1=x(9)  ; g1=0._rk !x(10) 

  write(333,'(a,11es17.8,i4,4es17.8,a3)')'ddi1',alpha,beta,gamma,delta,a1,b1,c1,d1,e1,f1,g1,&
       info,rcond,ferr,berr,work(1),equed
  
end subroutine dder_coeffs_i1

subroutine dder_coeffs_i2(a1,b1,c1,d1,e1,f1,g1,alpha,beta,gamma,delta,h1,h2,h3,h4,h5,h6)
! -----------------------------------------------------------------------
! Derivatives : Coefficients for second derivatives : non-uniform grid, second point
! -----------------------------------------------------------------------
! Matthieu Marquillie
! 04/2011
!
  implicit none
  real(rk),intent(out) :: a1,b1,c1,d1,e1,f1,g1,alpha,beta,gamma,delta
  real(rk),intent(in) :: h1,h2,h3,h4,h5,h6
  !
  ! n : size of linear system
  ! info : output of solver (zero is ok) 
  integer,parameter :: n=10
  character(len=1) :: fact,trans,equed
  integer(ik) :: nrhs,lda,ldb,ldaf,ldx
  real(rk) :: a(n,n),af(n,n),ipiv(n),b(n,1),r(n),c(n),x(n),work(4*n)
  real(rk) :: rcond,ferr,berr
  integer(ik) :: iwork(n),info

  !-> space interval
  h=0._rk
  h(1)=h1 ; h(2)=h2 ; h(3)=h3 ; h(4)=h4 ; h(5)=h5 ; h(6)=h6

  !-> define matrix
  A(1,1)=0._rk;A(1,2)=0._rk;A(1,3)=0._rk;A(1,4)=1._rk;A(1,5)=1._rk;A(1,6)=1._rk;A(1,7)=1._rk;A(1,8)=1._rk;A(1,9)=1._rk;A(1,10)=1._rk

  A(2,1)=0._rk;A(2,2)=0._rk;A(2,3)=0._rk;A(2,4)=-h1;A(2,5)=0._rk;A(2,6)=h2;A(2,7)=h3+h2;A(2,8)=h4+h3+h2
  A(2,9)=h5+h4+h3+h2;A(2,10)=h6+h5+h4+h3+h2

  A(3,1)=-1._rk;A(3,2)=-1._rk;A(3,3)=-1._rk;A(3,4)=h1**2/2.0_rk;A(3,5)=0._rk;A(3,6)=h2**2/2.0_rk
  A(3,7)=(-h3-h2)**2/2.0_rk;A(3,8)=(-h4-h3-h2)**2/2.0_rk;A(3,9)=(-h5-h4-h3-h2)**2/2.0_rk
  A(3,10)=(-h6-h5-h4-h3-h2)**2/2.0_rk

  A(4,1)=h1;A(4,2)=-h2;A(4,3)=-h3-h2;A(4,4)=-h1**3/6.0_rk;A(4,5)=0._rk;A(4,6)=h2**3/6.0_rk
  A(4,7)=-(-h3-h2)**3/6.0_rk;A(4,8)=-(-h4-h3-h2)**3/6.0_rk;A(4,9)=-(-h5-h4-h3-h2)**3/6.0_rk
  A(4,10)=-(-h6-h5-h4-h3-h2)**3/6.0_rk

  A(5,1)=-h1**2/2.0_rk;A(5,2)=-h2**2/2.0_rk;A(5,3)=-(-h3-h2)**2/2.0_rk;A(5,4)=h1**4/24.0_rk
  A(5,5)=0._rk;A(5,6)=h2**4/24.0_rk;A(5,7)=(-h3-h2)**4/24.0_rk;A(5,8)=(-h4-h3-h2)**4/24.0_rk
  A(5,9)=(-h5-h4-h3-h2)**4/24.0_rk;A(5,10)=(-h6-h5-h4-h3-h2)**4/24.0_rk
  
  A(6,1)=h1**3/6.0_rk;A(6,2)=-h2**3/6.0_rk;A(6,3)=(-h3-h2)**3/6.0_rk;A(6,4)=-h1**5/120.0_rk
  A(6,5)=0._rk;A(6,6)=h2**5/120.0_rk;A(6,7)=-(-h3-h2)**5/120.0_rk;A(6,8)=-(-h4-h3-h2)**5/120.0_rk
  A(6,9)=-(-h5-h4-h3-h2)**5/120.0_rk;A(6,10)=-(-h6-h5-h4-h3-h2)**5/120.0_rk

  A(7,1)=-h1**4/24.0_rk;A(7,2)=-h2**4/24.0_rk;A(7,3)=-(-h3-h2)**4/24.0_rk;A(7,4)=h1**6/720.0_rk
  A(7,5)=0._rk;A(7,6)=h2**6/720.0_rk;A(7,7)=(-h3-h2)**6/720.0_rk;A(7,8)=(-h4-h3-h2)**6/720.0_rk
  A(7,9)=(-h5-h4-h3-h2)**6/720.0_rk;A(7,10)=(-h6-h5-h4-h3-h2)**6/720.0_rk

  A(8,1)=h1**5/120.0_rk;A(8,2)=-h2**5/120.0_rk;A(8,3)=(-h3-h2)**5/120.0_rk;A(8,4)=-h1**7/5040.0_rk
  A(8,5)=0._rk;A(8,6)=h2**7/5040.0_rk;A(8,7)=-(-h3-h2)**7/5040.0_rk
  A(8,8)=-(-h4-h3-h2)**7/5040.0_rk;A(8,9)=-(-h5-h4-h3-h2)**7/5040.0_rk
  A(8,10)=-(-h6-h5-h4-h3-h2)**7/5040.0_rk

  A(9,1)=-h1**6/720.0_rk;A(9,2)=-h2**6/720.0_rk;A(9,3)=-(-h3-h2)**6/720.0_rk;A(9,4)=h1**8/40320.0_rk
  A(9,5)=0._rk;A(9,6)=h2**8/40320.0_rk;A(9,7)=(-h3-h2)**8/40320.0_rk;A(9,8)=(-h4-h3-h2)**8/40320.0_rk
  A(9,9)=(-h5-h4-h3-h2)**8/40320.0_rk;A(9,10)=(-h6-h5-h4-h3-h2)**8/40320.0_rk
  
  A(10,1)=h1**7/5040.0_rk;A(10,2)=-h2**7/5040.0_rk;A(10,3)=(-h3-h2)**7/5040.0_rk
  A(10,4)=-h1**9/362880.0_rk;A(10,5)=0._rk;A(10,6)=h2**9/362880.0_rk;A(10,7)=-(-h3-h2)**9/362880.0_rk
  A(10,8)=-(-h4-h3-h2)**9/362880.0_rk;A(10,9)=-(-h5-h4-h3-h2)**9/362880.0_rk
  A(10,10)=-(-h6-h5-h4-h3-h2)**9/362880.0_rk

!  A(10,:)=0._rk ; A(10,10)=0._rk

  !-> define rhs
  B(1,1)=0._rk ; B(2,1)=0._rk ; B(3,1)=1._rk ; B(4,1)=0._rk ; B(5,1)=0._rk ; B(6,1)=0._rk ; 
  B(7,1)=0._rk ; B(8,1)=0._rk ; B(9,1)=0._rk ; B(10,1)=0._rk
 
  fact='E' ; trans='N' ; nrhs=1 ; lda=n ; ldb=n ; ldaf=n ; equed='N' ; ldx=n
  call dgesvx( fact, trans, n, nrhs, a, lda, af, ldaf, ipiv,equed, r, c, b, ldb, x, &
       ldx, rcond, ferr, berr, work, iwork, info )

  !-> output coefficient
  alpha=x(1) ; beta=1._rk ; gamma=x(2) ; delta=x(3) 
  a1=x(4) ; b1=x(5) ; c1=x(6) ; d1=x(7) ; e1=x(8) ; f1=x(9)  ; g1=x(10) 

  write(333,'(a,11es17.8,i4,4es17.8,a3)')'ddi2',alpha,beta,gamma,delta,a1,b1,c1,d1,e1,f1,g1,&
       info,rcond,ferr,berr,work(1),equed
  
end subroutine dder_coeffs_i2

end module class_derivatives_coefficient

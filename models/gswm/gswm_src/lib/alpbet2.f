	SUBROUTINE ALPBET2(A,B,C,D,K,N,IR,IC,ALPH,BET,AUX,FX,IPVT,Z)

C  COMPUTES ALPHAS AND BETAS FOR USE IN LINDZEN-KUO ALGORITHM
C  AND STORES ON UNIT 4

C  Version 2.0 created by J. Forbes 2/3/91
C  Modified on 3/14/91 to include NCAR/LINPACK routines

        INTEGER IPVT(IC)
	COMPLEX Z(IC)
	COMPLEX A(IR,IC),B(IR,IC),C(IR,IC),D(IR)
	COMPLEX ALPH(IR,IC),BET(IR),AUX(IR,IC),FX(IR)

C  UPPER BOUNDARY CONDITION; COMPUTE ALPHA ZERO AND BETA ZERO

	IF(K-1) 1,1,2
1       CALL CGECO(A,IR,IC,IPVT,RCOND,Z)
	CALL CGESL(A,IR,IC,IPVT,D,0)
	DO 20 J=1,IC
	CALL CGESL(A,IR,IC,IPVT,B(1,J),0)
20      CONTINUE
	DO 11 KI=1,IR
	BET(KI)=D(KI)
	DO 11 JI=1,IC
11	ALPH(KI,JI)=-B(KI,JI)
	WRITE(UNIT=4,REC=K) ((ALPH(I,J),I=1,IR),J=1,IC),(BET(I),I=1,IR)
	RETURN

C  INTERIOR POINTS

2	CONTINUE

C  ALPHA(N-1) AND BETA(N-1) WERE SAVED FROM PREVIOUS CALL AND NOW USED:

	CALL MPRDD(A,ALPH,AUX,IR,IC,IC)
	CALL MPRDDV(A,BET,FX,IR,IC)
	CALL GMADDM(AUX,B,AUX,IR,IC,1.) 
	CALL GMADDV(D,FX,BET,IR,-1.)

	CALL CGECO(AUX,IR,IC,IPVT,RCOND,Z)
	CALL CGESL(AUX,IR,IC,IPVT,BET,0)
	DO 10 J=1,IC
	CALL CGESL(AUX,IR,IC,IPVT,C(1,J),0)
10      CONTINUE
	DO 12 KI=1,IR
	DO 12 JI=1,IC
12	ALPH(KI,JI)=-C(KI,JI)

	WRITE(UNIT=4,REC=K) ((ALPH(I,J),I=1,IR),J=1,IC),(BET(I),I=1,IR)

	RETURN
	END

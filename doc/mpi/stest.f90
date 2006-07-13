
! test of named pipes.   proposed way for 2 tasks to communicate
! they are ready to run, and finished running.  the read should
! pause until there is something to read, so the program does not
! have to sleep and loop.


program fred

character(len=128) :: junk

print *, "i am here"
call system('rm -f pipe; mkfifo pipe; ls -l pipe')
print *, "pipe created"

print *, "starting sleeping process which will write to pipe"
call system('(sleep 30; echo hello > pipe)&')
print *, "sleeper launched"

print *, "opening pipe back in main program again"
open(unit=9, file="pipe", status="old", action="read", &
     form="formatted")

read(unit=9, fmt=*) junk
print *, "read junk, ready to continue"

close(unit=9)
call system ('rm -f pipe')

print *, "pipe gone"

end program fred

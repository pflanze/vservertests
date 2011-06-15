#!/bin/bash
set -x

eR='\e[31m';eG='\e[32m';eY='\e[33m';eB='\e[34m';eN='\e[0m'

function eecho () {
    C=$1; shift
    echo -e "$C$*$eN"
}

function techo () {
    C=$1; shift
    echo -en "$C$*$eN"
}

function ececho () {
    rc=$1; shift
    id=$1; shift
    if [ $rc -eq 0 ]; then
	[ $terse -ne 0 ] && techo $eG "$id. " || \
        eecho $eG "$id# succeeded."
    else
	[ $terse -ne 0 ] && techo $eR "$id* " || \
        eecho $eR "$id# failed."
    fi 
    return $rc
}

function eexec () {
    local id=`printf "[%3.3s]" $1`; shift
    local eret=$1; shift
    
    echo -e "\t$*" >$outdev
    if [ $terse -gt 0 ]; then
	eval $* 1>/dev/null 2>&1 3>&1
    else
    	eval $* 3>&2 1>$outdev 2>$errdev
    fi
    local ret=$?
    [ -n "$eret" -a "$eret" -ne 0 ] \
        && ret=$(( ret - eret ))
    ececho $ret $id
    return $ret
}


function go_xid () {
    local xid=$1; shift

    if [ "$version" == "24" -a $xid -gt 0 ]; then
	echo -e "\tchcontext --ctx $xid $*"
	chcontext --ctx $xid $*
    elif [ $xid -gt 1 ]; then
	echo -e "\tvcontext --create --xid $xid -- $*"
	vcontext --create --xid $xid -- $*
    elif [ $xid -eq 1 ]; then
	echo -e "\tvcontext --migrate --xid 1 -- $*"
	vcontext --migrate --xid 1 -- $*
    else
	echo -e "\t$*"
	$*
    fi
}

function mnt_test () {
    local rc;

    mount -o $3 $1 $2 >/dev/null 2>&1
    rc=$?
    [ $rc -eq 0 ] && umount -f $2 >/dev/null 2>&1
    return $rc  
}

function do_xid_touch () {
    local path="$1"; shift
    local pos=1
    local ret=0

    while [ $# -gt 0 ]; do
	local file="$path/file_$pos"
	echo -e "\ttouch $file: $1"
	go_xid $1 "touch $file" 
	local rc=$?
	[ $rc -eq 0 ] || { ret=1;
	    eecho $eR "\ttouch $file: $1 [$rc]" 1>&3; }
	shift
	pos=$[pos+1];
    done
    return $ret
}

function do_xid_write () {
    local path="$1"; shift
    local pos=1 ret=0

    while [ $# -gt 1 ]; do
	local file="$path/file_$pos"
        local x=0 xx=""

	for x in 0 1 2 $1; do
	    echo "test-$pos" | go_xid $x tee "$file" >/dev/null
   	    local rc=$?
	    [ $rc -eq 0 ] && xx="$xx." || xx="$xx^"
	done
	[ "$xx" == "$2" ] || { ret=1;
	    eecho $eR "\twrite $file: [$xx:$2] $1" 1>&3; }
	
	shift; shift
	pos=$[pos+1];
    done
    return $ret
}


function do_mqon () {
    local dev=$1
    local mnt=$2
    local qfmt=$3
    local type=$4

    case $qfmt in
	vfsv0) 	qid=2 ;;
	vfsold)	qid=1 ;;
	xfs)	qid=0 ;;
    esac

    case $type in
	user)	tid=0 ;;
	group)	tid=1 ;;
    esac

    mqon -v -t $tid -F $qid -f $mnt/$qpre.$type $dev
}



function do_sync () {
    sync
    sleep 6
}


function do_test () {
    local mopt=$2
    local qfmt=$3
    local xopt="$mopt,tagxid"
    local X="-"
	
    do_sync
    eexec 001	0 "mount -o $mopt $DEV $MNT 3>&2"		|| return
    eexec 002	0 "quotacheck -F $qfmt -vugm $DEV 3>&2"	
    eexec 003	0 "do_mqon $DEV $MNT $qfmt user 3>&2"
    eexec 004	0 "do_mqon $DEV $MNT $qfmt group 3>&2"

    false && {

	[ $terse -ne 0 ] && echo "($1 format)"
    	eecho $eB "xid related tests ..."

	local xids="0 1 255 256 666"
	local rpat="0 .... 1 ..^. 255 ..^."
	local wpat="0 .... 1 ..^. 255 ..^."

	eexec 001  	0 "mount -o $mopt $DEV $MNT 3>&2"	|| return

	eval		  "umount $DEV 3>&2"
	
	[ $terse -ne 0 ] && echo ""
	X="X"
    }

    eexec 099	0 "umount $DEV 3>&2"
    [ $terse -ne 0 ] && echo ""

    true
}

verbose=0
terse=0
test_xid=0
qfmt="vfsv0"
qpre="aquota"

DEV="/dev/zero"
MNT="/test"
FSL="ext2,ext3,xfs,reiser"

while getopts ":hvxotF:D:M:E:" option; do
  case $option in
    h)  # help
        cat << EOF
Usage: $cmdname [OPTION]... 

  -h        help
  -v        be verbose
  -x        xid tagging tests
  -o        old quota format
  -t        terse output
  -F <fs>   filesystems
  -D <dev>  device to use [$DEV]
  -M <mnt>  mount point [$MNT]

  -E <file> act as ewrite helper
            (must be first option)

examples:
  
  $cmdname -F ext2  # check fs
  $cmdname -v       # verbose test
  
EOF
        exit 0
        ;;
    v)  # be verbose 
        verbose=$(( verbose + 1 ))
        ;;
    x)  # test xid tagging
        test_xid=1;
        ;;
    o)  # old quota format
        qfmt="vfsold"
        qpre="quota"
        ;;
    t)  # terse output
        terse=1
        ;;
    D)  # device 
        DEV="$OPTARG"
        ;;
    M)  # mount point
        MNT="$OPTARG"
        ;;
    F)  # single fs
        FSL="$OPTARG"
        ;;
  esac
done
shift $(($OPTIND - 1))

outdev="/dev/null"
[ $verbose -gt 1 ] && outdev="/dev/stdout"
errdev="/dev/null"
[ $verbose -gt 0 ] && errdev="/dev/stderr"


eecho $eY "Linux-VServer Quota Test [V0.01] Copyright (C) 2005 H.Poetzl"

KERN=`uname -srm`
CHCV=`chcontext --version 2>&1`
CHCO=`echo -e "$CHCV" |
    sed -n '/--\|version/ {s/.*\ \([0-9][0-9.]*\).*/\1/g;p;q;}'`

INFO=(`sed 's/.*:\t//' /proc/virtual/info 2>/dev/null || echo '<none>'`)
case ${INFO[2]:1:1} in
  0) TAGI="none"	;;
  1) TAGI="uid16"	;;
  2) TAGI="gid16"	;;
  3) TAGI="ugid24"	;;
  4) TAGI="intern"	;;
  5) TAGI="runtime"	;;
  *) TAGI="unknown"	;;
esac

echo "$KERN/$CHCO"
echo "VCI:  $INFO ${INFO[1]} ${INFO[2]} ($TAGI)"

fsl=`echo $FSL | tr ',' ' '`
mopt="rw,usrquota,grpquota"

for n in $fsl; do
    echo "---"
    eecho $eY "testing $n filesystem ..."
    case $n in 
    ext2)
	mkfs.ext2 $DEV 1>$outdev 2>$errdev
	ececho $? "[000]" && do_test ext2 "$mopt" "$qfmt"	\
	|| echo "(ext2 format failed)"
	;;
    ext3)
	mkfs.ext3 $DEV 1>$outdev 2>$errdev
	ececho $? "[000]" && do_test ext3 "$mopt" "$qfmt"	\
	|| echo "(ext3 format failed)"
	;;
    xfs)
	mkfs.xfs -f $DEV 1>$outdev 2>$errdev
	ececho $? "[000]" && do_test xfs "$mopt" "xfs" 		\
	|| echo "(xfs format failed)"
	;;
    reiser*)
	mkfs.reiserfs -f $DEV 1>$outdev 2>$errdev
	ececho $? "[000]" && do_test reiser "$mopt" "$qfmt"	\
	|| echo "(reiser format failed)"
	;;
    jfs)
	mkfs.jfs -f $DEV 1>$outdev 2>$errdev
	ececho $? "[000]" && do_test jfs "$mopt" "$qfmt"	\
	|| echo "(jfs format failed)"
	;;
    *)
	eecho $eR "unknown filesystem $n."
	;;
    esac
done


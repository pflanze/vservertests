#!/bin/bash

shopt -s extglob

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

function eeval () {
    if [ $terse -gt 0 ]; then
	eval $* 1>/dev/null 2>&1 3>&1
    else
    	eval $* 3>&2 1>$outdev 2>$errdev
    fi
    local ret=$?
    [ $pause -gt 0 ] && sleep $pause
    return $ret
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
    [ $pause -gt 0 ] && sleep $pause
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

function go_tag () {
    local tag=$1; shift

    if [ $KTAG -gt 0 ]; then
	echo -e "\tvtag --migrate --tag $tag -- $*"
	vtag --migrate --tag $tag -- $*
    else
	go_xid $tag $*
    fi
}



function do_tag_touch () {
    local path="$1"; shift
    local pos=1
    local ret=0

    while [ $# -gt 0 ]; do
	local file="$path/file_$pos"
	echo -e "\ttouch $file: $1"
	go_tag $1 "touch $file" 
	local rc=$?
	[ $rc -eq 0 ] || { ret=1;
	    eecho $eR "\ttouch $file: $1 [$rc]" 1>&3; }
	shift
	pos=$[pos+1];
    done
    return $ret
}

function do_tag_verify () {
    local path="$1"; shift
    local pos=1 ret=0

    while [ $# -gt 0 ]; do
	local file="$path/file_$pos"
	val=`$lstag -d $file | awk '{print $1}'`
	echo -e "\tverify $file: $1 = $val"
	[ "$val" -eq "$1" ] || { ret=1;
	    eecho $eR "\tverify $file: $1 = $val" 1>&3; }
	shift
	pos=$[pos+1];
    done
    return $ret
}

function do_tag_change () {
    local path="$1"; shift
    local pos=1 ret=0

    while [ $# -gt 0 ]; do
	local file="$path/file_$pos"
	echo -e "\tchange $file: $1"
	$chtag -c $1 $file
	local rc=$?
	[ $rc -eq 0 ] || { ret=1; 
	    eecho $eR "\tchange $file: $1 [$rc]" 1>&3; }
	shift
	pos=$[pos+1];
    done
    return $ret
}

function do_tag_read () {
    local path="$1"; shift
    local pos=1 ret=0

    while [ $# -gt 1 ]; do
	local file="$path/file_$pos"
        local x=0 xx=""

	for x in 0 1 2 $1; do
	    go_tag $x cat "$file" >/dev/null
   	    local rc=$?
	    [ $rc -eq 0 ] && xx="$xx." || xx="$xx^"
	done
	[ "$xx" == "$2" ] || { ret=1;
	    eecho $eR "\tread $file: $1 [$xx:$2]" 1>&3; }
	
	shift; shift
	pos=$[pos+1];
    done
    return $ret
}

function do_tag_write () {
    local path="$1"; shift
    local pos=1 ret=0

    while [ $# -gt 1 ]; do
	local file="$path/file_$pos"
        local x=0 xx=""

	for x in 0 1 2 $1; do
	    echo "test-$pos" | go_tag $x tee "$file" >/dev/null
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


function do_xattr_barrier () {
    local path="$1"; shift
    local bdir="$1"; shift
    local ret=0

    local x=0 xx=""
    for x in 0 1 2; do
        go_xid $x chmod +x "$bdir"
   	local rc=$?
	chmod -x "$bdir"
	[ $rc -eq 0 ] && xx="$xx." || xx="$xx^"
    done
    [ "$xx" == "$1" ] || { ret=1;
        eecho $eR "\tbarrier $bdir: [$xx:$1]" 1>&3; }
    return $ret
}

function do_xattr_iunlink () {
    local path="$1"; shift
    local file="$1"; shift
    local ret=0

    local x=0 xx=""
    for x in 0 1 2; do
        go_xid $x chmod +x "$file"
   	local rc=$?
	chmod -x "$file"
	[ $rc -eq 0 ] && xx="$xx." || xx="$xx^"
    done
    [ "$xx" == "$1" ] || { ret=1;
        eecho $eR "\tiunlink chmod $file: [$xx:$1]" 1>&3; }
    return $ret
}

function do_xattr_cowbreak () {
    local path="$1"; shift
    local file="$1"; shift
    local ret=0

    local x=0 xx=""
    for x in 0 1 2; do
	ln "$file" "$file.$x"
        go_xid $x chmod +x "$file.$x"
   	local rcb=$?
	cmp "$file" "$file.$x"
	local rcc=$?
	rm -f "$file.$x"
	[ $rcb -eq 0 -a $rcc -eq 0 ] && xx="$xx." || xx="$xx^"
    done
    [ "$xx" == "$1" ] || { ret=1;
        eecho $eR "\tiunlink chmod $file: [$xx:$1]" 1>&3; }
    return $ret
}

function do_xattr_verify () {
    local path="$1"; shift
    local vcmd="$1"; shift
    local pos=1 ret=0

    while [ $# -gt 0 ]; do
	local file="$1"; shift
	val=`$vcmd -d $file | awk '{print $1}'`
	echo -e "\tverify $file: $1 = $val"
	case $val in
	   $1) ;;
	   *)	ret=1
	        eecho $eR "\tverify $file: $1 ~ $val" 1>&3
		;;
	esac
	shift
    done
    return $ret
}

function do_dlimit_add () {
    local path="$1"; shift
    local space="$1"; shift
    local inodes="$1"; shift
    local xid="$1"; shift
    local ret=0

    vdlimit --xid "$xid" --set space_used=0 \
	--set space_total="$space" --set inodes_used=0 \
	--set inodes_total="$inodes" \
	--set reserved=0 "$path" || ret=1

    return $ret
}

function do_dlimit_save () {
    local path="$1"; shift
    local xid="$1"; shift
    local space_used=0
    local inodes_used=0

    _DLIMIT_DF_SPACE=`df "$path" |
	awk '$3 ~ /^[0-9]+$/ { if (NF == 5) { print $2 } else { print $3 } }'`
    _DLIMIT_DF_INODE=`df -i "$path" |
	awk '$3 ~ /^[0-9]+$/ { if (NF == 5) { print $2 } else { print $3 } }'`
    eval `vdlimit --xid "$xid" "$path" | grep _used=`

    _DLIMIT_VD_SPACE="$space_used"
    _DLIMIT_VD_INODE="$inodes_used"
    return $ret
}

function do_dlimit_verify () {
    local path="$1"; shift
    local xid="$1"; shift
    local ret=0

    local space_used=0
    local inodes_used=0
    local df_space=0
    local df_inode=0

    df_space=`df "$path" |
	awk '$3 ~ /^[0-9]+$/ { if (NF == 5) { print $2 } else { print $3 } }'`
    df_inode=`df -i "$path" |
	awk '$3 ~ /^[0-9]+$/ { if (NF == 5) { print $2 } else { print $3 } }'`
    eval `vdlimit --xid "$xid" "$path" | grep _used=` || ret=1

    local df_dspace=`expr $df_space - $_DLIMIT_DF_SPACE`
    local vd_dspace=`expr $space_used - $_DLIMIT_VD_SPACE`

    echo -e "\tverify $xid: space $df_dspace = $vd_dspace"
    [ "$df_dspace" -eq "$vd_dspace" ] || { ret=1;
        eecho $eR "\tverify $xid: $df_dspace ~ $vd_dspace" 1>&3; }

    local df_dinode=`expr $df_inode - $_DLIMIT_DF_INODE`
    local vd_dinode=`expr $inodes_used - $_DLIMIT_VD_INODE`

    echo -e "\tverify $xid: inode $df_dinode = $vd_dinode"
    [ "$df_dinode" -eq "$vd_dinode" ] || { ret=1;
        eecho $eR "\tverify $xid: $df_dinode ~ $vd_dinode" 1>&3; }

    return $ret
}

function do_dlimit_space () {
    local path="$1"; shift
    local size="$1"; shift
    local xid="$1"; shift

    go_tag "$xid" rm -f "$path/space-$xid"*
    go_tag "$xid" dd if=/dev/zero of="$path/space-$xid" bs=1k count=$size || \
	return 1

    return 0
}

function do_dlimit_cowtest () {
    local path="$1"; shift
    local size="$1"; shift
    local breaks="$1"; shift
    local xid="$1"; shift

    go_tag "$xid" rm -f "$path/cow-$xid"*
    go_tag "$xid" dd if=/dev/zero of="$path/cow-$xid" bs=1k count=$size || return 1
    setattr --iunlink "$path/cow-$xid"
    local i=0
    while [ $i -lt $breaks ]; do
	go_tag "$xid" ln "$path/cow-$xid" "$path/cow-$xid-$i" || return 1
	go_tag "$xid" touch "$path/cow-$xid-$i" || return 1
	i=$[i+1]
    done

    return 0
}

function do_dlimit_inodes () {
    local path="$1"; shift
    local files="$1"; shift
    local xid="$1"; shift

    go_tag "$xid" rm -f "$path/inodes-$xid"*
    local i=1
    while [ $i -lt $files ]; do
	go_tag "$xid" touch "$path/inodes-$xid-$i" || return 1
	i=$[i+1]
    done

    return 0
}

function do_dlimit_destroy () {
    local path="$1"; shift
    local xid="$1"; shift

    vdlimit --remove --xid "$xid" "$path" 2>/dev/null
    rm -fr "$path/$xid"
    return 0
}

function do_sync () {
    sync
    sleep 6
}

function do_fsck () {
    local fs=$1
    local dev="$2"
    local done=0 ret=0
    
    until [ $done -ne 0 ]; do
    	fsck.$fs $fsckopt $dev
	ret=$?
	if [ $ret -eq 8 ]; then
	    echo .
	    continue
	fi
	done=1;
    done
    return $ret;
}

function do_test () {
    local fs=$1
    local mopt=$2
    local xopt="$mopt,$tagxid"
    local X="-"
	
    do_sync

    {
	eexec 001  	0 "mount -t $fs -o $mopt $DEV $MNT 3>&2" || return
	eexec 002      32 "mount -o remount,$xopt $MNT 3>&2"
	eeval		  "umount $DEV 3>&2"
    }

    [ $test_xid -gt 0 ] && {

	[ $terse -ne 0 ] && echo "($fs format)"
    	eecho $eB "tag related tests ..."

	local tags="0 1 255 256 666"
	local rpat="0 .... 1 ..^. 255 ..^."
	local wpat="0 .... 1 ..^. 255 ..^."

	eexec 011  	0 "mount -t $fs -o $xopt $DEV $MNT 3>&2" || return
	eexec 012	0 "do_tag_touch $MNT $tags"
	eexec 014	0 "do_tag_verify $MNT $tags"
	eexec 015	0 "do_tag_read $MNT $rpat"
	eexec 019  	0 "umount $DEV 3>&2"

	[ $terse -ne 0 ] && echo ""

	eeval		  "mount -t $fs -o $xopt $DEV $MNT 3>&2" || return
	eexec 020  	0 "do_tag_verify $MNT $tags"
	eexec 021	0 "mount -o remount,$xopt $MNT 3>&2"
	eexec 022  	0 "do_tag_verify $MNT $tags"
	eexec 023	0 "mount -o remount,$mopt $MNT 3>&2"
	eexec 024  	0 "do_tag_verify $MNT $tags"
	eexec 025	0 "do_tag_read $MNT $rpat"
	eexec 026  	0 "do_tag_verify $MNT $tags"
	eexec 027	0 "do_tag_write $MNT $wpat"
	eexec 028  	0 "do_tag_verify $MNT $tags"

	[ $terse -ne 0 ] && echo ""

	local tags="200 201 256 254 777"
	local rpat="200 ..^."
	local wpat="200 ..^. 201 ..^."

	eexec 033  	0 "do_tag_change $MNT $tags"
	eexec 034  	0 "do_tag_verify $MNT $tags"
	eexec 035	0 "do_tag_read $MNT $rpat"
	eexec 037	0 "do_tag_write $MNT $wpat"
	eeval		  "umount $DEV 3>&2"

	local rpat="200 ...."
	local wpat="200 .... 201 ...."

	eeval		  "mount -t $fs -o $mopt $DEV $MNT 3>&2" || return
	eexec 045	0 "do_tag_read $MNT $rpat"
	eexec 047	0 "do_tag_write $MNT $wpat"
	eeval		  "umount $DEV 3>&2"
	
	[ $terse -ne 0 ] && echo ""

	X="X"
    }

    [ $test_xattr -gt 0 ] && {

    	eecho $eB "xattr related tests ..."
	
	case $version in
	  24)
	    local attr_B="---BU--" attr_b="---bu--"
	    local attr_U="----U--" attr_u="----u--"
	    local lsattr_B="-+(-)-t*(-)"
	    local lsattr_U="-+(-)-i-+(-)-t*(-)"
	    ;;
	  *)
	    local attr_B="-+(-)-Bui-" attr_b="-+(-)-bui-"
	    local attr_U="-+(-)--UI-" attr_u="-+(-)--ui-"
	    local lsattr_B="-+(-)?(A)+(-)"
	    local lsattr_U="-+(-)-i-+(-)?([AE])+(-)"
	    ;;
	esac

	local dpath="$MNT/dir_$$"
	local fpath="$MNT/file_$$"

	eexec 101  	0 "mount -t $fs -o $mopt $DEV $MNT 3>&2" || return
	eeval		  "mkdir -p $dpath"
	eexec 102	0 "setattr --barrier $dpath"
	eexec 103	0 "do_xattr_verify $MNT showattr $dpath $attr_B"
	eexec 104	0 "do_xattr_verify $MNT lsattr $dpath $lsattr_B"
	eexec 105	0 "go_xid 2 chattr =i $dpath"
	eexec 106	0 "do_xattr_barrier $MNT $dpath .^^"
	eexec 108	0 "setattr --~barrier $dpath"
	eexec 109	0 "do_xattr_verify $MNT showattr $dpath $attr_b"
	eeval		  "rmdir $dpath"

	[ $terse -ne 0 ] && echo ""

	eeval		  "echo five > $fpath"
	eeval		  "ln $fpath $fpath.x"
	eexec 112	0 "setattr --iunlink $fpath"
	eexec 113	0 "do_xattr_verify $MNT showattr $fpath $attr_U"
	eexec 114	0 "do_xattr_verify $MNT lsattr $fpath $lsattr_U"
	eexec 115	0 "ln $fpath $fpath.y"
	[ $KCOW -lt 2 ] && \
	eexec 116	0 "do_xattr_iunlink $MNT $fpath $ER"
	eexec 117	0 "go_xid 2 rm -f $fpath"
	eexec 118	0 "setattr --~iunlink $fpath.x"
	eexec 119	0 "do_xattr_verify $MNT showattr $fpath.x $attr_u"
	eeval		  "rm -f $fpath.y $fpath.x"

	[ $terse -ne 0 ] && echo ""

	eeval		  "mkdir -p $dpath"
	eeval		  "setattr --barrier $dpath"
	eeval		  "echo five > $fpath"
	eeval		  "setattr --iunlink $fpath"
	eeval  		  "umount $DEV 3>&2"
	eeval  		  "mount -t $fs -o $mopt $DEV $MNT 3>&2" || return
	eexec 121	0 "do_xattr_verify $MNT showattr $dpath $attr_B"
	eexec 122	0 "do_xattr_verify $MNT lsattr $dpath $lsattr_B"
	eexec 123	0 "do_xattr_verify $MNT showattr $fpath $attr_U"
	eexec 124	0 "do_xattr_verify $MNT lsattr $fpath $lsattr_U"
	eexec 125	0 "do_xattr_cowbreak $MNT $fpath ..."

	eexec 128  	0 "umount $DEV 3>&2"
	eexec 129	0 "do_fsck $fs $DEV 3>&2"

	[ $terse -ne 0 ] && echo ""
	if [ $KCOW -ge 2 ]; then
	eeval	  	  "mount -t $fs -o $mopt $DEV $MNT 3>&2" || return

	eexec 138  	0 "umount $DEV 3>&2"
	eexec 139	0 "do_fsck $fs $DEV 3>&2"
	fi

	[ $terse -ne 0 ] && echo ""
    }

    [ $test_dlimit -gt 0 ] && {

    	eecho $eB "disk limit related tests ..."

	local tags="300 301 600 900"

	eeval		  "mount -t $fs -o $xopt $DEV $MNT 3>&2" || return

	eeval		  "do_dlimit_destroy $MNT $tags"
	eexec 201	0 "do_dlimit_add $MNT 32 5 $tags"
	eeval		  "do_dlimit_save $MNT $tags"
	eexec 202	0 "do_dlimit_space $MNT 16 $tags"
	eexec 203	0 "do_dlimit_verify $MNT $tags"
	eeval		  "do_dlimit_save $MNT $tags"
	eexec 204	0 "do_dlimit_inodes $MNT 3 $tags"
	eexec 205	0 "do_dlimit_verify $MNT $tags"
	eeval		  "do_dlimit_save $MNT $tags"
	eexec 206	1 "do_dlimit_space $MNT 33 $tags"
	eexec 207	1 "do_dlimit_inodes $MNT 6 $tags"
	eexec 208	0 "do_dlimit_verify $MNT $tags"

	if [ $KCOW -ge 1 ]; then
	[ $terse -ne 0 ] && echo ""

	eeval		  "do_dlimit_destroy $MNT $tags"
	eexec 211	0 "do_dlimit_add $MNT 128 10 $tags"
	eeval		  "do_dlimit_save $MNT $tags"
	eexec 212	0 "do_dlimit_cowtest $MNT 5 9 $tags"
	eexec 213	0 "do_dlimit_verify $MNT $tags"
	eeval		  "do_dlimit_save $MNT $tags"
	eexec 222	1 "do_dlimit_cowtest $MNT 43 3 $tags"
	eexec 223	0 "do_dlimit_verify $MNT $tags"
	eeval		  "rm -f $MNT/cow-300*"
	eexec 231	0 "do_dlimit_verify $MNT $tags"
	eexec 232	1 "do_dlimit_cowtest $MNT 3 43 $tags"
	eexec 233	0 "do_dlimit_verify $MNT $tags"
	fi

	eeval		  "umount $DEV 3>&2"
	eexec 239	0 "do_fsck $fs $DEV 3>&2"

	[ $terse -ne 0 ] && echo ""
    }
    {
	eexec 999	0 "do_fsck $fs $DEV 3>&2"
    }
    return 0
}

verbose=0
terse=0
flash=0

test_xid=0
test_xattr=0
test_dlimit=0

version="26"
tagxid="tag"
lstag="lsxid"
chtag="chxid"
pause=0

DEV=""
MNT="/test"
NFS="127.0.0.1:/nfs"
FSL="ext2,ext3,xfs,reiser,jfs"

mntopt="rw"
nfsopt="vers=3,hard,intr,tcp,sync"


while getopts ":hlnotvxyzD:F:M:N:O:P:Z" option; do
  case $option in
    h)  # help
        cat << EOF
Usage: $cmdname [OPTION]...

  -h        help
  -l        legacy barrier code
  -n        no color codes
  -t        terse output
  -o <opt>  mount options [$mntopt]
  -v        be verbose
  -x        xid tagging tests
  -y        xattr tests
  -z        disk limit tests
  -D <dev>  device to use [$DEV]
  -F <fs>   filesystems
  -M <mnt>  mount point [$MNT]
  -N <src>  nfs source [$NFS]
  -O <opt>  nfs options [$nfsopt]
  -P <sec>  pause between tests
  -Z        use flash_eraseall

examples:
  
  $cmdname -F ext2  # check fs
  $cmdname -v       # verbose test
  
EOF
        exit 0
        ;;
    v)  # be verbose 
        verbose=$(( verbose + 1 ))
        ;;
    l)  # old barrier code
        version="24";
	# tagxid="tagctx";
        ;;
    n)  # no color
	eR='';eG='';eY='';eB='';eN=''
        nocolor=1
        ;;
    o)  # mount options
        mntopt="$OPTARG"
        ;;
    t)  # terse output
        terse=1
        ;;
    x)  # test xid tagging
        test_xid=1
        ;;
    y)  # test xattrs
        test_xattr=1
        ;;
    z)  # test disk limits
	test_dlimit=1
	;;
    D)  # device 
        DEV="$OPTARG"
        ;;
    F)  # single fs
        FSL="$OPTARG"
        ;;
    M)  # mount point
        MNT="$OPTARG"
        ;;
    N)  # nfs options
        NFS="$OPTARG"
        ;;
    O)  # nfs mount options
        nfsopt="$OPTARG"
        ;;
    P)  # nfs mount options
        pause="$OPTARG"
        ;;
    Z)  # use flash_eraseall
        flash=1
        ;;
  esac
done
shift $(($OPTIND - 1))

if [ -z "$DEV" ]; then
    eecho $eR "Please specify a device!" >&2
    exit 1
elif [ ! -e "$DEV" ]; then
    eecho $eR "Please specify a valid device!" >&2
    exit 1
fi

if [ ! -d "$MNT" ]; then
    eecho $eR "Please specify an existing mountpoint or create \"$MNT\"!" >&2
    exit 1
fi

outdev="/dev/null"
[ $verbose -gt 1 ] && outdev="/dev/stdout"
errdev="/dev/null"
[ $verbose -gt 0 ] && errdev="/dev/stderr"


eecho $eY "Linux-VServer FS Test [V0.20] Copyright (C) 2005-2008 H.Poetzl"

KERN=`uname -srm`
CHCV=`chcontext --version 2>&1`
CHCO=`echo -e "$CHCV" |
    sed -n '/--\|version/ {s/.*\ \([0-9][0-9.]*\).*/\1/g;p;q;}'`

INFO=(`sed 's/.*:\t//' /proc/virtual/info 2>/dev/null || echo '<none>'`)

KCIN="$[ 16#${INFO[2]} ]";

KCTM=$[ (KCIN >> 24) & 7 ];
KTAG=$[ (KCIN >> 28) & 1 ];

KCOW=$[ (KCIN >> 8) & 3 ];

case $KCTM in
  0) TAGI="None"	;;
  1) TAGI="UID16"	;;
  2) TAGI="GID16"	;;
  3) TAGI="ID24"	;;
  4) TAGI="Internal"	;;
  5) TAGI="Runtime"	;;
  *) TAGI="Unknown"	;;
esac

echo "$KERN/$CHCO"
echo "VCI:  $INFO ${INFO[1]} ${INFO[2]} ($TAGI)"

fsl=`echo $FSL | tr ',' ' '`

for fs in $fsl; do
    echo "---"
    eecho $eY "testing $fs filesystem ..."

    fsckopt="-p -f";
    case $fs in 
    nfs)
	do_test nfs "$nfsopt,$mntopt"
	continue
	;;
	
    ext2|ext3|ext4)
	mkfsopt="";
	testopt="$mntopt";
	;;
    ext4dev)
	mkfsopt="-E test_fs";
	testopt="$mntopt";
	;;
    xfs|jfs)
	mkfsopt="-f";
	testopt="$mntopt";
	;;
    reiser*)
	mkfsopt="-f";
	testopt="attrs,$mntopt"
	fs="reiserfs";
	;;
    ocfs2*)
	mkfsopt="";
	testopt="$mntopt"
	fsckopt="-f"
	fs="ocfs2";
	;;
    gfs2*)
	mkfsopt="";
	testopt="$mntopt"
	fs="gfs2";
	;;
    jffs2*)
	mkfsopt="--pad=65536 --root=$MNT -o ";
	testopt="$mntopt"
	fs="jffs2";
	;;
    *)
	eecho $eR "unknown filesystem $fs."
	continue
	;;
    esac
	
    [ $flash -gt 0 ] \
      && flash_eraseall -j $DEV 1>$outdev 2>$errdev \
      || yes | mkfs.$fs $mkfsopt $DEV 1>$outdev 2>$errdev 
    rc=$?; ececho $rc "[000]"
    [ $flash -gt 0 ] && DEV=${DEV##*/}
    [ $rc -gt 0 ] && echo "($fs format failed)" && continue
    do_test "$fs" "$testopt"
    [ $terse -ne 0 ] && echo "" 
done


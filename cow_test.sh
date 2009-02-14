#!/bin/sh

mount /dev/discs/disc1/part1 /mnt

DIR=/mnt/$$

mkdir -p $DIR/test/path

echo "five" >$DIR/five.data
ln $DIR/five.data $DIR/five.link
ln $DIR/five.data $DIR/five.lsym
ln $DIR/five.data $DIR/test/path/five.link
setattr --iunlink $DIR/five.link
ln $DIR/five.data $DIR/test/path/five.data
ln -s $DIR/five.lsym $DIR/test/five.sym

echo "- some test string" >>$DIR/five.link
echo "- another string" >>$DIR/test/five.sym
rm -f $DIR/test/path/five.data

echo "blocker" >$DIR/test/path/five.link©
echo "- some other string" >>$DIR/test/path/five.link

cat $DIR/five.data $DIR/five.link $DIR/test/path/five.link $DIR/test/five.sym
ls -la $DIR/five.data $DIR/five.link $DIR/test/path/five.link $DIR/test/five.sym

umount /mnt


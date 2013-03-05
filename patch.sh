#!/bin/bash

# This script takes an original source tarball, applies zenoss patches to it, and re-compresses it, and
# copies it to the Build/ directory.

# With no arguments, it will operate on all tarballs. If arguments are specified, it will operate on
# tarballs that have matching names. (ie. protobuf)

# Smart extract function
extract () {
  if [ $# != 1 ];
  then
    echo
    echo "  Usage: extract [COMPRESSED_FILENAME]"
    echo
  else
    if [ -f $1 ];
    then
      case $1 in
        *.tar)       tar -xf  $1  ;;
        *.tgz)       tar -xzf $1  ;;
        *.tar.gz)    tar -xzf $1  ;;
        *.tbz2)      tar -xjf $1  ;;
        *.tar.bz2)   tar -xjf $1  ;;
        *.gz)        gunzip    $1  ;;
        *.bz2)       bunzip2   $1  ;;
        *.zip)       unzip -qq     $1  ;;
        *)           echo "  '$1' file type unknown" ;;
      esac
    else
      echo "  '$1' is not a regular file"
      echo
    fi
  fi
}

#smart compress function
compress() {
  if [ $# != 2 ];
  then
    echo
    echo "  Usage: compress [COMPRESSED_FILENAME] [SOURCE_DIRECTORY]"
    echo
  else
    case $1 in
      *.tar.bz2)    tar -cjPf $1 $2 ;;
      *.tar.gz)     tar -czPf $1 $2 ;;
      *.tgz)        tar -czPf $1 $2 ;;
      *.zip)        zip -qr      $1 $2  ;;
      *)            echo "  '$1' file type unknown" ;;
    esac
  fi
}
SRC_REPO=$INSTDIR/externallibs
DST_REPO=`pwd`/Build/
if [ "$*" = "" ]; then
	# no args - create archives for all patched packages in $INSTDIR/externallibs:
	patch_packages=$(for patch in $(cd $SRC_REPO; ls *patch*); do echo ${patch}|perl -ne 'if (m/(.*)-r?\d/g){print "$1\n"}'; done|sort|uniq)
else
	# args - pattern match to pick individual archives only. "patch.sh protobuf" will look for protobuf*.tar.* to patch:
	patch_packages=""
	for p in $*; do
		echo -n "Looking for $p..."
		found_pkgs="$(cd $SRC_REPO; ls ${p}*.tar.*)"
		[ -z "$found_pkgs" ] && die "Couldn't find any match for $p. Exiting."
		echo "$found_pkgs"
		patch_packages="$patch_packages $found_pkgs"
	done
fi

if [ -d patch ]
then
   rm -rf patch
fi

for package in $patch_packages
do
   # do not create patched file if it already exists...
   [ -e $DST_REPO/$package ] && echo "$package exists in $DST_REPO, skipping." && continue 
   echo -n "Creating patched version of $package in $DST_REPO..."
   mkdir patch
   cp $SRC_REPO/$package* patch
   cd patch
   file=$(ls|grep -v patch)
   extract $file
   directory=$(ls -l|grep ^d| ls -l|grep ^d|awk '{print $9}')
   for patch in $(ls *.patch* 2>/dev/null); do echo "Applying patch ${patch}";patch -d $directory -p0 < ${patch}; done
   rm $file
   compress $file $directory
   mv $file $DST_REPO 
   cd ..
   rm -r patch
   echo " done!"
done

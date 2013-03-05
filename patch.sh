#!/bin/bash

# This script takes an original source tarball, applies zenoss patches to it, and re-compresses it, and
# copies it to the Build/ directory. Source tarball filenames are supplied via the command-line. The
# first argument is a relative path to search for files. Use "." for cwd.

die() {
echo $*
exit 1
}

try() {
"$@"
[ $? -ne 0 ] && echo Failure: $* && exit 1
}

# Smart extract function
extract () {
  if [ $# != 1 ];
  then
    die "  Usage: extract [COMPRESSED_FILENAME]"
  else
    if [ -f $1 ];
    then
      case $1 in
        *.tar)       try tar -xf  $1  ;;
        *.tgz)       try tar -xzf $1  ;;
        *.tar.gz)    try tar -xzf $1  ;;
        *.tbz2)      try tar -xjf $1  ;;
        *.tar.bz2)   try tar -xjf $1  ;;
        *.gz)        try gunzip    $1  ;;
        *.bz2)       try bunzip2   $1  ;;
        *.zip)       try unzip -qq     $1  ;;
        *)           die "  '$1' file type unknown" ;;
      esac
    else
      die "  '$1' is not a regular file"
    fi
  fi
}

#smart compress function
compress() {
  if [ $# != 2 ];
  then
    die "  Usage: compress [COMPRESSED_FILENAME] [SOURCE_DIRECTORY]"
  else
    case $1 in
      *.tar.bz2)    try tar -cjPf $1 $2 ;;
      *.tar.gz)     try tar -czPf $1 $2 ;;
      *.tgz)        try tar -czPf $1 $2 ;;
      *.zip)        try zip -qr      $1 $2  ;;
      *)            die "  '$1' file type unknown" ;;
    esac
  fi
}

DST_REPO=`pwd`/Build/

if [ -d patch ]
then
   rm -rf patch
fi
rel_path=$1
echo "Relative path: $rel_path"
shift
for archive_path in $*
do
   archive_path="$(ls -d $rel_path/$archive_path)"
   [ -d $archive_path ] && echo "Is directory: $archive_path, skipping..." && continue
   archive_basepath="${archive_path%/*}"
   archive_name="${archive_path##*/}"
   archive_noext="${archive_name%*.zip}"
   archive_noext="${archive_noext%*.tar.*}"
   [ ! -e $archive_path ] && die "Does not exist: $archive_path"
   echo "Processing archive $archive_name, applying any patches in $archive_basepath..."
   mkdir patch
   cp $archive_path patch
   cd patch
   extract $archive_path
   directory=$(ls -l|grep ^d| ls -l|grep ^d|awk '{print $9}')
   for patch in $(ls $archive_basepath/${archive_noext}*.patch* 2>/dev/null); do 
   	echo "Applying patch ${patch}"
	patch -d $directory -p0 < ${patch} || die "patch failed: $patch"
   done
   compress $DST_REPO/$archive_name $directory
   cd ..
   rm -r patch
done

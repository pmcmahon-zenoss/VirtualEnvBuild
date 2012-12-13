#!/bin/bash

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



#patch_packages="celery protobuf google-breakpad greenlet lxml networkx pyip pyOpenSSL PyXML RelStorage Twisted txAMQP urllib3 Zope2"
patch_packages=$(for patch in $(cd `pwd`/inst/externallibs; ls *patch*); do echo ${patch}|perl -ne 'if (m/(.*)-r?\d/g){print "$1\n"}'; done|sort|uniq)

if [ -d patch ]
then
   rm -rf patch
fi

for package in $patch_packages
do
   echo "extracting $package"
   mkdir patch
   cp `pwd`/inst/externallibs/$package* patch
   cd patch
   file=$(ls|grep -v patch)
   extract $file
   directory=$(ls -l|grep ^d| ls -l|grep ^d|awk '{print $9}')
   for patch in $(ls *.patch*); do echo "Applying patch ${patch}";patch -d $directory -p0 < ${patch}; done
   rm $file
   compress $file $directory
   mv $file ../Build
   cd ..
   rm -r patch
done

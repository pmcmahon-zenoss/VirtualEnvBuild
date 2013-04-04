#!/bin/bash

die() {
echo $*
exit 1
}

try() {
"$@"
[ $? -ne 0 ] && echo Failure: $* && exit 1
}

ORIG_DIR=`pwd`
ZENHOME=$1
if [ -d "$2" ]; then
	BUILDDIR=$2
else
	die "Please specify build directory as argument 2."
fi

[ -z "$MAKEOPTS" ] && MAKEOPTS="-j$(cat /proc/cpuinfo | grep -c vendor_id)"

A=$1
# strip path info if provided:
A_NAME="${A##*/}"
# expect source archive to have a directory inside with the same name, minus .tar.xz:
SRCDIR="$BUILDDIR/zenoss-*"
DESTDIR=$ORIG_DIR/image

# This is so maven and the python protocol install part can find both
# the "protoc" command as well as the libprotobuf shared library:
export PATH=$DESTDIR/$ZENHOME/bin:$PATH
export LD_LIBRARY_PATH=$DESTDIR/$ZENHOME/lib

##### mvn/oracle dependancies below ####
# Compile the java pieces
MVN_REPO=$BUILDDIR/maven_repo
install -d $MVN_REPO
MVN_OPTS="-Dmaven.repo.local=$MVN_REPO"
cd $SRCDIR/java/
mvn $MVN_OPTS clean install || die "core java build fail"

# Compile the protocols
cd $SRCDIR/protocols/
mvn $MVN_OPTS -f java/pom.xml clean install || die "java protocol build fail"

#compile zep
try cd $SRCDIR/zep
mvn $MVN_OPTS clean install || die "zep build fail"

#Install zep
ZEPDIST=$(ls -1 $SRCDIR/zep/dist/target/zep-dist-*.tar.gz)
(cd $DESTDIR/$ZENHOME;tar zxvhf $ZEPDIST) || die "zepdist extract fail"

# Compile the javascript , requires oracle java 1.6+
cp $SRCDIR/inst/externallibs/JSBuilder2.zip $BUILDDIR/
(cd $BUILDDIR/;unzip -o JSBuilder2.zip) || die "JSBuilder2 unzip fail"
JSBUILDER=$BUILDDIR/JSBuilder2.jar DESTDIR=$DESTDIR ZENHOME=$ZENHOME $SRCDIR/inst/buildjs.sh || die "JS compile failed"

echo "Setting permissions..."
chown -R zenoss:zenoss $DESTDIR/$ZENHOME || die "Couldn't set permissions"

# Maven does some nasty things with permissions. This is to fix that:
find $DESTDIR/$ZENHOME -type d -exec chmod 0775 {} \; || die "dir perm fix"
find $DESTDIR/$ZENHOME/webapps -type f -exec chmod 0664 {} \; || die "maven file fix"

echo "Done!"

#TODO:
#patch the zendmd file /opt/zenoss/bin/zendmd to point to the correct python path or reuse zenfunctions

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
BUILDDIR=$ORIG_DIR/Build
rm -rf $BUILDDIR
[ -z "$MAKEOPTS" ] && MAKEOPTS="-j$(cat /proc/cpuinfo | grep -c vendor_id)"

ZENHOME=/opt/zenoss4

if [ ! -e "$1" ]; then
die "Please specify archive to use as command-line argument 1."
fi

A=$1
# strip path info if provided:
A_NAME="${A##*/}"
# expect source archive to have a directory inside with the same name, minus .tar.xz:
SRCDIR=$BUILDDIR/${A_NAME%%.tar.*}
DESTDIR=$ORIG_DIR/image
INSTDIR=$SRCDIR/inst
export INSTDIR

# These are currently paths inside /opt, need to change so we write to DESTDIR rather than these paths
export ZENHOME
install -d $BUILDDIR || die

tar xvf $A -C $BUILDDIR || die "source tar extract fail"

# install some directory trees as-is from the source archive:
cp -a $SRCDIR/bin $DESTDIR/$ZENHOME/bin || die "bin install fail"
cp -a $SRCDIR/Products $DESTDIR/$ZENHOME/Products || die "products install fail"
cp -a $SRCDIR/inst/fs $DESTDIR/$ZENHOME/extras || die "extras install fail"
# Create some required directories:
mkdir -p $DESTDIR/$ZENHOME/{backups,export,build,etc} || die "standard dir create fail"
# Copy the license
for i in $(cd $INSTDIR/externallibs; ls Licenses.*)
do
cp $INSTDIR/externallibs/$i $DESTDIR/$ZENHOME || die "license $i fail"
done
cp $INSTDIR/License.zenoss $DESTDIR/$ZENHOME || die "license fail"

# This creates a patched version of the protobuf tarball in Build/, based on the original in Build/inst/externallibs:
./patch.sh protobuf || die "patch protobuf fail"

# Compile protocol buffers - protoc is required by maven stuff, below...
if [ ! -e $DESTDIR/$ZENHOME/bin/protoc ]
then
    cd $BUILDDIR
    tar xvf protobuf*tar* || die "protobuf extract fail"
    cd protobuf*
    ./configure --prefix=$ZENHOME --enable-shared=yes --enable-static=no || die "protobuf configure fail"
    make ${MAKEOPTS} || die "protobuf build fail"
    make DESTDIR=$DESTDIR install || die "protobuf install fail"
fi

##### mvn/oracle dependancies below ####
# Compile the java pieces
MVN_REPO=$BUILDDIR/maven_repo
install -d $MVN_REPO
MVN_OPTS="-Dmaven.repo.local=$MVN_REPO"
cd $SRCDIR/java/
mvn $MVN_OPTS clean install || die "core java build fail"
# Compile the protocols
cd $SRCDIR/protocols/
PATH=$DESTDIR/$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$DESTDIR/$ZENHOME/lib mvn $MVN_OPTS -f java/pom.xml clean install || die "java protocol build fail"

#compile zep
try cd $SRCDIR/zep
PATH=$DESTDIR/$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$DESTDIR/$ZENHOME/lib mvn $MVN_OPTS clean install || die "zep build fail"

#Install zep
ZEPDIST=$(ls -1 $SRCDIR/zep/dist/target/zep-dist-*.tar.gz)
(cd $DESTDIR/$ZENHOME;tar zxvhf $ZEPDIST) || die "zepdist extract fail"

# Compile the javascript , requires oracle java 1.6+
cp $INSTDIR/externallibs/JSBuilder2.zip $BUILDDIR/
(cd $BUILDDIR/;unzip -o JSBuilder2.zip) || die "JSBuilder2 unzip fail"
JSBUILDER=$BUILDDIR/JSBuilder2.jar DESTDIR=$DESTDIR ZENHOME=$ZENHOME $INSTDIR/buildjs.sh || die "JS compile failed"

echo "Setting permissions..."
chown -R zenoss:zenoss $DESTDIR/$ZENHOME || die "Couldn't set permissions"

# Maven does some nasty things with permissions. This is to fix that:
find $DESTDIR/$ZENHOME -type d -exec chmod 0775 {} \; || die "dir perm fix"
find $DESTDIR/$ZENHOME/webapps -type f -exec chmod 0664 {} \; || die "maven file fix"

echo "Done!"

#TODO:
#patch the zendmd file /opt/zenoss/bin/zendmd to point to the correct python path or reuse zenfunctions

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
PYTHON_VERSION=2.7
PYTHON=python${PYTHON_VERSION}

# this will vary based on tarball used:

if [ ! -e "$1" ]; then
die "Please specify archive to use as command-line argument 1."
fi

if [ ! -e "$2" ]; then
die "Please specify requirements.txt file as argument 2."
fi

A=$1
# strip path info if provided:
A_NAME="${A##*/}"
# expect source archive to have a directory inside with the same name, minus .tar.xz:
SRCDIR=$BUILDDIR/${A_NAME%%.tar.*}
DESTDIR=$ORIG_DIR/image
REQUIREMENTS=$2
INSTDIR=$SRCDIR/inst
export INSTDIR

# These are currently paths inside /opt, need to change so we write to DESTDIR rather than these paths
export ZENHOME
export VIRTUAL_ENV=$ZENHOME/venv
# we will tweak virtualenv so we can temporarily run it inside its destination build directory, without hard-coding 
# the temp build directory path. When zenoss is installed, this variable will be unset and things will operate
# correctly in their final location:
export VIRTUAL_ENV_PREFIX=$DESTDIR

install -d $BUILDDIR || die

mkdir -p $DESTDIR/$VIRTUAL_ENV || die "Couldn't create $VIRTUAL_ENV"
# Create a virtual environment if it doesnt already exist
if [ ! -e $DESTDIR/$VIRTUAL_ENV/bin/activate ]
then
try mkdir -p $DESTDIR/$VIRTUAL_ENV
virtualenv-$PYTHON_VERSION --distribute $DESTDIR/$VIRTUAL_ENV || die "virtualenv fail"
fi

#Change the paths and add a ZENHOME env variable:
# Ensure VIRTUAL_ENV is set to something like /opt/zenoss4/venv (it won't be by default)
# Ensure VIRTUAL_ENV_PREFIX can be used to move venv inside an image directory.

sed -i -e "s|^VIRTUAL_ENV=.*|VIRTUAL_ENV=$VIRTUAL_ENV|" -e 's|PATH="$VIRTUAL_ENV/bin:$PATH"|PATH="$VIRTUAL_ENV_PREFIX$VIRTUAL_ENV/bin:$PATH"\nZENHOME='$ZENHOME'\nexport ZENHOME|g' $DESTDIR/$VIRTUAL_ENV/bin/activate || die "path fix fail"

#Activate the virtual env
source $DESTDIR/$VIRTUAL_ENV/bin/activate || die "couldn't activate virtualenv"

tar xvf $A -C $BUILDDIR || die "source tar extract fail"

# patch some packages.
./patch.sh || die "patch fail" 

# The requirements.txt will be unique per branch
# Install the zope/python dependencies for the app.
cp $REQUIREMENTS $BUILDDIR/requirements.txt
sed -i -e "s|##INST##|$INSTDIR|g" $BUILDDIR/requirements.txt || die "couldn't sed tweak requirements.txt"
# auto-detect versions of archives in all source files... replace ##V## in the requirements.txt file with
# the version of the file from the archive:

# start with stub of all non-autodetected version lines:
sed -e "/##V##/d" $BUILDDIR/requirements.txt > $BUILDDIR/requirements.txt.autodetect
# now iteratively add auto-detected versions:
for line in $(grep "##V##" $BUILDDIR/requirements.txt); do
# get path info:
myp=${line/#file:/}
myp=${myp%/*}
# remove path info:
mya=${line##*/}
mya="${mya/\#\#V##/*}"
mya=$(ls $myp/$mya)
if [ ! -e "$mya" ]; then
	die "I am having trouble auto-detecting the version of this line from requirements.txt: $line"
fi
echo "file:"$mya >> $BUILDDIR/requirements.txt.autodetect
done

#pip should be found in the virtual environments path easily at this point
pip install -r $BUILDDIR/requirements.txt.autodetect || die "pip failure"

# Reactivate the virtual environment to update the PATH
source $DESTDIR/$VIRTUAL_ENV/bin/activate || die "activate fail"

# install some directory trees as-is from the source archive:
cp -a $SRCDIR/bin $DESTDIR/$ZENHOME/bin || die "bin install fail"
cp -a $SRCDIR/Products $DESTDIR/$ZENHOME/Products || die "products install fail"
cp -a $SRCDIR/inst/fs $DESTDIR/$ZENHOME/extras || die "extras install fail"
# Create some required directories:
mkdir -p $DESTDIR/$ZENHOME/{backups,export,build,etc} || die "standard dir create fail"
# Copy the license
cd $INSTDIR/externallibs || die "cd fail"
for i in $(ls Licenses.*)
do
cp $i $DESTDIR/$ZENHOME || die "license $i fail"
done
cp $INSTDIR/License.zenoss $DESTDIR/$ZENHOME || die "license fail"

#Setup the sitecustomize file
SITECUSTOMIZE=$DESTDIR/$VIRTUAL_ENV/lib/$PYTHON/sitecustomize.py
if [ -f $SITECUSTOMIZE ]
then
rm $SITECUSTOMIZE
fi

cat << EOF > $SITECUSTOMIZE || die "sitecustomize.py fail"
import sys, os, site
import warnings
warnings.filterwarnings('ignore', '.*', DeprecationWarning)
sys.setdefaultencoding('utf-8')
if os.environ.get('ZENHOME'):
site.addsitedir(os.path.join(os.getenv('ZENHOME'), 'ZenPacks'))
EOF

# Copy in conf files.

# zenoss.conf
sed -e "s;<<INSTANCE_HOME>>;$ZENHOME;g" $INSTDIR/conf/zenoss.conf.in > $DESTDIR/$ZENHOME/etc/zenoss.conf || die "zenoss.conf install fail"

# global.conf
if [ ! -f $DESTDIR/$ZENHOME/etc/global.conf ]
then
    cp $INSTDIR/conf/global.conf $DESTDIR/$ZENHOME/etc/ || die "global.conf copy fail"
fi

cd $INSTDIR/conf || die "conf cd fail"
for conf in *
do  
    if [ ! -f $DESTDIR/$ZENHOME/etc/$conf ]
    then
        cp $conf $DESTDIR/$ZENHOME/etc/$conf
        sed -i -e 's/ZENUSERNAME/$(ZOPEUSER)/' -e 's/ZENPASSWORD/$(ZOPEPASSWORD)/' $DESTDIR/$ZENHOME/etc/$conf || die "$conf fail"
    fi
done

# Copy in the skel files?
# Compile protocol buffers
# This tool is only required if we are going to compile them on our own.
if [ ! -e $DESTDIR/$ZENHOME/bin/protoc ]
then
    cd $BUILDDIR
    tar xvf protobuf*tar* || die "protobuf extract fail"
    cd protobuf*
    ./configure --prefix=$ZENHOME --enable-shared=yes --enable-static=no || die "protobuf configure fail"
    make ${MAKEOPTS} || die "protobuf build fail"
    make DESTDIR=$DESTDIR install || die "protobuf install fail"
# TODO: CHECK SETUP.PY INSTALL::::
    cd python/
    $PYTHON setup.py --distribute install || die "protobuf python install fail"
fi

#Make zensocket
#$ZENHOME is provided as part of the virtualenv environment and so thats how this knows where to go.
cd $INSTDIR/zensocket
make ${MAKEOPTS} || die "zensocket build fail"

# TODO: NEED TO CHECK THIS DESTDIR:
make DESTDIR=$DESTDIR install || "zensocket install fail"

#Make pyraw
# We need to patch this to make it venv aware.
if [ ! -f $INSTDIR/icmpecho/venv.patch ]
then
    cp $ORIG_DIR/patches/venv.patch $INSTDIR/icmpecho/venv.patch || die "venv patch copy fail"
    ( cd $INSTDIR/icmpecho; patch -p1 < venv.patch ) || die "venv patch fail"
fi

cd $INSTDIR/icmpecho
make VIRTUAL_ENV=/venv/ DESTDIR=$DESTDIR ${MAKEOPTS} || die "icmpecho fail"

# fix the python path by finding the virtualenv python in the path right now, hard-code it into zenfunctions:
sed -i -e 's|PYTHON=$ZENHOME/bin/python|PYTHON='`which $PYTHON`'|g' $DESTDIR/$ZENHOME/bin/zenfunctions || die "python path fix fail"
# TODO: add zendmd fix.

# build nmap, because we need it in the code and we set it setuid
if [ ! -e $DESTDIR/$ZENHOME/bin/nmap ]
then
    cd $BUILDDIR
    tar -xvf $INSTDIR/externallibs/nmap-* || die "nmap extract fail"
    cd $(ls -lda nmap*|grep ^drwx|awk '{print $9}') || die "nmap cd fail"
    ./configure --prefix=$ZENHOME --without-zenmap --without-ndiff || die "nmap configure fail"
    make ${MAKEOPTS} || die "nmap build fail"
    make DESTDIR=$DESTDIR install || die "nmap install fail"
fi

install -d $DESTDIR/$ZENHOME/share/mibs/site || die "mibs/site mkdir fail"
if [ ! -e $DESTDIR/$ZENHOME/share/mibs/site/ZENOSS-MIB.txt ]
then
    cp $INSTDIR/mibs/* $DESTDIR/$ZENHOME/share/mibs/site || die "mibs install fail"
fi
# Install libsmi
if [ ! -e $DESTDIR/$ZENHOME/bin/smidump ]
then
    rm -rf $BUILDDIR/libsmi*
    cp $INSTDIR/externallibs/libsmi-* $BUILDDIR
    cd $BUILDDIR
    tar xvf libsmi-* || die "libsmi extract fail"
    cd $(ls -lda libsmi*|grep ^drwx|awk '{print $9}') || die "libsmi cd fail"
    ./configure --prefix=$ZENHOME || die "libsmi configure fail"
    make ${MAKEOPTS} || die "libsmi build fail"
    make DESTDIR=$DESTDIR install || die "libsmi install fail"
fi

##### mvn/oracle dependancies below ####
# Compile the java pieces
cd $SRCDIR/java/
mvn clean install || die "core java build fail"
# Compile the protocols
cd $SRCDIR/protocols/
PATH=$DESTDIR/$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$DESTDIR/$ZENHOME/lib mvn -f java/pom.xml clean install || die "java protocol build fail"
PATH=$DESTDIR/$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$DESTDIR/$ZENHOME/lib make -C python clean build || die "python protocol build fail"
cd python/
$PYTHON setup.py --distribute install | die "python protocol install fail"

#compile zep
try cd $SRCDIR/zep
PATH=$DESTDIR/$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$DESTDIR/$ZENHOME/lib mvn clean install || die "zep build fail"

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
chmod 0775 $DESTDIR/$ZENHOME/bin/* || die "bin perm normalization"
chown root:zenoss $DESTDIR/$ZENHOME/bin/nmap $DESTDIR/$ZENHOME/bin/pyraw $DESTDIR/$ZENHOME/bin/zensocket || die "nmap/praw owner fail"
chmod 04750 $DESTDIR/$ZENHOME/bin/nmap $DESTDIR/$ZENHOME/bin/pyraw $DESTDIR/$ZENHOME/bin/zensocket || die "nmap/praw suid root fail"
# security fix - don't expose passwords to people who shouldn't see it:
chmod -R o-rwx $DESTDIR/$ZENHOME/etc || die "security fix fail"

echo "Done!"

#TODO:
#patch the zendmd file /opt/zenoss/bin/zendmd to point to the correct python path or reuse zenfunctions

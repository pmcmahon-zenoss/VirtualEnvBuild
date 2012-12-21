#!/bin/bash
ORIG_DIR=`pwd`
BUILDDIR=$ORIG_DIR/Build
rm -rf $BUILDDIR
[ -z "$MAKEOPTS" ] && MAKEOPTS="-j$(cat /proc/cpuinfo | grep -c vendor_id)"
ZENHOME=/opt/zenoss4
PYTHON_VERSION=2.7
PYTHON=python${PYTHON_VERSION}
VIRTUALENV=$ZENHOME/venv
VIRTUALENV_PROG=virtualenv-$PYTHON_VERSION

LIBSMI_PACKAGE=libsmi-0.4.8.tar.gz

# this will vary based on tarball used:

A=zenoss-core-trunk-20121219.tar.xz
SRCDIR=$BUILDDIR/core
REQUIREMENTS=requirements.txt.trunk
NMAP_PACKAGE=nmap-6.01.tgz

#A=zenoss-core-4.2.x-stable-20121219.tar.xz
#SRCDIR=$BUILDDIR/zenoss-4.2.x
#REQUIREMENTS=requirements.txt.stable
#NMAP_PACKAGE=nmap-5.51.4.tgz

INSTDIR=$SRCDIR/inst
export INSTDIR
export ZENHOME
export VIRTUALENV

die() {
	echo $*
	exit 1
}

try() {
	"$@"
	[ $? -ne 0 ] && echo Failure: $* && exit 1
}

mkdir -p $VIRTUALENV || die "Couldn't create $VIRTUALENV"
install -d $BUILDDIR || die

# Create a virtual environment if it doesnt already exist
if [ ! -e $VIRTUALENV/bin/activate ]
then
    try mkdir -p $VIRTUALENV
    $VIRTUALENV_PROG $VIRTUALENV || die "virtualenv fail"
fi

#Update the environment
#Change the paths and add a ZENHOME env variable
sed -i -e 's|PATH="$VIRTUAL_ENV/bin:$PATH"|PATH="$VIRTUAL_ENV/../bin:$VIRTUAL_ENV/bin:$PATH"\nZENHOME='$ZENHOME'\nexport ZENHOME|g' $VIRTUALENV/bin/activate || die "path fix fail"

#Activate the virtual env
source $VIRTUALENV/bin/activate || die "couldn't activate virtualenv"

tar xvf $A -C $BUILDDIR || die "source tar extract fail"

# patch some packages.
./patch.sh || die "patch fail" 

# The requirements.txt will be unique per branch
# Install the zope/python dependancies for the app.
cp $REQUIREMENTS $BUILDDIR/requirements.txt
sed -i -e "s|##INST##|$INSTDIR|g" $BUILDDIR/requirements.txt || die "couldn't sed tweak requirements.txt"

#pip should be found in the virtual environments path easily at this point
pip install -r $BUILDDIR/requirements.txt || die "pip failure"

# Reactivate the virtual environment to update the PATH
source $VIRTUALENV/bin/activate || die "activate fail"

# install some directory trees as-is from the source archive:
cp -a $SRCDIR/bin $ZENHOME/bin || die "bin install fail"
cp -a $SRCDIR/Products $ZENHOME/Products || die "products install fail"
cp -a $SRCDIR/inst/fs $ZENHOME/extras || die "extras install fail"
# Create some required directories:
mkdir -p $ZENHOME/{backups,export,build,etc} || die "standard dir create fail"
# Copy the license
cd $INSTDIR/externallibs || die "cd fail"
for i in $(ls Licenses.*)
do
    cp $i $ZENHOME || die "license $i fail"
done
cp $INSTDIR/License.zenoss $ZENHOME || die "license fail"

#Setup the sitecustomize file
SITECUSTOMIZE=$VIRTUALENV/lib/$PYTHON/sitecustomize.py
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
sed -e "s;<<INSTANCE_HOME>>;$ZENHOME;g" $INSTDIR/conf/zenoss.conf.in > $ZENHOME/etc/zenoss.conf || die "zenoss.conf install fail"

# global.conf
if [ ! -f $ZENHOME/etc/global.conf ]
then
    cp $INSTDIR/conf/global.conf $ZENHOME/etc/ || die "global.conf copy fail"
fi

cd $INSTDIR/conf || die "conf cd fail"
for conf in *
do  
    if [ ! -f $ZENHOME/etc/$conf.example ]
    then
        cp $conf $ZENHOME/etc/$conf.example
        sed -i -e 's/ZENUSERNAME/$(ZOPEUSER)/' -e 's/ZENPASSWORD/$(ZOPEPASSWORD)/' $ZENHOME/etc/$conf.example || die "$conf fail"
    fi
done

# Copy in the skel files?
# Compile protocol buffers
# This tool is only required if we are going to compile them on our own.
if [ ! -e $ZENHOME/bin/protoc ]
then
    cd $BUILDDIR
    tar xvf protobuf*tar* || die "protobuf extract fail"
    cd protobuf*
    ./configure --prefix=$ZENHOME --enable-shared=yes --enable-static=no || die "protobuf configure fail"
    make ${MAKEOPTS} || die "protobuf build fail"
    make install || die "protobuf install fail"
    cd python/
    python setup.py install || die "protobuf python install fail"
fi

#Make zensocket
#$ZENHOME is provided as part of the virtualenv environment and so thats how this knows where to go.
cd $INSTDIR/zensocket
make ${MAKEOPTS} || die "zensocket build fail"
make install || "zensocket install fail"

#Make pyraw
# We need to patch this to make it venv aware.
if [ ! -f $INSTDIR/icmpecho/venv.patch ]
then
    cp $ORIG_DIR/patches/venv.patch $INSTDIR/icmpecho/venv.patch || die "venv patch copy fail"
    ( cd $INSTDIR/icmpecho; patch -p0 < venv.patch ) || die "venv patch fail"
fi

cd $INSTDIR/icmpecho
make ${MAKEOPTS} || die "icmpecho fail"

# fix the python path by finding the virtualenv python in the path right now, hard-code it into zenfunctions:
sed -i -e 's|PYTHON=$ZENHOME/bin/python|PYTHON='`which $PYTHON`'|g' $ZENHOME/bin/zenfunctions || die "python path fix fail"
# TODO: add zendmd fix.

# build nmap, because we need it in the code and we set it setuid
if [ ! -e $ZENHOME/bin/nmap ]
then
    cd $BUILDDIR
    tar -xvf $INSTDIR/externallibs/$NMAP_PACKAGE || die "nmap extract fail"
    cd $(ls -lda nmap*|grep ^drwx|awk '{print $9}') || die "nmap cd fail"
    ./configure --prefix=$ZENHOME --without-zenmap --without-ndiff || die "nmap configure fail"
    make ${MAKEOPTS} || die "nmap build fail"
    make install || die "nmap install fail"
fi

install -d $ZENHOME/share/mibs/site || die "mibs/site mkdir fail"
if [ ! -e $ZENHOME/share/mibs/site/ZENOSS-MIB.txt ]
then
    cp $INSTDIR/mibs/* $ZENHOME/share/mibs/site || die "mibs install fail"
fi
# Install libsmi
if [ ! -e $ZENHOME/bin/smidump ]
then
    rm -rf $BUILDDIR/libsmi*
    cp $INSTDIR/externallibs/$LIBSMI_PACKAGE $BUILDDIR
    cd $BUILDDIR
    tar xvf $LIBSMI_PACKAGE || die "libsmi extract fail"
    cd $(ls -lda libsmi*|grep ^drwx|awk '{print $9}') || die "libsmi cd fail"
    ./configure --prefix=$ZENHOME || die "libsmi configure fail"
    make ${MAKEOPTS} || die "libsmi build fail"
    make install || die "libsmi install fail"
fi

##### mvn/oracle dependancies below ####
# Compile the java pieces
cd $SRCDIR/java/
mvn clean install || die "core java build fail"
# Compile the protocols
cd $SRCDIR/protocols/
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib mvn -f java/pom.xml clean install || die "java protocol build fail"
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib make -C python clean build || die "python protocol build fail"
cd python/
python setup.py install | die "python protocol install fail"

#compile zep
try cd $SRCDIR/zep
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib mvn clean install || die "zep build fail"

#Install zep
ZEPDIST=$(ls -1 $SRCDIR/zep/dist/target/zep-dist-*.tar.gz)
(cd $ZENHOME;tar zxvhf $ZEPDIST) || die "zepdist extract fail"

# Compile the javascript , requires oracle java 1.6+
cp $INSTDIR/externallibs/JSBuilder2.zip $BUILDDIR/
(cd $BUILDDIR/;unzip -o JSBuilder2.zip) || die "JSBuilder2 unzip fail"
JSBUILDER=$BUILDDIR/JSBuilder2.jar ZENHOME=$ZENHOME $INSTDIR/buildjs.sh || die "JS compile failed"

echo "Setting permissions..."
chown -R zenoss:zenoss $ZENHOME || die "Couldn't set permissions"

# Maven does some nasty things with permissions. This is to fix that:
find $ZENHOME -type d -exec chmod 0775 {} \; || die "dir perm fix"
find $ZENHOME/webapps -type f -exec chmod 0664 {} \; || die "maven file fix"
chmod 0775 $ZENHOME/bin/* || die "bin perm normalization"
chown root:zenoss $ZENHOME/bin/nmap $ZENHOME/bin/pyraw $ZENHOME/bin/zensocket || die "nmap/praw owner fail"
chmod 04750 $ZENHOME/bin/nmap $ZENHOME/bin/pyraw $ZENHOME/bin/zensocket || die "nmap/praw suid root fail"

echo "Done!"

#TODO:
#patch the zendmd file /opt/zenoss/bin/zendmd to point to the correct python path or reuse zenfunctions

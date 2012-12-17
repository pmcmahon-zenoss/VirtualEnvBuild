export BUILDDIR=`pwd`/Build
rm -rf $BUILDDIR
[ -z "$MAKEOPTS" ] && MAKEOPTS="-j$(cat /proc/cpuinfo | grep -c vendor_id)"
ZENHOME=/opt/zenoss4
PYTHON_VERSION=2.7
PYTHON=python-2.7
VIRTUALENV=$ZENHOME/venv
VIRTUALENV_PROG=virtualenv-$PYTHON_VERSION
ZOPEUSER=admin
ZOPEPASSWORD=zenoss
LIBSMI_PACKAGE=libsmi-0.4.8.tar.gz
NMAP_PACKAGE=nmap-6.01.tgz

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

# Early checkout of the inst directory.
if [ ! -d $BUILDDIR/inst ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/inst $BUILDDIR/inst || die "couldn't check out inst"
else
    (cd inst && svn up) 
fi

# patch some packages.
./patch.sh || die "patch fail" 

# The requirements.txt will be unique per branch
# Install the zope/python dependancies for the app.
cp requirements.txt $BUILDDIR/
sed -i -e "s|##PWD##|$BUILDDIR|g" $BUILDDIR/requirements.txt || die "couldn't sed tweak requirements.txt"

#pip should be found in the virtual environments path easily at this point
pip install -r $BUILDDIR/requirements.txt || die "pip failure"

# Reactivate the virtual environment to update the PATH
source $VIRTUALENV/bin/activate || die "activate fail"

#Checkout our sources and scripts
# Setup the bin folder
if [ ! -d $ZENHOME/bin ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/bin $ZENHOME/bin || die svn fail
else
    (cd $ZENHOME/bin && svn up)
fi

if [ ! -d $ZENHOME/Products ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/Products $ZENHOME/Products || die svn fail
else
    (cd $ZENHOME/Products && svn up)
fi

if [ ! -d $ZENHOME/extras ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/inst/fs $ZENHOME/extras || die svn fail
else
    (cd $ZENHOME/extras && svn up)
fi

if [ ! -d $BUILDDIR/core ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core $BUILDDIR/core || die svn fail
else
    (cd $BUILDDIR/core && svn up)
fi

# Create some required directories
mkdir -p $ZENHOME/{backups,export,build,etc} || die "standard dir create fail"

# Copy the license
cd $BUILDDIR/inst/externallibs || die "cd fail"
for i in $(ls Licenses.*)
do
    cp $i $ZENHOME || die "license $i fail"
done

cp $BUILDDIR/inst/License.zenoss $ZENHOME || die "license fail"

#Setup the sitecustomize file
PYTHONPATH=$(python -c "from distutils.sysconfig import get_python_lib; print(get_python_lib().replace('/site-packages',''))")
SITECUSTOMIZE=$VIRTUALENV/$PYTHON/sitecustomize.py
if [ -f $SITECUSTOMIZE ]
then
    rm $SITECUSTOMIZE
fi

cat << EOF > $SITECUSTOMIZE
import sys, os, site
import warnings
warnings.filterwarnings('ignore', '.*', DeprecationWarning)
sys.setdefaultencoding('utf-8')
if os.environ.get('ZENHOME'):
    site.addsitedir(os.path.join(os.getenv('ZENHOME'), 'ZenPacks'))
EOF

# Copy in conf files.

# zenoss.conf
sed -e "s;<<INSTANCE_HOME>>;$ZENHOME;g" inst/conf/zenoss.conf.in > $ZENHOME/etc/zenoss.conf || die "zenoss.conf install fail"

# global.conf
if [ ! -f $ZENHOME/etc/global.conf ]
then
    cp inst/conf/global.conf $ZENHOME/etc/ || die "global.conf copy fail"
fi

cd $BUILDDIR/inst/conf
for conf in *
do  
    if [ ! -f $ZENHOME/etc/$conf.example ]
    then
        cp $conf $ZENHOME/etc/$conf.example
        sed -i -e 's/ZENUSERNAME/$(ZOPEUSER)/' -e 's/ZENPASSWORD/$(ZOPEPASSWORD)/' $ZENHOME/etc/$conf || die "$conf fail"
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
cd $BUILDDIR/zensocket
make ${MAKEOPTS} || die "zensocket build fail"
make install || "zensocket install fail"

#Make pyraw
# We need to patch this to make it venv aware.
if [ ! -f $BUILDDIR/inst/icmpecho/venv.patch ]
then
    cp patches/venv.patch inst/icmpecho/venv.patch || die "venv patch copy fail"
    ( cd $BUILDDIR/inst/icmpecho; patch -p0 < venv.patch ) || die "venv patch fail"
fi

cd $BUILDDIR/inst/icmpecho
make ${MAKEOPTS} || die "icmpecho fail"

# fix the python path
sed -i -e 's|PYTHON=$ZENHOME/bin/python|PYTHON=`which python`|g' $ZENHOME/bin/zenfunctions || die "python path fix fail"

# build nmap, because we need it in the code and we set it setuid
if [ ! -e $ZENHOME/bin/nmap ]
then
    tar -C $BUILDDIR -xvf inst/externallibs/$NMAP_PACKAGE || die "nmap extract fail"
    cd $BUILDDIR
    cd $(ls -lda nmap*|grep ^drwx|awk '{print $9}') || die "nmap cd fail"
    ./configure --prefix=$ZENHOME --without-zenmap --without-ndiff || die "nmap configure fail"
    make ${MAKEOPTS} || die "nmap build fail"
    make install || die "nmap install fail"
fi

if [ ! -e $ZENHOME/share/mibs/site ]
then
    if [ ! -d $ZENHOME/share/mibs/site ]
    then
        mkdir -p $ZENHOME/share/mibs/site; || die "mibs/site mkdir fail"
    fi
fi

if [ ! -e $ZENHOME/share/mibs/site/ZENOSS-MIB.txt ]
then
    cp inst/mibs/* $ZENHOME/share/mibs/site || die "mibs install fail"
fi


# Install libsmi
if [ ! -e $ZENHOME/bin/smidump ]
then
    rm -rf $BUILDDIR/libsmi*
    cp inst/externallibs/$LIBSMI_PACKAGE $BUILDDIR
    cd $BUILDDIR
    tar xvf $LIBSMI_PACKAGE || die "libsmi extract fail"
    cd $(ls -lda libsmi*|grep ^drwx|awk '{print $9}') || die "libsmi cd fail"
    ./configure --prefix=$ZENHOME || die "libsmi configure fail"
    make ${MAKEOPTS} || die "libsmi build fail"
    make install || die "libsmi install fail"
fi

##### mvn/oracle dependancies below ####
# Compile the java pieces
cd $BUILDDIR/core/java/
mvn clean install || die "core java build fail"
# Compile the protocols
cd $BUILDDIR/core/protocols/
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib mvn -f java/pom.xml clean install || die "java protocol build fail"
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib make -C python clean build || die "python protocol build fail"
cd python/
python setup.py install | die "python protocol install fail"

#compile zep
try cd $BUILDDIR/core/zep
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib mvn clean install || die "zep build fail"

#Install zep
ZEPDIST=$(ls -1 $BUILDDIR/core/zep/dist/target/zep-dist-*.tar.gz)
(cd $ZENHOME;tar zxvhf $ZEPDIST) || die "zepdist extract fail"

# Compile the javascript , requires oracle java 1.6+
cp $BUILDDIR/inst/externallibs/JSBuilder2.zip $BUILDDIR/
(cd $BUILDDIR/;unzip -o JSBuilder2.zip) || die "JSBuilder2 unzip fail"
JSBUILDER=$BUILDDIR/JSBuilder2.jar ZENHOME=$ZENHOME $BUILDDIR/inst/buildjs.sh || die "JS compile failed"

echo "Setting permissions..."
chown -R zenoss:zenoss $ZENHOME || die "Couldn't set permissions"
echo "Done!"

#TODO:
#patch the zendmd file /opt/zenoss/bin/zendmd to point to the correct python path or reuse zenfunctions

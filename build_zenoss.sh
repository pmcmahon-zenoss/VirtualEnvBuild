export BUILDDIR=`pwd`/Build
rm -rf $BUILDDIR
ZENHOME=/opt/zenoss4
VIRTUALENV=$ZENHOME/venv
VIRTUALENV_PROG=virtualenv-2.7
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
./patch.sh || die

# The requirements.txt will be unique per branch
# Install the zope/python dependancies for the app.
cp requirements.txt $BUILDDIR/
sed -i -e "s|##PWD##|$BUILDDIR|g" $BUILDDIR/requirements.txt || die "couldn't sed tweak requirements.txt"

#pip should be found in the virtual environments path easily at this point
pip install -r $BUILDDIR/requirements.txt || die "pip failure"

# Reactivate the virtual environment to update the PATH
source $VIRTUALENV/bin/activate

#Checkout our sources and scripts
# Setup the bin folder
if [ ! -d $ZENHOME/bin ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/bin $ZENHOME/bin
else
    (cd $ZENHOME/bin && svn up)
fi

if [ ! -d $ZENHOME/Products ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/Products $ZENHOME/Products
else
    (cd $ZENHOME/Products && svn up)
fi

if [ ! -d $ZENHOME/extras ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/inst/fs $ZENHOME/extras
else
    (cd $ZENHOME/extras && svn up)
fi

if [ ! -d $BUILDDIR/core ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core $BUILDDIR/core
else
    (cd $BUILDDIR/core && svn up)
fi

# Create some required directories
mkdir -p $ZENHOME/{backups,export,build,etc}

# Copy the license
cd inst/externallibs
for i in $(ls Licenses.*)
do
    cp $i $ZENHOME
done
cd ../..

cp inst/License.zenoss $ZENHOME

#Setup the sitecustomize file
PYTHONPATH=$(python -c "from distutils.sysconfig import get_python_lib; print(get_python_lib().replace('/site-packages',''))")
SITECUSTOMIZE=$PYTHONPATH/sitecustomize.py
if [ -f $SITECUSTOMIZE ]
then
    rm $SITECUSTOMIZE
fi

cat << EOF > $PYTHONPATH/sitecustomize.py
import sys, os, site
import warnings
warnings.filterwarnings('ignore', '.*', DeprecationWarning)
sys.setdefaultencoding('utf-8')
if os.environ.get('ZENHOME'):
    site.addsitedir(os.path.join(os.getenv('ZENHOME'), 'ZenPacks'))
EOF

# Copy in conf files.

# zenoss.conf
sed -e "s;<<INSTANCE_HOME>>;$ZENHOME;g" inst/conf/zenoss.conf.in > $ZENHOME/etc/zenoss.conf

# global.conf
if [ ! -f $ZENHOME/etc/global.conf ]
then
    cp inst/conf/global.conf $ZENHOME/etc/
fi

cd inst/conf
for conf in *
do  
    if [ ! -f $ZENHOME/etc/$conf.example ]
    then
        cp $conf $ZENHOME/etc/$conf.example
        sed -i -e 's/ZENUSERNAME/$(ZOPEUSER)/' -e 's/ZENPASSWORD/$(ZOPEPASSWORD)/' $ZENHOME/etc/$conf
    fi
done
cd ../..

# Copy in the skel files?
# Compile protocol buffers
# This tool is only required if we are going to compile them on our own.
if [ ! -e $ZENHOME/bin/protoc ]
then
    cd $BUILDDIR
    tar xvf protobuf*tar*
    cd protobuf*
    ./configure --prefix=$ZENHOME --enable-shared=yes --enable-static=no
    make
    make install
    cd python/
    python setup.py install
fi

#Make zensocket
#$ZENHOME is provided as part of the virtualenv environment and so thats how this knows where to go.
cd $BUILDDIR/zensocket
make
make install

#Make pyraw
# We need to patch this to make it venv aware.
if [ ! -f $BUILDDIR/inst/icmpecho/venv.patch ]
then
    cp patches/venv.patch inst/icmpecho/venv.patch
    ( cd $BUILDDIR/inst/icmpecho; patch -p0 < venv.patch )
fi

cd $BUILDDIR/inst/icmpecho
make

# fix the python path
sed -i -e 's|PYTHON=$ZENHOME/bin/python|PYTHON=`which python`|g' $ZENHOME/bin/zenfunctions

# build nmap, because we need it in the code and we set it setuid
if [ ! -e $ZENHOME/bin/nmap ]
then
    tar -C $BUILDDIR -xvf inst/externallibs/$NMAP_PACKAGE
    cd $BUILDDIR
    cd $(ls -lda nmap*|grep ^drwx|awk '{print $9}')
    ./configure --prefix=$ZENHOME --without-zenmap --without-ndiff
    make
    make install
fi

if [ ! -e $ZENHOME/share/mibs/site ]
then
    if [ ! -d $ZENHOME/share/mibs/site ]
    then
        mkdir -p $ZENHOME/share/mibs/site;
    fi
fi

if [ ! -e $ZENHOME/share/mibs/site/ZENOSS-MIB.txt ]
then
    cp inst/mibs/* $ZENHOME/share/mibs/site
fi


# Install libsmi
if [ ! -e $ZENHOME/bin/smidump ]
then
    rm -rf $BUILDDIR/libsmi*
    cp inst/externallibs/$LIBSMI_PACKAGE $BUILDDIR
    cd $BUILDDIR
    tar xvf $LIBSMI_PACKAGE
    cd $(ls -lda libsmi*|grep ^drwx|awk '{print $9}')
    ./configure --prefix=$ZENHOME
    make
    make install
fi

##### mvn/oracle dependancies below ####
# Compile the java pieces
cd $BUILDDIR/core/java/
mvn clean install
pwd
# Compile the protocols
cd $BUILDDIR/core/protocols/
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib mvn -f java/pom.xml clean install
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib make -C python clean build
cd python/
python setup.py install

#compile zep
cd $BUILDDIR/core/zep
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib mvn clean install

#Install zep
ZEPDIST=$(ls -1 `pwd`/dist/target/zep-dist-*.tar.gz)
(cd $ZENHOME;tar zxvhf $ZEPDIST)

# Compile the javascript , requires oracle java 1.6+
cp $BUILDDIR/inst/externallibs/JSBuilder2.zip $BUILDDIR/
(cd $BUILDDIR/;unzip -o JSBuilder2.zip)
JSBUILDER=$BUILDDIR/JSBuilder2.jar ZENHOME=$ZENHOME `pwd`/inst/buildjs.sh

echo "Setting permissions..."
chown -R zenoss:zenoss $ZENHOME || die "Couldn't set permissions"
echo "Done!"

#TODO:
#patch the zendmd file /opt/zenoss/bin/zendmd to point to the correct python path or reuse zenfunctions

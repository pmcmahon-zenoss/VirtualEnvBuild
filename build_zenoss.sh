ZENHOME=/opt/zenoss
VIRTUALENV=$ZENHOME/venv
ZOPEUSER=admin
ZOPEPASSWORD=zenoss

export ZENHOME
export VIRTUALENV

./build_deps.sh

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

if [ ! -d Build/core ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core Build/core
else
    (cd Build/core && svn up)
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

# Compile the javascript
cp inst/externallibs/JSBuilder2.zip Build/ 
(cd Build/;unzip -o JSBuilder2.zip)
JSBUILDER=`pwd`/Build/JSBuilder2.jar ZENHOME=$ZENHOME `pwd`/inst/buildjs.sh

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
# Compile protoc
if [ ! -e /opt/zenoss/bin/protoc ]
then
    cd Build
    tar xvf protobuf*tar*
    cd protobuf*
    ./configure --prefix=$ZENHOME --enable-shared=yes --enable-static=no
    make
    make install
    cd python/
    python setup.py install
    cd ../../..
fi

# Compile the java pieces
cd Build/core/java/
mvn clean install

# Compile the protocols
cd ../protocols/
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib mvn -f java/pom.xml clean install
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib make -C python clean build
cd python/
python setup.py install

#compile zep
cd ../../zep
PATH=$ZENHOME/bin/:${PATH} LD_LIBRARY_PATH=$ZENHOME/lib mvn clean install

#Install zep
ZEPDIST=$(ls -1 `pwd`/dist/target/zep-dist-*.tar.gz)
(cd $ZENHOME;tar zxvhf $ZEPDIST)
cd ../../..

#Make zensocket
cd inst/zensocket
make
make install
cd ../..

#Make pyraw
# We need to patch this to make it venv aware.
if [ ! -f inst/icmpecho/venv.patch ]
then
    cp patches/venv.patch inst/icmpecho/venv.patch
    ( cd inst/icmpecho; patch -p0 < venv.patch )
fi

cd inst/icmpecho
make
cd ../../

# fix the python path
sed -i -e 's|PYTHON=$ZENHOME/bin/python|PYTHON=`which python`|g' $ZENHOME/bin/zenfunctions


# Optional build nmap  ... preferrably we do use the system nmap.

tar -C Build -xvf inst/externallibs/nmap-6.01.tgz
cd Build/nmap-6.01
./configure --prefix=/opt/zenoss --without-zenmap --without-ndiff
make
make install
cd ../..

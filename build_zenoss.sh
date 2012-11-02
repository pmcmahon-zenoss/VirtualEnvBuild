ZENHOME=/opt/zenoss
VIRTUALENV=$ZENHOME/venv
export ZENHOME
export VIRTUALENV

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

# Copy in zenoss.conf files.
sed -e "s;<<INSTANCE_HOME>>;$ZENHOME;g" inst/conf/zenoss.conf.in > $ZENHOME/etc/zenoss.conf

# Copy in the skel files?

# Compile protoc
if [ ! -e /opt/zenoss/bin/protoc ]
then
    cd Build
    tar xvf protobuf*
    cd protobuf*
    ./configure --prefix=$ZENHOME --enable-shared=yes --enable-static=no
    make
    make install
    cd ../..
fi

# Compile the java pieces
cd Build/core/java/
mvn clean install

# Compile the protocols
cd ../protocols/
LD_LIBRARY_PATH=$ZENHOME/lib mvn -f java/pom.xml clean install
LD_LIBRARY_PATH=$ZENHOME/lib make -C python clean build
cd python/
python setup.py install

#compile zep
cd ../../zep
LD_LIBRARY_PATH=$ZENHOME/lib mvn clean install

#Install zep
ZEPDIST=$(ls -1 `pwd`/dist/target/zep-dist-*.tar.gz)
(cd $ZENHOME;tar zxvhf $ZEPDIST)



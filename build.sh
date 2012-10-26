

#TODO(per Ian)
# Incorporate virtualenvwrapper
#http://www.doughellmann.com/articles/pythonmagazine/completely-different/2008-05-virtualenvwrapper/index.html

#also a todo is wrap this in a fabric script
# http://hynek.me/articles/python-app-deployment-with-native-packages/

As Root 
mkdir -p /opt/zenoss/venv
#http://rackerhacker.com/2012/01/31/create-a-local-pypi-repository-using-only-mod_rewrite/
yum -y groupinstall "Development tools"
yum -y install zlib-devel
yum -y install bzip2-devel
yum -y install openssl-devel
yum -y install ncurses-devel
yum -y install postgresql-libs
#wget http://www.python.org/ftp/python/2.7.3/Python-2.7.3.tar.bz2
#tar xf Python-2.7.3.tar.bz2
#cd Python-2.7.3
#./configure --prefix=/usr/local
#make -j4 && make altinstall


#wget http://pypi.python.org/packages/source/d/distribute/distribute-0.6.27.tar.gz
#tar xf distribute-0.6.27.tar.gz
#cd distribute-0.6.27
#python2.7 setup.py install


curl -O http://pypi.python.org/packages/2.7/s/setuptools/setuptools-0.6c11-py2.7.egg
chmod 775 setuptools-0.6c11-py2.7.egg
sh setuptools-0.6c11-py2.7.egg
#This should install the egg here: /usr/local/lib/python2.7/site-packages/

curl -O http://pypi.python.org/packages/source/p/pip/pip-1.0.tar.gz
tar xvfz pip-1.0.tar.gz
cd pip-1.0
python setup.py install # may need to be root</pre>

easy_install-2.7 virtualenv
virtualenv /opt/zenoss/venv
#update foo/bin/activate to set ZENHOME etc.
#update the ZENHOME=/opt/zenoss    environment variable
#update the path to be PATH=/opt/zenoss/bin:${PATH}
#update the path to add LD_LIBRARY_PATH=/opt/zenoss/lib    # this is only needed for protocols compilation since we are not using the system provided one
source /opt/zenoss/venv/bin/activate

# Early checkout of some requirements to make pip happy :)
svn co http://dev.zenoss.com/svnint/trunk/core/inst inst

./patch.sh  # Patch the files from inst. again to make pip happy.
            # we could have this process append these patched files to the end
            # of the requirements.txt

# The requirements.txt will be unique per branch
pip install -r requirements.txt


# Mkdirs (not sure this is absolutely necessary but it doesnt hurt.)
mkdir -p foo/{backups,export,build,etc}

#Checkout our sources and scripts
svn co http://dev.zenoss.com/svnint/trunk/core/bin /opt/zenoss/bin
svn co http://dev.zenoss.com/svnint/trunk/core/Products /opt/zenoss/Products
svn co http://dev.zenoss.com/svnint/trunk/core/inst/fs /opt/zenoss/extras
svn co http://dev.zenoss.com/svnint/trunk/core/protocols protocols
svn co http://dev.zenoss.com/svnint/trunk/core/zep zep


#copy the license
cp inst/License.zenoss /opt/zenoss

#Compile the javascript
mkdir build
cp inst/externallibs/JSBuilder2.zip build/
cd build/
unzip JSBuilder2.zip 
cd /opt/zenoss/
JSBUILDER=/home/foo/build/JSBuilder2.jar ZENHOME=`(pwd)` /home/foo/inst/buildjs.sh

# Setup the sitecustomize file.
cp in the sitecustomize.py

cat /opt/zenoss/venv/lib/python2.7/sitecustomize.py
import sys, os, site
import warnings
warnings.filterwarnings('ignore', '.*', DeprecationWarning)
sys.setdefaultencoding('utf-8')
if os.environ.get('ZENHOME'):
    site.addsitedir(os.path.join(os.getenv('ZENHOME'), 'ZenPacks'))



########### Not done yet
cp inst/conf/* /opt/zenoss/etc/
############

#zope-configuration
  sed (INSTANCE_HOME)
  
# Compile the protoc binary  (prefix=$ZENHOME)

# Compile the java pieces
svn co http://dev.zenoss.com/svnint/trunk/core core
cd core/java/
mvn clean install
# Compile the protocols
cd ../protocols/
PATH=/opt/zenoss/bin:/${PATH} LD_LIBRARY_PATH=/opt/zenoss/lib mvn -f java/pom.xml clean install
PATH=/opt/zenoss/bin:/${PATH} LD_LIBRARY_PATH=/opt/zenoss/lib make -C python clean build
cd python/
python setup.py install

#compile zep
cd ../../zep
PATH=/opt/zenoss/bin:/${PATH} LD_LIBRARY_PATH=/opt/zenoss/lib mvn clean install

#Install zep
cd /opt/zenoss
tar zxhf /home/foo/core/zep/dist/target/zep-dist-1.3-SNAPSHOT.tar.gz


#zensocket
cd inst/zensocket/
make
ZENHOME=/opt/zenoss make install


# icmpecho(pyraw) needs to point to system python (requires python development tools installed instead

# update PYTHON paths in bin files

# Require nmap ?? (setuid) might be an issue down the road.

./mkzenossinstance.sh

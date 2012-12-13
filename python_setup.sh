#!/bin/bash
PYTHON_BIN=python2.7
PIP_BIN=pip-2.7

sudo mkdir -p /opt/zenoss/venv
#http://rackerhacker.com/2012/01/31/create-a-local-pypi-repository-using-only-mod_rewrite/
if [ -e /usr/bin/yum ]
then

    sudo yum -y groupinstall "Development tools"
    sudo yum -y install zlib-devel bzip2-devel openssl-devel ncurses-devel postgresql-libs
fi

if [ ! -d 'Build' ]
then
   mkdir Build
fi

cd Build

PIP=`which $PIP_BIN`
if [ ! -n $PIP ]
then
    PYTHON=`which $PYTHON_BIN`
    if [ ! -n $PYTHON ]
    then
        if [ ! -x '/usr/local/bin/python2.7' ]
        then
            if [ ! -e 'Python-2.7.3.tar.bz2' ]
            then
                wget http://www.python.org/ftp/python/2.7.3/Python-2.7.3.tar.bz2
            fi

            if [ -d 'Python-2.7.3' ]
            then
                sudo rm -rf Python-2.7.3
            fi

            tar xf Python-2.7.3.tar.bz2
            cd Python-2.7.3
            ./configure --prefix=/usr/local
            sudo make -j4 && sudo make altinstall
            cd ..
        fi
    fi

    if [ ! -e 'setuptools-0.6c11-py2.7.egg' ]
    then
        curl -O http://pypi.python.org/packages/2.7/s/setuptools/setuptools-0.6c11-py2.7.egg
    fi

    chmod 775 setuptools-0.6c11-py2.7.egg
    sudo PATH=/usr/local/bin:${PATH} sh setuptools-0.6c11-py2.7.egg

    if [ ! -e 'pip-1.0.tar.gz' ]
    then
        curl -O http://pypi.python.org/packages/source/p/pip/pip-1.0.tar.gz
    fi
    tar xvfz pip-1.0.tar.gz
    cd pip-1.0
    sudo $PYTHON setup.py install # may need to be root</pre>
fi

#Install the virtualenv tool 
PIP=`which $PIP_BIN`
sudo $PIP install virtualenv

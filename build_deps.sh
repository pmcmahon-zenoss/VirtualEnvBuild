ZENHOME=/opt/zenoss
VIRTUALENV=$ZENHOME/venv
VIRTUALENV_PROG=virtualenv-2.7

export ZENHOME
export VIRTUALENV

sudo mkdir -p $ZENHOME
sudo chown -R zenoss $ZENHOME

chmod +x /opt/zenoss/bin/zopectl
chmod +x /opt/zenoss/bin/runzope

./python_setup.sh

# Create a virtual environment if it doesnt already exist
if [ ! -e $VIRTUALENV/bin/activate ]
then
    sudo mkdir -p $VIRTUALENV
    sudo chown -R zenoss $VIRTUALENV
    $VIRTUALENV_PROG $VIRTUALENV
fi

#Update the environment
#Change the paths and add a ZENHOME env variable
sed -i -e 's|PATH="$VIRTUAL_ENV/bin:$PATH"|PATH="$VIRTUAL_ENV/../bin:$VIRTUAL_ENV/bin:$PATH"\nZENHOME=/opt/zenoss\nexport ZENHOME|g' $VIRTUALENV/bin/activate

#Activate the virtual env
source $VIRTUALENV/bin/activate


# Early checkout of the inst directory.
if [ ! -d inst ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/inst inst
else
    (cd inst && svn up)
fi

# patch some packages.
./patch.sh 

# The requirements.txt will be unique per branch
# Install the zope/python dependancies for the app.
cp requirements.txt Build/
sed -i -e "s|##PWD##|`pwd`|g" Build/requirements.txt

#pip should be found in the virtual environments path easily at this point
pip install -r Build/requirements.txt

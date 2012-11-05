ZENHOME=/opt/zenoss
VIRTUALENV=$ZENHOME/venv
export ZENHOME
export VIRTUALENV

sudo mkdir -p $ZENHOME
sudo chown -R zenoss $ZENHOME

./python_setup.sh

if [ ! -e $VIRTUALENV/bin/activate ]
then
    sudo mkdir -p $VIRTUALENV
    sudo chown -R zenoss $VIRTUALENV
    /usr/local/bin/virtualenv $VIRTUALENV
fi

#Update the environment
sed -i -e 's|PATH="$VIRTUAL_ENV/bin:$PATH"|PATH="$VIRTUAL_ENV/../bin:$VIRTUAL_ENV/bin:$PATH"\nZENHOME=/opt/zenoss\nexport ZENHOME|g' $VIRTUALENV/bin/activate

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
pip install -r Build/requirements.txt

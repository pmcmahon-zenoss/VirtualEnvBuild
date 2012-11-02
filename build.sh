ZENHOME=/opt/zenoss
VIRTUALENV=$ZENHOME/venv

sudo mkdir -p /opt/zenoss
sudo chown -R zenoss /opt/zenoss
if [ ! -d $VIRTUALENV ]
then
    /usr/local/bin/virtualenv $VIRTUALENV
fi

#Update the environment
sed 's|PATH="$VIRTUAL_ENV/bin:$PATH"|PATH="$VIRTUAL_ENV/bin:$VIRTUAL_ENV/../bin:PATH\nZENHOME=$VIRTUAL_ENV\nexport $ZENHOME"|g' $VIRTUALENV/bin/activate > $VIRTUALENV/bin/activate

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
sed "s|##PWD##|`pwd`|g" requirements.txt > requirements.txt
cat requirements.txt
pip install -r requirements.txt

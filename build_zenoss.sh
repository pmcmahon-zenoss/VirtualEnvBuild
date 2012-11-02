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

if [ ! -d Build/protocols ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/protocols Build/protocols
else
    (cd Build/protocols && svn up)
fi

if [ ! -d Build/zep ]
then
    svn co http://dev.zenoss.com/svnint/trunk/core/zep Build/zep
else
    (cd Build/zep && svn up)
fi

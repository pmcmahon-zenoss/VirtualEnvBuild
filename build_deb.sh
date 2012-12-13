#sudo gem install fpm

fpm -s dir -t deb -n Zenoss -v 4.2.2 \
-a all -x "*.git" -x "*.bak" -x "*.orig" -x "**/.svn/**" \
--description "Automated build.  Branch: 4.2 Commit: X" \
/opt/zenoss

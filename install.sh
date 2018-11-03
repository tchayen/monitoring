#!/bin/bash

# Runs correctly on s-1vcpu-1gb droplet with Ubuntu 18.04

function generate_random {
  < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32}
}

export GRAPHITE_USER=graphite_user
export GRAPHITE_PASSWORD=$(generate_random)
export GRAPHITE_DB_NAME=graphite_db
export GRAFANA_DB_NAME=grafana_fb
export SECRET_KEY=$(generate_random)
export IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

apt-get update

# GRAPHITE #####################################################################

DEBIAN_FRONTEND=noninteractive apt-get -q -y --force-yes install graphite-web graphite-carbon
apt-get install -y postgresql libpq-dev python-psycopg2
su -c postgres psql -c "CREATE USER $GRAPHITE_USER WITH PASSWORD '$GRAPHITE_PASSWORD';"
su -c postgres createdb -O $GRAPHITE_USER $GRAPHITE_DB_NAME
su -c postgres createdb -O $GRAPHITE_USER $GRAFANA_DB_NAME

# Configure database
sed -i "s/\/var\/lib\/graphite\/graphite\.db/$GRAPHITE_DB_NAME/g" /etc/graphite/local_settings.py
sed -i 's/django\.db\.backends\.sqlite3/django\.db\.backends\.postgresql_psycopg2/g' /etc/graphite/local_settings.py
sed -i "s/'USER': ''/'USER': '$GRAPHITE_USER'/g" /etc/graphite/local_settings.py
sed -i "s/'PASSWORD': ''/'PASSWORD': '$GRAPHITE_PASSWORD'/g" /etc/graphite/local_settings.py
sed -i "s/'HOST': ''/'HOST': '127.0.0.1'/g" /etc/graphite/local_settings.py

# Use remote authentication
sed -i "s/#USE_REMOTE_USER_AUTHENTICATION/USE_REMOTE_USER_AUTHENTICATION/g" /etc/graphite/local_settings.py

# Set timezone
sed -i "s/#TIME_ZONE = 'America\/Los_Angeles'/TIME_ZONE = 'Europe\/London'/g" /etc/graphite/local_settings.py

# Set secret key
sed -i "s/#SECRET_KEY = 'UNSAFE_DEFAULT'/SECRET_KEY = '$SECRET_KEY'/g" /etc/graphite/local_settings.py

# Migrate database
graphite-manage migrate auth
graphite-manage migrate

# Enable graphite cache
sed -i "s/CARBON_CACHE_ENABLED=false/CARBON_CACHE_ENABLED=true/g" /etc/default/graphite-carbon

# Enable log rotation
sed -i "s/ENABLE_LOGROTATION = False/ENABLE_LOGROTATION = True/g" /etc/carbon/carbon.conf

# Listen on $IP
sed -i "s/0.0.0.0/$IP/g" /etc/carbon/carbon.conf

# Start carbon & graphite on boot
systemctl start carbon-cache
systemctl enable carbon-cache

# Copy default storage aggregation file to carbon directory
cp /usr/share/doc/graphite-carbon/examples/storage-aggregation.conf.example /etc/carbon/storage-aggregation.conf

# Start carbon service
service carbon-cache start

# APACHE #######################################################################

apt-get install -y apache2 libapache2-mod-wsgi

# Disable default site
a2dissite 000-default

# Copy Graphite’s virtual host template to Apache’s available sites directory
cp /usr/share/graphite-web/apache2-graphite.conf /etc/apache2/sites-available

# Enable Graphite virtual host and reload Apache
a2ensite apache2-graphite
service apache2 reload

# COLLECTD #####################################################################

apt-get install -y collectd collectd-utils

sed -i "s/#LoadPlugin ping/LoadPlugin ping/g" /etc/collectd/collectd.conf
sed -i "s/#LoadPlugin write_graphite/LoadPlugin write_graphite/g" /etc/collectd/collectd.conf

echo -e "<Plugin write_graphite>\
  <Node "example">\n\
    Host "$IP"\n\
    Port "2003"\n\
    Protocol "tcp"\n\
    LogSendErrors true\n\
    Prefix "collectd."\n\
    StoreRates true\n\
    AlwaysAppendDS false\n\
    EscapeCharacter "_"\n\
  </Node>\n\
</Plugin>" >> /etc/collectd/collectd.conf

perl -i -pe 's/retentions = 60:90d\n/retentions = 60:90d\n\n[collectd]\npattern = ^collectd.*\nretentions = 10s:1h,1m:1d,10m:1y\n/' /etc/carbon/storage-schemas.conf

# Start collectd and enable the service
systemctl start collectd.service
systemctl enable collectd.service

# Restart both Carbon and collectd for changes to take effect
service carbon-cache stop
service carbon-cache start
service collectd restart

# GRAFANA ######################################################################

apt-get install -y adduser libfontconfig
wget https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana_5.3.2_amd64.deb
dpkg -i grafana_5.3.2_amd64.deb
systemctl start grafana-server

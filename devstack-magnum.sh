#Should be run from 'ubuntu' account and root privileges should be given to ubuntu in visudo
# Require atlest 8 GB VM to run the first magnum bay. (After running 1 node Bay - 1 master and 1 minion, only 200 MB memory left.)
sudo apt-get update
sudo apt-get install git libffi-dev libssl-dev -y || sudo yum install -y git libffi-dev libssl-dev
cd ~
git clone https://git.openstack.org/openstack-dev/devstack
git clone https://github.com/openstack/barbican.git
mv barbican/contrib/devstack/lib/barbican devstack/lib/
mv barbican/contrib/devstack/extras.d/70-barbican.sh devstack/extras.d/
sudo mv ~/devstack/ /opt/stack/
cd /opt/stack/
export STACK_PASSWORD='replace_password'
cat > local.conf << END
[[local|localrc]]
DATABASE_PASSWORD=$STACK_PASSWORD
RABBIT_PASSWORD=$STACK_PASSWORD
SERVICE_TOKEN=$STACK_PASSWORD
SERVICE_PASSWORD=$STACK_PASSWORD
ADMIN_PASSWORD=$STACK_PASSWORD

KEYSTONE_TOKEN_FORMAT=UUID

# Repo related changes
RECLONE=yes

# Log
SCREEN_LOGDIR=/opt/stack/logs    # logs screen logs to /opt/stack/logs
DEBUG=True                       # enables/disables debug messages

# Enable Rally
#enable_service rally

# Enable the ceilometer metering services
#enable_service ceilometer-acompute ceilometer-acentral ceilometer-anotification ceilometer-collector
# Enable the ceilometer alarming services
#enable_service ceilometer-alarm-evaluator,ceilometer-alarm-notifier
# Enable the ceilometer api services
#enable_service ceilometer-api
disable_service tempest
enable_service heat
enable_service h-api
enable_service h-api-cfn
enable_service h-api-cw
enable_service h-eng
# Enable Neutron
disable_service n-net
enable_service q-svc
enable_service q-agt
enable_service q-dhcp
enable_service q-l3
enable_service q-meta
enable_service q-lbaas
enable_service neutron

enable_service rabbit mysql key barbican

# This is to keep the token small for testing
KEYSTONE_TOKEN_FORMAT=UUID
END

cat > local.sh << 'END_LOCAL_SH'
#!/bin/sh
ROUTE_TO_INTERNET=$(ip route get 8.8.8.8)
OBOUND_DEV=$(echo ${ROUTE_TO_INTERNET#*dev} | awk '{print $1}')
sudo iptables -t nat -A POSTROUTING -o $OBOUND_DEV -j MASQUERADE
END_LOCAL_SH
chmod 755 local.sh
./stack.sh
source /opt/stack/openrc admin admin
cd /tmp/
wget https://fedorapeople.org/groups/magnum/fedora-21-atomic-3.qcow2
glance image-create --name fedora-21-atomic-3 \
                    --visibility public \
                    --disk-format qcow2 \
                    --property os_distro='fedora-atomic'\
                    --container-format bare < fedora-21-atomic-3.qcow2
mysql -h 127.0.0.1 -u root -p$STACK_PASSWORD mysql <<EOF
CREATE DATABASE IF NOT EXISTS magnum DEFAULT CHARACTER SET utf8;
GRANT ALL PRIVILEGES ON magnum.* TO
    'root'@'%' IDENTIFIED BY '$STACK_PASSWORD'
EOF
cd ~
git clone https://git.openstack.org/openstack/magnum
cd magnum
sudo pip install -e .

# create the magnum conf directory
sudo mkdir -p /etc/magnum

# copy sample config and modify it as necessary
sudo cp etc/magnum/magnum.conf.sample /etc/magnum/magnum.conf

# copy policy.json
sudo cp etc/magnum/policy.json /etc/magnum/policy.json

# enable debugging output
sudo sed -i "s/#debug\s*=.*/debug=true/" /etc/magnum/magnum.conf

# set RabbitMQ userid
sudo sed -i "s/#rabbit_userid\s*=.*/rabbit_userid=stackrabbit/" \
         /etc/magnum/magnum.conf

# set RabbitMQ password
sudo sed -i "s/#rabbit_password\s*=.*/rabbit_password=$STACK_PASSWORD/" \
         /etc/magnum/magnum.conf

# set SQLAlchemy connection string to connect to MySQL
sudo sed -i "s/#connection\s*=.*/connection=mysql:\/\/root:$STACK_PASSWORD@localhost\/magnum/" \
         /etc/magnum/magnum.conf

# set Keystone account username
sudo sed -i "s/#admin_user\s*=.*/admin_user=admin/" \
         /etc/magnum/magnum.conf

# set Keystone account password
sudo sed -i "s/#admin_password\s*=.*/admin_password=$STACK_PASSWORD/" \
         /etc/magnum/magnum.conf

# set admin Identity API endpoint
sudo sed -i "s/#identity_uri\s*=.*/identity_uri=http:\/\/127.0.0.1:35357/" \
         /etc/magnum/magnum.conf

# set public Identity API endpoint
sudo sed -i "s/#auth_uri\s*=.*/auth_uri=http:\/\/127.0.0.1:5000\/v2.0/" \
         /etc/magnum/magnum.conf

# set notification_driver (if using ceilometer)
sudo sed -i "s/#notification_driver\s*=.*/notification_driver=messaging/" \
         /etc/magnum/magnum.conf

cd ~
git clone https://git.openstack.org/openstack/python-magnumclient
cd python-magnumclient
sudo pip install -e .
magnum-db-manage upgrade
cd /opt/stack/devstack/
source openrc admin admin
keystone service-create --name=magnum \
                        --type=container \
                        --description="magnum Container Service"
keystone endpoint-create --service=magnum \
                         --publicurl=http://127.0.0.1:9511/v1 \
                         --internalurl=http://127.0.0.1:9511/v1 \
                         --adminurl=http://127.0.0.1:9511/v1 \
                         --region RegionOne
screen -S stack -x -X screen magnum-api
screen -S stack -x -X screen magnum-conductor
#


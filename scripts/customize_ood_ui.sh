#!/bin/bash
# Customize OOD front-end
cd /var/www/ood/public
sudo wget https://raw.githubusercontent.com/koiker/oci-hpc/master/artifacts/ondemand/oci_logo.png
sudo wget https://raw.githubusercontent.com/koiker/oci-hpc/master/artifacts/ondemand/header_logo.png
sudo wget https://raw.githubusercontent.com/koiker/oci-hpc/master/artifacts/ondemand/oj-redwood-min.css
sudo wget -O favicon.ico https://raw.githubusercontent.com/koiker/oci-hpc/master/artifacts/ondemand/favicon.ico
sudo mkdir /etc/ood/config/ondemand.d
cd /etc/ood/config/ondemand.d
sudo wget https://raw.githubusercontent.com/koiker/oci-hpc/master/artifacts/ondemand/oracle_ux.yml
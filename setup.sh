#!/bin/bash
# Install dependencies using apt

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# function to print text with color
function print_text {
    echo -e "${1}${2}${NC}"
}

# makes sure this is not run as root
if [ "$EUID" -eq 0 ]; then
  print_text "${RED}" "Please do not run this script as root."
  exit
fi

# get the current directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# write the cloudflare key to ${DIR}/.secrets/cloudflare.key
mkdir -p ${DIR}/.secrets
print_text $CYAN "Enter your Cloudflare API key: "
read -s CLOUDFLARE_API_KEY
echo "dns_cloudflare_api_token = ${CLOUDFLARE_API_KEY}" > ${DIR}/.secrets/cloudflare.key
chmod 600 ${DIR}/.secrets/cloudflare.key

# get the subdomain
print_text $CYAN "Enter your subdomain:"
read SUBDOMAIN

# get the email
print_text $CYAN "Enter your email:"
read EMAIL

print_text $CYAN "Do you want to add the cloudflare dns records? (y/n)"
read CLOUDFLARE_ANSWER

# setting up
print_text $CYAN "Setting up in 5 seconds... (it's normal to see a certbot error and a lot of output)"
sleep 5

# setup nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
# source nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
# use nvm to install nodejs lts
nvm install --lts

# install npm
sudo apt-get install npm -y

# frps and its systemd service are already in the git repo
# just link it to /usr/bin
sudo ln -s ${DIR}/frps /usr/bin/frps
# link its systemd service to /etc/systemd/system/frps.service
sudo ln -s ${DIR}/systemd/frps.service /etc/systemd/system/frps.service
# copy example config then link to /etc/frp/frps.ini
cp ${DIR}/configs/frps-example.ini ${DIR}/configs/frps.ini
# echo the subdomain into the config
echo "subdomain_host = ${SUBDOMAIN}.lodestone.link" >> ${DIR}/configs/frps.ini
sudo mkdir -p /etc/frp
sudo ln -s ${DIR}/configs/frps.ini /etc/frp/frps.ini

# start the systemd service for frps
sudo systemctl daemon-reload
sudo systemctl start frps
sudo systemctl enable frps

# install nginx
sudo apt-get install nginx -y
sudo systemctl stop nginx
# copy the example config, then link it to /etc/nginx/nginx.conf
cp ${DIR}/configs/nginx-example.conf ${DIR}/configs/nginx.conf
# change line 17 to "server_name = ${SUBDOMAIN}.lodestone.link"
sed -i "17s/.*/server_name = ${SUBDOMAIN}.lodestone.link;/" ${DIR}/configs/nginx.conf
# backup the original nginx config
sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
sudo ln -s ${DIR}/configs/nginx.conf /etc/nginx/nginx.conf
sudo systemctl start nginx
sudo systemctl reload nginx

# install certbot snap, assuming snapd is installed
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot

#confirm plugin containment level
sudo snap set certbot trust-plugin-with-root=ok
# install certbot dns challenge plugin
sudo snap install certbot-dns-cloudflare
# sets up certbot, with nginx block 1
sudo certbot --installer nginx --dns-cloudflare --dns-cloudflare-credentials ${DIR}/.secrets/cloudflare.key -d "*.${SUBDOMAIN}.lodestone.link" -d "${SUBDOMAIN}.lodestone.link" --agree-tos --non-interactive --email ${EMAIL}
# install to nginx, pipe 1\n1\n to the script
echo -e "\n\n\n" | sudo certbot install --nginx --cert-name ${SUBDOMAIN}.lodestone.link 

# adds the cron job to renew the cert
(crontab -l 2>/dev/null; echo "0 0 1 * * certbot renew --post-hook \"sudo systemctl reload nginx\"") | crontab -

# reload nginx
sudo systemctl reload nginx

# opens up ports 80, 443, 7000 to 50000 to the world
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 7000:50000
# enable ufw
sudo ufw enable

# hard coded cloudflare zone id
CLOUDFLARE_ZONE_ID="7e33a6c50e6b91c041ac986dad84035e"
# get my own ip address
IP_ADDRESS=$(curl -s https://api.ipify.org)

if [ "$CLOUDFLARE_ANSWER" == "y" ]; then
  # automatically add cloudflare dns records using the api token
  curl -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_KEY}" \
    --data '{"type":"A","name":"'${SUBDOMAIN}'.lodestone.link","content":"'${IP_ADDRESS}'","ttl":1,"proxied":false}'
  curl -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_KEY}" \
    --data '{"type":"A","name":"*.'${SUBDOMAIN}'.lodestone.link","content":"'${IP_ADDRESS}'","ttl":1,"proxied":false}'
else
  # manually add cloudflare dns records
  print_text $CYAN "please add the following records to your dns manually:"
  print_text $CYAN "A ${SUBDOMAIN}.lodestone.link ${IP_ADDRESS}"
  print_text $CYAN "A *.${SUBDOMAIN}.lodestone.link ${IP_ADDRESS}"
fi

echo "\n"

# reboot system?
print_text $RED "Reboot? (y/n)"
read -n 1 -s
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi

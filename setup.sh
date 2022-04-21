# Install dependencies using apt
# need nginx, nodejs, npm, certbot, frp

# get the current directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# write the cloudflare key to ${DIR}/.secrets/cloudflare.key
mkdir -p ${DIR}/.secrets
echo "Enter your Cloudflare API key:"
read -s CLOUDFLARE_API_KEY
echo "dns_cloudflare_api_token = ${CLOUDFLARE_API_KEY}" > ${DIR}/.secrets/cloudflare.key
chmod 600 ${DIR}/.secrets/cloudflare.key

# get the subdomain
echo "Enter your subdomain:"
read SUBDOMAIN

# setting up
echo "Setting up..."

# install nginx
sudo apt-get install nginx
# copy the example config, then link it to /etc/nginx/nginx.conf
cp ${DIR}/configs/nginx-example.conf ${DIR}/configs/nginx.conf
sudo ln -s ${DIR}/configs/nginx.conf /etc/nginx/nginx.conf

# setup nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
# use nvm to install nodejs lts
nvm install --lts

# install npm
sudo apt-get install npm

# frps and its systemd service are already in the git repo
# just link it to /usr/bin
sudo ln -s /home/ubuntu/link/frps /usr/bin/frps
# link its systemd service to /etc/systemd/system/frps.service
sudo ln -s /home/ubuntu/link/systemd/frps.service /etc/systemd/system/frps.service
# copy example config then link to /etc/frp/frps.ini
cp ${DIR}/configs/frps-example.ini ${DIR}/configs/frps.ini
# echo the subdomain into the config
echo "subdomain_host = ${SUBDOMAIN}" >> ${DIR}/configs/frps.ini
sudo ln -s ${DIR}/configs/frps.ini /etc/frp/frps.ini

# start the systemd service for frps
sudo systemctl daemon-reload
sudo systemctl start frps
sudo systemctl enable frps

# reload nginx
sudo systemctl reload nginx

# install certbot snap, assuming snapd is installed
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
# sets up certbot
sudo certbot --install nginx --dns-cloudflare-credentials ${DIR}/.secrets/cloudflare.key -d "*.${SUBDOMAIN}.lodestone.link" -d "${SUBDOMAIN}.lodestone.link" --agree-tos --non-interactive

# adds the cron job to renew the cert
(crontab -l 2>/dev/null; echo "0 0 1 * * certbot renew --post-hook \"sudo systemctl reload nginx\"") | crontab -

# opens up ports 80, 443, 7000 to 50000 to the world
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 7000:50000
# enable ufw
sudo ufw enable
# reboot system?
echo "Reboot? (y/n)"
read -n 1 -s
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi

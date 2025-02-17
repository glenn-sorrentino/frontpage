#!/bin/bash
set -euo pipefail

# Run as root
if [[ $EUID -ne 0 ]]; then
  echo "Script needs to run as root. Elevating permissions now."
  exec sudo /bin/bash "$0" "$@"
  exit $?
fi

# Welcome message and ASCII art
cat <<"EOF"
  _____                _                          
 |  ___| __ ___  _ __ | |_ _ __   __ _  __ _  ___ 
 | |_ | '__/ _ \| '_ \| __| '_ \ / _` |/ _` |/ _ \
 |  _|| | | (_) | | | | |_| |_) | (_| | (_| |  __/
 |_|  |_|  \___/|_| |_|\__| .__/ \__,_|\__, |\___|
                          |_|          |___/      

📰 A self-hosted, privacy-focused publishing platform for independent and autonomous newsrooms.
https://github.com/scidsg/frontpage

A free tool by Science & Design - https://scidsg.org

EOF

# Function to display error message and exit
error_exit() {
    echo "An error occurred during installation. Please check the output above for more details."
    exit 1
}

# Trap any errors and call the error_exit function
trap error_exit ERR

# Update and upgrade the system
export DEBIAN_FRONTEND=noninteractive
apt update && apt -y dist-upgrade

# Install Python and pip
apt install -y \
    git \
    nginx \
    python3 \
    python3-pip \
    python3-venv

cd /var/www/html
if [ ! -d frontpage ]; then
    git clone https://github.com/scidsg/frontpage
fi
cd frontpage

# Create and activate Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Debian only have 1.3.2, and we need 1.6.0 or higher
pip install -U poetry

# Install Flask and other dependencies
poetry self add poetry-plugin-export
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
poetry export --only main -f requirements.txt --output requirements.txt
pip install -r requirements.txt

touch .env

# Generate and export Flask secret key
if ! egrep -q '^FLASK_SECRET_KEY=' .env; then
    echo 'Generating new secret key'
    FLASK_SECRET_KEY=$(openssl rand -hex 32)
    echo "FLASK_SECRET_KEY=$FLASK_SECRET_KEY" >> .env
fi

# Initialize the Flask app and create the database within application context
export FLASK_APP=frontpage:app
poetry run flask db upgrade
poetry run flask db-extras add-article-types

# Change owner and permissions of the SQLite database file
chown -R www-data:www-data /var/www/html/frontpage

# Add upload directory
mkdir -p /var/www/html/frontpage/frontpage/static/uploads
chown -R www-data:www-data /var/www/html/frontpage/frontpage/static/uploads
chmod -R 755 /var/www/html/frontpage/frontpage/static/uploads

cp -n files/frontpage.service /etc/systemd/system/frontpage.service

# Set up Nginx to proxy requests to Flask
cp files/nginx.conf /etc/nginx/sites-available/frontpage
ln -sf /etc/nginx/sites-available/frontpage /etc/nginx/sites-enabled
rm -f /etc/nginx/sites-available/default
rm -f /etc/nginx/sites-enabled/default
pkill -9 nginx
systemctl restart nginx.service

systemctl enable frontpage.service
systemctl start frontpage.service
systemctl restart frontpage.service

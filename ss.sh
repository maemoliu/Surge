.sh
#!/bin/bash
#
# This macOS bash script helps you initialize a new Shadowsocks server with doctl in seconds.
# Original author: lexrus https://github.com/lexrus
#
# You can get $100 free credit for create VPS in DigitalOcean with my referral link:
# https://m.do.co/c/3eb5cf371fc9
# 
# Please intall and authorize doctl before running this script.
# https://github.com/digitalocean/doctl


PASSWORD=$2
METHOD=$3

if [ -z "$PASSWORD" ]; then
  PASSWORD=$(openssl rand -base64 12)
fi

if [ -z "$METHOD" ]; then
  METHOD=chacha20-ietf-poly1305
fi

function userdata {
  JSON=$(bash "$0" json "${PASSWORD}" "${METHOD}")
  JSON_STR=$(echo "$JSON" | python -m json.tool | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
  SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)

  cat <<EOF
#!/bin/bash
update-locale LANG=en_US.UTF-8
apt install -y shadowsocks-libev simple-obfs
echo "${SSH_PUB_KEY}" > ~/.ssh/authorized_keys
printf ${JSON_STR} > /etc/shadowsocks-libev/config.json
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
setcap cap_net_bind_service+ep /usr/bin/obfs-server
sysctl -p
systemctl restart shadowsocks-libev.service
EOF
}

case $1 in
  "json")
    cat <<EOF
{
  "server":["::1", "0.0.0.0"],
  "mode":"tcp_and_udp",
  "server_port":443,
  "local_port":1080,
  "password":"${PASSWORD}",
  "timeout":86400,
  "method":"${METHOD}",
  "workers": 4,
  "plugin": "obfs-server",
  "plugin_opts": "obfs=tls;obfs-host=www.bing.com",
  "fast_open": true,
  "reuse_port": true
}
EOF
    ;;

  "new")
    doctl compute region list | grep true
    read -rp "Select region(just type alias): " REGION
    echo "Selected region: $REGION"

    if [ -z "$REGION" ]; then
      echo "Region is empty"
      exit 1
    fi

    SERVER_NAME="$REGION-$(date +%Y%m%d)"

    userdata > /tmp/.userdata.sh

    echo "Creating droplet..."
    doctl compute droplet create \
      --user-data-file /tmp/.userdata.sh \
      --enable-ipv6 --enable-monitoring \
      --image debian-11-x64 \
      --size s-1vcpu-1gb \
      --region "$REGION" "$SERVER_NAME" \
      --wait
    rm -rf /tmp/.userdata.sh

    SERVER_IP=$(doctl compute droplet get "$SERVER_NAME" --format PublicIPv4 | tail -n 1)
    echo "Add this line to your Surge config:"
    echo ""
    echo "${SERVER_NAME} = ss, ${SERVER_IP}, 443, encrypt-method=${METHOD}, password=${PASSWORD}"
    echo ""
    ;;

  "help")
    cat << EOF
A tiny script to initialize a new Shadowsocks server in DigitalOcean.
Usage:
  ./doss.sh json ["SS_PASSWORD"] ["SS_METHOD"]
    Generates a config file for Shadowsocks server.
    If SS_PASSWORD is not specified, a random password will be generated.
    If SS_METHOD is not specified, chacha20-ietf-poly1305 will be used.
  ./doss.sh new ["SS_PASSWORD"] ["SS_METHOD"]
    Creates a new Droplet and initialize the Shadowsocks server.
    If SS_PASSWORD is not specified, a random password will be generated.
    If SS_METHOD is not specified, chacha20-ietf-poly1305 will be used.
  ./doss.sh help
    Just print me.
EOF
    ;;

  "")
    bash "$0" help
    ;;

esac
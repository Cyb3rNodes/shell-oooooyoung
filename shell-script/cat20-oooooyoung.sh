Crontab_file="/usr/bin/crontab"
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m"
Font_color_suffix="\033[0m"
Info="[${Green_font_prefix}information${Font_color_suffix}]"
Error="[${Red_font_prefix}error${Font_color_suffix}]"
Tip="[${Green_font_prefix}Notice${Font_color_suffix}]"

check_root() {
    [[ $EUID != 0 ]] && echo -e "${Error} The current account is not a ROOT account (or does not have ROOT permissions), and the operation cannot continue. Please change the ROOT account or use ${Green_background_prefix}sudo su${Font_color_suffix} Command to obtain temporary ROOT permissions (you may be prompted to enter the password of the current account after execution)。" && exit 1
}

install_env_and_full_node() {
    check_root
    sudo apt update && sudo apt upgrade -y
    sudo apt install curl tar wget clang pkg-config libssl-dev jq build-essential git make docker.io postgresql-client -y
    VERSION=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
    DESTINATION=/usr/local/bin/docker-compose
    sudo curl -L https://github.com/docker/compose/releases/download/${VERSION}/docker-compose-$(uname -s)-$(uname -m) -o $DESTINATION
    sudo chmod 755 $DESTINATION

    sudo apt-get install npm -y
    sudo npm install n -g
    sudo n stable
    sudo npm i -g yarn

    git clone https://github.com/CATProtocol/cat-token-box
    cd cat-token-box
    sudo yarn install
    sudo yarn build

    cd ./packages/tracker/
    sudo chmod 777 docker/data
    sudo chmod 777 docker/pgdata
    sudo docker-compose up -d

    cd ../../
    sudo docker build -t tracker:latest .
    BASE_URL="http://88.99.70.27:41187/"
    FILES=$(curl -s $BASE_URL | grep -oP 'dump_file_\d+\.sql')
    LATEST_FILE=$(echo "$FILES" | sort -V | tail -n 1)
    echo "Downloading the latest file: $LATEST_FILE"
    curl -O "$BASE_URL$LATEST_FILE"

    export PGPASSWORD='postgres'
    psql -h 127.0.0.1 -U postgres -d postgres -f "$LATEST_FILE"
    unset PGPASSWORD

    sudo docker run -d \
        --name tracker \
        --add-host="host.docker.internal:host-gateway" \
        -e DATABASE_HOST="host.docker.internal" \
        -e RPC_HOST="host.docker.internal" \
        -p 3000:3000 \
        tracker:latest
    echo '{
      "network": "fractal-mainnet",
      "tracker": "http://127.0.0.1:3000",
      "dataDir": ".",
      "maxFeeRate": 30,
      "rpc": {
          "url": "http://127.0.0.1:8332",
          "username": "bitcoin",
          "password": "opcatAwesome"
      }
    }' > ~/cat-token-box/packages/cli/config.json
}

create_wallet() {
  echo -e "\n"
  cd ~/cat-token-box/packages/cli
  sudo yarn cli wallet create
  echo -e "\n"
  sudo yarn cli wallet address
  echo -e "Please save the wallet address and mnemonic phrase created above."
}

start_mint_cat() {
  # Prompt for token ID
  read -p "Please enter the mint tokenId: " tokenId

  # Prompt for gas (maxFeeRate)
  read -p "Enter mint gas: " newMaxFeeRate
  sed -i "s/\"maxFeeRate\": [0-9]*/\"maxFeeRate\": $newMaxFeeRate/" ~/cat-token-box/packages/cli/config.json

  # Prompt for amount to mint
  read -p "Please enter the mint amount: " amount

  cd ~/cat-token-box/packages/cli

  # Update the mint command with tokenId and amount
  command="sudo yarn cli mint -i $tokenId $amount"

  # Run the minting loop
  while true; do
      $command

      if [ $? -ne 0 ]; then
          echo "Command execution failed, exit the loop"
          exit 1
      fi

      sleep 1
  done
}

check_tracker_log() {
  docker logs -f --tail 100 tracker
}

check_node_log() {
  docker logs -f tracker-bitcoind-1 --tail 100
}

check_wallet_balance() {
  cd ~/cat-token-box/packages/cli
  sudo yarn cli wallet balances
}

send_token() {
  read -p "Please enter tokenId (not token name): " tokenId
  read -p "Please enter the receiving address: " receiver
  read -p "Please enter the transfer amount: " amount
  cd ~/cat-token-box/packages/cli
  sudo yarn cli send -i $tokenId $receiver $amount
  if [ $? -eq 0 ]; then
      echo -e "${Info} Transfer successful"
  else
      echo -e "${Error} Transfer failed, please check the information and try again"
  fi
}


echo && echo -e " ${Red_font_prefix}dusk_network 一Key installation script${Font_color_suffix} by \033[1;35moooooyoung\033[0m
This script is completely free and open source, created by Twitter user ${Green_font_prefix}@ouyoung11${Font_color_suffix}, 
and translated by ${Green_font_prefix}@cyb3r_nodes${Font_color_suffix}。
 ———————————————————————
 ${Green_font_prefix} 1.Install dependencies and full node ${Font_color_suffix}
 ${Green_font_prefix} 2.Create a wallet ${Font_color_suffix}
 ${Green_font_prefix} 3.Check your wallet balance ${Font_color_suffix}
 ${Green_font_prefix} 4.Start minting cat20 tokens ${Font_color_suffix}
 ${Green_font_prefix} 5.View tracker synchronization log ${Font_color_suffix}
 ${Green_font_prefix} 6.View the node synchronization log ${Font_color_suffix}
 ${Green_font_prefix} 7.Transfer cat20 tokens ${Font_color_suffix}
 ———————————————————————" && echo
read -e -p " Please refer to the above steps and enter the number:" num
case "$num" in
1)
    install_env_and_full_node
    ;;
2)
    create_wallet
    ;;
3)
    check_wallet_balance
    ;;
4)
    start_mint_cat
    ;;
5)  
    check_tracker_log
    ;;
6)
    check_node_log
    ;;
7)
    send_token
    ;;
*)
    echo
    echo -e " ${Error} Please enter a valid number"
    ;;
esac

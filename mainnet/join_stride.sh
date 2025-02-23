#!/bin/bash
set -e
clear 

SCRIPT_VERSION="v2.1.0"

# you can always install this script with
# bash -c "$(curl -sSL node.stride.zone/install)"

PURPLE='\033[0;35m'
BOLD="\033[1m"
BLUE='\033[1;34m'
ITALIC="\033[3m"
NC="\033[0m"
LOG_FILE="install.log"

STRIDE_COMMIT_HASH=v16.0.0
GENESIS_URL=https://raw.githubusercontent.com/Stride-Labs/mainnet/main/mainnet/genesis.json
CHAIN_NAME=stride-1
PERSISTENT_PEER_ID=""
SEED_ID="ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:12256"

SNAPSHOT_LANDING_PAGE=https://polkachu.com/tendermint_snapshots/stride
SNAPSHOT_DOWNLOAD_URL_PREFIX=https://snapshots.polkachu.com/snapshots/stride/stride_
SNAPSHOT_URL=$(curl -v --stderr - $SNAPSHOT_LANDING_PAGE | grep -m 1 $SNAPSHOT_DOWNLOAD_URL_PREFIX | cut -d'"' -f 2)

printf "\n\n${BOLD}Welcome to the setup script for ${PURPLE}Stride's Mainnet${NC}!\n\n"
printf "This script will guide you through setting up your very own Stride node locally.\n"
printf "You're currently running $BOLD$SCRIPT_VERSION$NC of the setup script.\n\n"

printf "Before we begin, let's make sure you have all the required dependencies installed.\n"
DEPENDENCIES=( "git" "go" "jq" "lsof" "gcc" "make" )
missing_deps=false
for dep in ${DEPENDENCIES[@]}; do
    printf "\t%-8s" "$dep..."
    if [[ $(type $dep 2> /dev/null) ]]; then
        printf "$BLUE\xE2\x9C\x94$NC\n" # checkmark
    else
        missing_deps=true
        printf "$PURPLE\xE2\x9C\x97$NC\n" # X
    fi
done
if [[ $missing_deps = true ]]; then
    printf "\nPlease install all required dependencies and rerun this script!\n"
    exit 1
fi

printf "\nAwesome, you're all set.\n"

BLINE="\n${BLUE}============================================================================================${NC}\n"
printf $BLINE

printf "\nNext, we need to give your node a nickname. "

node_name_prompt="What would you like to call it? "
while true; do
    read -p "$(printf $PURPLE"$node_name_prompt"$NC)" NODE_NAME
    if [[ ! "$NODE_NAME" =~ ^[A-Za-z0-9-]+$ ]]; then
        printf '\nNode names can only container letters, numbers, and hyphens.\n'
        node_name_prompt="Please enter a new name. "
    else
        break
    fi
done

NETWORK="mainnet"
TESTNET="main"
INSTALL_FOLDER="$HOME/.stride/$NETWORK"
STRIDE_FOLDER="$HOME/.stride"
LOG_PATH=$STRIDE_FOLDER/$LOG_FILE

BLINE="\n${BLUE}============================================================================================${NC}\n"
printf $BLINE

printf "\nGreat, now we'll download the latest version of Stride.\n"
printf "Stride will keep track of blockchain state in ${BOLD}$STRIDE_FOLDER${NC}\n\n"

if [ -d $STRIDE_FOLDER ] 
then
    printf "${BOLD}Looks like you already have Stride installed.${NC}\n"
    printf "Proceed carefully, because you won't be able to recover your data if you overwrite it.\n\n\n"
    printf "${BOLD}${BLUE}Make sure you have you've backed up your mnemonics or private keys!\nIf you lose your private key, you will not be able to claim your rewards!${NC}\n\n"
    printf "If you're a validator, please back up your priv_validator_key so you can use the same validator when you restart!"
    printf "${BOLD} Run \"strided keys export {NAME_OF_YOUR_KEY}\" to export your key, and save the info down.${NC}\n\n"
    sleep 3
    pstr="Please confirm that you have backed up your private keys. [y/n] "
    while true; do
        read -p "$(printf $PURPLE"$pstr"$NC)" yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
            * ) printf "Please answer yes or no.\n";;
        esac
    done

    pstr="Do you want to overwrite your existing $NETWORK installation and proceed? [y/n] "
    while true; do
        read -p "$(printf $PURPLE"$pstr"$NC)" yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
            * ) printf "Please answer yes or no.\n";;
        esac
    done
fi
printf $BLINE

rm -rf $STRIDE_FOLDER/config
rm -rf $STRIDE_FOLDER/data
rm -rf $STRIDE_FOLDER/cosmovisor
rm -rf $STRIDE_FOLDER/$NETWORK
rm -f $STRIDE_FOLDER/install.log

mkdir -p $INSTALL_FOLDER
cd $INSTALL_FOLDER

date > $LOG_PATH

printf "\nFetching Stride's code..."
git clone https://github.com/Stride-Labs/stride.git >> $LOG_PATH 2>&1
cd $INSTALL_FOLDER/stride 
git checkout $STRIDE_COMMIT_HASH >> $LOG_PATH 2>&1
printf " Done \n"

# pick install location
DEFAULT_BINARY="$HOME/go/bin"
rstr="\nWhere do you want to install your stride and cosmovisor binaries? [default: $DEFAULT_BINARY] "
read -p "$(printf $PURPLE"$rstr"$NC)" BINARY_LOCATION
if [ -z "$BINARY_LOCATION" ]; then
    BINARY_LOCATION=$DEFAULT_BINARY
elif [ "$BINARY_LOCATION" == "y" ]; then
    BINARY_LOCATION=$DEFAULT_BINARY
fi
mkdir -p $BINARY_LOCATION
printf "\nBuilding Stride..."
go build -mod=readonly -trimpath -o $BINARY_LOCATION ./... >> $LOG_PATH 2>&1
printf " Done \n"

printf $BLINE

install_cosmovisor() {
    suffix=$1 # optional
    printf "This one might take a few minutes...\n"

    cd $INSTALL_FOLDER
    git clone https://github.com/cosmos/cosmos-sdk >> $LOG_PATH 2>&1
    cd cosmos-sdk 
    git checkout cosmovisor/v1.1.0 >> $LOG_PATH 2>&1
    make cosmovisor >> $LOG_PATH 2>&1
    mv $STRIDE_FOLDER/cosmovisor/cosmovisor "$BINARY_LOCATION/cosmovisor${suffix}"

    cd ..
    rm -rf cosmos-sdk
}

printf "\nAlmost there! You'll also need cosmosvisor which will enable automatic upgrades.\n"
COSMOVISOR_BINARY=$BINARY_LOCATION/cosmovisor
if [[ -f $COSMOVISOR_BINARY ]]; then
    printf "\nIt looks like you already have it installed! (in $COSMOVISOR_BINARY)\n"

    cosmovisor_version=$($COSMOVISOR_BINARY version | grep Version | awk '{print $3}')
    if [[ "$cosmovisor_version" != "v1.1.0" ]]; then
        printf "\nHowever, you'll need to run version v1.1.0 for Stride.\n"
        pstr="\nDo you want to overwrite your current version? [y/n] "
        while true; do
            read -p "$(printf $PURPLE"$pstr"$NC)" yn
            case $yn in
                [Yy]* ) overwrite=true; break ;;
                [Nn]* ) overwrite=false; break ;;
                * ) printf "Please answer yes or no.\n";;
            esac
        done

        if [ $overwrite = true ]; then 
            printf "\nInstalling now!\n"
            rm $COSMOVISOR_BINARY
            install_cosmovisor 
        else 
            COSMOVISOR_BINARY="${COSMOVISOR_BINARY}-v1.1.0"
            printf "\nNo problem! We'll download to ${COSMOVISOR_BINARY} instead.\n"
            install_cosmovisor -v1.1.0
        fi
    fi
else 
    printf "\nInstalling now!\n"
    install_cosmovisor
fi

printf $BLINE

STRIDE_BINARY=$BINARY_LOCATION/strided
printf "\nLast step, we need to setup your genesis state to match $NETWORK.\n"

$STRIDE_BINARY init $NODE_NAME --home $STRIDE_FOLDER --chain-id $CHAIN_NAME --overwrite >> $LOG_PATH 2>&1

# Now pull the genesis file
curl -L $GENESIS_URL -o $STRIDE_FOLDER/config/genesis.json >> $LOG_PATH 2>&1

# Add persistent peer
config_path="$STRIDE_FOLDER/config/config.toml"
client_path="$STRIDE_FOLDER/config/client.toml"
app_path="$STRIDE_FOLDER/config/app.toml"
sed -i -E "s|persistent_peers = \".*\"|persistent_peers = \"$PERSISTENT_PEER_ID\"|g" $config_path
sed -i -E "s|seeds = \".*\"|seeds = \"$SEED_ID\"|g" $config_path

# Fetch snapshot
printf "\nTo expedite connecting, we'll fetch a recent Stride mainnet snapshot...\n"

curl -L -f $SNAPSHOT_URL -o ${STRIDE_FOLDER}/pruned_state.tar.lz4 --progress-bar
lz4 -c -d ${STRIDE_FOLDER}/pruned_state.tar.lz4 | tar -x -C $STRIDE_FOLDER
rm -f ${STRIDE_HOME}/pruned_state.tar.lz4
printf "\nDone! Now we'll setup your local config...\n" 

sed -i -E "s|snapshot-interval = .*|snapshot-interval = 200|g" $app_path
sed -i -E "s|trust_period = \"168h0m0s\"|trust_period = \"3600s\"|g" $config_path
sed -i -E "s|max_num_inbound_peers = 40|max_num_inbound_peers = 100|g" $config_path
sed -i -E "s|max_num_outbound_peers = 10|max_num_outbound_peers = 100|g" $config_path

sed -i -E "s|chain-id = \"\"|chain-id = \"$CHAIN_NAME\"|g" $client_path
sed -i -E "s|keyring-backend = \"os\"|keyring-backend = \"test\"|g" $client_path

# Setup cosmovisor
cosmovisor_home=$STRIDE_FOLDER/cosmovisor
mkdir -p $cosmovisor_home/genesis/bin
mkdir -p $cosmovisor_home/upgrades
cp $STRIDE_BINARY $cosmovisor_home/genesis/bin/

# Create launch script
launch_file=$INSTALL_FOLDER/launch_stride.sh
rm -f $launch_file
echo "export DAEMON_NAME=strided" >> $launch_file
echo "export DAEMON_HOME=$STRIDE_FOLDER" >> $launch_file
echo "export DAEMON_RESTART_AFTER_UPGRADE=true" >> $launch_file
echo "$COSMOVISOR_BINARY run start --home $STRIDE_FOLDER" >> $launch_file
printf $BLINE
printf "\n"
printf "You're all done! You can now launch your node with the following command:\n\n"
printf "     ${PURPLE}sh $launch_file${NC}\n\n"

sleep 2
printf "\nNow for the fun part.\n\n"
sleep 2

while true; do
    read -p "$(printf $PURPLE"Do you want to launch your blockchain? [y/n] "$NC)" yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) printf "Please answer yes or no.\n";;
    esac
done

# kill ports if they're already running
PORT_NUMBER=6060
lsof -i tcp:${PORT_NUMBER} | awk 'NR!=1 {print $2}' | xargs -r kill
PORT_NUMBER=26657
lsof -i tcp:${PORT_NUMBER} | awk 'NR!=1 {print $2}' | xargs -r kill 
# we likely don't need to kill this - look into why this is causing issues
PORT_NUMBER=26557
lsof -i tcp:${PORT_NUMBER} | awk 'NR!=1 {print $2}' | xargs -r kill

strided start
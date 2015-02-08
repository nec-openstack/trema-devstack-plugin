# configure_trema - Set config files, create data dirs, etc
function configure_trema {
    local _pwd=$(pwd)

    # prepare dir
    for d in $TREMA_SS_ETC_DIR $TREMA_SS_DB_DIR $TREMA_SS_SCRIPT_DIR; do
        sudo mkdir -p $d
        sudo chown -R `whoami` $d
    done
    sudo mkdir -p $TREMA_TMP_DIR

    # Initialize databases for Sliceable Switch
    cd $TREMA_SS_DIR
    rm -f filter.db slice.db
    ./create_tables.sh
    mv filter.db slice.db $TREMA_SS_DB_DIR
    sed -i -e "s|/home/sliceable_switch/db|$TREMA_SS_DB_DIR|" restapi.psgi
    cd $_pwd

    cp $TREMA_SS_DIR/sliceable_switch_null.conf $TREMA_SS_CONFIG
    sed -i -e "s|^\$apps_dir.*$|\$apps_dir = \"$TREMA_DIR/apps\"|" \
        -e "s|^\$db_dir.*$|\$db_dir = \"$TREMA_SS_DB_DIR\"|" \
        $TREMA_SS_CONFIG
}

function gem_install {
    [[ "$OFFLINE" = "True" ]] && return
    [ -n "$RUBYGEMS_CMD" ] || get_gem_command

    local pkg=$1
    $RUBYGEMS_CMD list | grep "^${pkg} " && return
    sudo $RUBYGEMS_CMD install $pkg
}

function gem_version {
    [ -n "$RUBYGEMS_CMD" ] || get_gem_command
    $RUBYGEMS_CMD --version
}

function get_gem_command {
    # Trema requires ruby 1.8 on Ubuntu 12.04.
    # Since Ubuntu 14.04, Trema works with newer versions of Ruby.
    RUBYGEMS_CMD=$(which gem1.8 || which gem)
    if [ -z "$RUBYGEMS_CMD" ]; then
        echo "Warning: ruby gems command not found."
    fi
}

function get_required_packages {
    # Trema
    cat <<EOF
make
ruby
ruby-dev
libpcap-dev
libsqlite3-dev
libglib2.0-dev
EOF
    if [[ "$os_CODENAME" == "precise" ]]; then
	echo rubygems
    else
	echo rubygems-integration
    fi

    # Sliceable Switch
    cat <<EOF
sqlite3
libdbi-perl
libdbd-sqlite3-perl
libjson-perl
libplack-perl
EOF
}

function install_trema {
    local packages=$(get_required_packages)
    install_package $packages

    # rubygems on Ubuntu 14.04 has a bug which prevents Trema installation.
    if [[ "$os_CODENAME" == "trusty" ]]; then
	local gem_ver=$(gem_version)
	if [[ "$gem_ver" == "1.8.23" ]]; then
	    gem_install rubygems-update
            sudo update_rubygems
	fi
    fi

    # Trema
    gem_install trema
    # Sliceable Switch
    git_clone $TREMA_APPS_REPO $TREMA_DIR/apps $TREMA_APPS_BRANCH
    make -C $TREMA_DIR/apps/topology
    make -C $TREMA_DIR/apps/flow_manager
    make -C $TREMA_DIR/apps/sliceable_switch
}

function start_trema {
    screen_it trema "cd $TREMA_SS_DIR && plackup -r -p $OFC_API_PORT restapi.psgi"
    if ! timeout $SERVICE_TIMEOUT sh -c "while ! wget --no-proxy -q -O- http://$OFC_API_HOST:$OFC_API_PORT/networks; do sleep 1; done"; then
        die $LINENO "Trema Sliceable Switch REST API did not start"
    fi

    sudo LOGGING_LEVEL=$TREMA_LOG_LEVEL TREMA_TMP=$TREMA_TMP_DIR \
        trema run -d -c $TREMA_SS_CONFIG
}

function stop_trema {
    sudo TREMA_TMP=$TREMA_TMP_DIR trema killall
}

function cleanup_trema {
    :
}

if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
    install_trema
elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
    configure_trema
    start_trema
fi

if [[ "$1" == "unstack" ]]; then
    cleanup_trema
    stop_trema
fi

if [[ "$1" == "clean" ]]; then
    cleanup_trema
fi

## Local variables:
## mode: shell-script
## End:

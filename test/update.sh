
DIRNAME=$(dirname -- $(readlink -f -- $0))
export XDG_DATA_HOME=$DIRNAME
update-mime-database $DIRNAME/mime

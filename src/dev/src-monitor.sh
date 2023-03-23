#!/bin/bash
## ================================================================
## Listen for changes in source files
## ================================================================

## Execute this script in a separate terminal window to start
## listening for changes in source files. Press Ctrl+C to cancel
## the process before stopping the current container.
 
## Run inotifywait to indefinitely report any of the following
## file system events in the /src/bin, /src/lib and /src/test
## directories: file created, file modified or file moved to
## the monitored dir. Notice that the output of inotifywait is
## piped through into a loop that reads each line reported.
## By default, inotifywait reports 3 terms: target dir, event
## list and name of file that the events refer to. The file in
## question will be copied to the appropriate target directory.
## Provided that the /src volume is correctly mapped, running
## this script allows testing a series of minor code changes
## inside the current container without the need for rebuilding
## the Docker image one step at a time.
inotifywait --monitor --event close_write,moved_to,create /src/bin /src/lib /src/test |
while read -r directory events filename; do
  printf '%s %s %s\n' "$directory" "$events" "$filename"
  if [ "$filename" =  coldbar-cli.sh ]; then
    dest="/usr/local/bin/coldbar-cli/${filename}"
    sudo cp "${directory}/${filename}" $dest
    printf "Updated %s\n" $dest
  fi
  if [ "$filename" = pg_coldbar.control.template ]; then
    dest="${PGEXTDIR}pg_coldbar.control.template"
    sudo cp "${directory}/${filename}" $dest
    sudo envsubst < $dest > ${dest%.*}
    printf "Updated %s\n" ${dest%.*}
  fi
  if [ "$filename" = pg_coldbar.sql ]; then
    dest="${PGEXTDIR}pg_coldbar--${PG_COLDBAR_VERSION}.sql"
    sudo cp "${directory}/${filename}" $dest
    printf "Updated %s\n" $dest
  fi 
done

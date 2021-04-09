#!/bin/bash
script_dir="$(dirname "$(readlink -f "$0")")"
source "$script_dir/gobi.sh.conf"

fetchgobi_data_dir="/opt/gobi"

fetchgobi_done_dir="$fetchgobi_data_dir/fetchgobi_done"

adjustgobi_in_dir="$fetchgobi_data_dir/adjustgobi_in"
adjustgobi_err_dir="$fetchgobi_data_dir/adjustgobi_err"

bulkmarcimport_in_dir="$fetchgobi_data_dir/bulkmarcimport_in"
bulkmarcimport_err_dir="$fetchgobi_data_dir/bulkmarcimport_err"

done_dir="$fetchgobi_data_dir/done"

# Paths to executables
fetchgobi="$script_dir/fetchgobi.pl"
adjustgobi="$script_dir/adjustgobi.pl"
bulkmarcimport="$koha_path/misc/migration_tools/bulkmarcimport.pl"
koha_shell="$script_dir/koha-shell"
logger="$script_dir/logger.pl"

function log_error {
  echo "$1" | $logger --level=error --logger=Gobi.loadgobi
}

function log_info {
  echo "$1" | $logger --level=info --logger=Gobi.loadgobi
}

# Fetch
# All errors are logged within fetchgobi.pl, so no need to capture output here
$fetchgobi \
  --local-directory="$adjustgobi_in_dir"\
  --skip-files="$(ls $fetchgobi_done_dir)"\
  --remote-directory="$ftp_remote_directory"\
  --host="$ftp_host"\
  --user="$ftp_user"\
  --password="$ftp_password"\
  --file-pattern="$ftp_marc_file_pattern"

cp "$adjustgobi_in_dir"/* "$fetchgobi_done_dir"/ 2>/dev/null

# Adjust
for filepath in $(find "$adjustgobi_in_dir" -name '*.mrc' | sort); do
  filename=$(basename "$filepath")
  errors=$($adjustgobi --input-file="$filepath" --output-file="$bulkmarcimport_in_dir/$filename" 2>&1 >/dev/null)
  if [ $? -eq 0 ]; then
    log_info "adjustgobi successfully processed \"$filename\""
    rm "$filepath"
  else
    mv "$filepath" "$adjustgobi_err_dir/"
    log_error "adjustgobi on file \"$adjusgobi_err_dir/$filename\" failed with exit status $? and errors \"$errors\""
    echo "$errors" > "$adjustgobi_err_dir/${filename}.err"
  fi
done

# Load
for filepath in $(find "$bulkmarcimport_in_dir" -name '*.mrc' | sort); do
  filename=$(basename "$filepath")
  output=$($koha_shell -c cd\ $koha_path/misc/migration_tools\ \&\&\ ./bulkmarcimport.pl\ -b\ -file\ \"$filepath\"\ -l\ \"$fetchgobi_data_dir/log/bulkmarcimport.log\"\ -append\ "$bulkmarcimport_options" $koha_instance 2>&1)
  if [ $? -eq 0 ]; then
    log_info "bulkmarcimport successfully processed \"$filename\""
    log_info "bulkmarcimport output: \"$output\""
    mv "$filepath" "$done_dir/"
  else
    log_error "bulkmarcimport on file \"$bulkmarcimport_err_dir/$filename\" failed with exit status $?"
    mv "$filepath" "$bulkmarcimport_err_dir/$filename"
    echo "$output" > "$bulkmarcimport_err_dir/${filename}.err"
  fi
done

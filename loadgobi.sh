#!/bin/bash
script_dir="$(dirname "$(readlink -f "$0")")"
source "$script_dir/gobi.sh.conf"

adjustgobi_in_dir="$script_dir/adjustgobi_in"
adjustgobi_in_archive_dir="$script_dir/adjustgobi_in_archive"
adjustgobi_err_dir="$script_dir/adjustgobi_err"

bulkmarcimport_in_dir="$script_dir/bulkmarcimport_in"
bulkmarcimport_err_dir="$script_dir/bulkmarcimport_err"

done_dir="$script_dir/done"

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

file_date_today=$(date +"%y%m%d")

# Fetch
# All errors are logged within fetchgobi.pl, so no need to capture output here
$fetchgobi --file-date="$file_date_today" --local-directory="$adjustgobi_in_dir"
# Adjust
for filepath in $(find "$adjustgobi_in_dir" -name '*.mrc' | sort); do
  filename=$(basename "$filepath")
  errors=$($adjustgobi --input-file="$filepath" --output-file="$bulkmarcimport_in_dir/$filename" 2>&1 >/dev/null)
  if [ $? -eq 0 ]; then
    log_info "ajustgobi successfully processed \"$filename\""
    mv "$filepath" "$adjustgobi_in_archive_dir/"
  else
    mv "$filepath" "$adjustgobi_err_dir/"
    log_error "adjustgobi on file \"$adjusgobi_err_dir/$filename\" failed with exit status $? and errors \"$errors\""
    echo "$errors" > "$adjustgobi_err_dir/${filename}.err"
  fi
done

# Load
for filepath in $(find "$bulkmarcimport_in_dir" -name '*.mrc' | sort); do
  filename=$(basename "$filepath")
  output=$($koha_shell -c cd\ $koha_path/misc/migration_tools\ \&\&\ ./bulkmarcimport.pl\ -b\ -file\ \"$filepath\"\ -l\ \"$script_dir/log/bulkmarcimport.log\"\ -append\ "$bulkmarcimport_options" $koha_instance 2>&1)
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

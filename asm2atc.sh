#!/bin/sh

CONFIG_FILENAME=asm2atc.cfg

config_read_file() {
    (grep -E "^${2}=" -m 1 "${1}" 2>/dev/null || echo "VAR=__UNDEFINED__") | head -n 1 | cut -d '=' -f 2-;
}

config_get() {
    val="$(config_read_file "$CONFIG_FILENAME" "${1}")";
#    if [ "${val}" = "__UNDEFINED__" ]; then
#        val="$(config_read_file config.cfg.defaults "${1}")";
#    fi
    printf -- "%s" "${val}";
}


# read parameters

APM_URL="$(config_get APM_URL)";
#printf -- "%s\n" "APM_URL: $APM_URL"; # safer way of echoing!
APM_API_TOKEN="$(config_get APM_API_TOKEN)";
#printf -- "%s\n" "APM_API_TOKEN: $APM_API_TOKEN";
APM_AGENT_NAME="$(config_get APM_AGENT_NAME)";

ASM_USER_EMAIL="$(config_get ASM_USER_EMAIL)";
#printf -- "%s\n" "ASM_USER_EMAIL: $ASM_USER_EMAIL"; # safer way of echoing!
ASM_API_PASSWORD="$(config_get ASM_API_PASSWORD)";
#printf -- "%s\n" "ASM_API_PASSWORD: $ASM_API_PASSWORD";


# configure the ASM extension in DX APM Team Center

curl -H "Authorization: Bearer $APM_API_TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" --data @configure_asm_extension.json $APM_URL/apm/appmap/ats/extension/configure


# login to ASM API

LOGIN=$(curl -s -d "user=$ASM_USER_EMAIL&password=$ASM_API_PASSWORD" -H "Content-Type: application/x-www-form-urlencoded" -X POST https://api.asm.saas.broadcom.com/1.6/acct_login)

#printf -- "%s\n" "ASM login response: $LOGIN";

if [[ $LOGIN != *"<code>0</code>"* ]]; then
  printf -- "%s\n" "error in ASM login: $LOGIN";
  exit 1;
fi

# extract token
NKEY=`echo $LOGIN | sed -E 's#.*<nkey>(.*)</nkey>.*#\1#'`
#printf -- "%s\n" "NKEY: $NKEY";


# get rules from ASM API
RULES=$(curl -s -d "nkey=$NKEY&view=json" -H "Content-Type: application/x-www-form-urlencoded" -X POST https://api.asm.saas.broadcom.com/1.6/rule_get)
printf -- "%s\n\n" "RULES: $RULES";
#RULES=`cat test.json`

# split monitors
delimiter='"name":'
s=$RULES$delimiter
array=();
while [[ $s ]]; do
    array+=( "${s%%"$delimiter"*}" );
    s=${s#*"$delimiter"};
done;

# create string send to ATC API
ATC_STRING="{\"graph\":{\"vertices\":["

count=0
for line in "${array[@]}"
do
    #printf -- "%s\n" "line: $line";

    if [[ $line != "{\"version"* ]]; then
      #printf -- "%s\n" "  not first line";

      line=${line:1} # remove '"'
      monitor=${line%%"\","*}
      line=${line#*"\","}
      #printf -- "%s\n" "  monitor:    $monitor";

      line=${line#*"\"rid\":\""}
      rid=${line%%"\","*}
      line=${line#*"\","}
      #printf -- "%s\n" "  rid:        $rid";

      line=${line#*"\"folder\":\""}
      folder=${line%%"\","*}
      line=${line#*"\","}
      #printf -- "%s\n" "  folder:     $folder";

      line=${line#*"\"active\":\""}
      active=${line%%"\","*}
      line=${line#*"\","}
      #printf -- "%s\n" "  active:     $active";

      line=${line#*"\"interval\":\""}
      interval=${line%%"\","*}
      line=${line#*"\","}
      #printf -- "%s\n" "  interval:   $interval";

      line=${line#*"\"type\":\""}
      type=${line%%"\","*}
      line=${line#*"\","}
      #printf -- "%s\n" "  type:       $type";

      line=${line#*"\"host\":\""}
      host=${line%%"\","*}
      line=${line#*"\","}
      #printf -- "%s\n" "  host:       $host";

      #printf -- "%s\n" "  line:       $line";

      # append ',' to existing string if not first monitor
      if [[ $count != 0 ]]; then
        ATC_STRING="$ATC_STRING,"
      fi
      ((count++))

      ATC_STRING="$ATC_STRING{\"id\":\"ASM:$folder:$monitor\",\"layer\":\"ATC\",\"attributes\":{"
      ATC_STRING="$ATC_STRING\"name\":\"$folder|$monitor\",\"type\":\"Synthetic Transaction\","
      ATC_STRING="$ATC_STRING\"agent\":\"$APM_AGENT_NAME\","
      ATC_STRING="$ATC_STRING\"monitor\":\"$monitor\",\"folder\":\"$folder\","
      ATC_STRING="$ATC_STRING\"active\":\"$active\",\"interval\":\"$interval\","
      ATC_STRING="$ATC_STRING\"monitor_type\":\"$type\",\"host\":\"$host\","
		  ATC_STRING="$ATC_STRING\"ASM link\":\"https://asm.saas.broadcom.com/logviewer.php?rid=$rid\","
		  ATC_STRING="$ATC_STRING\"IsExperience\":\"Yes\",\"Experience\":\"$folder|$monitor\"}}"
    fi

done

ATC_STRING=$ATC_STRING"],\"edges\":[]}}"
printf -- "%s\n\n" "creating/updating $count monitors:  $ATC_STRING";


curl -H "Authorization: Bearer $APM_API_TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" --data "$ATC_STRING" $APM_URL/apm/appmap/ats/graph/store

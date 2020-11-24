#!/bin/sh


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


# find path of script and files in that directory
#echo $0
full_path=$0
# if not on Mac
if [[ `uname -a` != *Darwin* ]]; then
  full_path=$(realpath $0)
fi
#echo $full_path

dir_path=$(dirname $full_path)
#echo $dir_path
CONFIG_FILENAME=$dir_path/asm2atc.cfg
EXTENSION_FILENAME=$dir_path/configure_asm_extension.json

[ ! -f "$CONFIG_FILENAME" ] && { echo "$0: $CONFIG_FILENAME file not found."; exit 2; }
[ ! -f "$EXTENSION_FILENAME" ] && { echo "$0: $EXTENSION_FILENAME file not found."; exit 2; }

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

curl -H "Authorization: Bearer $APM_API_TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" --data @$EXTENSION_FILENAME $APM_URL/apm/appmap/ats/extension/configure


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
#printf -- "%s\n\n" "RULES: $RULES";
#RULES=`cat test.json`

# split monitors
delimiter='"name":'
s=$RULES$delimiter
array=();
while [[ $s ]]; do
    array+=( "${s%%"$delimiter"*}" );
    s=${s#*"$delimiter"};
done;

# create string to send to ATC API to create/update vertices
ATC_STRING="{\"graph\":{\"vertices\":["
EDGE_STRING="\"edges\": ["

count=0
edgeCount=0

#iterate over all rules
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
      #printf -- "%s\n" "  line:       $line";

      if [[ $line == "\"folder\":null"* ]]; then
        folder="ROOT_FOLDER";
      else
        line=${line#*"\"folder\":\""}
        folder=${line%%"\","*}
        line=${line#*"\","}
      fi
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

      # only create vertex if active
      if [[ $active == "y" ]]; then

        # append ',' to existing string if not first monitor
        if [[ $count != 0 ]]; then
          ATC_STRING="$ATC_STRING,"
        fi
        ((count++))

        # create ATC vertex
        ATC_STRING="$ATC_STRING{\"id\":\"ASM:$folder:$monitor\", \
          \"layer\":\"ATC\",\"attributes\":{ \
          \"name\":\"$folder|$monitor\", \
          \"type\":\"Synthetic Transaction\", \
          \"agent\":\"$APM_AGENT_NAME\", \
          \"monitor\":\"$monitor\", \
          \"folder\":\"$folder\", \
          \"serviceId\":\"$folder\", \
          \"active\":\"$active\", \
          \"interval\":\"$interval\", \
          \"monitor_type\":\"$type\", \
          \"host\":\"$host\", \
  		    \"ASM link\":\"https://asm.saas.broadcom.com/logviewer.php?rid=$rid\", \
  		    \"IsExperience\":\"Yes\", \
          \"Experience\":\"$folder|$monitor\"}}"

        # create graph query for BT vertex with serviceID=$folder,
        # name=$monitor Step * via ASM*
        GRAPH_STRING="{\"includeStartPoint\":false, \
          \"outputLayer\":\"ATC\", \
          \"attributesToInclude\":[\"name\",\"type\",\"serviceId\"], \
          \"orItems\":[{\"andItems\":[{ \
            \"itemType\" : \"attributeFilter\",\
            \"attributeName\": \"type\", \
            \"attributeOperator\": \"IN\", \
            \"values\": [ \"BUSINESSTRANSACTION\" ], \
            \"layer\":\"ATC\" \
          },{ \
            \"itemType\" : \"attributeFilter\",\
            \"attributeName\": \"serviceId\", \
            \"attributeOperator\": \"IN\", \
            \"values\": [ \"$folder\" ], \
            \"layer\":\"ATC\" \
          },{ \
            \"itemType\" : \"attributeFilter\", \
            \"attributeName\": \"name\", \
            \"attributeOperator\": \"MATCHES\", \
            \"values\": [ \"$monitor* via ASM*\" ], \
            \"layer\":\"ATC\" \
          } ] } ] }"

        # run vertex query
        VERTEX=$(curl -s -H "Authorization: Bearer $APM_API_TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" --data "$GRAPH_STRING" $APM_URL/apm/appmap/graph/vertex)
        #printf -- "%s\n\n" "  VERTEX:       $VERTEX";

        # if we received an id create an edge from new synthetic to existing BT vertex
        if [[ $VERTEX == *"}},\"id\":\""* ]]; then
          VERTEX=${VERTEX#*"}},\"id\":\""}
          id=${VERTEX%%"\"}"*}
          #printf -- "%s\n\n" "  found id:       $id";

          # append ',' to existing string if not first monitor
          if [[ $edgeCount != 0 ]]; then
            EDGE_STRING="$EDGE_STRING,"
          fi
          ((edgeCount++))

          EDGE_STRING="$EDGE_STRING{ \
            \"source\": \"ASM:$folder:$monitor\", \
            \"targetId\": $id, \
            \"flowId\": $id}"
        fi
      fi
    fi
done

ATC_STRING=$ATC_STRING"],$EDGE_STRING]}}"
printf -- "%s\n%s\n\n" "creating/updating $count monitors and $edgeCount edges:" "$ATC_STRING";


curl -H "Authorization: Bearer $APM_API_TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" --data "$ATC_STRING" $APM_URL/apm/appmap/ats/graph/store

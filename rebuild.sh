#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #  script to rebuild lost docker container unraid templates after flash drive failure/corruption   # # 
# #  by - SpaceinvaderOne                                                                           # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# ------------------------
# VARIABLES USED
# ------------------------

check_orphaned="yes"  # defualt set to yes then only prcesses containers without Unraid xml moving them at end. No processes all and leaves them in working dir
xml_location="/boot/config/plugins/dockerMan/templates-user"

# working directory (in ram)
template_dir="/tmp/docker-template-restore"
mkdir -p "$template_dir"

# xmlstarlet compiled url
xmlstarlet_unraid="https://github.com/SpaceinvaderOne/rebuild-missing-Unraid-docker-templates/raw/refs/heads/main/xmlstarlet/xmlstarlet-1.6.1-x86_64-1_SBo-2.tgz"

# ca appfeed url
feed_url="https://assets.ca.unraid.net/feed/applicationFeed.json"
# downloaded appfeed
feed_file="$template_dir/applicationFeed.json"

# array of vars to excluse (as prob set in dockerfile/baseimage)
declare -a blacklistfull=(
  "AMDGPU_IDS" "APACHE_RUN_GROUP" "APACHE_RUN_USER" "CARGO_HOME" "CI"
  "CI_COMMIT_SHA" "CI_JOB_ID" "CI_PIPELINE_ID" "CI_PROJECT_DIR" "COMPOSER_HOME"
  "DEBIAN_FRONTEND" "DOCKERIZE_VERSION" "DOTNET_ROOT" "ETV_CONFIG_FOLDER" "ETV_TRANSCODE_FOLDER"
  "FLINK_HOME" "FONTCONFIG_PATH" "GEM_HOME" "GIT_COMMITTER_EMAIL" "GIT_COMMITTER_NAME"
  "GO_VERSION" "GOPATH" "GRADLE_HOME" "HADOOP_HOME" "HOME" "HOST_CONTAINERNAME"
  "HOST_HOSTNAME" "HOST_OS" "IGNORE_VAAPI_ENABLED_FLAG" "JAVA_HOME" "JDK_HOME" "JRE_HOME"
  "LANG" "LANGUAGE" "LD_LIBRARY_PATH" "LD_PRELOAD" "LIBVA_DISPLAY" "LIBVA_DRIVERS_PATH"
  "LIBVA_MESSAGING_LEVEL" "LSIO_FIRST_PARTY" "MAKEFLAGS" "MAVEN_HOME" "NGINX_VERSION"
  "NODE_ENV" "NODE_MAJOR" "OCL_ICD_VENDORS" "PATH" "PCI_IDS_PATH" "PERL5LIB"
  "PERLBREW_HOME" "PHP_INI_DIR" "PNPM_HOME" "PS1" "PYTHONPATH" "RUBY_VERSION"
  "RUSTUP_HOME" "S6_CMD_WAIT_FOR_SERVICES_MAXTIME" "S6_STAGE2_HOOK" "S6_VERBOSITY" "SHELL"
  "SPARK_HOME" "SSL_CERT_FILE" "TERM" "TUNARR_BIND_ADDR" "TZ" "USER" "VIRTUAL_ENV"
  "XDG_CACHE_HOME"
)
# ------------------------------------------
# Check for and install xmlstarlet
# ------------------------------------------
install_xmlstarlet() {
  # see if xmlstarlet is installed on the server
  if command -v xmlstarlet >/dev/null 2>&1; then
    echo "xmlstarlet is instaled...continuing"
  else
    echo "xmlstarlet not found. Installing..."

    # create the directory if not present
    mkdir -p "$template_dir"

    # download unraid compliled xmlstarlet
    echo "Downloading xmlstarlet package from $xmlstarlet_unraid..."
    curl -L "$xmlstarlet_unraid" -o "$template_dir/xmlstarlet.tgz"

    # install the package
    echo "Installing xmlstarlet using installpkg..."
    installpkg "$template_dir/xmlstarlet.tgz"

    # check it installed correctly
    if command -v xmlstarlet >/dev/null 2>&1; then
      echo "xmlstarlet successfully installed...continuing"
    else
      echo "xmlstarlet installation failed. Exiting script."
      exit 1  # exit wif installation fails
    fi
  fi
}
# ------------------------------------------
# MAIN FUNCTION CHECK ORPHANED CONTAINERS
# ------------------------------------------

# check for orphaned containers (containers without an Unraid xml in flash)
check_orphaned_containers() {
  local containers_to_process=()

  # get list of all running containers
  local containers
  containers=$(docker ps --format '{{.Names}}')

  # loop through each container & check if it has an xml template
  while IFS= read -r container_name; do
    local template_file="${xml_location}/my-${container_name}.xml"
    
    if [[ "$check_orphaned" == "yes" ]]; then
      # only add to list if container has no unraid xml in flash (if orpaned var isset)
      if [[ ! -f "$template_file" ]]; then
        containers_to_process+=("$container_name")
      fi
    else
      # add all containers (if orpaned var is no set)
      containers_to_process+=("$container_name")
    fi
  done <<< "$containers"

  # echo containers to process
  echo "${containers_to_process[@]}"
}

# ------------------------------------------
# MAIN FUNCTION: FETCH APPFEED TEMPLATES
# ------------------------------------------

# Function to download the Community Applications feed
fetch_application_feed() {
  curl -o "$feed_file" "$feed_url"
}
# match repository to template in app feed (method1)
match_template() {
  local container_repo="$1"
  jq -r --arg repo "$container_repo" '.applist[] | select(.Repository == $repo) | .TemplateURL' "$feed_file"
}

# match repository to template in app feed (method2)
match_template2() {
  local container_repo="$1"
  local repo_no_tag
  repo_no_tag=$(echo "$container_repo" | cut -d: -f1)
  echo "Searching for repository: $repo_no_tag" >&2

  local template_url
  template_url=$(jq -r --arg repo "$repo_no_tag" '.applist[] | select(.Repository | type == "string" and startswith($repo)) | .caTemplateURL | select(. != null)' "$feed_file")
  
  if [[ -z "$template_url" ]]; then
    echo "caTemplateURL not found, trying TemplateURL..." >&2
    template_url=$(jq -r --arg repo "$repo_no_tag" '.applist[] | select(.Repository | type == "string" and startswith($repo)) | .TemplateURL | select(. != null)' "$feed_file")
  fi

  echo "$template_url"
}

# fetch and download templates from app feed
fetch_appfeed_templates() {
  fetch_application_feed
  local containers_to_process=("$@")

  for container_name in "${containers_to_process[@]}"; do
    local container_image
    container_image=$(docker inspect --format '{{.Config.Image}}' "$container_name")

    echo "Searching for template for $container_image using the old-style method..."
    template_url=$(match_template "$container_image")

    if [[ -n "$template_url" && "$template_url" != "null" ]]; then
      echo "Downloading template for $container_name using the old-style method..."
      template_file="$template_dir/${container_name}_template.xml"
      curl -o "$template_file" "$template_url"
      echo "Template for $container_name saved to $template_file"
    else
      echo "No matching template found for $container_image using the old-style method. Trying new-style..."
      template_url=$(match_template2 "$container_image")

      if [[ -n "$template_url" && "$template_url" != "null" ]]; then
        echo "Downloading template for $container_name using the new-style method..."
        template_file="$template_dir/${container_name}_template.xml"
        curl -o "$template_file" "$template_url"
        echo "Template for $container_name saved to $template_file"
      else
        echo "No matching template found for $container_image using either method."
      fi
    fi
  done
}

# ------------------------
# MAIN FUNCTION GET CONFIG
# ------------------------

# get confif from the containers
get_config() {
  local containers_to_process=("$@")

  for container_name in "${containers_to_process[@]}"; do
    local container_id
    container_id=$(docker inspect --format '{{.Id}}' "$container_name")
    generate_config_json "$container_id" "$container_name"
  done
}

# make config.json file
generate_config_json() {
  local container_id="$1"
  local container_name="$2"
  local config_file="$template_dir/${container_name}_config.json"

  local container_info
  container_info=$(docker inspect "$container_id")
  echo "$container_info" > "$config_file"
  echo "Configuration file for ${container_name} saved to ${config_file}"
}

# ------------------------------------------
# MAIN FUNCTION GENERATE THE XML TEMPLATES
# ------------------------------------------

# refine the blacklist (checks if a blacklisted var is in orginal template and if so removes from list)
refine_blacklist() {
  local template_file="$1"
  if [[ -f "$template_file" ]]; then
    local template_vars
    template_vars=$(xmlstarlet sel -t -m "//Config[@Type='Variable']" -v "Target" -n "$template_file" 2>/dev/null || echo "")
    for var in $template_vars; do
      # Remove the variable from the blacklist if it is in the template
      blacklist=("${blacklist[@]/$var}")
    done
  fi
}

# generate xml
generate_xml_template() {
  local config_file="$1"
  local container_name="$2"
  
  local blacklist=("${blacklistfull[@]}")
  local repository registry support project overview webui template_url icon shell privileged donate_text donate_link
  repository=$(jq -r '.[0].Config.Image' "$config_file" || echo "")

  local template_file="$template_dir/${container_name}_template.xml"
  if [[ -f "$template_file" ]]; then
    registry=$(xmlstarlet sel -t -v "//Registry" "$template_file" 2>/dev/null || echo "")
    support=$(xmlstarlet sel -t -v "//Support" "$template_file" 2>/dev/null || echo "")
    project=$(xmlstarlet sel -t -v "//Project" "$template_file" 2>/dev/null || echo "")
    overview=$(xmlstarlet sel -t -v "//Overview" "$template_file" 2>/dev/null || echo "")
    webui=$(xmlstarlet sel -t -v "//WebUI" "$template_file" 2>/dev/null || echo "")
    template_url=$(xmlstarlet sel -t -v "//TemplateURL" "$template_file" 2>/dev/null || echo "")
    icon=$(xmlstarlet sel -t -v "//Icon" "$template_file" 2>/dev/null || echo "")
    shell=$(xmlstarlet sel -t -v "//Shell" "$template_file" 2>/dev/null || echo "sh")
    privileged=$(xmlstarlet sel -t -v "//Privileged" "$template_file" 2>/dev/null || echo "false")
    donate_text=$(xmlstarlet sel -t -v "//DonateText" "$template_file" 2>/dev/null || echo "")
    donate_link=$(xmlstarlet sel -t -v "//DonateLink" "$template_file" 2>/dev/null || echo "")
    refine_blacklist "$template_file"
  fi

  local xml_content
  xml_content="<?xml version=\"1.0\"?>\n<Container version=\"2\">\n"
  xml_content+="  <Name>${container_name}</Name>\n"
  xml_content+="  <Repository>${repository}</Repository>\n"
  xml_content+="  <Registry>${registry}</Registry>\n"
  xml_content+="  <Network>$(jq -r '.[0].HostConfig.NetworkMode' "$config_file" || echo "bridge")</Network>\n"
  xml_content+="  <MyIP/>\n"
  xml_content+="  <Shell>${shell}</Shell>\n"
  xml_content+="  <Privileged>${privileged}</Privileged>\n"
  xml_content+="  <Support>${support}</Support>\n"
  xml_content+="  <Project>${project}</Project>\n"
  xml_content+="  <Overview>${overview}</Overview>\n"
  xml_content+="  <Category/>\n"
  xml_content+="  <WebUI>${webui}</WebUI>\n"
  xml_content+="  <TemplateURL>${template_url}</TemplateURL>\n"
  xml_content+="  <Icon>${icon}</Icon>\n"
  xml_content+="  <ExtraParams/>\n"
  xml_content+="  <PostArgs/>\n"
  xml_content+="  <CPUset/>\n"
  xml_content+="  <DateInstalled>$(date +%s)</DateInstalled>\n"
  xml_content+="  <DonateText>${donate_text}</DonateText>\n"
  xml_content+="  <DonateLink>${donate_link}</DonateLink>\n"
  xml_content+="  <Requires/>\n"

  # read the json config for paths ports vars and devices
  local paths ports env_vars devices

  # host port mode
  ports=$(jq -r '
    .[0].HostConfig.PortBindings // {} 
    | to_entries[] 
    | "<Config Name=\"Port: " + (.key | split("/")[0]) + "\" Target=\"" + (.key | split("/")[0]) + "\" Default=\"" + (.value[0].HostPort) + "\" Mode=\"" + (.key | split("/")[1]) + "\" Description=\"\" Type=\"Port\" Display=\"always\" Required=\"false\" Mask=\"false\">" + (.value[0].HostPort) + "</Config>"' "$config_file")

  # apped path (bind mounts)
  paths=$(jq -r '.[] | .Mounts?[]? | select(.Type == "bind") | "<Config Name=\"" + (.Source | split("/")[-1]) + " path\" Target=\"" + .Destination + "\" Default=\"" + .Destination + "\" Mode=\"" + .Mode + "\" Description=\"\" Type=\"Path\" Display=\"always\" Required=\"false\" Mask=\"false\"/>"' "$config_file")

  # variables code (but excluding blacklisted vars)
  env_vars=$(jq -r '.[] | .Config?.Env[]? | select(test("=")) | split("=") | if .[0] | IN($blacklist[]) | not then "<Config Name=\"" + .[0] + "\" Target=\"" + .[0] + "\" Default=\"" + .[1] + "\" Mode=\"\" Description=\"\" Type=\"Variable\" Display=\"always\" Required=\"false\" Mask=\"false\"/>" else empty end' --argjson blacklist "$(printf '%s\n' "${blacklist[@]}" | jq -R . | jq -s .)" "$config_file")

  # devices code
  devices=$(jq -r '.[] | .HostConfig?.Devices[]? | "<Config Name=\"" + (.PathOnHost | split("/")[-1]) + "\" Target=\"" + .PathInContainer + "\" Default=\"" + .PathOnHost + "\" Mode=\"\" Description=\"\" Type=\"Device\" Display=\"always\" Required=\"false\" Mask=\"false\"/>"' "$config_file")

  # add the config to the xml (paths ports vars and devices)
  xml_content+="${paths}\n"
  xml_content+="${ports}\n"
  xml_content+="${env_vars}\n"
  xml_content+="${devices}\n"

  # close xml structure
  xml_content+="</Container>\n"

  # save the xml
  local output_file="${template_dir}/my-${container_name}.xml"
  echo -e "$xml_content" > "$output_file"

  # move the new xml to flash if set to (in orpaned variable)
  if [[ "$check_orphaned" == "yes" ]]; then
    local target_file="$xml_location/my-${container_name}.xml"
    mv "$output_file" "$target_file"
    echo "Moved generated XML for ${container_name} to ${target_file}"
  else
    echo "Generated Unraid XML template for ${container_name} saved to ${output_file}"
  fi
}

# make the xml for all containers
generate_templates_for_all_containers() {
  local containers_to_process=("$@")

  # loop through each container that needs it
  for container_name in "${containers_to_process[@]}"; do
    generate_xml_template "$template_dir/${container_name}_config.json" "$container_name"
  done
}

# clean up old files
cleanup_template_dir() {
  if [[ "$check_orphaned" == "yes" ]]; then
    rm -r "$template_dir"
    echo "Cleaned up $template_dir after moving XML files"
  fi
}

# ------------------------
# Run the main functions
# ------------------------

# install xmlstarlet if not already present
install_xmlstarlet

# check if the containers have an unraid xml if orpaned is set
containers_to_process=($(check_orphaned_containers))

# get the templates from the ca application feed
fetch_appfeed_templates "${containers_to_process[@]}"

# get the config from the current running containers
get_config "${containers_to_process[@]}"

# make the xml for all relivant containers
generate_templates_for_all_containers "${containers_to_process[@]}"

# cleanup
cleanup_template_dir
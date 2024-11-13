#!/bin/bash

# html style variables for bold and underline
bold="<b>"
underline="<u>"
reset="</b></u>"

#  check if any containers are running
check_running_containers() {
  local containers=$(docker ps --format '{{.ID}} {{.Names}} {{.Image}}')
  if [[ -z "$containers" ]]; then
    echo "<p>No containers are currently running. Please start any containers you wish to monitor for output.</p>"
    exit 0
  fi
  echo "$containers"
}

# get the list of running containers
containers=$(check_running_containers)

# go through each container
container_index=1
while IFS= read -r container; do
  # Extract container ID, name, and image
  container_id=$(echo "$container" | awk '{print $1}')
  container_name=$(echo "$container" | awk '{print $2}')
  container_image=$(echo "$container" | awk '{print $3}')

  # divider line before each container
  echo -e "<p style='font-weight:bold; text-align:center;'>**************************<br>Container $container_index<br>**************************</p>"

  # get the container name and image 
  echo -e "<p>${bold}${underline}Name:${reset} $container_name</p>"
  echo -e "<p>${bold}${underline}Repository:${reset} $container_image</p>"

  # get the bind mounts for the current container 
  echo -e "<p>${bold}${underline}Bind Mounts - Host -> Container:${reset}</p>"
  echo -e "<pre>$(docker inspect --format='{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}{{end}}' "$container_id")</pre>"

  # get network information
  echo -e "<p>${bold}${underline}Network Type:${reset}</p>"
  echo -e "<pre>$(docker inspect --format='{{.HostConfig.NetworkMode}}' "$container_id")</pre>"

  # get port mappings
  echo -e "<p>${bold}${underline}Port Mappings:${reset}</p>"

  network_mode=$(docker inspect --format='{{.HostConfig.NetworkMode}}' "$container_id")

  if [[ "$network_mode" == "bridge" ]]; then
    # bridge mode, ensure consistent port format
    echo -e "<p>${bold}${underline}Exposed Ports (container):${reset}</p>"
    echo -e "<pre>$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}}{{"\n"}}{{end}}' "$container_id" 2>/dev/null || echo "No exposed ports")</pre>"

    echo -e "<p>${bold}${underline}Port Bindings (host-to-container):${reset}</p>"
    echo -e "<pre>$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}}{{"\n"}}{{end}}' "$container_id" 2>/dev/null || echo "No port bindings")</pre>"
  else
    # custom networks, show consistent formatting
    echo -e "<p>${bold}${underline}Exposed Ports (container):${reset}</p>"
    echo -e "<pre>$(docker inspect --format='{{range $port, $conf := .Config.ExposedPorts}}{{$port}}{{"\n"}}{{end}}' "$container_id" 2>/dev/null || echo "No exposed ports")</pre>"

    echo -e "<p>${bold}${underline}Port Bindings (host-to-container):${reset}</p>"
    echo -e "<pre>$(docker inspect --format='{{range $port, $conf := .HostConfig.PortBindings}}{{$port}} -> {{(index $conf 0).HostPort}}{{"\n"}}{{end}}' "$container_id" 2>/dev/null || echo "No port bindings")</pre>"
  fi

  # get environment variables
  echo -e "<p>${bold}${underline}Environment Variables:${reset}</p>"
  echo -e "<pre>$(docker inspect --format='{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' "$container_id")</pre>"

  # get container labels
  echo -e "<p>${bold}${underline}Labels:${reset}</p>"
  echo -e "<pre>$(docker inspect --format='{{range $key, $value := .Config.Labels}}{{$key}}: {{$value}}{{"\n"}}{{end}}' "$container_id" || echo "No labels")</pre>"

  # get devices mapped to the container like igpu ect
  echo -e "<p>${bold}${underline}Devices - Host -> Container:${reset}</p>"
  echo -e "<pre>$(docker inspect --format='{{range .HostConfig.Devices}}{{.PathOnHost}} -> {{.PathInContainer}}{{"\n"}}{{end}}' "$container_id" || echo "No devices mapped")</pre>"

  # separator
  echo -e "<hr>"

  container_index=$((container_index + 1))

done <<< "$containers"
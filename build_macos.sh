#!/bin/bash

# Read the plugin name from name.conf
config_file="./name.conf"

if [ -f "$config_file" ]; then
    plugin_name=$(<"$config_file")
    echo "Using plugin name from name.conf: $plugin_name"
else
    echo "Error: Configuration file name.conf not found."
    exit 1
fi

# Set the date in YYYY.MM.DD format
current_date=$(date +%Y.%m.%d)

# Define the main output filename
output_filename="${plugin_name}-${current_date}-x86_64.txz"

# Define directories
source_dir="./source/usr"
output_dir="./packages/pluginmain"
archive_dir="./packages/archive"
dependencies_dir="./packages/dependencies"

# Ensure the necessary directories exist
mkdir -p "$output_dir" "$archive_dir" "$dependencies_dir"

# Move existing files in ./packages/pluginmain to ./packages/archive if any exist
if compgen -G "$output_dir/*" > /dev/null; then
    echo "Moving existing files in ${output_dir} to ${archive_dir}."
    mv "$output_dir"/* "$archive_dir"/
else
    echo "No files to move from ${output_dir} to ${archive_dir}."
fi

# Create the main .txz archive
if [ -d "$source_dir" ]; then
    tar -cJf "${output_dir}/${output_filename}" -C ./source usr
    echo "Created ${output_filename} in ${output_dir}"
else
    echo "Error: Source directory ${source_dir} does not exist."
    exit 1
fi

# Create the MD5 checksum file for the main .txz, with .txt extension
md5 "${output_dir}/${output_filename}" | awk '{print $4}' > "${output_dir}/${plugin_name}_md5.txt"
echo "Created MD5 checksum file: ${plugin_name}_md5.txt in ${output_dir}"

# Generate MD5 files for dependencies in ./packages/dependencies, with .txt extension
for file in "$dependencies_dir"/*.txz "$dependencies_dir"/*.tgz; do
    if [ -f "$file" ]; then
        # Extract filename without extension
        base_name=$(basename "$file" | sed 's/\.[^.]*$//')
        md5 "$file" | awk '{print $4}' > "${dependencies_dir}/${base_name}_md5.txt"
        echo "Created MD5 checksum file: ${base_name}_md5.txt in ${dependencies_dir}"
    fi
done

echo "Packaging and checksum generation complete."
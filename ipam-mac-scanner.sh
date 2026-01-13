#!/bin/bash

echo "[INFO] Fetching token ..."
if ! token=$(curl -X POST --user "${USERNAME}":"${PASSWORD}" "${API_URL}/${API_APP_NAME}/user/" -s | jq --raw-output .data.token); then
    echo "[FAIL] Error while fetching token from phpIPAM" 1>&2
    exit 1
fi
if [ -z "${token}" ]; then
    echo "[FAIL] No valid token response from phpIPAM" 1>&2
    exit 1
fi

echo "[INFO] Getting token expiry ..."
if ! expire_time=$(curl -X GET --header "token: ${token}" "${API_URL}/${API_APP_NAME}/user/" -s | jq --raw-output .data.expires); then
    echo "[FAIL] Error while fetching token expiry from phpIPAM" 1>&2
    exit 1
fi
if [ -z "${expire_time}" ]; then
    echo "[FAIL] No valid token expiry response from phpIPAM" 1>&2
    exit 1
fi

echo "[INFO] Requesting subnet details ..."
if ! subnet_id=$(curl -X GET --header "token: ${token}" "${API_URL}/${API_APP_NAME}/subnets/search/${SUBNET}" -s | jq --raw-output .data[0].id); then
    echo "[FAIL] Error while fetching subnet details from phpIPAM" 1>&2
    exit 1
fi
if [ -z "${subnet_id}" ]; then
    echo "[FAIL] No valid subnet details response from phpIPAM" 1>&2
    exit 1
fi

update_address() {
    local ip=${1}
    local mac=${2}

    local ip_id
    if ! ip_id=$(curl -X GET --header "token: ${token}" "${API_URL}/${API_APP_NAME}/addresses/${ip}/${subnet_id}" -s | jq --raw-output .data.id); then
        echo "[FAIL] Error while fetching IP-ID from phpIPAM for IP ${ip}" 1>&2
        exit 1
    fi
    if [ -z "${ip_id}" ] || [ "${ip_id}" = "null" ]; then
        echo "[WARN] IP ${ip} not found in phpIPAM: ${ip}"
        return
    fi

    local no_update=0
    local json_data
    if ! json_data=$(curl -X GET --header "token: ${token}" "${API_URL}/${API_APP_NAME}/addresses/${ip_id}/" -s); then
        echo "[FAIL] Error while fetching IP data for ${ip} from phpIPAM" 1>&2
        exit 1
    fi
    local ip_tag
    ip_tag=$(echo "${json_data}" | jq --raw-output .data.tag)
    IFS=',' read -r -a ignored_tags_array <<< "$IGNORED_TAGS"
    for tag in "${ignored_tags_array[@]}"; do
        if [ "${ip_tag}" = "${tag}" ]; then
            echo "[INFO] IP ${ip} has IP-Tag: ${IPTAG} - skipping update"
            no_update=1
        fi
    done
    if [ ${no_update} -eq 1 ]; then return; fi

    local ip_mac
    ip_mac=$(echo ${json_data} | jq --raw-output .data.mac)
    if [ -z "${ip_mac}" ]; then
        echo "[INFO] First MAC-Address for ${ip} found: ${mac}"
    fi
    if [ "${ip_mac}" = "${mac}" ]; then
        echo "[INFO] MAC-Address for ${ip} already up-to-date: ${mac}"
        return
    fi

    local json_data
    if ! json_data=$(curl -X PATCH --header "token: ${token}" "${API_URL}/${API_APP_NAME}/addresses/${ip_id}/" -s --data "mac=${mac}"); then
        echo "[FAIL] Error while updating MAC-Address for IP ${ip}" 1>&2
        exit 1
    fi
    local result_response
    result_response=$(echo "${json_data}" | jq --raw-output .success)
    if [ "${result_response}" != "true" ]; then
        echo "[FAIL] phpIPAM returned an unsuccessful response for IP ${ip}: ${json_data}"
        exit 1
    fi

    echo "[INFO] MAC-Address updated for IP ${ip} - MAC-Address: ${mac}"
}

echo "[INFO] Updating subnet ${SUBNET} ... (this may take a while)"
network=$(echo ${SUBNET} | cut -d/ -f1 | sed 's/\.[0-9]*$//')
for subnet_ip in $(seq 1 254); do
    ip="${network}.${subnet_ip}"
    # Running arping with 1s timeout
    mac=$(arping -c 1 -w 1 -I "${INTERFACE}" "${ip}" 2>/dev/null | grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -n1)
    if [[ -n "${mac}" && "${mac}" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        update_address "${ip}" "${mac}"
    fi
done

# Update local interface IPs
echo "[INFO] Starting update for local interface ${INTERFACE} ..."
if ! json_data=$(ip -j a show "${INTERFACE}"); then
    echo "[FAIL] Error while reading local interface details" 1>&2
    exit 1
fi

local_mac=$(echo "${json_data}" | jq --raw-output '.[0].address')
if [[ ${local_mac} =~ ^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$ ]]; then
    length=$(echo "${json_data}" | jq --raw-output '.[0].addr_info | length')
    for ((i=0; i<length; i++)); do
        local_ip=$(echo "${json_data}" | jq --raw-output .[0].addr_info[${i}].local)
        if [ -z "${local_ip}" ]; then
            echo "[WARN] Error while parsing local IP ${i}: ${json_data}" 1>&2
            continue
        fi
        echo "[INFO] Found local IP ${local_ip} on interface ${INTERFACE}: MAC-Address: ${local_mac} ($((i +1))/${length})"
        update_address "${local_ip}" "${local_mac}"
    done
else
    echo "[INFO] Invalid MAC-Address found: ${local_mac}"
fi

echo "[INFO] Update done"

echo "[INFO] Removing token ..."
if ! json_data=$(curl -X DELETE --header "token: ${token}" "${API_URL}/${API_APP_NAME}/user/" -s); then
    echo "[FAIL] Error while trying to remove token" 1>&2
    exit 1
fi
result_response=$(echo ${json_data} | jq --raw-output .success)
if [ "${RESULT}" != "true" ]; then
    echo "[FAIL] Error while trying to remove token: ${json_data}"
    exit 1
fi
echo "[INFO] Removed token"
#!/bin/bash

# https://www.espboards.dev/blog/secure-mqtt-broker-docker-hass/

IP_ADDR="localhost"
INFO_CA="/C=BE/ST=Brussels/L=Brussels/O=espboards/OU=CA/CN=$IP_ADDR"
INFO_SERVER="/C=BE/ST=Brussels/L=Brussels/O=espboards/OU=Server/CN=$IP_ADDR"
INFO_CLIENT="/C=BE/ST=Brussels/L=Brussels/O=espboards/OU=Client/CN=$IP_ADDR"

function gen_CA () {
   openssl req -x509 -nodes -sha256 -newkey rsa:2048 -subj "$INFO_CA"  -days 365 -keyout ca.key -out ca.crt
}

function gen_server () {
   openssl req -nodes -sha256 -new -subj "$INFO_SERVER" -keyout server.key -out server.csr
   openssl x509 -req -sha256 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365
}

function gen_client () {
   openssl req -new -nodes -sha256 -subj "$INFO_CLIENT" -out client.csr -keyout client.key 
   openssl x509 -req -sha256 -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt -days 365
}

gen_CA
gen_server
gen_client
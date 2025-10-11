### Setup
Export env variables:
```
source .env
```

Run the following command:
```
docker run --rm -it \
-v ${PROJECT_PATH}/${CONFIG}/isponsorblocktv:/app/data \
--net=host \
-e TERM=$TERM -e COLORTERM=$COLORTERM \
ghcr.io/dmunozv04/isponsorblocktv \
--setup
```
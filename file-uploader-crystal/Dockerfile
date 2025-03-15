# Based on https://github.com/iv-org/invidious/blob/master/docker/Dockerfile
FROM crystallang/crystal:1.14.0-alpine AS builder

RUN apk add --no-cache sqlite-static yaml-static

ARG release

WORKDIR /file-uploader-crystal 
COPY ./shard.yml ./shard.yml
COPY ./shard.lock ./shard.lock
RUN shards install --production

COPY ./src/ ./src/
# TODO: .git folder is required for building – this is destructive.
# See definition of CURRENT_BRANCH, CURRENT_COMMIT and CURRENT_VERSION.
COPY ./.git/ ./.git/

RUN crystal build ./src/file-uploader-crystal.cr \
	--release \
	--static --warnings all

FROM alpine:3.20
RUN apk add --no-cache tini ffmpeg
WORKDIR /file-uploader-crystal
RUN addgroup -g 1000 -S file-uploader-crystal && \
	adduser -u 1000 -S file-uploader-crystal -G file-uploader-crystal
COPY --chown=file-uploader-crystal ./config/config.* ./config/
RUN mv -n config/config.example.yml config/config.yml
COPY --from=builder /file-uploader-crystal/file-uploader-crystal .
RUN chmod o+rX -R ./config 

EXPOSE 8080
USER file-uploader-crystal
ENTRYPOINT ["/sbin/tini", "--"]
CMD [ "/file-uploader-crystal/file-uploader-crystal" ]

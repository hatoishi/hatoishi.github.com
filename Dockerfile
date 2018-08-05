FROM ruby:2.5-stretch
MAINTAINER Jon Doveston <jon@doveston.me.uk>

# https://github.com/docker-library/docs/tree/master/ruby#encoding
ENV LANG C.UTF-8

RUN apt-get update -qq
RUN apt-get install -y build-essential

ENV SRC /src
RUN mkdir $SRC
WORKDIR $SRC

RUN gem install bundler
ENV BUNDLE_PATH $SRC/vendor/bundle

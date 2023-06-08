# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.2.2
ARG BUNDLE_VERSION=2.4.12

FROM ruby:${RUBY_VERSION}-slim as base

ENV BUNDLE_PATH vendor/bundle

RUN apt-get update -qq
RUN apt-get install -y build-essential zlib1g-dev

ENV SRC /src
RUN mkdir $SRC
WORKDIR $SRC

RUN gem install bundler
ENV BUNDLE_PATH $SRC/vendor/bundle

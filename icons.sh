#!/bin/bash

convert images/mon500.png -resize 320x460 images/startup.png
convert images/mon500.png -resize 144x144 images/apple-touch-icon-144x144-precomposed.png
convert images/mon500.png -resize 114x114 images/apple-touch-icon-114x114-precomposed.png
convert images/mon500.png -resize 72x72   images/apple-touch-icon-72x72-precomposed.png
convert images/mon500.png -resize 57x57   images/apple-touch-icon-57x57-precomposed.png
convert images/mon500.png -resize 57x57   images/apple-touch-icon-precomposed.png
convert images/mon500.png -resize 57x57   images/apple-touch-icon.png
convert images/mon500.png -resize 32x32   images/favicon.png

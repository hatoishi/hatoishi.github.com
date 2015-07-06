#!/usr/bin/env bash

######################################
# INITIALIZE VARS

CONVERT_CMD=`which convert`
SRC_IMAGE="mon500.png"
PWD=`pwd`
TRANSPARENT_COLOUR="#FFFFFF"
IMAGE_NAME="favicon"
WEBSITE_DOMAIN="{{ site.url }}/images"

######################################
# REQUIREMENTS

if [ -z $CONVERT_CMD ] || [ ! -f $CONVERT_CMD ] || [ ! -x $CONVERT_CMD ];
then
  echo "ImageMagick needs to be installed to run this script" 1>&2
  exit;
fi

if [ -z $SRC_IMAGE ];
then
  echo "You must supply a source image as the argument to this command." 1>&2
  exit;
fi

if [ ! -f $SRC_IMAGE ];
then
  echo "Source image \"$SRC_IMAGE\" does not exist." 1>&2
  exit;
fi

function generate_png {
  local SIZE=$1
  local SOURCE=$2

  if [ -z "$SOURCE" ];
  then
    SOURCE="$PWD/$IMAGE_NAME-256.png"
  fi

  if [ ! -f $SOURCE ];
  then
    echo "Could not find the source image $SOURCE" 1>&2
    exit 1;
  fi

  if [[ $SIZE =~ ^([0-9]+)x([0-9]+)$ ]];
  then
    WIDTH=${BASH_REMATCH[1]}
    HEIGHT=${BASH_REMATCH[2]}
  else
    WIDTH=$SIZE
    HEIGHT=$SIZE
  fi

  echo "$IMAGE_NAME-${SIZE}.png" 1>&2
  $CONVERT_CMD $SOURCE -resize ${WIDTH}x${HEIGHT}! -crop ${WIDTH}x${HEIGHT}+0+0 -alpha On $PWD/$IMAGE_NAME-${SIZE}.png
}

echo "Generating square base image" 1>&2
# Converts the source image to 256 square, ignoring aspect ratio
generate_png 256 $SRC_IMAGE

######################################
# GENERATE THE VARIOUS SIZE VERSIONS

echo "Generating required versions at different sizes" 1>&2
generate_png 16
generate_png 32
generate_png 48
generate_png 57
generate_png 60
generate_png 64
generate_png 70
generate_png 72
generate_png 76
generate_png 114
generate_png 120
generate_png 144
generate_png 150
generate_png 152
generate_png 180
generate_png 192
generate_png 196
# TODO Figure out crop/resize priority etc.
# generate_png 310x150
generate_png 310

######################################
# GENERATE THE FAVICON.ICO FILE

echo "Generating ico" 1>&2
$CONVERT_CMD \
$PWD/$IMAGE_NAME-16.png \
$PWD/$IMAGE_NAME-32.png \
$PWD/$IMAGE_NAME-48.png \
$PWD/$IMAGE_NAME-64.png \
-background $TRANSPARENT_COLOUR $PWD/$IMAGE_NAME.ico

######################################
# OUTPUT USEFUL MARKUP

echo "<link rel=\"icon\" sizes=\"16x16 32x32 48x48 64x64\" href=\"${WEBSITE_DOMAIN}/favicon.ico\">"
echo "<!--[if IE]><link rel=\"shortcut icon\" href=\"${WEBSITE_DOMAIN}/favicon.ico\"><![endif]-->"

echo "<meta name=\"msapplication-TileColor\" content=\"${TRANSPARENT_COLOUR}\">"
echo "<meta name=\"msapplication-TileImage\" content=\"${WEBSITE_DOMAIN}/favicon-144.png\">"

echo "<meta name=\"msapplication-square70x70logo\" content=\"${WEBSITE_DOMAIN}/favicon-70.png\">"
echo "<meta name=\"msapplication-square150x150logo\" content=\"${WEBSITE_DOMAIN}/favicon-150.png\">"
# echo "<meta name=\"msapplication-wide310x150logo\" content=\"${WEBSITE_DOMAIN}/favicon-310x150.png\">"
echo "<meta name=\"msapplication-square310x310logo\" content=\"${WEBSITE_DOMAIN}/favicon-310.png\">"

echo "<link rel=\"icon\" sizes=\"192x192\" href=\"${WEBSITE_DOMAIN}/favicon-192.png\">"

echo "<link rel=\"apple-touch-icon-precomposed\" sizes=\"180x180\" href=\"${WEBSITE_DOMAIN}/favicon-180.png\">"
echo "<link rel=\"apple-touch-icon-precomposed\" sizes=\"152x152\" href=\"${WEBSITE_DOMAIN}/favicon-152.png\">"
echo "<link rel=\"apple-touch-icon-precomposed\" sizes=\"144x144\" href=\"${WEBSITE_DOMAIN}/favicon-144.png\">"
echo "<link rel=\"apple-touch-icon-precomposed\" sizes=\"120x120\" href=\"${WEBSITE_DOMAIN}/favicon-120.png\">"
echo "<link rel=\"apple-touch-icon-precomposed\" sizes=\"114x114\" href=\"${WEBSITE_DOMAIN}/favicon-114.png\">"
echo "<link rel=\"apple-touch-icon-precomposed\" sizes=\"76x76\" href=\"${WEBSITE_DOMAIN}/favicon-76.png\">"
echo "<link rel=\"apple-touch-icon-precomposed\" sizes=\"72x72\" href=\"${WEBSITE_DOMAIN}/favicon-72.png\">"
echo "<link rel=\"apple-touch-icon-precomposed\" href=\"${WEBSITE_DOMAIN}/favicon-57.png\">"

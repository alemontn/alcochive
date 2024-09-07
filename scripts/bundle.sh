#!/usr/bin/env bash
shLength=149

# this file is meant to be used when creating
# the bundle for alcochive.
# do not use it in its standalone form, it
# won't work.

set -o "errexit"

function fatal()
{
  local red=$(echo -ne '\e[1;31m') \
        none=$(echo -ne '\e[0m')

  echo $red"error (fatal):"$none "$@"
  exit 1
}

function extract()
{
  function _removeLine()
  {
    rmLength=$1
    cat "$tmpAr" | tail -n+$((rmLength+1)) >"$tmpAr".tmp && mv "$tmpAr".tmp "$tmpAr"
  }

  function _removeChar()
  {
    rmLength=$1
    cat "$tmpAr" | tail -c+$((rmLength+1)) >"$tmpAr".tmp && mv "$tmpAr".tmp "$tmpAr"
  }

  function _headerDigest()
  {
    header="$(cat "$tmpAr" | head -n1)"
  
    if [ ! "${header::4}" == "alzr" ]
    then
      fatal "corrupted archive": "header is invalid"
    fi
    # remove starting indentifier
    header="${header#alzr}"

    if [ ! "${header::2}" == "zs" ]
    then
      fatal "unknown compressor" "only 'zs' (zstd) is supported"
    fi
    header="${header#zs}"

    # last 64 chars (sha256sum)
    catSum="${header: -64}"
    # remove checksum
    header="${header::-64}"
  
    fileLengths=(${header//,/ })
  }

  function _fileDigest()
  {
    fileInfo="$1"
  
    filePerms="${fileInfo::4}"
    fileOwner="${fileInfo:4}"
      fileOwner="${fileOwner%)*}"
      fileOwner="${fileOwner#(}"
    fileName="${fileInfo#$filePerms($fileOwner)}"
  
    if [[ "$fileName" == */* ]]
    then
      dirName="${fileName%/*}"
    else
      unset dirName
    fi
  }

  function _fileSort()
  {
    for length in ${fileLengths[@]}
    do
      _fileDigest "$(cat "$tmpAr" | head -n1)"
      _removeLine 1

      fileName=/"$fileName"
      dirName=/"$dirName"

      if [ -n "$dirName" ]
      then
        mkdir -p "$dirName"
      fi

      if [ "${fileName: -1}" == / ]
      then
        mkdir -p "$fileName"
      else
        cat "$tmpAr" | head -c$length >"$fileName"
      fi

      if [ ! "$filePerms" == 0000 ]
      then
        chmod -R "$filePerms" "$fileName"
      fi

      if [ -n "$fileOwner" ]
      then
        chown -R "$fileOwner" "$fileName"
      fi

      _removeChar $length
    done
  }

  tmpAr="$(mktemp /tmp/alcochive-extract-XXXXXXX)"

  tail -n+$shLength "$0" >"$tmpAr"

  _headerDigest
  # remove header
  _removeLine 1

  arSum="$(cat "$tmpAr" | sha256sum)"
  arSum="${arSum::64}"

  if [ ! "$arSum" == "$catSum" ]
  then
    fatal "corrupted archive" "checksum (sha256) mismatch"
  fi

  unzstd <"$tmpAr" >"$tmpAr".new && mv "$tmpAr".new "$tmpAr"

  # extract files
  _fileSort

  rm -f "$tmpAr"
}

if [ ! -w / ]
then
  fatal "write permission to root denied"
fi

if ! command -v zstd > /dev/null
then
  fatal "zstd must be installed for decompression"
fi

extract
exit

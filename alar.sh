#!/usr/bin/env bash

# exit on errors
set -o "errexit"

# colours & formatting :o
red=$(echo -ne '\e[1;31m')
none=$(echo -ne '\e[0m')
bold=$(echo -ne '\e[1m')

function errorContent()
{
  for s in "$@"
  do
    content+="$s: "
  done
  content="${content%: }"
  echo -n "$content"
}

function fatal()
{
  errorContent="$(
    for s in "$@"
    do
      echo -n "$s: "
    done
  )"
    errorContent="${errorContent%: }"

  rm -f "$tmpAr"

  echo $red"error (fatal):"$none "$(errorContent "$@")" >&2
  exit 1
}

function usage()
{
  echo "\
Usage: ${0##*/} <OPERATION> [ARGUMENTs] [TARGETs]

${bold}Operations:${none}
 -h, --help       show this help prompt
 -V, --version    show alcochive version
 -x, --extract    extract file/s from archive
 -c, --create     create an archive from file/s
 -t, --list       list contents of archive

${bold}Arguments:${none}
 -C, --dir        specify directory to extract to
     --overwrite  let existing files be overwritten
     --no-owner   don't change owner when extracting
     --no-perms   don't change permissions when extracting
"
  exit 0
}

function version()
{
  echo $bold"alcochive"$none "version" 0.0.1 >&2
  exit 0
}

function headerDigest()
{
  header="$(head -n1 "$tmpAr")"

  if [ ! "${header::4}" == "alar" ]
  then
    fatal "corrupted archive" "header is invalid"
  fi
  # remove starting indentifier
  header="${header#alar}"

  # last 64 chars (sha256sum)
  catSum="${header: -64}"
  # remove checksum
  header="${header::-64}"

  fileLengths=(${header//,/ })
}

function fileDigest()
{
  fileInfo="$1"

  filePerms="${fileInfo::4}"
  fileOwner="${fileInfo:4}"
    fileOwner="${fileOwner%%)*}"
    fileOwner="${fileOwner#(}"
  fileName="${fileInfo#$filePerms($fileOwner)}"

  if [[ "$fileName" == */* ]]
  then
    dirName="${fileName%/*}"
  else
    unset dirName
  fi
}

function removeLine()
{
  rmLength=$1
  cat "$tmpAr" | tail -n+$((rmLength+1)) >"$tmpAr".tmp && mv "$tmpAr".tmp "$tmpAr"
}

function removeChar()
{
  rmLength=$1
  cat "$tmpAr" | tail -c+$((rmLength+1)) >"$tmpAr".tmp && mv "$tmpAr".tmp "$tmpAr"
}

function read()
{
  tmpAr="$(mktemp /tmp/alcochive-read-XXXXXXX)"
  cat >"$tmpAr"

  headerDigest
  removeLine 1

  for length in ${fileLengths[@]}
  do
    fileDigest "$(cat "$tmpAr" | head -n1)"
    removeLine 1
    removeChar $length

    echo "$fileName"
  done

  rm -f "$tmpAr"
}

function extract()
{
  function _fileSort()
  {
    for length in ${fileLengths[@]}
    do
      fileDigest "$(cat "$tmpAr" | head -n1)"
      removeLine 1

      if [ -n "$dirName" ]
      then
        mkdir -p "$dirName"
      fi

      if [ "${fileName: -1}" == / ]
      then
        mkdir -p "$fileName"
      elif [ ! "$overwrite" == "true" ] && [ -f "$fileName" ]
      then
        fatal "$fileName" "cannot write to existing file (use '--overwrite')"
      else
        cat "$tmpAr" | head -c$length >"$fileName"
      fi

      if [ ! "$filePerms" == 0000 ] && [ ! "$setPerms" == false ]
      then
        chmod -R "$filePerms" "$fileName"
      fi

      if [ -n "$fileOwner" ] && [ ! "$setOwner" == false ]
      then
        chown -R "$fileOwner" "$fileName"
      fi

      removeChar $length
    done
  }

  if [ -n "$directory" ]
  then
    cd "$directory"
  fi

  tmpAr="$(mktemp /tmp/alcochive-extract-XXXXXXX)"
  # copy stdin to temporary file
  cat >"$tmpAr"

  headerDigest

  # long way of removing header but oh well
  removeLine 1

  arSum="$(cat "$tmpAr" | sha256sum)"
  arSum="${arSum::64}"

  if [ ! "$arSum" == "$catSum" ]
  then
    fatal "corrupted archive" "checksum (sha256) mismatch"
  fi

  _fileSort

  rm -f "$tmpAr"
}

function create()
{
  tmpAr="$(mktemp /tmp/alcochive-create-XXXXXXX)"

  function _addFile()
  {
    fileLength=$(cat "$fileName" | wc -c)

    if [ $fileLength -eq 0 ]
    then
      fatal "$fileName" "cannot add empty files to archive"
    fi

    header+=$fileLength,
  }

  function _addDir()
  {
    # add slash to signify it is a directory
    fileName+=/
  }

  for fileName in "${targets[@]}"
  do
    filePerms=$(stat -c '%a' "$fileName")
    fileOwner="$(stat -c '%U:%G' "$fileName")"

    if [ -d "$fileName" ]
    then
      continue #_addDir
    elif [ -f "$fileName" ]
    then
      _addFile
    else
      fatal "$fileName" "no such file or directory"
    fi

    if [ ${#filePerms} -eq 3 ]
    then
      filePerms=0$filePerms
    fi

    body+=("$filePerms($fileOwner)$fileName")
  done

  if [ -z "$body" ]
  then
    fatal "cowardly refusing to create an empty archive"
  fi

  for fileAdd in "${body[@]}"
  do
    fileName="${fileAdd:4}"
      fileName="${fileName#(*)}"

    echo "$fileAdd" >>"$tmpAr"

    if [ ! "${fileAdd: -1}" == / ]
    then
      # a file
      cat "$fileName" >>"$tmpAr"
    fi
  done

  sum="$(cat "$tmpAr" | sha256sum)"
  sum="${sum::64}"

  header="${header%,}"

  echo alar"$header$sum"
  cat "$tmpAr"
  rm -f "$tmpAr"
}

function main()
{
  while [ $# -ne 0 ]
  do
    case "$1" in
      "--help"|"-h")
        operation="usage"
        ;;
      "--version"|"-V")
        operation="version"
        ;;
      "--extract"|"-x")
        operation="extract"
        ;;
      "--create"|"-c")
        operation="create"
        ;;
      "--list"|"-t")
        operation="read"
        ;;
      "--dir="*)
        directory="${arg#--dir=}"
        ;;
      "-C"*)
        shift
        directory="$1"
        ;;
      "--overwrite")
        overwrite=true
        ;;
      "--no-perms")
        setPerms=false
        ;;
      "--no-owner")
        setOwner=false
        ;;
      *)
        targets+=("$1")
        ;;
    esac
    # move on to next argument
    shift
  done

  if [ ${#targets[@]} -ne 0 ]
  then
    case "$operation" in
      "usage"|"version")
        fatal "invalid arguments" "target/s provided when none were needed"
        ;;
      "extract"|"read")
        fatal "invalid arguments" "use stdin instead of filenames for extracting/listing"
        ;;
    esac
  fi

  if [ -z "$operation" ]
  then
    operation="usage"
  fi

  case "$operation" in
    "extract"|"read")
      if [ -t 0 ]
      then
        fatal "cannot read input" "stdin is a tty"
      fi
      ;;
  esac

  eval "$operation"
}

main "$@"

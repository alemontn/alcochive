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

function warn()
{
  echo $red"warning:"$none "$(errorContent "$@")" >&2
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
  header="$(cat "$tmpAr" | head -n1)"

  if [ ! "${header::4}" == "alar" ]
  then
    fatal "corrupted archive" "header is invalid"
  fi
  # remove starting indentifier
  header="${header#alar}"

  fileLengths=(${header//,/ })
}

function fileDigest()
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

function read()
{
  tmpAr=/dev/stdin headerDigest

  declare -i maxLength=1

  for fileLength in "${fileLengths[@]}"
  do
    declare -i useLength=$maxLength

    if [ $maxLength -eq 1 ]
    then
      useLength+=1
    fi

    fileDigest "$(head -n+$useLength | tail -n1)"
    echo "$fileName"
    maxLength+=$fileLength
  done
}

function extract()
{
  function _removeLine()
  {
    rmLength=$1
    cat "$tmpAr" | tail -n+$((rmLength+1)) >"$tmpAr".tmp && mv "$tmpAr".tmp "$tmpAr"
  }

  function _fileSort()
  {
    for length in ${fileLengths[@]}
    do
      fileDigest "$(cat "$tmpAr" | head -n1)"

      _removeLine 1

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
        cat "$tmpAr" | head -n$length | head -c-1 >"$fileName"
      fi

      if [ ! "$filePerms" == 0000 ] && [ ! "$setPerms" == false ]
      then
        chmod -R "$filePerms" "$fileName"
      fi

      if [ -n "$fileOwner" ] && [ ! "$setOwner" == false ]
      then
        chown -R "$fileOwner" "$fileName"
      fi

      _removeLine $length
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
  _removeLine 1

  _fileSort

  rm -f "$tmpAr"
}

function create()
{
  function _addFile()
  {
    fileLength=$(cat "$fileName" | wc -l)

    if [ $fileLength -eq 0 ]
    then
      fatal "$fileName" "cannot add empty files to archive"
    fi

    if ! file - <"$fileName" | grep -qF "text"
    then
      warn "binary files are not fully supported - expect file corruption"
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

  header="${header%,}"
  echo alar"$header"

  for fileAdd in "${body[@]}"
  do
    fileName="${fileAdd:4}"
      fileName="${fileName#(*)}"

    echo "$fileAdd"

    if [ ! "${fileAdd: -1}" == / ]
    then
      # a file
      cat "$fileName"
    fi
  done
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

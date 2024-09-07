#!/usr/bin/env bash

# exit on errors
set -o "errexit"
# extended globbing
shopt -s "extglob"
shopt -s "globstar"

# colours & formatting :o
red=$(echo -ne '\e[1;31m')
none=$(echo -ne '\e[0m')
bold=$(echo -ne '\e[1m')

function cleanup()
{
  rm -f "$tmpAr"{,.tmp}
}

trap "cleanup" EXIT

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
  cleanup

  echo $red"error (fatal):"$none "$(errorContent "$@")" >&2
  exit 1
}

function usage()
{
  compressors="$(
    for compressor in /lib/alcochive/compress.d/*
    do
      echo -n "${compressor##*/}|"
    done
  )"
  compressors="${compressors%|}"

  echo "\
Usage: ${0##*/} <OPERATION> [ARGUMENTs] [TARGETs]

${bold}Operations:${none}
 -h, --help       show this help prompt
 -V, --version    show alcochive version
 -x, --extract    extract file/s from archive
 -c, --create     create an archive from file/s
 -t, --list       list contents of archive

${bold}Arguments:${none}
 -v, --verbose    show more information
 -z, --compress   compress archival content ($compressors)
 -O, --stdout     output a single file's contents to stdout
 -C, --dir        specify directory to extract to
     --overwrite  let existing files be overwritten
     --no-owner   don't include or change file ownership
     --no-perms   don't include or change file permissions
     --skip-sum   skip archive integrity check (checksum) when extracting
"
  exit 0
}

function version()
{
  echo $bold"alcochive"$none "version" 0.0.2 >&2
  exit 0
}

function headerDigest()
{
  header="$(head -n1 "$tmpAr")"

  case "${header::4}" in
    "alar")
      header="${header#alar}"
      ;;
    "alzr")
      header="${header#alzr}"

      for compressTemplate in /lib/alcochive/compress.d/*
      do
        eval "$(<"$compressTemplate")"

        if [ "$zHeader" == "${header::2}" ]
        then
          # matched compressor
          header="${header:3}"
          break
        fi
      done
      ;;
    *)
      fatal "corrupted archive" "header is invalid"
      ;;
  esac

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
    fileBase="$(basename "$fileName")"
  else
    unset dirName
    fileBase="$fileName"
  fi
}

function removeLine()
{
  rmLength=$1
  sed -i ${rmLength}d "$tmpAr"
}

function removeChar()
{
  rmLength=$1
  tail -c+$((rmLength+1)) "$tmpAr" >"$tmpAr".new && mv "$tmpAr".new "$tmpAr"
}

function read()
{
  tmpAr="$(mktemp /tmp/alcochive-read-XXXXXXX)"
  cat >"$tmpAr"

  headerDigest
  removeLine 1

  if [ -n "$decompress" ]
  then
    eval "$decompress" <"$tmpAr" >"$tmpAr".new && mv "$tmpAr".new "$tmpAr"
  fi

  declare -i skipLength=0 \
             skipLine=1

  for length in ${fileLengths[@]}
  do
    if [ $skipLength -eq 1 ]
    then
      fileDigest "$(head -n1 "$tmpAr")"
    else
      fileDigest "$(tail -c+$((skipLength+1)) "$tmpAr" | head -n$((skipLine+1)) | head -n1)"
    fi

    if [ "$verbose" == true ]
    then
      echo "$fileName $fileOwner $filePerms $(echo $length | numfmt --to=si)"
    else
      echo "$fileName"
    fi

    skipLength+=$((${#fileInfo}+length+1))
    skipLine+=1
  done
}

function extract()
{
  function _extract()
  {
    if [ -n "$dirName" ]
    then
      mkdir -p "$dirName"
    fi

    if [ "${fileName: -1}" == / ]
    then
      mkdir -p "$fileName"
    elif [ ! "$overwrite" == true ] && [ -f "$fileName" ]
    then
      fatal "$fileName" "cannot write to existing file (use '--overwrite')"
    else
      cat "$tmpAr" | head -c$length >"$fileName"
    fi

    if [ ! "$fileName" == /dev/stdout ]
    then
      if [ ! "$filePerms" == 0000 ] && [ ! "$setPerms" == false ]
      then
        chmod -R "$filePerms" "$fileName"
      fi

      if [ -n "$fileOwner" ] && [ ! "$setOwner" == false ]
      then
        chown -R "$fileOwner" "$fileName"
      fi

      if [ "$verbose" == true ]
      then
        echo "$fileName"
      fi
    fi
  }

  function _matchTarget()
  {
    ret=1
    for target in "${targets[@]}"
    do
      if [ "$target" == "$fileName" ]
      then
        ret=0
      fi
    done
    return $ret
  }

  function _fileSort()
  {
    for length in ${fileLengths[@]}
    do
      fileDigest "$(cat "$tmpAr" | head -n1)"
      removeLine 1

      if [ "$stdout" == true ]
      then
        if [ "${targets[@]}" == "$fileName" ]
        then
          fileName=/dev/stdout _extract
          exit 0
        else
          removeChar $length
          continue
        fi
      fi

      if [ ${#targets[@]} -eq 0 ]
      then
        _extract
      else
        if _matchTarget
        then
          _extract
        else
          removeChar $length
          continue
        fi
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

  if [ ! "$skipSum" == true ]
  then
    arSum="$(cat "$tmpAr" | sha256sum)"
    arSum="${arSum::64}"

    if [ ! "$arSum" == "$catSum" ]
    then
      fatal "corrupted archive" "checksum (sha256) mismatch"
    fi
  fi

  if [ -n "$decompress" ]
  then
    eval "$decompress" <"$tmpAr" >"$tmpAr".new && mv "$tmpAr".new "$tmpAr"
  fi

  _fileSort
}

function create()
{
  headerId="alar"

  if [ -n "$compressor" ]
  then
    headerId="alzr"

    if [[ "$compressor" == *:+([0-9]) ]] ||
       [[ "$compressor" == *:@("max"|"min") ]]
    then
      compressLevel=${compressor#*:}
      compressor="${compressor%:*}"
    fi

    if [ ! -f /lib/alcochive/compress.d/"$compressor" ]
    then
      fatal "$compressor" "unknown compressor"
    fi

    eval "$(</lib/alcochive/compress.d/"$compressor")"

    levelId=D

    if [ -n "$compressLevel" ]
    then
      levelId=S
      case "$compressLevel" in
        +([0-9])) :;;
        "min") compressLevel=$fastestLevel levelId=N;;
        "max") compressLevel=$bestLevel levelId=X;;
        *) fatal "$compressLevel" "unknown compression level (range = $fastestLevel-$bestLevel)"
      esac
    fi

    headerId+="$zHeader"$levelId
  fi

  tmpAr="$(mktemp /tmp/alcochive-create-XXXXXXX)"

  if [ ${#targets[@]} -eq 1 ] && [ "${targets[@]}" == "." ]
  then
    targets=(**/*)
  fi

  function _addFile()
  {
    fileLength=$(cat "$filePath" | wc -c)

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

  for filePath in "${targets[@]}"
  do
    fileName="$filePath"

    # remove leading slashes from name
    until [ ! "${fileName::1}" == / ]
    do
      fileName="${fileName#/}"
    done

    fileName="${fileName#./}"

    fileBase="$(basename "$fileName")"
    filePerms=$(stat -c '%a' "$filePath")
    fileOwner="$(stat -c '%U:%G' "$filePath")"

    if [ -d "$filePath" ]
    then
      continue #_addDir
    elif [ -f "$filePath" ]
    then
      _addFile
    else
      fatal "$filePath" "no such file or directory"
    fi

    if [ ${#filePerms} -eq 3 ]
    then
      filePerms=0$filePerms
    fi

    body+=("$filePerms($fileOwner)$fileName")
    paths+=("$filePath")
  done

  if [ -z "$body" ]
  then
    fatal "cowardly refusing to create an empty archive"
  fi

  declare -i fileLoop=0

  for fileAdd in "${body[@]}"
  do
    filePath="${paths[$fileLoop]}"
    fileName="${fileAdd:4}"
      fileName="${fileName#(*)}"

    fileBase="$(basename "$fileName")"

    echo "$fileAdd" >>"$tmpAr"

    if [ ! "${fileAdd: -1}" == / ]
    then
      # a file
      cat "$filePath" >>"$tmpAr"
    fi

    if [ "$verbose" == true ]
    then
      echo "$fileName" >&2
    fi

    fileLoop+=1
  done

  if [ -n "$compressor" ] && [ -n "$compressLevel" ]
  then
    compressArgs="$setLevel"$compressLevel
  fi

  if [ -n "$compressor" ]
  then
    eval "$compressor" "$compressArgs" <"$tmpAr" >"$tmpAr".z &&
     mv "$tmpAr".z "$tmpAr"
  fi

  sum="$(cat "$tmpAr" | sha256sum)"
  sum="${sum::64}"

  header="${header%,}"

  echo "$headerId$header$sum"
  cat "$tmpAr"
}

function main()
{
  function _setOperation()
  {
    if [ -n "$operation" ]
    then
      fatal "invalid arguments" "conflicting arguments provided"
    fi

    export operation="$1"
  }

  function _seperateArg()
  {
    if [[ "$arg" == -[A-Za-z]+([A-Za-z]) ]]
    then
      arg="${arg#-}"

      while [ ${#arg} -ne 0 ]
      do
        args+=("-${arg::1}")
        arg="${arg:1}"
      done
    else
      args+=("$arg")
    fi
  }

  for arg in "$@"
  do
    _seperateArg
  done

  set -- "${args[@]}"
  unset args

  while [ $# -ne 0 ]
  do
    case "$1" in
      "--help"|"-h")    _setOperation "usage";;
      "--version"|"-V") _setOperation "version";;
      "--extract"|"-x") _setOperation "extract";;
      "--create"|"-c")  _setOperation "create";;
      "--list"|"-t")    _setOperation "read";;
      "--verbose"|"-v") verbose=true;;
      "--stdout"|"-O")  stdout=true;;
      "--overwrite")    overwrite=true;;
      "--no-perms")     setPerms=false;;
      "--no-owner")     setOwner=false;;
      "--skip-sum")     skipSum=true;;
      "--dir="*)        directory="${1#--dir=}";;
      "-C"*)            directory="$2"; shift;;
      "--compress="*)   compressor="${1##--compress=}";;
      "-z")             compressor="$2"; shift;;
      *)                targets+=("$1");;
    esac
    # move on to next argument
    shift
  done

  if [ ${#targets[@]} -gt 1 ] && [ "$stdout" == true ]
  then
    fatal "argument '--stdout' only takes one target"
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
  cleanup
}

main "$@"

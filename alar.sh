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
  if [[ "$tmpAr" == *.swp* ]]
  then
    rm -f "$tmpAr"{,.tmp}
  fi
}
# before exiting fully, remove tmp file
trap "cleanup" EXIT

function makeTmp()
{
  tmpAr=."$1".alar.swp

  : >"$tmpAr" || fatal "failed to create temporary file (current directory: $PWD)"
}

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
 -q, --show       show information about an archive
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
     --exclude    exclude file patterns
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
  header="$(head -n1 "$tmpAr" | cut -d'>' -f1)"
  headerLength=${#header}

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
          header="${header:2}"
          levelId="${header::1}"
          header="${header:1}"
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

function matchExclude()
{
  ret=1
  for excludeFile in "${exclude[@]}"
  do
    if [[ "$fileName" == $excludeFile ]]
    then
      ret=0
    fi
  done

  return $ret
}

function show()
{
  tmpAr=/dev/stdin headerDigest
  unset tmpAr

  case "$levelId" in
    D) levelDisplay="default";;
    S) levelDisplay="custom";;
    X) levelDIsplay="best";;
    N) levelDisplay="fastest";;
  esac

  if [ -n "$compress" ]
  then
    echo "$compressName with $levelDisplay compression"
  else
    echo "uncompressed archive"
  fi

  echo "total of ${#fileLengths[@]} file(s)"

  if [ -z "$compress" ]
  then
    fileAdd=$(
      for length in "${fileLengths[@]}"
      do
        echo -n $length+
      done
    )
    fileTotal="$(echo $((${fileAdd%+})) | numfmt --to=iec)"
    echo "~$fileTotal extracted size"
  fi
}

function readContents()
{
  makeTmp "in"
  # save stdin to tmp file
  cat >"$tmpAr"

  headerDigest

  if [ -n "$decompress" ]
  then
    eval "$decompress" <"$tmpAr" >"$tmpAr".new && mv "$tmpAr".new "$tmpAr"
  fi

  declare -i skipLength=$((headerLength+1)) \
             skipLine=1

  for length in ${fileLengths[@]}
  do
    fileDigest "$(tail -c+$((skipLength+1)) "$tmpAr" | head -n$((skipLine+1)) | head -n1)"

    if [ "$verbose" == true ]
    then
      echo "$fileName $fileOwner $filePerms $(echo $length | numfmt --to=iec)"
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
      tail -c+$((skipLength+1)) "$tmpAr" | tail -n+2 | head -c$length >"$fileName"
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
      fileDigest "$(tail -c+$((skipLength+1)) "$tmpAr" | head -n$((skipLine+1)) | head -n1)"

      if [ "$stdout" == true ] && [ "${targets[@]}" == "$fileName" ]
      then
        fileName=/dev/stdout _extract
        exit
      fi

      if [ ! "$stdout" == true ] && [ ${#targets[@]} -eq 0 ] || _matchTarget
      then
        _extract
      fi

      skipLine+=1
      skipLength+=$((${#fileInfo}+length+1))
    done
  }

  if [ -n "$directory" ]
  then
    cd "$directory"
  fi

  makeTmp "in"
  # copy stdin to temporary file
  cat >"$tmpAr"

  headerDigest

  declare -i skipLength=$((headerLength+1)) \
             skipLine=1

  if [ ! "$skipSum" == true ]
  then
    arSum="$(tail -c+$((skipLength+1)) "$tmpAr" | sha256sum)"
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

  if [ ${#targets[@]} -eq 1 ] && [ "${targets[@]}" == "." ]
  then
    if [ -f .out.alar.swp ]
    then
      fatal "invalid filename" "file cannot be called '.out.alar.swp'"
    fi

    targets=()
    while read fileName
    do
      targets+=("$fileName")
    done \
      <<<"$(find -type f -print0 | xargs -0 ls -1)"
  fi

  makeTmp "out"

  function _addFile()
  {
    fileLength=$(cat "$filePath" | wc -c)
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

    if matchExclude
    then
      continue
    fi

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

    if [ "$setPerms" == false ]
    then
      filePerms=0000
    fi

    if [ "$setOwner" == false ]
    then
      fileOwner=
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

  echo -n "$headerId$header$sum>"
  cat "$tmpAr"
}

function main()
{
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

  function _setOperation()
  {
    if [ -n "$operation" ]
    then
      fatal "invalid arguments" "conflicting arguments provided"
    fi

    export operation="$1"
  }

  function _setArgValue()
  {
    varName="$1"
    varContent="${2##--*=}"

    if [ "$3" == "-+" ]
    then
      eval "$varName+=('$varContent')"
    else
      eval "$varName='$varContent'"
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
      "--help"|"-h")     _setOperation "usage";;
      "--version"|"-V")  _setOperation "version";;
      "--extract"|"-x")  _setOperation "extract";;
      "--create"|"-c")   _setOperation "create";;
      "--show"|"-q")     _setOperation "show";;
      "--list"|"-t")     _setOperation "readContents";;
      "--dir="*)         _setArgValue "dirName" "$1";;
      "--compress="*)    _setArgValue "compressor" "$1";;
      "--exclude="*)     _setArgValue "exclude" "$1" -+;;
      "-C")              directory="$2"; shift;;
      "-z")              compressor="$2"; shift;;
      "--verbose"|"-v")  verbose=true;;
      "--stdout"|"-O")   stdout=true;;
      "--overwrite")     overwrite=true;;
      "--no-perms")      setPerms=false;;
      "--no-owner")      setOwner=false;;
      "--skip-sum")      skipSum=true;;
      *)                 targets+=("$1");;
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
    "extract"|"readContents")
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

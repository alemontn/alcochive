# alcochive

## what?

this is an archive tool, written in shell script

it isn't meant to be used seriously but instead for me
to go "look I made an archiver in bash lol"

there is no real reason to use this since it is slower
than all other archivers & has less functionality

## usage

to create an archive use `-c`:

```
$ alar -c file0 file1 file2 ... > files.alar
```

to list the contents of an archive use `-t`:

```
$ alar -t < files.alar
```

to extract an archive use `-x`:

```
$ alar -x < files.alar
```

you can also use `-C` to specify the output directory:

```
$ alar -C out -x < files.alar
```

## installation

see [releases](https://github.com/alemontn/alcochive/releases)
for available package formats (deb) as well as an install
bundle, for other distros

## building

a `package.sh` script is provided for packaging & making
bundles

to make - for example - a deb package:

```
$ ./package.sh deb
```

or a bundle:

```
$ ./package.sh bundle
```

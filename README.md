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

## speed

alcochive is much slower than other archivers, as shown
by these speed tests

the folder is `SF` and contains 65 different files, all
amounting to 793 mib of data

### creating:

```
$ time alar -c . > ../sf.alar

real	0m3.812s
user	0m0.853s
sys	0m1.372s

$ time tar -c . > ../sf.tar

real	0m2.206s
user	0m0.008s
sys	0m0.466s

$ time find | cpio -o > ../sf.cpio

real	0m3.467s
user	0m0.144s
sys	0m1.840s
```

alcochive is ~2x slower than `tar` and ~1.1x slower
than `cpio` at creating

### extracting:

```
$ time alar -x < ../sf.alar

real	0m30.193s
user	0m2.883s
sys	0m40.328s

$ time tar -x < ../sf.tar

real	0m2.564s
user	0m0.014s
sys	0m0.474s

$ time cpio -di < ../sf.cpio

real	0m5.149s
user	0m0.186s
sys	0m2.061s
```

alcochive is ~12x slower than `tar` and ~6x slower
than `cpio` at extracting

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

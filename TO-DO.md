
targets are sorted from most to least concern, the
higher the target is, the more likely it is to be
fixed/implemented

### FORMAT:

 * only files can be added, not directories

 * symlinks not yet implemented

 * binary files may be corrupted when creating/extracting

 * date last modified not yet implemented

 * sha256sum for archive integrity not yet implemeted

 * xattrs not yet implemented (no idea what they even are)

### CLI:

 * reading (`-t`) only works for first file, and misreads
   the rest of the archive afterwards

 * bash cannot properly handle null bytes (`\0`) add will
   throw the error "ignored null byte in input", leading
   to a corrupted input/output

 * reading (`-t`) only displays filenames, no other info
   (permissions, owner, etc..)

 * arguments have to be seperated (e.g. `-x -C /`) when ideally
   should be able to be put together (e.g. `-xC /`)

### MORE:

 * need to implement other packaging formats (rpm, pacman)

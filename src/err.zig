pub const SysErr = error{
    ErrFault, // Page fsul, user process tried to read outisde its addr space
    ErrChild, // No child to wait for
    ErrIO, // IO error reading/writing to ide disk
    ErrBadFd, // Invalid file handle
    ErrInval, // Invalid agr combination. For example, opening a folder with eec permissions.
    ErrNotDir, // Path isn't a directory
    ErrNoExec, // File is not a valid ELF executable
    ErrNoFile, // File to execute not found
    ErrNoMem, // Not enough memory to handle syscall
    ErrExists, // File already exists
    ErrMaxOpen, // Reached max open files per process limit
    ErrNoEnt, // Invalid path passed to sys call
    ErrArgs, // Too many args to exec sys call
};

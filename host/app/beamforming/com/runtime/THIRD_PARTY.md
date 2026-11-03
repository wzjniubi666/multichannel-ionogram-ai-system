# Bundled interface scripts

The tcl/ directory is copied without source modification from the project's
existing Python3.12.14 runtime Tcl/Tk8.6.12 library. It supplies the matching
portable Tk initialization/resources; no system package installation or environment
modification is performed. Copyright headers remain in each source file.

Tk's license.terms is retained under tcl/tk8.6/ (and its demos directory).
The source runtime Python license is retained in Python_LICENSE.txt.
The application continues to use the existing project Python/DLLs and numerical
packages; this is not a replacement or an independent Python distribution.

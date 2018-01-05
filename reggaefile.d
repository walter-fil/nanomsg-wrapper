import reggae;
import std.typecons: No;
enum commonFlags = "-w -g -debug";
mixin build!(dubTestTarget!(CompilerFlags(commonFlags),
                            LinkerFlags(),
                            No.allTogether));

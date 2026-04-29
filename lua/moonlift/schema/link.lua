-- Clean MoonLink schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonLink" {
        A.product "LinkPath" {
            A.field "text" "string",
            A.unique,
        },

        A.product "LinkSymbol" {
            A.field "name" "string",
            A.unique,
        },

        A.product "LinkEnv" {
            A.field "key" "string",
            A.field "value" "string",
            A.unique,
        },

        A.sum "LinkPlatform" {
            A.variant "LinkPlatformLinux",
            A.variant "LinkPlatformMacOS",
            A.variant "LinkPlatformWindows",
            A.variant "LinkPlatformWasm",
            A.variant "LinkPlatformUnknown" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.sum "LinkArch" {
            A.variant "LinkArchX86_64",
            A.variant "LinkArchAArch64",
            A.variant "LinkArchX86",
            A.variant "LinkArchArm",
            A.variant "LinkArchWasm32",
            A.variant "LinkArchUnknown" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.sum "LinkObjectFormat" {
            A.variant "LinkFormatElf",
            A.variant "LinkFormatMachO",
            A.variant "LinkFormatCoff",
            A.variant "LinkFormatWasm",
            A.variant "LinkFormatUnknown" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.sum "LinkRelocationModel" {
            A.variant "LinkRelocStatic",
            A.variant "LinkRelocPic",
            A.variant "LinkRelocPie",
        },

        A.product "LinkTargetModel" {
            A.field "backend" "MoonBack.BackTargetModel",
            A.field "platform" "MoonLink.LinkPlatform",
            A.field "arch" "MoonLink.LinkArch",
            A.field "object_format" "MoonLink.LinkObjectFormat",
            A.field "relocation" "MoonLink.LinkRelocationModel",
            A.unique,
        },

        A.sum "LinkArtifactKind" {
            A.variant "LinkArtifactObject",
            A.variant "LinkArtifactStaticArchive",
            A.variant "LinkArtifactSharedLibrary",
            A.variant "LinkArtifactExecutable",
        },

        A.sum "LinkerKind" {
            A.variant "LinkerSystemCc",
            A.variant "LinkerCc",
            A.variant "LinkerClang",
            A.variant "LinkerGcc",
            A.variant "LinkerLd",
            A.variant "LinkerLld",
            A.variant "LinkerAr",
            A.variant "LinkerLibtool",
            A.variant "LinkerCustom" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.product "LinkTool" {
            A.field "kind" "MoonLink.LinkerKind",
            A.field "path" "MoonLink.LinkPath",
            A.unique,
        },

        A.sum "LinkInput" {
            A.variant "LinkInputObject" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
            A.variant "LinkInputStaticArchive" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
            A.variant "LinkInputSharedLibrary" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
            A.variant "LinkInputSystemLibrary" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "LinkInputFramework" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "LinkInputLibrarySearchPath" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
            A.variant "LinkInputLinkerScript" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
        },

        A.sum "LinkExportPolicy" {
            A.variant "LinkExportAll",
            A.variant "LinkExportNone",
            A.variant "LinkExportSymbols" {
                A.field "symbols" (A.many "MoonLink.LinkSymbol"),
                A.variant_unique,
            },
            A.variant "LinkExportVersionScript" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
        },

        A.sum "LinkExternPolicy" {
            A.variant "LinkExternRequireResolved",
            A.variant "LinkExternAllowUnresolved",
        },

        A.sum "LinkDebugPolicy" {
            A.variant "LinkDebugDefault",
            A.variant "LinkDebugKeep",
            A.variant "LinkDebugStrip",
        },

        A.sum "LinkRuntimePath" {
            A.variant "LinkRpath" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
            A.variant "LinkRunpath" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
        },

        A.sum "LinkOption" {
            A.variant "LinkOptRuntimePath" {
                A.field "path" "MoonLink.LinkRuntimePath",
                A.variant_unique,
            },
            A.variant "LinkOptEntry" {
                A.field "symbol" "MoonLink.LinkSymbol",
                A.variant_unique,
            },
            A.variant "LinkOptSoname" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "LinkOptInstallName" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "LinkOptOutputImplib" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
            A.variant "LinkOptDebug" {
                A.field "policy" "MoonLink.LinkDebugPolicy",
                A.variant_unique,
            },
            A.variant "LinkOptWholeArchiveBegin",
            A.variant "LinkOptWholeArchiveEnd",
            A.variant "LinkOptNoDefaultLibs",
            A.variant "LinkOptStaticLibgcc",
            A.variant "LinkOptCustomArg" {
                A.field "arg" "string",
                A.variant_unique,
            },
        },

        A.product "LinkPlan" {
            A.field "target" "MoonLink.LinkTargetModel",
            A.field "kind" "MoonLink.LinkArtifactKind",
            A.field "tool" "MoonLink.LinkTool",
            A.field "output" "MoonLink.LinkPath",
            A.field "inputs" (A.many "MoonLink.LinkInput"),
            A.field "exports" "MoonLink.LinkExportPolicy",
            A.field "externs" "MoonLink.LinkExternPolicy",
            A.field "options" (A.many "MoonLink.LinkOption"),
            A.unique,
        },

        A.sum "LinkIssue" {
            A.variant "LinkIssueMissingOutput",
            A.variant "LinkIssueNoInputs",
            A.variant "LinkIssueMissingInput" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
            A.variant "LinkIssueUnsupportedPlatform" {
                A.field "platform" "MoonLink.LinkPlatform",
                A.field "kind" "MoonLink.LinkArtifactKind",
                A.variant_unique,
            },
            A.variant "LinkIssueUnsupportedInput" {
                A.field "input" "MoonLink.LinkInput",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "LinkIssueUnsupportedOption" {
                A.field "option" "MoonLink.LinkOption",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "LinkIssueUnresolvedSymbol" {
                A.field "symbol" "MoonLink.LinkSymbol",
                A.variant_unique,
            },
            A.variant "LinkIssueDuplicateSymbol" {
                A.field "symbol" "MoonLink.LinkSymbol",
                A.variant_unique,
            },
            A.variant "LinkIssueToolUnavailable" {
                A.field "tool" "MoonLink.LinkTool",
                A.variant_unique,
            },
            A.variant "LinkIssueCommandFailed" {
                A.field "index" "number",
                A.field "code" "number",
                A.field "stderr" "string",
                A.variant_unique,
            },
        },

        A.product "LinkReport" {
            A.field "issues" (A.many "MoonLink.LinkIssue"),
            A.unique,
        },

        A.sum "LinkCommand" {
            A.variant "LinkCmdRun" {
                A.field "tool" "MoonLink.LinkTool",
                A.field "args" (A.many "string"),
                A.field "env" (A.many "MoonLink.LinkEnv"),
                A.variant_unique,
            },
            A.variant "LinkCmdWriteFile" {
                A.field "path" "MoonLink.LinkPath",
                A.field "contents" "string",
                A.variant_unique,
            },
            A.variant "LinkCmdRemoveFile" {
                A.field "path" "MoonLink.LinkPath",
                A.variant_unique,
            },
        },

        A.product "LinkCommandPlan" {
            A.field "plan" "MoonLink.LinkPlan",
            A.field "commands" (A.many "MoonLink.LinkCommand"),
            A.unique,
        },

        A.sum "LinkResult" {
            A.variant "LinkOk" {
                A.field "output" "MoonLink.LinkPath",
                A.variant_unique,
            },
            A.variant "LinkFailed" {
                A.field "report" "MoonLink.LinkReport",
                A.variant_unique,
            },
        },
    }
end

#!/usr/bin/env python3
"""Generates NotchNote.xcodeproj from the files under NotchNote/.

Run from the repository root:  python3 tools/gen_xcodeproj.py
Re-run it whenever you add or remove a source file. (Alternatively just add files in Xcode.)
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = "NotchNote"
PROJ = "NotchNote.xcodeproj"
BUNDLE_ID = "com.clement.NotchNote"


def oid(label: str) -> str:
    return hashlib.md5(label.encode()).hexdigest()[:24].upper()


def q(v: str) -> str:
    """Quote a pbxproj string when needed."""
    if v and all(c.isalnum() or c in "_./$" for c in v) and not v[0].isdigit() or v in ("YES", "NO"):
        return v
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


# ---------------------------------------------------------------- collect files
sources, others = [], []
for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, SRC)):
    dirnames.sort()
    for f in sorted(filenames):
        rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
        if f.endswith(".swift"):
            sources.append(rel)
        elif f in ("Info.plist",) or f.endswith(".entitlements"):
            others.append(rel)

# ---------------------------------------------------------------- groups
class Group:
    def __init__(self, path):
        self.path = path
        self.children = []  # Group or file rel path
        self.subs = {}


root_group = Group(SRC)
for rel in sources + others:
    parts = rel.split(os.sep)[1:]  # drop leading NotchNote
    g = root_group
    for p in parts[:-1]:
        if p not in g.subs:
            g.subs[p] = Group(p)
            g.children.append(g.subs[p])
        g = g.subs[p]
    g.children.append(rel)

file_ref = {rel: oid("fileref:" + rel) for rel in sources + others}
build_file = {rel: oid("buildfile:" + rel) for rel in sources}

PRODUCT_REF = oid("product")
MAIN_GROUP = oid("maingroup")
PRODUCTS_GROUP = oid("productsgroup")
TARGET = oid("target")
PROJECT = oid("project")
SOURCES_PHASE = oid("sourcesphase")
FRAMEWORKS_PHASE = oid("frameworksphase")
RESOURCES_PHASE = oid("resourcesphase")
PROJ_CFGLIST = oid("projcfglist")
TARGET_CFGLIST = oid("targetcfglist")
PROJ_DEBUG, PROJ_RELEASE = oid("projdebug"), oid("projrelease")
TGT_DEBUG, TGT_RELEASE = oid("tgtdebug"), oid("tgtrelease")

out = []
w = out.append


def filetype(rel):
    if rel.endswith(".swift"):
        return "sourcecode.swift"
    if rel.endswith(".plist"):
        return "text.plist.xml"
    if rel.endswith(".entitlements"):
        return "text.plist.entitlements"
    return "text"


w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {\n\t};")
w("\tobjectVersion = 56;")
w("\tobjects = {")
w("")

w("/* Begin PBXBuildFile section */")
for rel in sources:
    w(f"\t\t{build_file[rel]} /* {os.path.basename(rel)} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref[rel]} /* {os.path.basename(rel)} */; }};")
w("/* End PBXBuildFile section */")
w("")

w("/* Begin PBXFileReference section */")
w(f"\t\t{PRODUCT_REF} /* NotchNote.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = NotchNote.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for rel in sources + others:
    name = os.path.basename(rel)
    w(f"\t\t{file_ref[rel]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {filetype(rel)}; path = {q(name)}; sourceTree = \"<group>\"; }};")
w("/* End PBXFileReference section */")
w("")

w("/* Begin PBXFrameworksBuildPhase section */")
w(f"\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
w("/* End PBXFrameworksBuildPhase section */")
w("")


def group_id(path_key):
    return oid("group:" + path_key)


def emit_group(g, key, is_root=False):
    gid = MAIN_GROUP if False else group_id(key)
    lines = [f"\t\t{gid} /* {g.path} */ = {{", "\t\t\tisa = PBXGroup;", "\t\t\tchildren = ("]
    for c in g.children:
        if isinstance(c, Group):
            lines.append(f"\t\t\t\t{group_id(key + '/' + c.path)} /* {c.path} */,")
        else:
            lines.append(f"\t\t\t\t{file_ref[c]} /* {os.path.basename(c)} */,")
    lines += ["\t\t\t);", f"\t\t\tpath = {q(g.path)};", "\t\t\tsourceTree = \"<group>\";", "\t\t};"]
    out.extend(lines)
    for c in g.children:
        if isinstance(c, Group):
            emit_group(c, key + "/" + c.path)


w("/* Begin PBXGroup section */")
w(f"\t\t{MAIN_GROUP} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{group_id(SRC)} /* {SRC} */,\n\t\t\t\t{PRODUCTS_GROUP} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
w(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{PRODUCT_REF} /* NotchNote.app */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
emit_group(root_group, SRC)
w("/* End PBXGroup section */")
w("")

w("/* Begin PBXNativeTarget section */")
w(f"""\t\t{TARGET} /* NotchNote */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TARGET_CFGLIST} /* Build configuration list for PBXNativeTarget "NotchNote" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE} /* Sources */,
\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,
\t\t\t\t{RESOURCES_PHASE} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = NotchNote;
\t\t\tproductName = NotchNote;
\t\t\tproductReference = {PRODUCT_REF} /* NotchNote.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};""")
w("/* End PBXNativeTarget section */")
w("")

w("/* Begin PBXProject section */")
w(f"""\t\t{PROJECT} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{TARGET} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {PROJ_CFGLIST} /* Build configuration list for PBXProject "NotchNote" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP};
\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET} /* NotchNote */,
\t\t\t);
\t\t}};""")
w("/* End PBXProject section */")
w("")

w("/* Begin PBXResourcesBuildPhase section */")
w(f"\t\t{RESOURCES_PHASE} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
w("/* End PBXResourcesBuildPhase section */")
w("")

w("/* Begin PBXSourcesBuildPhase section */")
w(f"\t\t{SOURCES_PHASE} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (")
for rel in sources:
    w(f"\t\t\t\t{build_file[rel]} /* {os.path.basename(rel)} in Sources */,")
w("\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};")
w("/* End PBXSourcesBuildPhase section */")
w("")


def settings(d, indent="\t\t\t\t"):
    lines = []
    for k in sorted(d):
        v = d[k]
        lines.append(f"{indent}{k} = {q(v)};")
    return "\n".join(lines)


proj_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "MACOSX_DEPLOYMENT_TARGET": "15.0",
    "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0",
}
proj_debug = dict(proj_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
proj_release = dict(proj_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
})
tgt_common = {
    "CODE_SIGN_ENTITLEMENTS": "NotchNote/Resources/NotchNote.entitlements",
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_HARDENED_RUNTIME": "NO",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "NotchNote/Resources/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
}

w("/* Begin XCBuildConfiguration section */")
for cid, name, d in ((PROJ_DEBUG, "Debug", proj_debug), (PROJ_RELEASE, "Release", proj_release)):
    w(f"\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(d)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};")
for cid, name in ((TGT_DEBUG, "Debug"), (TGT_RELEASE, "Release")):
    w(f"\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(tgt_common)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};")
w("/* End XCBuildConfiguration section */")
w("")

w("/* Begin XCConfigurationList section */")
w(f"\t\t{PROJ_CFGLIST} /* Build configuration list for PBXProject \"NotchNote\" */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{PROJ_DEBUG} /* Debug */,\n\t\t\t\t{PROJ_RELEASE} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};")
w(f"\t\t{TARGET_CFGLIST} /* Build configuration list for PBXNativeTarget \"NotchNote\" */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{TGT_DEBUG} /* Debug */,\n\t\t\t\t{TGT_RELEASE} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};")
w("/* End XCConfigurationList section */")
w("")
w("\t};")
w(f"\trootObject = {PROJECT} /* Project object */;")
w("}")

proj_dir = os.path.join(ROOT, PROJ)
os.makedirs(proj_dir, exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
    f.write("\n".join(out) + "\n")

# ---------------------------------------------------------------- shared scheme
scheme_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TARGET}"
               BuildableName = "NotchNote.app"
               BlueprintName = "NotchNote"
               ReferencedContainer = "container:NotchNote.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET}"
            BuildableName = "NotchNote.app"
            BlueprintName = "NotchNote"
            ReferencedContainer = "container:NotchNote.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
with open(os.path.join(scheme_dir, "NotchNote.xcscheme"), "w") as f:
    f.write(scheme)

print(f"Generated {PROJ} with {len(sources)} Swift files")
